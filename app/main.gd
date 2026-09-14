extends Control

const DEFAULT_CONFIG: ClientConnectionConfig = preload("res://config/default_client_connection.tres")
const TRAVEL_INTENT_STATE = preload("res://modules/team3/travel/travel_intent_state.gd")
const TRAVEL_PROJECTION = preload("res://modules/team3/travel/travel_projection.gd")

@onready var sss_connection: SssConnection = %SssConnection
@onready var host_edit: LineEdit = %HostEdit
@onready var port_edit: SpinBox = %PortEdit
@onready var connect_button: Button = %ConnectButton
@onready var status_label: Label = %StatusLabel
@onready var metadata_label: Label = %MetadataLabel
@onready var ship_label: Label = %ShipLabel
@onready var travel_label: Label = %TravelLabel
@onready var confirm_travel_button: Button = %ConfirmTravelButton
@onready var cancel_travel_button: Button = %CancelTravelButton
@onready var world_debug_view: WorldDebugView = %WorldDebugView

var _world_state := WorldState.new()
var _travel_intent: RefCounted = TRAVEL_INTENT_STATE.new()
var _runtime_config: ClientConnectionConfig
var _player_id: String = ""


func _ready() -> void:
	_runtime_config = DEFAULT_CONFIG.duplicate(true) as ClientConnectionConfig
	host_edit.text = _runtime_config.host
	port_edit.value = _runtime_config.port
	world_debug_view.set_world_state(_world_state)
	connect_button.pressed.connect(_connect_from_form)
	sss_connection.connection_state_changed.connect(_on_connection_state_changed)
	sss_connection.authenticated.connect(_on_authenticated)
	sss_connection.map_delta_received.connect(_on_map_delta)
	sss_connection.latency_updated.connect(_on_latency_updated)
	sss_connection.server_time_received.connect(_world_state.synchronize_server_time)
	sss_connection.protocol_error.connect(_on_protocol_error)
	sss_connection.server_error.connect(_on_server_error)
	sss_connection.desync_detected.connect(_on_desync_detected)
	world_debug_view.entity_selected.connect(_on_entity_selected)
	world_debug_view.destination_selected.connect(_on_destination_selected)
	confirm_travel_button.pressed.connect(_on_confirm_travel)
	cancel_travel_button.pressed.connect(_on_cancel_travel)
	status_label.text = "SSS: desconectado"
	_refresh_travel_controls()
	if _runtime_config.auto_connect:
		_connect_from_form()


func _process(_delta: float) -> void:
	# La cuenta atrás se deriva del reloj del SSS y avanza con reloj monotónico.
	# No altera el estado ni la posición autoritativa de WorldState.
	var own_ship: Dictionary = _world_state.ship_for_player(_player_id)
	if str(own_ship.get("state", "")) == "TRAVELING":
		_refresh_travel_controls()


func _connect_from_form() -> void:
	_clear_transient_travel_ui()
	_runtime_config.host = host_edit.text.strip_edges()
	_runtime_config.port = int(port_edit.value)
	status_label.text = "SSS: conectando a %s" % _runtime_config.websocket_url()
	sss_connection.connect_to_server(_runtime_config)


func _on_connection_state_changed(state: String) -> void:
	status_label.text = "SSS: %s" % state
	connect_button.text = "Reconectar" if state != "disconnected" else "Conectar"
	if state == "disconnected":
		_clear_transient_travel_ui()


func _on_authenticated(payload: Dictionary) -> void:
	_player_id = str(payload.get("player_id", ""))
	_travel_intent.set_player_id(_player_id)
	status_label.text = "SSS: autenticación mock aceptada; solicitando full_snapshot"
	metadata_label.text = "protocol=%s · seq=%d · server_time=%d" % [
		payload.get("protocol_version", ""),
		int(payload.get("seq", -1)),
		int(payload.get("server_time", 0)),
	]


func _on_map_delta(payload: Dictionary) -> void:
	var full: bool = bool(payload.get("full", false))
	if full:
		if not _world_state.apply_full_snapshot(payload):
			_on_protocol_error("El full_snapshot no pudo aplicarse")
			return
		status_label.text = "SSS: full_snapshot aplicado"
	else:
		if not _world_state.apply_map_delta(payload):
			_on_protocol_error("El map_delta no pudo aplicarse (desincronización local)")
			sss_connection.request_full_snapshot()
			return
		status_label.text = "SSS: world_delta aplicado"

	var own_ship: Dictionary = _world_state.ship_for_player(_player_id)
	_travel_intent.apply_authoritative_ship(own_ship)
	if str(own_ship.get("state", "")) == "TRAVELING":
		sss_connection.resolve_start_travel_request()
	_refresh_ship_label()
	_refresh_travel_controls()
	metadata_label.text = "protocol=%s · seq=%d · server_time=%d · system_id=%s · entidades=%d" % [
		_world_state.protocol_version,
		_world_state.seq,
		_world_state.server_time,
		_world_state.system_id,
		_world_state.entities.size(),
	]


func _refresh_ship_label() -> void:
	var ship: Dictionary = _world_state.ship_for_player(_player_id)
	if ship.is_empty():
		ship = _world_state.first_ship()
	if ship.is_empty():
		ship_label.text = "Nave: no encontrada en la réplica"
		return
	ship_label.text = "Nave · entity_id=%s · ship_id=%s · player_id=%s · state=%s · pos=%s" % [
		ship.get("entity_id", ""),
		ship.get("ship_id", ""),
		ship.get("player_id", ""),
		ship.get("state", ""),
		str(ship.get("position", [])),
	]
	print("CLIENT_M2_SNAPSHOT_OK protocol=%s seq=%d entidades=%d" % [
		_world_state.protocol_version,
		_world_state.seq,
		_world_state.entities.size(),
	])


