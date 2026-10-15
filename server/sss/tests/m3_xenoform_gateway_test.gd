extends SceneTree
## WebSocket real: baselines independientes, envelope, delta y reconstrucción.
## No crea mensajes de debug, UI ni consumidores Combat.

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
var _failures: int = 0
var _world: SolarSystemWorld
var _gateway: WebSocketGateway
var _peers: Array[WebSocketPeer] = []
var _sequences: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config: SssConfig = CONFIG.duplicate(true)
	var seed: MockWorldSeed = SEED.duplicate(true)
	_world = SolarSystemWorld.new(config, seed)
	for port: int in range(19300, 19400):
		config.port = port
		_gateway = WebSocketGateway.new(config, MockClientAuthenticator.new(seed), _world)
		root.add_child(_gateway)
		if _gateway.start() == OK:
			break
		_gateway.free()
		_gateway = null
	if _gateway == null:
		_check(false, "no hay puerto disponible para prueba local")
		_finish()
		return
	var first: WebSocketPeer = await _connect(config.port, seed.accepted_token)
	if first == null:
		_finish()
		return
	_send(first, "full_snapshot")
	var snapshot: Dictionary = await _receive(first)
	_check(snapshot.get("full", false), "snapshot inicial completo")
	var demo: EntityState = _world.entity_registry.get_entity(seed.xenoform_entity_id)
	_check(_entity(snapshot.get("added", []), demo.entity_id).get("state") == "IDLE", "Xenoform real recibido por WebSocket")
	var second: WebSocketPeer = await _connect(config.port, seed.accepted_token)
	if second == null:
		_finish()
		return
	var definition: XenoformConfig = (demo as XenoformState).get_configuration()
	var enemy: XenoformState = _world.spawn_xenoform("network-pve", definition, Vector2i(320, 320))
	_gateway.flush_pending_deltas()
	var delta: Dictionary = await _receive(first)
	_check(_entity(delta.get("added", []), "network-pve").get("xenoform") == {"config_id": "m3-demo-static"}, "creación runtime llega por added completo")
	_check(await _no_message(second), "no delta antes de snapshot inicial de segunda conexión")
	_send(second, "full_snapshot")
	var later_snapshot: Dictionary = await _receive(second)
	_check(not _entity(later_snapshot.get("added", []), "network-pve").is_empty(), "segunda sesión reconstruye estado actual")
	_gateway.flush_pending_deltas()
	_check(await _no_message(first) and await _no_message(second), "spawn ya publicado no se duplica")
	_world.acknowledge_changes()
	enemy.display_name = "Updated fixture"
	_world.change_set.update_entity(enemy)
	_gateway.flush_pending_deltas()
	var first_update: Dictionary = await _receive(first)
	var second_update: Dictionary = await _receive(second)
	_check(_entity(first_update.get("updated", []), "network-pve").get("display_name") == "Updated fixture", "datos específicos actualizados en sesión uno")
	_check(_entity(second_update.get("updated", []), "network-pve").get("display_name") == "Updated fixture", "sesión dos recibe mismo cambio sin drenar changeset")
	_world.acknowledge_changes()
	_world.set_entity_position(seed.entity_id, Vector2i(500, 500))
	_gateway.flush_pending_deltas()
	var first_exit: Dictionary = await _receive(first)
	var second_exit: Dictionary = await _receive(second)
	_check(first_exit.get("removed", []).has("network-pve") and second_exit.get("removed", []).has("network-pve"), "observador móvil retira enemigo de ambas réplicas")
	_check(_world.entity_registry.get_entity("network-pve") == enemy, "removed por AOI no destruye instancia")
	_world.acknowledge_changes()
	_world.set_entity_position(seed.entity_id, Vector2i(300, 300))
	_gateway.flush_pending_deltas()
	var first_entry: Dictionary = await _receive(first)
	await _receive(second)
	_check(_entity(first_entry.get("added", []), "network-pve").get("display_name") == "Updated fixture", "reentrada conserva datos actuales")
	_world.acknowledge_changes()
	# Snapshot explícito recupera baseline; cerrar y reconectar crea otro baseline/seq.
	_send(first, "full_snapshot")
	var rebuilt: Dictionary = await _receive(first)
	# JSON de Godot convierte números a float; expectativas literales de datos en red.
	var expected_enemy: Dictionary = {
		"entity_id": "network-pve", "kind": "xenoform", "system_id": seed.system_id,
		"position": [320.0, 320.0], "display_name": "Updated fixture", "state": "IDLE",
		"xenoform": {"config_id": "m3-demo-static"},
	}
	_check(rebuilt.get("full", false) and _entity(rebuilt.get("added", []), "network-pve") == expected_enemy, "full_snapshot reconstruye entidad completa actual")
	first.close(1000, "reconnect test")
	var third: WebSocketPeer = await _connect(config.port, seed.accepted_token)
	if third == null:
		_finish()
		return
	_send(third, "full_snapshot")
	var reconnected: Dictionary = await _receive(third)
	_check(_entity(reconnected.get("added", []), "network-pve") == expected_enemy, "conexión nueva reconstruye desde snapshot")
	_world.remove_xenoform("network-pve")
	_gateway.flush_pending_deltas()
	var removal: Dictionary = await _receive(third)
	_check(removal.get("removed", []) == ["network-pve"], "retirada explícita publicada")
	_check(removal.get("added", []).is_empty() and removal.get("updated", []).is_empty(), "categorías de delta disjuntas")
	_finish()


func _connect(port: int, token: String) -> WebSocketPeer:
	var peer := WebSocketPeer.new()
	_peers.append(peer)
	peer.connect_to_url("ws://127.0.0.1:%d" % port)
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			break
		await process_frame
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_check(false, "conexión WebSocket abierta")
		return null
	peer.send_text(JSON.stringify({"type": "auth", "protocol_version": "team3-m2.0", "jwt": token}))
	var response: Dictionary = await _receive(peer)
	_check(response.get("type") == "auth_ok" and response.get("seq") == 1, "auth y secuencia nueva")
	return peer


func _send(peer: WebSocketPeer, message_type: String) -> void:
	peer.send_text(JSON.stringify({"type": message_type, "protocol_version": "team3-m2.0"}))


func _receive(peer: WebSocketPeer) -> Dictionary:
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_available_packet_count() > 0:
			var message: Dictionary = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			var previous_seq: int = int(_sequences.get(peer, 0))
			_check(message.get("protocol_version") == "team3-m2.0" and message.has("server_time"), "sobre preservado")
			_check(int(message.get("seq", -1)) == previous_seq + 1, "secuencia continua por conexión")
			_sequences[peer] = int(message["seq"])
			return message
		await process_frame
	_check(false, "timeout esperando mensaje SSS")
	return {}


func _no_message(peer: WebSocketPeer) -> bool:
	var deadline: int = Time.get_ticks_msec() + 100
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_available_packet_count() > 0:
			return false
		await process_frame
	return true


func _entity(entities: Array, entity_id: String) -> Dictionary:
	for entity: Dictionary in entities:
		if entity.get("entity_id") == entity_id:
			return entity
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_XENOFORM_GATEWAY_TEST_FAILED: %s" % message)


func _finish() -> void:
	for peer: WebSocketPeer in _peers:
		peer.close()
	if _gateway != null:
		_gateway.stop()
		_gateway.free()
	_sequences.clear()
	print("M3_XENOFORM_GATEWAY_TEST_OK" if _failures == 0 else "M3_XENOFORM_GATEWAY_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
