extends SceneTree
## Smoke E2E de TEAM3-M1 contra el SSS headless real.
## Ejecutar mediante tools/run_m1_smoke.ps1.

const PROTOCOL_VERSION: String = "team3-m1.0"
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
var _entity_count: int = 0


func _initialize() -> void:
	_read_arguments()
	var error: Error = _peer.connect_to_url("ws://%s:%d" % [_host, _port])
	if error != OK:
		_fail("connect_to_url fallo: %s" % error_string(error))
		return
	print("M1_SMOKE connecting ws://%s:%d" % [_host, _port])


func _process(delta: float) -> bool:
	_elapsed += delta
	if _elapsed > TIMEOUT_SECONDS:
		_fail("timeout esperando full_snapshot y pong")
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
			_fail("conexion cerrada antes de completar el smoke: %s" % _peer.get_close_reason())
	return false


func _handle_message(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		_fail("respuesta no es objeto JSON")
		return
	var message: Dictionary = parsed
	if str(message.get("protocol_version", "")) != PROTOCOL_VERSION:
		_fail("protocol_version incorrecto: %s" % message.get("protocol_version", ""))
		return
	var incoming_seq: int = int(message.get("seq", 0))
	if incoming_seq <= _last_seq:
		_fail("seq no es creciente: anterior=%d actual=%d" % [_last_seq, incoming_seq])
		return
	if int(message.get("server_time", 0)) <= 0:
		_fail("server_time ausente")
		return
	_last_seq = incoming_seq

	match str(message.get("type", "")):
		"auth_ok":
			if _authenticated:
				_fail("auth_ok duplicado")
				return
			if str(message.get("player_id", "")) == "" or str(message.get("system_id", "")) == "":
				_fail("auth_ok sin IDs")
				return
			if str(message.get("auth_mode", "")) != "mock":
				_fail("auth_mode no es mock")
				return
			_authenticated = true
			_send({"type": "full_snapshot"})
		"map_delta":
			if not _authenticated:
				_fail("map_delta recibido antes de auth_ok")
				return
			_validate_snapshot(message)
		"pong":
			_validate_pong(message)
		"error":
			_fail("SSS error %s: %s" % [message.get("error_code", ""), message.get("message", "")])
		_:
			_fail("tipo de mensaje inesperado: %s" % message.get("type", ""))


func _validate_snapshot(message: Dictionary) -> void:
	if not bool(message.get("full", false)):
		_fail("map_delta no es full snapshot")
		return
	if str(message.get("system_id", "")) == "":
		_fail("full_snapshot sin system_id")
		return
	var map_size: Array = message.get("map_size", [])
	if map_size.size() != 2 or int(map_size[0]) != 600 or int(map_size[1]) != 600:
		_fail("map_size no es 600x600: %s" % str(map_size))
		return
	var added: Array = message.get("added", [])
	if added.size() < 2:
		_fail("snapshot no contiene multiples entidades: %d" % added.size())
		return
	var kinds: Dictionary = {}
	for raw_entity: Variant in added:
		if not raw_entity is Dictionary:
			_fail("added contiene una entidad no valida")
			return
		var entity: Dictionary = raw_entity
		if str(entity.get("entity_id", "")) == "":
			_fail("entidad sin entity_id")
			return
		kinds[str(entity.get("kind", ""))] = true
	for expected_kind: String in ["ship", "asteroid", "xenoform"]:
		if not kinds.has(expected_kind):
			_fail("snapshot sin tipo esperado: %s" % expected_kind)
			return
	if not message.get("updated", []).is_empty() or not message.get("removed", []).is_empty():
		_fail("full_snapshot inicial contiene updated/removed")
		return
	_snapshot_seq = int(message["seq"])
	_snapshot_server_time = int(message["server_time"])
	_entity_count = added.size()
	_waiting_for_pong = true
	_send({"type": "ping", "client_time": Time.get_ticks_msec()})


func _validate_pong(message: Dictionary) -> void:
	if not _waiting_for_pong or int(message.get("client_time", 0)) <= 0:
		_fail("pong invalido o inesperado")
		return
	if int(message["seq"]) <= _snapshot_seq:
		_fail("seq de pong no crece respecto al snapshot")
		return
	print("M1_SMOKE_OK protocol=%s snapshot_seq=%d pong_seq=%d server_time=%d entities=%d" % [
		message["protocol_version"],
		_snapshot_seq,
		int(message["seq"]),
		_snapshot_server_time,
		_entity_count,
	])
	_peer.close(1000, "smoke complete")
	quit(0)


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
	push_error("M1_SMOKE_FAILED: %s" % message)
	quit(1)
