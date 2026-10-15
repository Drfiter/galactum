extends SceneTree
## TEAM3-M3 ETAPA 4: payload, correlación y separación Combat/Travel.

var _failures: int = 0
var _combat_results: int = 0


class FakeSssConnection extends SssConnection:
	var sent_messages: Array[Dictionary] = []

	func authenticate_for_test() -> void:
		_state = State.AUTHENTICATED
		_has_world_snapshot = true

	func _send(payload: Dictionary) -> bool:
		sent_messages.append(payload.duplicate(true))
		return true


func _initialize() -> void:
	_test_exact_payload_and_unique_request_ids()
	_test_error_domains_and_result()
	_test_reconnect_clears_pending_attack()
	_test_mining_and_combat_share_pending()
	_finish()


func _test_exact_payload_and_unique_request_ids() -> void:
	var fixed: Dictionary = SssConnection._build_attack_payload("target-1", "request-fixed")
	_check(fixed == {
		"type": "attack",
		"protocol_version": "team3-m2.0",
		"request_id": "request-fixed",
		"target_entity_id": "target-1",
	}, "payload attack exacto")
	for forbidden: String in ["attacker", "attacker_entity_id", "player_id", "ship_id", "units", "damage", "outcome"]:
		_check(not fixed.has(forbidden), "payload no contiene %s" % forbidden)

	var connection := FakeSssConnection.new()
	connection.authenticate_for_test()
	var first_id: String = connection.request_attack("target-1")
	_check(not first_id.is_empty(), "genera request_id para primera intención")
	_check(connection.is_attack_pending() and connection.pending_attack_request_id() == first_id,
		"conexión conserva correlación pendiente")
	_check(connection.sent_messages.size() == 1, "envía exactamente un attack")
	_check(connection.sent_messages[0] == SssConnection._build_attack_payload("target-1", first_id),
		"mensaje enviado coincide con contrato")
	_check(connection.request_attack("target-2") == "", "bloquea segunda intención pendiente")
	connection.resolve_attack_request(first_id)
	var second_id: String = connection.request_attack("target-2")
	_check(not second_id.is_empty() and second_id != first_id, "cada intención usa request_id único")
	connection.free()


func _test_error_domains_and_result() -> void:
	var connection := FakeSssConnection.new()
	connection.authenticate_for_test()
	connection.combat_result_received.connect(func(_payload: Dictionary) -> void: _combat_results += 1)
	_check(connection.request_start_travel(Vector2i(420, 180)), "Travel pendiente para prueba de separación")
	_check(connection.request_attack("target-1") == "", "Travel pendiente bloquea attack")
	# Inyectar ambos dominios para comprobar aislamiento incluso ante respuestas antiguas.
	var attack_id: String = "attack-fixture-1"
	connection._attack_pending_request_id = attack_id
	connection.call("_handle_packet", JSON.stringify(_envelope({
		"type": "error",
		"request_type": "attack",
		"request_id": attack_id,
		"error_code": "INVALID_REQUEST",
		"message": "Combat rejected",
	}, 1)))
	_check(not connection.is_attack_pending(), "error Combat limpia sólo Combat")
	_check(connection.is_start_travel_pending(), "error Combat no resuelve Travel aunque comparta código")

	connection.resolve_start_travel_request()
	var second_attack_id: String = connection.request_attack("target-2")
	_check(not second_attack_id.is_empty(), "Combat disponible al resolver Travel")
	_check(not connection.request_start_travel(Vector2i(420, 180)), "Combat pendiente bloquea Travel")
	connection._start_travel_pending = true
	connection.call("_handle_packet", JSON.stringify(_envelope({
		"type": "error",
		"error_code": "INVALID_DESTINATION",
		"message": "Travel rejected",
	}, 2)))
	_check(connection.is_attack_pending(), "error Travel no resuelve Combat")
	_check(not connection.is_start_travel_pending(), "error Travel mantiene comportamiento M2")

	connection.call("_handle_packet", JSON.stringify(_envelope({
		"type": "combat_result",
		"request_id": second_attack_id,
		"combat_id": "combat-1",
		"combat_version": "m3-provisional-1",
		"attacker": {},
		"defender": {},
		"outcome": "draw",
		"casualties": {"attacker": [], "defender": []},
		"remaining_forces": {"attacker": [], "defender": []},
	}, 3)))
	_check(_combat_results == 1, "combat_result se publica al estado cliente")
	_check(not connection.is_attack_pending(), "resultado correlacionado limpia pendiente")
	connection.free()


func _test_reconnect_clears_pending_attack() -> void:
	var connection := FakeSssConnection.new()
	connection.authenticate_for_test()
	_check(not connection.request_attack("target-1").is_empty(), "crea pendiente antes de reconnect")
	connection.call("_reset_sequence_tracking")
	_check(not connection.is_attack_pending() and connection.pending_attack_request_id() == "",
		"nueva conexión no conserva pendiente falsa")
	connection.free()


func _test_mining_and_combat_share_pending() -> void:
	var connection := FakeSssConnection.new()
	connection._config = ClientConnectionConfig.new()
	connection._config.protocol_version = "team3-m3.0"
	connection.authenticate_for_test()
	var action: Dictionary = {"type": "start_mining", "request_id": "00000000-0000-4000-8000-000000000001", "asteroid_entity_id": "asteroid"}
	_check(connection.request_mining(action), "M3 inicia intención minera")
	_check(connection.request_attack("target") == "", "minería pendiente bloquea ataque")
	connection.resolve_mining_request()
	var request_id: String = connection.request_attack("target")
	_check(not request_id.is_empty(), "M3 admite combate")
	_check(connection.sent_messages[-1]["protocol_version"] == "team3-m3.0", "attack usa versión negociada")
	_check(not connection.request_mining(action), "ataque pendiente bloquea minería")
	connection.free()


func _envelope(body: Dictionary, seq: int) -> Dictionary:
	var message: Dictionary = body.duplicate(true)
	message["protocol_version"] = "team3-m2.0"
	message["seq"] = seq
	message["server_time"] = 1780000000000 + seq
	return message


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_COMBAT_CONNECTION_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("M3_COMBAT_CONNECTION_TEST_OK" if _failures == 0 else "M3_COMBAT_CONNECTION_TEST_FAILED failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)
