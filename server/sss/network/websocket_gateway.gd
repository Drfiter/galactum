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


## Called after each tick by main.gd. Emits map_delta(full:false) a cada sesión
## si cambian entidades conocidas o la visibilidad del AOI de esa conexión.
## No drena el changeset — el ChangeSet del mundo es compartido entre todas las sesiones.
func flush_pending_deltas() -> void:
	for raw_session_id: Variant in _sessions.keys():
		var session_id: int = int(raw_session_id)
		var session: Dictionary = _sessions[session_id]
		if not bool(session.get("authenticated", false)) or not bool(session.get("snapshot_ready", false)):
			continue
		var player_id: String = str(session.get("player_id", ""))
		var known_ids: Array[String] = session["visible_entity_ids"]
		var delta: Dictionary = _world.delta_for(player_id, known_ids)
		if delta.is_empty():
			continue
		delta["type"] = "map_delta"
		if _send(session_id, delta):
			for entity_id: String in delta["removed"]:
				known_ids.erase(entity_id)
			for entity: Dictionary in delta["added"]:
				known_ids.append(str(entity["entity_id"]))


func _accept_connection() -> void:
	var stream: StreamPeerTCP = _tcp_server.take_connection()
	var peer := WebSocketPeer.new()
	var error: Error = peer.accept_stream(stream)
	if error != OK:
		stream.disconnect_from_host()
		return
	var visible_ids: Array[String] = []
	_sessions[_next_session_id] = {
		"peer": peer,
		"authenticated": false,
		"player_id": "",
		"system_id": "",
		"seq": 0,
		"snapshot_ready": false,
		"visible_entity_ids": visible_ids,
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
	if message_type == "start_travel":
		_handle_start_travel(session_id, message)
		return
	if not bool(session.get("authenticated", false)):
		_send_error(session_id, "ERR_NOT_AUTHENTICATED", "Authenticate first")
		return

	match message_type:
		"full_snapshot":
			var snapshot: Dictionary = _world.full_snapshot_for(str(session.get("player_id", "")))
			snapshot["type"] = "map_delta"
			if _send(session_id, snapshot):
				var visible_ids: Array[String] = []
				for entity: Dictionary in snapshot["added"]:
					visible_ids.append(str(entity["entity_id"]))
				session["visible_entity_ids"] = visible_ids
				session["snapshot_ready"] = true
		"ping":
			_send(session_id, {
				"type": "pong",
				"client_time": int(message.get("client_time", 0)),
			})
		_:
			_send_error(session_id, "ERR_UNKNOWN_MESSAGE", "Unsupported TEAM3-M1 message")


func _handle_start_travel(session_id: int, message: Dictionary) -> void:
	var session: Dictionary = _sessions[session_id]
	var player_id: String = str(session.get("player_id", ""))
	var dest_arr: Array = message.get("destination", [])
	if dest_arr.size() != 2:
		_send_error(session_id, "INVALID_REQUEST", "Destination must be array [x, y]")
		return
	var destination: Vector2i = Vector2i(int(dest_arr[0]), int(dest_arr[1]))
	var res: Dictionary = _world.start_travel(player_id, destination)
	if res.has("error_code"):
		_send_error(session_id, str(res["error_code"]), str(res.get("message", "")))
		return
	# Éxito: NO se envía travel_started.
	# La confirmación llega por map_delta en flush_pending_deltas (mismo ciclo).
	# El start_travel registró un update en el ChangeSet; el siguiente flush lo emite.


func _handle_auth(session_id: int, message: Dictionary) -> void:
	var identity: Dictionary = _authenticator.authenticate(str(message.get("jwt", "")))
	if identity.is_empty():
		_send_error(session_id, "ERR_MOCK_AUTH", "Mock authentication failed")
		return
	var session: Dictionary = _sessions[session_id]
	session["authenticated"] = true
	session["snapshot_ready"] = false
	var empty_ids: Array[String] = []
	session["visible_entity_ids"] = empty_ids
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


func _send(session_id: int, payload: Dictionary) -> bool:
	if not _sessions.has(session_id):
		return false
	var session: Dictionary = _sessions[session_id]
	var peer: WebSocketPeer = session["peer"]
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var message: Dictionary = payload.duplicate(true)
	message["protocol_version"] = _config.protocol_version
	message["seq"] = int(session.get("seq", 0)) + 1
	message["server_time"] = _world.server_time
	if peer.send_text(JSON.stringify(message)) != OK:
		# Sin ACKs propios: una escritura fallida fuerza reconstrucción por conexión.
		peer.close(1011, "send failed")
		session["snapshot_ready"] = false
		return false
	session["seq"] = message["seq"]
	return true
