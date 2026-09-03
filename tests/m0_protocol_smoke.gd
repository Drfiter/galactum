extends SceneTree

const PROTOCOL_VERSION: String = "team3-m0.1"
const DEFAULT_HOST: String = "127.0.0.1"
const DEFAULT_PORT: int = 9100
const MOCK_TOKEN: String = "team3-m0-local-player"
const TIMEOUT_SECONDS: float = 8.0

var _peer := WebSocketPeer.new()
var _host: String = DEFAULT_HOST
var _port: int = DEFAULT_PORT
var _elapsed: float = 0.0
var _last_seq: int = 0
var _auth_sent: bool = false
var _authenticated: bool = false
var _waiting_for_pong: bool = false
var _snapshot_seq: int = 0
var _snapshot_server_time: int = 0
var _snapshot_entity_id: String = ""


func _initialize() -> void:
	_read_arguments()
	var error: Error = _peer.connect_to_url("ws://%s:%d" % [_host, _port])
	if error != OK:
		_fail("connect_to_url fallo: %s" % error_string(error))
		return
	print("M0_SMOKE connecting ws://%s:%d" % [_host, _port])


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		_fail("timeout esperando full_snapshot")
		return true
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _auth_sent:
				_send({"type": "auth", "jwt": MOCK_TOKEN})
				_auth_sent = true
			while _peer.get_available_packet_count() > 0:
				_handle_message(_peer.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_fail("conexion cerrada antes del snapshot: %s" % _peer.get_close_reason())
	return false


func _handle_message(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		_fail("respuesta no es objeto JSON")
		return
	var message: Dictionary = parsed
	if str(message.get("protocol_version", "")) != PROTOCOL_VERSION:
		_fail("protocol_version incorrecto")
		return
	var incoming_seq: int = int(message.get("seq", 0))
	if incoming_seq <= _last_seq:
		_fail("seq no es creciente")
		return
	if int(message.get("server_time", 0)) <= 0:
		_fail("server_time ausente")
		return
	_last_seq = incoming_seq
	match str(message.get("type", "")):
		"auth_ok":
			if str(message.get("player_id", "")) == "" or str(message.get("system_id", "")) == "":
				_fail("auth_ok sin IDs")
				return
			_authenticated = true
			_send({"type": "full_snapshot"})
		"map_delta":
			_validate_snapshot(message)
		"pong":
			if not _waiting_for_pong or int(message.get("client_time", 0)) <= 0:
				_fail("pong invalido")
				return
			print("M0_SMOKE_OK protocol=%s snapshot_seq=%d pong_seq=%d server_time=%d entity_id=%s" % [
				message["protocol_version"],
				_snapshot_seq,
				int(message["seq"]),
				_snapshot_server_time,
				_snapshot_entity_id,
			])
			_peer.close(1000, "smoke complete")
			quit(0)
		"error":
			_fail("SSS error %s: %s" % [message.get("error_code", ""), message.get("message", "")])


func _validate_snapshot(message: Dictionary) -> void:
	if not bool(message.get("full", false)):
		_fail("map_delta no es full snapshot")
		return
	var map_size: Array = message.get("map_size", [])
	if map_size.size() != 2 or int(map_size[0]) != 600 or int(map_size[1]) != 600:
		_fail("map_size no es 600x600: %s" % str(map_size))
		return
	var added: Array = message.get("added", [])
	if added.size() != 1 or not added[0] is Dictionary:
		_fail("snapshot no contiene exactamente una nave dummy")
		return
	var ship: Dictionary = added[0]
	if str(ship.get("kind", "")) != "ship":
		_fail("entidad dummy no es ship")
		return
	var ids: Array[String] = [
		str(ship.get("player_id", "")),
		str(ship.get("ship_id", "")),
		str(ship.get("entity_id", "")),
		str(ship.get("system_id", "")),
	]
	for identifier: String in ids:
		if identifier == "":
			_fail("snapshot contiene un ID vacio")
			return
	var unique_ids: Dictionary = {}
	for identifier: String in ids:
		unique_ids[identifier] = true
	if unique_ids.size() != ids.size():
		_fail("player_id, ship_id, entity_id y system_id no son distintos")
		return
	_snapshot_seq = int(message["seq"])
	_snapshot_server_time = int(message["server_time"])
	_snapshot_entity_id = str(ship["entity_id"])
	_waiting_for_pong = true
	_send({"type": "ping", "client_time": Time.get_ticks_msec()})


func _send(payload: Dictionary) -> void:
	var message: Dictionary = payload.duplicate(true)
	message["protocol_version"] = PROTOCOL_VERSION
	_peer.send_text(JSON.stringify(message))


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--host="):
			_host = argument.trim_prefix("--host=")
		elif argument.begins_with("--port="):
			var raw_port: String = argument.trim_prefix("--port=")
			if raw_port.is_valid_int():
				_port = clampi(int(raw_port), 1, 65535)


func _fail(message: String) -> void:
	push_error("M0_SMOKE_FAILED: %s" % message)
	quit(1)
