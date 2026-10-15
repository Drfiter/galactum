class_name SssConnection
extends Node
## Cliente WebSocket hacia el SSS (Equipo 3).
## TEAM3-M0: conexión, auth mock, full_snapshot, ping/pong, reconexión.
## TEAM3-M1: valida continuidad de seq en TODOS los mensajes del SSS y, ante un
## gap real, marca desincronización y solicita full_snapshot para reconstruir
## WorldState. Reinicia el seguimiento de seq al abrir cada conexión nueva.
## TEAM3-M2-I: envía una única intención start_travel pendiente, publica el
## reloj del SSS y separa rechazos del servidor de errores de protocolo.
## TEAM3-M3: añade la extensión provisional attack sobre team3-m2.0, con
## correlación por request_id y separación estricta entre Combat y Travel.

signal connection_state_changed(state: String)
signal authenticated(payload: Dictionary)
signal full_snapshot_received(payload: Dictionary)
signal map_delta_received(payload: Dictionary)
signal latency_updated(milliseconds: int)
signal server_time_received(server_time_ms: int)
signal protocol_error(message: String)
signal server_error(payload: Dictionary)
signal combat_result_received(payload: Dictionary)
signal desync_detected

const PROTOCOL_VERSION: String = "team3-m2.0"
const TRAVEL_ERROR_CODES: Array[String] = [
	"INVALID_REQUEST",
	"INVALID_DESTINATION",
	"SHIP_NOT_FOUND",
	"SHIP_NOT_ANCHORED",
]

enum State {
	DISCONNECTED,
	CONNECTING,
	AUTHENTICATING,
	AUTHENTICATED,
}

var _config: ClientConnectionConfig
var _peer: WebSocketPeer = WebSocketPeer.new()
var _state: State = State.DISCONNECTED
var _manual_disconnect: bool = false
var _reconnect_remaining: float = 0.0
var _ping_remaining: float = 0.0
var _last_ping_ticks: int = 0

# Seguimiento de secuencia monotónica por conexión (todos los mensajes del SSS).
# -1 => aún sin base (esperamos el primer mensaje de la conexión).
var _next_expected_seq: int = -1
var _start_travel_pending: bool = false
var _attack_pending_request_id: String = ""
var _issued_attack_request_ids: Dictionary = {}


func connect_to_server(config: ClientConnectionConfig) -> void:
	_config = config
	_manual_disconnect = false
	_reconnect_remaining = 0.0
	_peer = WebSocketPeer.new()
	# Nueva conexión => nuevo seguimiento de secuencia (el SSS la reinicia en 1).
	_reset_sequence_tracking()
	var error: Error = _peer.connect_to_url(config.websocket_url())
	if error != OK:
		_set_state(State.DISCONNECTED)
		protocol_error.emit("No se pudo iniciar la conexión WebSocket: %s" % error_string(error))
		_schedule_reconnect()
		return
	_set_state(State.CONNECTING)
	set_process(true)


func disconnect_from_server() -> void:
	_manual_disconnect = true
	_reconnect_remaining = 0.0
	if _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.close(1000, "client disconnect")
	_set_state(State.DISCONNECTED)


func request_full_snapshot() -> void:
	if _state != State.AUTHENTICATED:
		return
	_send({"type": "full_snapshot"})


## Envía una única intención de viaje para la nave del jugador autenticado.
## El SSS identifica esa nave: el cliente no envía entity_id ni player_id.
func request_start_travel(destination: Vector2i) -> bool:
	if _state != State.AUTHENTICATED or _start_travel_pending:
		return false
	if not _send(_build_start_travel_payload(destination)):
		return false
	_start_travel_pending = true
	return true


func resolve_start_travel_request() -> void:
	_start_travel_pending = false


func is_start_travel_pending() -> bool:
	return _start_travel_pending


## Envia exclusivamente la intencion minima aprobada. El SSS deriva al atacante.
## Devuelve el request_id generado o "" cuando no pudo iniciar la solicitud.
func request_attack(target_entity_id: String) -> String:
	if (_state != State.AUTHENTICATED or target_entity_id == ""
		or _attack_pending_request_id != ""):
		return ""
	var request_id: String = _generate_attack_request_id()
	if not _send(_build_attack_payload(target_entity_id, request_id)):
		return ""
	_attack_pending_request_id = request_id
	_issued_attack_request_ids[request_id] = true
	return request_id


func resolve_attack_request(request_id: String = "") -> bool:
	if _attack_pending_request_id == "":
		return false
	if request_id != "" and request_id != _attack_pending_request_id:
		return false
	_attack_pending_request_id = ""
	return true


func is_attack_pending() -> bool:
	return _attack_pending_request_id != ""


func pending_attack_request_id() -> String:
	return _attack_pending_request_id


static func _build_start_travel_payload(destination: Vector2i) -> Dictionary:
	return {
		"type": "start_travel",
		"protocol_version": PROTOCOL_VERSION,
		"destination": [destination.x, destination.y],
	}


static func _build_attack_payload(target_entity_id: String, request_id: String) -> Dictionary:
	return {
		"type": "attack",
		"protocol_version": PROTOCOL_VERSION,
		"request_id": request_id,
		"target_entity_id": target_entity_id,
	}


