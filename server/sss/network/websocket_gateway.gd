class_name WebSocketGateway
extends Node

const M2_PROTOCOL: String = "team3-m2.0"
const M3_PROTOCOL: String = "team3-m3.0"

var _config: SssConfig
var _authenticator: ClientAuthenticator
var _world: SolarSystemWorld
var _combat_service: CombatService
var _tcp_server := TCPServer.new()
var _sessions: Dictionary = {}
var _next_session_id: int = 1


func _init(
		config: SssConfig,
		authenticator: ClientAuthenticator,
		world: SolarSystemWorld,
		combat_service: CombatService = null,
) -> void:
	_config = config
	_authenticator = authenticator
	_world = world
	_combat_service = combat_service


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
## si el changeset tiene cambios relevantes para su AOI.
## No drena el changeset — el ChangeSet del mundo es compartido entre todas las sesiones.
func flush_pending_deltas() -> void:
	if not _world.change_set.has_changes():
		return
	for raw_session_id: Variant in _sessions.keys():
		var session_id: int = int(raw_session_id)
		var session: Dictionary = _sessions[session_id]
		if not bool(session.get("authenticated", false)) or not bool(session.get("has_snapshot", false)):
			continue
		var player_id: String = str(session.get("player_id", ""))
		var visible_ids: Array[String] = session["visible_ids"]
		var delta: Dictionary = _world.delta_for_session(player_id, visible_ids, session["protocol_version"] == M3_PROTOCOL)
		if delta.is_empty():
			continue
		delta["type"] = "map_delta"
		_send(session_id, delta)


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
		"visible_ids": visible_ids,
		"has_snapshot": false,
		"protocol_version": _config.protocol_version,
	}
	_next_session_id += 1