func _on_latency_updated(milliseconds: int) -> void:
	status_label.text = "SSS: conectado · ping %d ms" % milliseconds


func _on_protocol_error(message: String) -> void:
	status_label.text = "SSS error de protocolo: %s" % message


func _on_server_error(payload: Dictionary) -> void:
	var error_code: String = str(payload.get("error_code", "UNKNOWN_SERVER_ERROR"))
	var message: String = str(payload.get("message", "El SSS rechazó la solicitud"))
	if SssConnection.TRAVEL_ERROR_CODES.has(error_code):
		_travel_intent.reject_request(error_code)
		status_label.text = "SSS rechazó start_travel: %s" % error_code
		travel_label.text = "Viaje rechazado · %s · %s" % [error_code, message]
		_refresh_travel_controls(true)
		return
	status_label.text = "SSS error: %s · %s" % [error_code, message]


func _on_desync_detected() -> void:
	status_label.text = "SSS: secuencia desincronizada — solicitando full_snapshot"


func _on_entity_selected(entity_id: String) -> void:
	if entity_id == "":
		_travel_intent.select_entity({})
		ship_label.text = "Selección: —"
		_refresh_travel_controls()
		return
	var entity: Dictionary = _world_state.get_entity(entity_id)
	if entity.is_empty():
		_travel_intent.select_entity({})
		ship_label.text = "Selección: %s (desconocida)" % entity_id
		_refresh_travel_controls()
		return
	var is_own_ship: bool = _travel_intent.select_entity(entity)
	ship_label.text = "Selección · kind=%s · entity_id=%s · state=%s · pos=%s%s" % [
		entity.get("kind", ""),
		entity_id,
		entity.get("state", ""),
		str(entity.get("position", [])),
		" · propia" if is_own_ship else "",
	]
	_refresh_travel_controls()


func _on_destination_selected(destination: Vector2i) -> void:
	if not _travel_intent.choose_destination(destination, _world_state.map_size):
		return
	status_label.text = "Destino provisional seleccionado; confirma o cancela"
	_refresh_travel_controls()


func _on_confirm_travel() -> void:
	if not _travel_intent.begin_request():
		return
	_refresh_travel_controls()
	if sss_connection.request_start_travel(_travel_intent.provisional_destination):
		status_label.text = "start_travel enviado; esperando estado autoritativo"
		return
	_travel_intent.reject_request("CLIENT_NOT_CONNECTED")
	status_label.text = "No se pudo enviar start_travel"
	_refresh_travel_controls(true)


func _on_cancel_travel() -> void:
	if not _travel_intent.cancel_destination():
		return
	status_label.text = "Destino provisional cancelado"
	_refresh_travel_controls()


func _refresh_travel_controls(preserve_rejection_text: bool = false) -> void:
	var own_ship: Dictionary = _world_state.ship_for_player(_player_id)
	var ship_state: String = str(own_ship.get("state", ""))
	var may_pick_destination: bool = _travel_intent.can_choose_destination()
	world_debug_view.set_tap_actions_enabled(not _travel_intent.awaiting_resolution)
	world_debug_view.set_destination_selection_enabled(may_pick_destination)
	world_debug_view.set_provisional_destination(
		_travel_intent.provisional_destination,
		_travel_intent.has_provisional_destination,
	)
	confirm_travel_button.disabled = (
		not _travel_intent.has_provisional_destination
		or _travel_intent.awaiting_resolution
		or not may_pick_destination
	)
	cancel_travel_button.disabled = (
		not _travel_intent.has_provisional_destination
		or _travel_intent.awaiting_resolution
	)

	if ship_state == "TRAVELING":
		var remaining_ms: int = TRAVEL_PROJECTION.remaining_milliseconds(
			own_ship,
			_world_state.estimated_server_time_ms(),
		)
		travel_label.text = "TRAVELING · ETA %s · destino %s" % [
			_format_eta(remaining_ms),
			str(TRAVEL_PROJECTION.destination(own_ship)),
		]
		return
	if _travel_intent.awaiting_resolution:
		travel_label.text = "Esperando al SSS · destino %s" % str(_travel_intent.provisional_destination)
		return
	if preserve_rejection_text:
		return
	if _travel_intent.has_provisional_destination:
		travel_label.text = "Destino provisional %s" % str(_travel_intent.provisional_destination)
		return
	if _travel_intent.selected_own_ship_id != "":
		if ship_state == "ANCHORED":
			travel_label.text = "ANCHORED · toca una coordenada del mapa"
		else:
			travel_label.text = "La nave propia no está disponible para viajar"
		return
	travel_label.text = "Selecciona tu nave para preparar un viaje"


func _format_eta(remaining_ms: int) -> String:
	var total_seconds: int = ceili(float(maxi(0, remaining_ms)) / 1000.0)
	var hours: int = total_seconds / 3600
	var minutes: int = (total_seconds % 3600) / 60
	var seconds: int = total_seconds % 60
	if hours > 0:
		return "%02d:%02d:%02d" % [hours, minutes, seconds]
	return "%02d:%02d" % [minutes, seconds]


func _clear_transient_travel_ui() -> void:
	sss_connection.resolve_start_travel_request()
	_travel_intent.reset_transient()
	world_debug_view.set_destination_selection_enabled(false)
	world_debug_view.set_provisional_destination(Vector2i.ZERO, false)
	_refresh_travel_controls()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		# Android: descartamos intención local y reconstruimos la trayectoria
		# autoritativa mediante full_snapshot en la nueva conexión.
		_world_state.clear()
		world_debug_view.clear_selection()
		_clear_transient_travel_ui()
		sss_connection.connect_to_server(_runtime_config)
