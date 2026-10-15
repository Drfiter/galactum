extends SceneTree
## WebSocket real con dos jugadores, versiones M2/M3 y reconexión.

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
const ASTEROID: String = "018f0000-0000-7000-8000-000000000007"
var _world: SolarSystemWorld
var _gateway: WebSocketGateway
var _seed: MockWorldSeed
var _peers: Array[WebSocketPeer] = []
var _versions: Dictionary = {}
var _sequences: Dictionary = {}
var _now: int = 10_000_000
var _port: int = 19324
var _failures: int = 0


class TestAuthenticator extends ClientAuthenticator:
	var identities: Dictionary = {}
	func authenticate(token: String) -> Dictionary:
		return identities.get(token, {}).duplicate(true)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))
	var config: SssConfig = CONFIG.duplicate(true) as SssConfig
	config.port = _port
	_seed = SEED.duplicate(true) as MockWorldSeed
	_seed.ship_position = Vector2i(310, 290)
	_world = SolarSystemWorld.new(config, _seed)
	_world.set_now_provider(func() -> int: return _now)
	_world.add_mock_entity("p2ship", "ship", Vector2i(310, 290), {"player_id": "p2", "system_id": _seed.system_id})
	_world.acknowledge_changes()
	var auth := TestAuthenticator.new()
	auth.identities = {"p1": {"player_id": _seed.player_id, "system_id": _seed.system_id},
		"p2": {"player_id": "p2", "system_id": _seed.system_id}}
	_gateway = WebSocketGateway.new(config, auth, _world)
	root.add_child(_gateway)
	if _gateway.start() != OK:
		_check(false, "puerto disponible")
		_finish()
		return
	var first: WebSocketPeer = await _open("team3-m3.0")
	var other: WebSocketPeer = await _open("team3-m3.0")
	var legacy: WebSocketPeer = await _open("team3-m2.0")
	if first == null or other == null or legacy == null:
		_finish()
		return
	_send(first, _start(1))
	_check_error(await _receive(first), "MINING_NOT_AUTHENTICATED", "start_mining")
	var full: Dictionary = await _authenticate(first, "p1")
	_check(_entity(full.get("added", []), ASTEROID).get("remaining_quantity") == 10, "snapshot M3 con asteroide")
	await _authenticate(other, "p2")
	full = await _authenticate(legacy, "p1")
	_check(not _entity(full.get("added", []), ASTEROID).has("remaining_quantity"), "snapshot M2 mantiene forma previa")
	_send(legacy, _start(1))
	_check((await _receive(legacy)).get("error_code") == "ERR_UNKNOWN_MESSAGE", "M2 no admite minería")
	_send(legacy, {"type": "ping", "protocol_version": "team3-m3.0"})
	_check((await _receive(legacy)).get("error_code") == "ERR_PROTOCOL_VERSION", "versión fijada al autenticar")
	var forged: Dictionary = _start(1)
	forged["entity_id"] = "p2ship"
	_send(first, forged)
	_check_error(await _receive(first), "MINING_INVALID_REQUEST", "start_mining")
	_send(first, {"type": "start_mining", "request_id": _id(1), "asteroid_entity_id": [ASTEROID]})
	_check_error(await _receive(first), "MINING_INVALID_REQUEST", "start_mining")
	_send(first, {"type": "stop_mining", "mining_id": 123})
	_check_error(await _receive(first), "MINING_INVALID_REQUEST", "stop_mining")
	_send(first, _start(1))
	await _barrier(first)
	var readers: Array[WebSocketPeer] = [first, other, legacy]
	var deltas: Array[Dictionary] = await _flush_receive(readers)
	var mining: Dictionary = _entity(deltas[0]["updated"], _seed.entity_id).get("mining", {})
	var mining_id: String = str(mining.get("mining_id", ""))
	_check(not mining_id.is_empty() and mining.get("status") == "ACTIVE", "aceptación sólo por delta")
	_check(_entity(deltas[1]["updated"], ASTEROID).get("occupant_entity_id") == _seed.entity_id, "ocupación visible al otro jugador")
	_check(not _entity(deltas[2]["updated"], _seed.entity_id).has("mining"), "sesión M2 no recibe bloques nuevos")
	_send(other, _start(2))
	_check_error(await _receive(other), "MINING_ASTEROID_OCCUPIED", "start_mining")
	_send(other, {"type": "stop_mining", "mining_id": mining_id})
	_check_error(await _receive(other), "MINING_NOT_OWNER", "stop_mining")
	var replacement: WebSocketPeer = await _open("team3-m3.0")
	if replacement == null:
		_finish()
		return
	full = await _authenticate(replacement, "p1")
	_check(_entity(full.get("added", []), _seed.entity_id)["mining"]["mining_id"] == mining_id, "segunda sesión reconstruye misma operación")
	first.close()
	readers = [replacement, other, legacy]
	_now += 2500
	deltas = await _flush_receive(readers)
	_check(_entity(deltas[0]["updated"], _seed.entity_id)["mining"]["extracted_quantity"] == 2, "continúa extracción desconectado")
	_send(replacement, _start(1))
	await _barrier(replacement)
	deltas = await _flush_receive(readers)
	_check(_entity(deltas[0]["updated"], _seed.entity_id)["mining"]["mining_id"] == mining_id, "reintento tras reconexión no duplica")
	_now += 7500
	deltas = await _flush_receive(readers)
	var completed: Dictionary = _entity(deltas[0]["updated"], _seed.entity_id)
	_check(completed.get("mining") == null and completed["last_mining_result"]["quantity"] == 10, "resultado completo autoritativo")
	_check(_entity(deltas[0]["updated"], ASTEROID)["asteroid_state"] == "DEPLETED", "agotamiento publicado")
	_send(replacement, _start(1))
	var replay: Dictionary = await _receive(replacement)
	_check(replay.get("type") == "mining_replay" and replay["result"]["mining_id"] == mining_id, "replay terminal conserva identidad")
	_send(replacement, _start(3))
	_check_error(await _receive(replacement), "MINING_DEPLETED", "start_mining")
	_send(replacement, {"type": "stop_mining", "mining_id": mining_id})
	_check((await _receive(replacement)).get("type") == "mining_replay", "parada terminal sin consecuencia repetida")
	_world.set_asteroid_resource_state(ASTEROID, 10, "") # Fixture, no respawn de runtime.
	_send(replacement, _start(4))
	await _barrier(replacement)
	deltas = await _flush_receive(readers)
	var next_id: String = _entity(deltas[0]["updated"], _seed.entity_id)["mining"]["mining_id"]
	_now += 1500
	_send(replacement, {"type": "stop_mining", "mining_id": next_id})
	await _barrier(replacement)
	deltas = await _flush_receive(readers)
	var cancelled: Dictionary = _entity(deltas[0]["updated"], _seed.entity_id)["last_mining_result"]
	_check(cancelled["quantity"] == 1 and cancelled["reason"] == "USER_CANCELLED", "parada liquida por tiempo")
	_send(replacement, _start(1))
	replay = await _receive(replacement)
	_check(replay["result"]["quantity"] == 10, "replay antiguo conserva resultado original")
	_send(replacement, {"type": "full_snapshot"})
	full = await _receive(replacement)
	_check(_entity(full.get("added", []), _seed.entity_id)["last_mining_result"]["mining_id"] == next_id, "replay no sobrescribe último resultado del mundo")
	_check((_world.entity_registry.get_entity(ASTEROID) as AsteroidState).remaining_quantity == 9, "sin extracción duplicada")
	_finish()


