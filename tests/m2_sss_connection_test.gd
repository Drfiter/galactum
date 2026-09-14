extends SceneTree
## Contrato saliente exacto y separación server_error/protocol_error.

var _failures: int = 0
var _server_errors: int = 0
var _protocol_errors: int = 0

class FakeSssConnection extends SssConnection:
	var sent_messages: Array[Dictionary] = []

	func authenticate_for_test() -> void:
		_state = State.AUTHENTICATED

	func _send(payload: Dictionary) -> bool:
		sent_messages.append(payload.duplicate(true))
		return true


func _initialize() -> void:
	_test_start_travel_payload()
	_test_single_pending_request()
	_test_error_separation()
	if _failures == 0:
		print("M2_SSS_CONNECTION_TEST_OK")
		quit(0)
	else:
		print("M2_SSS_CONNECTION_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _test_start_travel_payload() -> void:
	var payload: Dictionary = SssConnection._build_start_travel_payload(Vector2i(420, 180))
	_check(payload == {
		"type": "start_travel",
		"protocol_version": "team3-m2.0",
		"destination": [420, 180],
	}, "payload start_travel exacto")
	_check(not payload.has("entity_id"), "payload no contiene entity_id")
	_check(not payload.has("request_id"), "payload no contiene request_id")


func _test_single_pending_request() -> void:
	var connection := FakeSssConnection.new()
	connection.authenticate_for_test()
	_check(connection.request_start_travel(Vector2i(420, 180)), "primera intención se envía")
	_check(not connection.request_start_travel(Vector2i(100, 100)), "segunda intención pendiente se bloquea")
	_check(connection.sent_messages.size() == 1, "start_travel se envía exactamente una vez")
	_check(connection.sent_messages[0] == {
		"type": "start_travel",
		"protocol_version": "team3-m2.0",
		"destination": [420, 180],
	}, "mensaje enviado coincide exactamente con contrato")
	connection.resolve_start_travel_request()
	_check(connection.request_start_travel(Vector2i(100, 100)), "nueva intención permitida tras resolución")
	connection.free()


func _test_error_separation() -> void:
	var connection := SssConnection.new()
	connection.server_error.connect(_on_server_error)
	connection.protocol_error.connect(_on_protocol_error)
	connection.call("_handle_packet", JSON.stringify({
		"type": "error",
		"protocol_version": "team3-m2.0",
		"seq": 1,
		"server_time": 1780000000000,
		"error_code": "INVALID_DESTINATION",
		"message": "Destination rejected",
	}))
	_check(_server_errors == 1, "rechazo genera server_error")
	_check(_protocol_errors == 0, "rechazo no genera protocol_error")
	connection.call("_handle_packet", JSON.stringify({
		"type": "pong",
		"protocol_version": "otra-version",
		"seq": 2,
		"server_time": 1780000000001,
	}))
	_check(_protocol_errors == 1, "versión incompatible genera protocol_error")
	connection.free()


func _on_server_error(_payload: Dictionary) -> void:
	_server_errors += 1


func _on_protocol_error(_message: String) -> void:
	_protocol_errors += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M2_SSS_CONNECTION_TEST_FAILED: %s" % message)