func _handle_packet(session_id: int, raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		_send_error(session_id, "ERR_INVALID_JSON", "Expected a JSON object")
		return
	var message: Dictionary = parsed
	var incoming_version: String = str(message.get("protocol_version", ""))
	var session: Dictionary = _sessions[session_id]
	if (incoming_version not in [M2_PROTOCOL, M3_PROTOCOL]
		or (bool(session["authenticated"]) and incoming_version != str(session["protocol_version"]))):
		_send_error(session_id, "ERR_PROTOCOL_VERSION", "Unsupported protocol_version")
		return
	if not bool(session["authenticated"]):
		session["protocol_version"] = incoming_version
		_sessions[session_id] = session
	var message_type: String = str(message.get("type", ""))
	if message_type == "auth":
		_handle_auth(session_id, message)
		return
	if message_type in ["start_mining", "stop_mining"]:
		if incoming_version != M3_PROTOCOL:
			_send_error(session_id, "ERR_UNKNOWN_MESSAGE", "Mining requires team3-m3.0")
		else:
			_handle_mining(session_id, message)
		return
	if message_type == "start_travel":
		_handle_start_travel(session_id, message)
		return
	# Combat valida autenticación antes de inspeccionar o procesar la intención.
	# El orden histórico de start_travel se conserva fuera de este cambio.
	if message_type == "attack":
		var attack_request_id: String = str(message.get("request_id", ""))
		if not bool(session.get("authenticated", false)):
			_send_combat_error(session_id, attack_request_id, "ERR_NOT_AUTHENTICATED", "Authenticate first")
			return
		_handle_attack(session_id, message)
		return
	if not bool(session.get("authenticated", false)):
		_send_error(session_id, "ERR_NOT_AUTHENTICATED", "Authenticate first")
		return

	match message_type:
		"full_snapshot":
			var snapshot: Dictionary = _world.full_snapshot_for(str(session.get("player_id", "")), incoming_version == M3_PROTOCOL)
			snapshot["type"] = "map_delta"
			_send(session_id, snapshot)
		"ping":
			_send(session_id, {
				"type": "pong",
				"client_time": int(message.get("client_time", 0)),
			})
		_:
			_send_error(session_id, "ERR_UNKNOWN_MESSAGE", "Unsupported message")


func _handle_mining(session_id: int, message: Dictionary) -> void:
	var session: Dictionary = _sessions[session_id]
	if not bool(session["authenticated"]):
		_send_mining_error(session_id, message, "MINING_NOT_AUTHENTICATED")
		return
	var request_type: String = str(message["type"])
	var allowed: Array[String] = ["type", "protocol_version"]
	var valid: bool
	if request_type == "start_mining":
		allowed.append_array(["request_id", "asteroid_entity_id"])
		valid = (message.get("request_id") is String
			and MiningService.is_valid_request_id(str(message["request_id"]))
			and message.get("asteroid_entity_id") is String
			and not str(message["asteroid_entity_id"]).is_empty())
	else:
		allowed.append("mining_id")
		valid = message.get("mining_id") is String and not str(message["mining_id"]).is_empty()
	for field: Variant in message:
		if not allowed.has(str(field)):
			valid = false
	if not valid:
		_send_mining_error(session_id, message, "MINING_INVALID_REQUEST")
		return
	var player_id: String = str(session["player_id"])
	var result: Dictionary
	if request_type == "start_mining":
		result = _world.start_mining(player_id, str(message["request_id"]), str(message["asteroid_entity_id"]))
	else:
		result = _world.stop_mining(player_id, str(message["mining_id"]))
	if result.has("error_code"):
		_send_mining_error(session_id, message, str(result["error_code"]))
	elif result.has("result"):
		var replay: Dictionary = {
			"type": "mining_replay", "request_type": request_type,
			"mining_id": result["mining_id"], "result": result["result"],
		}
		if message.has("request_id"):
			replay["request_id"] = str(message["request_id"]).to_lower()
		_send(session_id, replay)
	# Inicio/parada nuevos se confirman sólo por el próximo map_delta del tick.


func _send_mining_error(session_id: int, request: Dictionary, code: String) -> void:
	var response: Dictionary = {
		"type": "error", "error_code": code, "message": code,
		"request_type": str(request.get("type", "")),
	}
	if request.get("request_id") is String:
		response["request_id"] = str(request["request_id"]).to_lower()
	if request.get("mining_id") is String:
		response["mining_id"] = request["mining_id"]
	_send(session_id, response)


func _handle_attack(session_id: int, message: Dictionary) -> void:
	var raw_request_id: Variant = message.get("request_id", "")
	var request_id: String = raw_request_id if raw_request_id is String else ""
	var allowed_fields: Array[String] = [
		"type",
		"protocol_version",
		"request_id",
		"target_entity_id",
	]
	for raw_key: Variant in message.keys():
		if not allowed_fields.has(str(raw_key)):
			_send_combat_error(
				session_id,
				request_id,
				CombatService.ERROR_INVALID_ATTACK_REQUEST,
				"Unexpected field in attack request: %s" % str(raw_key),
			)
			return
	if not raw_request_id is String or not message.get("target_entity_id", "") is String:
		_send_combat_error(
			session_id,
			request_id,
			CombatService.ERROR_INVALID_ATTACK_REQUEST,
			"request_id and target_entity_id must be strings",
		)
		return
	if _combat_service == null:
		_send_combat_error(session_id, request_id, "COMBAT_UNAVAILABLE", "Combat service is unavailable")
		return
	var session: Dictionary = _sessions[session_id]
	var result: Dictionary = _combat_service.request_attack(
		str(session.get("player_id", "")),
		request_id,
		str(message.get("target_entity_id", "")),
	)
	_send(session_id, result)


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
	session["player_id"] = str(identity.get("player_id", ""))
	session["system_id"] = str(identity.get("system_id", ""))
	var visible_ids: Array[String] = []
	session["visible_ids"] = visible_ids
	session["has_snapshot"] = false
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


func _send_combat_error(session_id: int, request_id: String, error_code: String, message: String) -> void:
	_send(session_id, CombatService.combat_error(request_id, error_code, message))


func _send(session_id: int, payload: Dictionary) -> void:
	if not _sessions.has(session_id):
		return
	var session: Dictionary = _sessions[session_id]
	var peer: WebSocketPeer = session["peer"]
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var message: Dictionary = payload.duplicate(true)
	message["protocol_version"] = session["protocol_version"]
	message["seq"] = int(session.get("seq", 0)) + 1
	message["server_time"] = _world.server_time
	if peer.send_text(JSON.stringify(message)) != OK:
		return
	session["seq"] = message["seq"]
	if str(payload.get("type", "")) == "map_delta":
		var visible_ids: Array[String] = session["visible_ids"]
		if bool(payload.get("full", false)):
			visible_ids.clear()
			session["has_snapshot"] = true
		for entity: Dictionary in payload.get("added", []):
			var entity_id: String = str(entity["entity_id"])
			if not visible_ids.has(entity_id):
				visible_ids.append(entity_id)
		for entity_id: String in payload.get("removed", []):
			visible_ids.erase(entity_id)
	_sessions[session_id] = session
