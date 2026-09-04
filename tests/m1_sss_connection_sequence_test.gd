extends SceneTree
## Regresion minima de continuidad, desync y re-baseline de SssConnection.

var _failures: int = 0
var _desync_count: int = 0
var _protocol_errors: int = 0
var _full_snapshots: int = 0


func _initialize() -> void:
	var connection := SssConnection.new()
	connection.desync_detected.connect(_on_desync_detected)
	connection.protocol_error.connect(_on_protocol_error)
	connection.full_snapshot_received.connect(_on_full_snapshot)

	connection.call("_handle_packet", _message("auth_ok", 1))
	connection.call("_handle_packet", _message("pong", 2))
	connection.call("_handle_packet", _message("pong", 3))
	_check(_desync_count == 0, "1 -> 2 -> 3 debe ser valido")

	connection.call("_reset_sequence_tracking")
	connection.call("_handle_packet", _message("auth_ok", 1))
	connection.call("_handle_packet", _message("pong", 3))
	_check(_desync_count == 1, "1 -> 3 debe detectar desync")
	_check(_protocol_errors == 1, "el gap debe emitir un error de protocolo")

	var snapshot: Dictionary = _message_dictionary("map_delta", 7)
	snapshot.merge({
		"full": true,
		"map_size": [600, 600],
		"added": [],
		"updated": [],
		"removed": [],
	})
	connection.call("_handle_packet", JSON.stringify(snapshot))
	connection.call("_handle_packet", _message("pong", 8))
	_check(_full_snapshots == 1, "full_snapshot posterior debe recibirse")
	_check(_desync_count == 1, "full_snapshot debe re-baselinear para aceptar seq 8")
	_check(_protocol_errors == 1, "no debe haber error adicional despues del re-baseline")

	connection.free()
	if _failures == 0:
		print("M1_SSS_CONNECTION_SEQUENCE_TEST_OK")
		quit(0)
	else:
		print("M1_SSS_CONNECTION_SEQUENCE_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _message(type: String, seq: int) -> String:
	return JSON.stringify(_message_dictionary(type, seq))


func _message_dictionary(type: String, seq: int) -> Dictionary:
	return {
		"type": type,
		"protocol_version": SssConnection.PROTOCOL_VERSION,
		"seq": seq,
		"server_time": 1780000000000 + seq,
		"client_time": 1,
		"player_id": "player-test",
		"system_id": "system-test",
	}


func _on_desync_detected() -> void:
	_desync_count += 1


func _on_protocol_error(_message_text: String) -> void:
	_protocol_errors += 1


func _on_full_snapshot(_payload: Dictionary) -> void:
	_full_snapshots += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M1_SSS_CONNECTION_SEQUENCE_TEST_FAILED: %s" % message)
