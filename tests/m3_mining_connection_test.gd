extends SceneTree

var _failures: int = 0


class RecordingConnection extends SssConnection:
	var sent: Array[Dictionary] = []
	func setup() -> void:
		_config = ClientConnectionConfig.new()
		_config.protocol_version = MINING_PROTOCOL_VERSION
		_state = State.AUTHENTICATED
		_has_world_snapshot = true
	func _send(payload: Dictionary) -> bool:
		sent.append(payload.duplicate(true))
		return true


func _initialize() -> void:
	var connection := RecordingConnection.new()
	connection.setup()
	var action: Dictionary = {"type": "start_mining", "request_id": "req", "asteroid_entity_id": "a", "player_id": "forged"}
	_check(connection.request_mining(action), "intención M3 enviada")
	_check(connection.sent[0] == {"type": "start_mining", "protocol_version": "team3-m3.0", "request_id": "req", "asteroid_entity_id": "a"}, "payload mínimo sin campos autoritativos")
	_check(not connection.request_start_travel(Vector2i(1, 2)), "minería pendiente bloquea Travel")
	_packet(connection, 1, {"type": "error", "error_code": "MINING_OUT_OF_RANGE", "request_type": "start_mining", "request_id": "old"})
	_check(connection.is_action_pending(), "error antiguo no resuelve")
	_packet(connection, 2, {"type": "error", "error_code": "MINING_OUT_OF_RANGE", "request_type": "start_mining", "request_id": "req"})
	_check(not connection.is_action_pending(), "rechazo coincidente resuelve")
	_check(connection.request_start_travel(Vector2i(1, 2)), "Travel permitido tras resolución")
	_check(connection.sent[-1]["protocol_version"] == "team3-m3.0" and not connection.sent[-1].has("request_id"), "viaje M3 conserva forma M2")
	_check(not connection.request_mining(action), "Travel pendiente bloquea minería")
	_packet(connection, 3, {"type": "error", "error_code": "MINING_DEPLETED", "request_type": "start_mining", "request_id": "req"})
	_check(connection.is_start_travel_pending(), "error minería no resuelve Travel")
	connection.resolve_start_travel_request()
	_packet(connection, 5, {"type": "pong"})
	_check(not connection.request_mining(action), "desync bloquea acciones")
	_packet(connection, 6, {"type": "map_delta", "full": true})
	_check(connection.request_mining(action), "snapshot recupera continuidad")
	connection._reset_sequence_tracking()
	_check(not connection.is_action_pending() and not connection.request_mining(action), "nueva conexión requiere snapshot")
	connection.free()
	print("M3_MINING_CONNECTION_TEST_OK" if _failures == 0 else "M3_MINING_CONNECTION_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _packet(connection: SssConnection, seq: int, payload: Dictionary) -> void:
	payload.merge({"protocol_version": "team3-m3.0", "seq": seq, "server_time": 1780000000000})
	connection.call("_handle_packet", JSON.stringify(payload))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_MINING_CONNECTION_TEST_FAILED: %s" % message)