func _process(delta: float) -> void:
	if _state == State.DISCONNECTED:
		_process_reconnect(delta)
		return

	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if _state == State.CONNECTING:
				_set_state(State.AUTHENTICATING)
				_send({"type": "auth", "jwt": _config.mock_token})
			while _peer.get_available_packet_count() > 0:
				_handle_packet(_peer.get_packet().get_string_from_utf8())
			_process_ping(delta)
		WebSocketPeer.STATE_CLOSED:
			_set_state(State.DISCONNECTED)
			_schedule_reconnect()


func _process_reconnect(delta: float) -> void:
	if _manual_disconnect or _config == null or not _config.auto_reconnect:
		return
	if _reconnect_remaining <= 0.0:
		return
	_reconnect_remaining -= delta
	if _reconnect_remaining <= 0.0:
		connect_to_server(_config)


func _process_ping(delta: float) -> void:
	if _state != State.AUTHENTICATED:
		return
	_ping_remaining -= delta
	if _ping_remaining > 0.0:
		return
	_last_ping_ticks = Time.get_ticks_msec()
	_send({"type": "ping", "client_time": _last_ping_ticks})
	_ping_remaining = _config.ping_interval_seconds


func _handle_packet(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		protocol_error.emit("El SSS envió JSON inválido")
		return
	var message: Dictionary = parsed
	if str(message.get("protocol_version", "")) != PROTOCOL_VERSION:
		protocol_error.emit("Versión de protocolo incompatible")
		return
	if not message.has("seq") or not message.has("server_time"):
		protocol_error.emit("Mensaje sin seq o server_time")
		return

	var is_full_snapshot: bool = (str(message.get("type", "")) == "map_delta"
		and bool(message.get("full", false)))
	if not _validate_sequence(message):
		if is_full_snapshot:
			# Un snapshot completo es autoritativo y resetea la continuidad:
			# re-baselineamos la secuencia a partir de él (recupera una desync).
			_next_expected_seq = int(message.get("seq", -1)) + 1
		else:
			# Gap real de secuencia: no inventamos estado, marcamos desync y
			# reconstruimos desde un full_snapshot.
			desync_detected.emit()
			protocol_error.emit("Secuencia desincronizada (seq=%d)" % int(message.get("seq", -1)))
			request_full_snapshot()
			return
	server_time_received.emit(int(message.get("server_time", 0)))

	match str(message.get("type", "")):
		"auth_ok":
			_set_state(State.AUTHENTICATED)
			_ping_remaining = 0.0
			authenticated.emit(message)
			request_full_snapshot()
		"map_delta":
			map_delta_received.emit(message)
			if bool(message.get("full", false)):
				full_snapshot_received.emit(message)
		"pong":
			var echoed_time: int = int(message.get("client_time", _last_ping_ticks))
			latency_updated.emit(maxi(0, Time.get_ticks_msec() - echoed_time))
		"error":
			if str(message.get("request_type", "")) == "attack":
				resolve_attack_request(str(message.get("request_id", "")))
			elif TRAVEL_ERROR_CODES.has(str(message.get("error_code", ""))):
				_start_travel_pending = false
			server_error.emit(message)
		"combat_result":
			resolve_attack_request(str(message.get("request_id", "")))
			combat_result_received.emit(message)
		_:
			protocol_error.emit("Tipo de mensaje M2 desconocido: %s" % message.get("type", ""))


## Valida que el seq entrante sea estrictamente el siguiente esperado.
## El primer mensaje de una conexión establece la base (sin exigir continuidad).
func _validate_sequence(message: Dictionary) -> bool:
	var incoming_seq: int = int(message.get("seq", -1))
	if incoming_seq < 1:
		return false
	if _next_expected_seq == -1:
		# Primer mensaje de la conexión: aceptamos y fijamos la base.
		_next_expected_seq = incoming_seq + 1
		return true
	if incoming_seq != _next_expected_seq:
		return false
	_next_expected_seq = incoming_seq + 1
	return true


func _reset_sequence_tracking() -> void:
	_next_expected_seq = -1
	_start_travel_pending = false
	_attack_pending_request_id = ""


func _generate_attack_request_id() -> String:
	var request_id: String = ""
	while request_id == "" or _issued_attack_request_ids.has(request_id):
		request_id = "attack-%s" % Crypto.new().generate_random_bytes(16).hex_encode()
	return request_id


func _send(payload: Dictionary) -> bool:
	if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var message: Dictionary = payload.duplicate(true)
	message["protocol_version"] = PROTOCOL_VERSION
	return _peer.send_text(JSON.stringify(message)) == OK


func _schedule_reconnect() -> void:
	if not _manual_disconnect and _config != null and _config.auto_reconnect:
		_reconnect_remaining = _config.reconnect_delay_seconds


func _set_state(next_state: State) -> void:
	if _state == next_state:
		return
	_state = next_state
	connection_state_changed.emit(_state_name())


func _state_name() -> String:
	match _state:
		State.CONNECTING:
			return "connecting"
		State.AUTHENTICATING:
			return "authenticating"
		State.AUTHENTICATED:
			return "authenticated"
		_:
			return "disconnected"
