extends SceneTree
## WebSocket real: snapshot, dos réplicas, AOI por viaje y reconexión bajo M2.

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
const NEAR: String = "018f0000-0000-7000-8000-000000000007"
const FAR: String = "018f0000-0000-7000-8000-000000000008"
var _world: SolarSystemWorld
var _gateway: WebSocketGateway
var _seed: MockWorldSeed
var _peers: Array[WebSocketPeer] = []
var _sequences: Dictionary = {}
var _failures: int = 0
var _now: int = 10_000_000
var _port: int = 19322


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))
	var config: SssConfig = CONFIG.duplicate(true) as SssConfig
	config.port = _port
	config.travel_speed_tiles_per_min = 60000.0
	_seed = SEED.duplicate(true) as MockWorldSeed
	_world = SolarSystemWorld.new(config, _seed)
	_world.set_now_provider(func() -> int: return _now)
	_world.tick()
	_gateway = WebSocketGateway.new(config, MockClientAuthenticator.new(_seed), _world)
	root.add_child(_gateway)
	if _gateway.start() != OK:
		_check(false, "puerto disponible para gateway")
		_finish()
		return
	var first: WebSocketPeer = await _connect_peer()
	var second: WebSocketPeer = await _connect_peer()
	if first == null or second == null:
		_finish()
		return
	for peer: WebSocketPeer in [first, second]:
		_send(peer, {"type": "auth", "jwt": _seed.accepted_token})
		_check(str((await _receive(peer)).get("type")) == "auth_ok", "autenticación real")
		_send(peer, {"type": "full_snapshot"})
		var full: Dictionary = await _receive(peer)
		_check(bool(full.get("full", false)), "snapshot antes de incrementales")
		var near: Dictionary = _entity(full.get("added", []), NEAR)
		_check(not near.is_empty() and _entity(full.get("added", []), FAR).is_empty(), "snapshot filtrado AOI")
		_check(not near.has("remaining_quantity"), "wire M2 no recibe extensión M3 silenciosa")
	# Actualización de datos autoritativos: sólo forma M2 en red durante ETAPA 2.
	_world.set_asteroid_resource_state(NEAR, 7, "")
	_flush()
	for peer: WebSocketPeer in [first, second]:
		var update: Dictionary = _entity((await _receive(peer)).get("updated", []), NEAR)
		_check(not update.is_empty() and not update.has("asteroid_state"), "update M2 entregado a ambas sesiones")
	_send(first, {"type": "start_travel", "destination": [550, 500]})
	var deadline: int = Time.get_ticks_msec() + 3000
	while not _world.entity_registry.get_entity(_seed.entity_id).is_traveling() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(_world.entity_registry.get_entity(_seed.entity_id).is_traveling(), "intención de viaje llega al SSS")
	_flush()
	for peer: WebSocketPeer in [first, second]:
		var traveling: Dictionary = _entity((await _receive(peer)).get("updated", []), _seed.entity_id)
		_check(traveling.get("state") == "TRAVELING" and traveling.get("travel") is Dictionary, "confirmación M2 por delta")
	_now += 1000
	_flush()
	for peer: WebSocketPeer in [first, second]:
		var arrival: Dictionary = await _receive(peer)
		_check(arrival.get("removed", []).has(NEAR), "removed de asteroide inmóvil al viajar observador")
		_check(not _entity(arrival.get("added", []), FAR).is_empty(), "added de asteroide inmóvil en nuevo AOI")
		var ship: Dictionary = _entity(arrival.get("updated", []), _seed.entity_id)
		_check(ship.get("state") == "ANCHORED" and ship.get("travel") == null, "llegada y limpieza M2")
	_check(_world.entity_registry.has(NEAR), "removed no destruye entidad autoritativa")
	_send(first, {"type": "full_snapshot"})
	var reset: Dictionary = await _receive(first)
	_check(bool(reset.get("full", false)) and not _entity(reset.get("added", []), FAR).is_empty(), "snapshot reinicia conjunto visible")
	_world.set_entity_position(_seed.entity_id, Vector2i(300, 300))
	_flush()
	for peer: WebSocketPeer in [first, second]:
		var returned: Dictionary = await _receive(peer)
		_check(returned.get("removed", []).has(FAR) and not _entity(returned.get("added", []), NEAR).is_empty(), "reentrada completa sin depender de movimiento asteroide")
	_flush()
	_send(first, {"type": "ping", "client_time": 123})
	_check((await _receive(first)).get("type") == "pong", "tick sin cambios no reenvía delta")
	first.close()
	var reconnected: WebSocketPeer = await _connect_peer()
	if reconnected != null:
		_send(reconnected, {"type": "auth", "jwt": _seed.accepted_token})
		_check((await _receive(reconnected)).get("seq") == 1, "nueva conexión reinicia seq")
		_send(reconnected, {"type": "full_snapshot"})
		var restored: Dictionary = await _receive(reconnected)
		_check(not _entity(restored.get("added", []), NEAR).is_empty() and _entity(restored.get("added", []), FAR).is_empty(), "reconexión reconstruye AOI vigente")
	_finish()


func _connect_peer() -> WebSocketPeer:
	var peer := WebSocketPeer.new()
	_peers.append(peer)
	if peer.connect_to_url("ws://127.0.0.1:%d" % _port) != OK:
		_check(false, "conexión WebSocket iniciada")
		return null
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return peer
		await process_frame
	_check(false, "conexión WebSocket dentro del timeout")
	return null


func _send(peer: WebSocketPeer, message: Dictionary) -> void:
	message["protocol_version"] = "team3-m2.0"
	_check(peer.send_text(JSON.stringify(message)) == OK, "solicitud enviada")


func _receive(peer: WebSocketPeer) -> Dictionary:
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_available_packet_count() > 0:
			var parsed: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if not parsed is Dictionary:
				break
			var message: Dictionary = parsed
			var key: int = peer.get_instance_id()
			var expected: int = int(_sequences.get(key, 0)) + 1
			_check(message.get("seq") == expected, "seq continuo en todos los mensajes")
			_sequences[key] = expected
			_check(message.get("protocol_version") == "team3-m2.0" and message.has("server_time"), "sobre M2 preservado")
			return message
		await process_frame
	_check(false, "respuesta JSON dentro del timeout")
	return {}


func _flush() -> void:
	_world.tick()
	_gateway.flush_pending_deltas()
	_world.acknowledge_changes()


func _entity(entities: Array, entity_id: String) -> Dictionary:
	for entity: Dictionary in entities:
		if str(entity.get("entity_id", "")) == entity_id:
			return entity
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("ASTEROID_GATEWAY_SYNC_TEST_FAILED: %s" % message)


func _finish() -> void:
	for peer: WebSocketPeer in _peers:
		peer.close()
	if _gateway != null:
		_gateway.stop()
		_gateway.free()
	print("ASTEROID_GATEWAY_SYNC_TEST_OK" if _failures == 0 else "ASTEROID_GATEWAY_SYNC_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