func _open(version: String) -> WebSocketPeer:
	var peer := WebSocketPeer.new()
	_peers.append(peer)
	_versions[peer.get_instance_id()] = version
	if peer.connect_to_url("ws://127.0.0.1:%d" % _port) != OK:
		_check(false, "conexión iniciada")
		return null
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return peer
		await process_frame
	_check(false, "WebSocket abierto antes del timeout")
	return null


func _authenticate(peer: WebSocketPeer, token: String) -> Dictionary:
	_send(peer, {"type": "auth", "jwt": token})
	_check((await _receive(peer)).get("type") == "auth_ok", "auth mock de test")
	_send(peer, {"type": "full_snapshot"})
	return await _receive(peer)


func _barrier(peer: WebSocketPeer) -> void:
	_send(peer, {"type": "ping", "client_time": 1})
	_check((await _receive(peer)).get("type") == "pong", "orden de intenciones antes del tick")


func _flush_receive(readers: Array[WebSocketPeer]) -> Array[Dictionary]:
	_world.tick()
	_gateway.flush_pending_deltas()
	_world.acknowledge_changes()
	var messages: Array[Dictionary] = []
	for peer: WebSocketPeer in readers:
		var message: Dictionary = await _receive(peer)
		_check(message.get("type") == "map_delta", "estado recibido por delta")
		messages.append(message)
	return messages


func _send(peer: WebSocketPeer, message: Dictionary) -> void:
	if not message.has("protocol_version"):
		message["protocol_version"] = _versions[peer.get_instance_id()]
	_check(peer.send_text(JSON.stringify(message)) == OK, "mensaje enviado")


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
			_check(message.get("seq") == expected, "seq común y continuo")
			_sequences[key] = expected
			_check(message.get("protocol_version") == _versions[key] and message.has("server_time"), "sobre de versión de sesión")
			return message
		await process_frame
	_check(false, "respuesta dentro de timeout")
	return {}


func _start(index: int) -> Dictionary:
	return {"type": "start_mining", "request_id": _id(index), "asteroid_entity_id": ASTEROID}


func _id(index: int) -> String:
	return "00000000-0000-4000-8000-%012d" % index


func _entity(entities: Array, entity_id: String) -> Dictionary:
	for entity: Dictionary in entities:
		if entity.get("entity_id") == entity_id:
			return entity
	return {}


func _check_error(message: Dictionary, code: String, request_type: String) -> void:
	_check(message.get("type") == "error" and message.get("error_code") == code, "rechazo %s" % code)
	_check(message.get("request_type") == request_type, "error correlacionado sin código Travel")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("MINING_GATEWAY_TEST_FAILED: %s" % message)


func _finish() -> void:
	for peer: WebSocketPeer in _peers:
		peer.close()
	if _gateway != null:
		_gateway.stop()
		_gateway.free()
	print("MINING_GATEWAY_TEST_OK" if _failures == 0 else "MINING_GATEWAY_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
