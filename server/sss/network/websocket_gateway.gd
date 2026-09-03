class_name WebSocketGateway
extends Node

var _config: SssConfig
var _authenticator: ClientAuthenticator
var _world: SolarSystemWorld
var _tcp_server := TCPServer.new()
var _sessions: Dictionary = {}
var _next_session_id: int = 1


func _init(config: SssConfig, authenticator: ClientAuthenticator, world: SolarSystemWorld) -> void:
	_config = config
	_authenticator = authenticator
	_world = world


func start() -> Error:
	var error: Error = _tcp_server.listen(_config.port)
	if error == OK:
		set_process(true)
	return error


func stop() -> void:
	for session_id: Variant in _sessions.keys():
		var session: Dictionary = _sessions[session_id]
		var peer: WebSocketPeer = session["peer"]
		peer.close(1001, "server stopping")
	_sessions.clear()
	_tcp_server.stop()
	set_process(false)


func _process(_delta: float) -> void:
	while _tcp_server.is_connection_available():
		_accept_connection()
	for raw_session_id: Variant in _sessions.keys().duplicate():
		var session_id: int = int(raw_session_id)
		var session: Dictionary = _sessions[session_id]
		var peer: WebSocketPeer = session["peer"]
		peer.poll()
		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while peer.get_available_packet_count() > 0:
					_handle_packet(session_id, peer.get_packet().get_string_from_utf8())
			WebSocketPeer.STATE_CLOSED:
				_sessions.erase(session_id)


func _accept_connection() -> void:
	var stream: StreamPeerTCP = _tcp_server.take_connection()
	var peer := WebSocketPeer.new()
	var error: Error = peer.accept_stream(stream)
	if error != OK:
		stream.disconnect_from_host()
		return
	_sessions[_next_session_id] = {
		"peer": peer,
		"authenticated": false,
		"player_id": "",
		"system_id": "",
		"seq": 0,
	}
	_next_session_id += 1


func _handle_packet(session_id: int, raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		_send_error(session_id, "ERR_INVALID_JSON", "Expected a JSON object")
		return
	var message: Dictionary = parsed
	if str(message.get("protocol_version", "")) != _config.protocol_version:
		_send_error(session_id, "ERR_PROTOCOL_VERSION", "Unsupported protocol_version")
		return

	var session: Dictionary = _sessions[session_id]
	var message_type: String = str(message.get("type", ""))
	if message_type == "auth":
		_handle_auth(session_id, message)
		return
	if not bool(session.get("authenticated", false)):
		_send_error(session_id, "ERR_NOT_AUTHENTICATED", "Authenticate first")
		return

	match message_type:
		"full_snapshot":
			var snapshot: Dictionary = _world.full_snapshot_for(str(session.get("player_id", "")))
			snapshot["type"] = "map_delta"
			_send(session_id, snapshot)
		"ping":
			_send(session_id, {
				"type": "pong",
				"client_time": int(message.get("client_time", 0)),
			})
		_:
			_send_error(session_id, "ERR_UNKNOWN_MESSAGE", "Unsupported TEAM3-M0 message")


func _handle_auth(session_id: int, message: Dictionary) -> void:
	var identity: Dictionary = _authenticator.authenticate(str(message.get("jwt", "")))
	if identity.is_empty():
		_send_error(session_id, "ERR_MOCK_AUTH", "Mock authentication failed")
		return
	var session: Dictionary = _sessions[session_id]
	session["authenticated"] = true
	session["player_id"] = str(identity.get("player_id", ""))
	session["system_id"] = str(identity.get("system_id", ""))
	_sessions[session_id] = session
	_send(session_id, {
		"type": "auth_ok",
		"player_id": session["player_id"],
		"system_id": session["system_id"],
		"auth_mode": "mock",
	})


func _send_error(session_id: int, error_code: String, message: String) -> void:
	_send(session_id, {
		"type": "error",
		"error_code": error_code,
		"message": message,
	})


func _send(session_id: int, payload: Dictionary) -> void:
	if not _sessions.has(session_id):
		return
	var session: Dictionary = _sessions[session_id]
	var peer: WebSocketPeer = session["peer"]
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	session["seq"] = int(session.get("seq", 0)) + 1
	_sessions[session_id] = session
	var message: Dictionary = payload.duplicate(true)
	message["protocol_version"] = _config.protocol_version
	message["seq"] = session["seq"]
	message["server_time"] = _world.server_time
	peer.send_text(JSON.stringify(message))
