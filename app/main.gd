extends Control

const DEFAULT_CONFIG: ClientConnectionConfig = preload("res://config/default_client_connection.tres")
const TRAVEL_INTENT_STATE = preload("res://modules/team3/travel/travel_intent_state.gd")
const TRAVEL_PROJECTION = preload("res://modules/team3/travel/travel_projection.gd")
const ATTACK_INTENT_STATE = preload("res://modules/team3/combat/attack_intent_state.gd")
const COMBAT_RESULT_STATE = preload("res://modules/team3/combat/combat_result_state.gd")

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
@onready var combat_target_label: Label = %CombatTargetLabel
@onready var attack_button: Button = %AttackButton
@onready var combat_status_label: Label = %CombatStatusLabel
@onready var combat_result_label: Label = %CombatResultLabel
@onready var world_debug_view: WorldDebugView = %WorldDebugView

var _world_state := WorldState.new()
var _ship_selection := ShipSelectionState.new(_world_state)
var _travel_intent: RefCounted = TRAVEL_INTENT_STATE.new()
var _attack_intent: RefCounted = ATTACK_INTENT_STATE.new(_world_state, _ship_selection)
var _combat_result_state: RefCounted = COMBAT_RESULT_STATE.new()
var _runtime_config: ClientConnectionConfig
var _player_id: String = ""


func _ready() -> void:
	_runtime_config = DEFAULT_CONFIG.duplicate(true) as ClientConnectionConfig
	host_edit.text = _runtime_config.host
	port_edit.value = _runtime_config.port
	world_debug_view.set_world_state(_world_state)
	world_debug_view.set_selection_state(_ship_selection)
	connect_button.pressed.connect(_connect_from_form)
	sss_connection.connection_state_changed.connect(_on_connection_state_changed)
	sss_connection.authenticated.connect(_on_authenticated)
	sss_connection.map_delta_received.connect(_on_map_delta)
	sss_connection.latency_updated.connect(_on_latency_updated)
	sss_connection.server_time_received.connect(_world_state.synchronize_server_time)
	sss_connection.protocol_error.connect(_on_protocol_error)
	sss_connection.server_error.connect(_on_server_error)
	sss_connection.combat_result_received.connect(_on_combat_result)
	sss_connection.desync_detected.connect(_on_desync_detected)
	_ship_selection.changed.connect(_on_ship_selection_changed)
	_attack_intent.changed.connect(_refresh_combat_controls)
	world_debug_view.destination_selected.connect(_on_destination_selected)
	confirm_travel_button.pressed.connect(_on_confirm_travel)
	cancel_travel_button.pressed.connect(_on_cancel_travel)
	attack_button.pressed.connect(_on_attack_pressed)
	status_label.text = "SSS: desconectado"
	_refresh_travel_controls()
	_refresh_combat_controls()
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
	_clear_transient_combat_ui()
	_runtime_config.host = host_edit.text.strip_edges()
	_runtime_config.port = int(port_edit.value)
	status_label.text = "SSS: conectando a %s" % _runtime_config.websocket_url()
	sss_connection.connect_to_server(_runtime_config)


func _on_connection_state_changed(state: String) -> void:
	status_label.text = "SSS: %s" % state
	connect_button.text = "Reconectar" if state != "disconnected" else "Conectar"
	if state == "disconnected":
		_clear_transient_travel_ui()
		_clear_transient_combat_ui()


func _on_authenticated(payload: Dictionary) -> void:
	_player_id = str(payload.get("player_id", ""))
	_travel_intent.set_player_id(_player_id)
	_attack_intent.set_player_id(_player_id)
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
	_refresh_combat_controls()
	metadata_label.text = "protocol=%s · seq=%d · server_time=%d · system_id=%s · entidades=%d" % [
		_world_state.protocol_version,
		_world_state.seq,
		_world_state.server_time,
		_world_state.system_id,
		_world_state.entities.size(),
	]


func _refresh_ship_label() -> void:
	var ship: ShipRepresentation = _ship_selection.get_selected_ship()
	if ship == null:
		ship = _world_state.get_ship_for_player(_player_id)
	if ship == null:
		ship_label.text = "Nave: no encontrada en la réplica"
		return
	ship_label.text = "Nave · entity_id=%s · ship_id=%s · player_id=%s · state=%s · pos=%s" % [
		ship.entity_id,
		ship.ship_id,
		ship.player_id if ship.player_id != "" else "desconocido",
		ship.state,
		str(ship.position),
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
	if str(payload.get("request_type", "")) == "attack":
		var request_id: String = str(payload.get("request_id", ""))
		_attack_intent.reject_request(request_id, error_code, message)
		status_label.text = "SSS rechazó attack: %s" % error_code
		_refresh_combat_controls()
		return
	if SssConnection.TRAVEL_ERROR_CODES.has(error_code):
		_travel_intent.reject_request(error_code)
		status_label.text = "SSS rechazó start_travel: %s" % error_code
		travel_label.text = "Viaje rechazado · %s · %s" % [error_code, message]
		_refresh_travel_controls(true)
		return
	status_label.text = "SSS error: %s · %s" % [error_code, message]


func _on_desync_detected() -> void:
	status_label.text = "SSS: secuencia desincronizada — solicitando full_snapshot"


func _on_ship_selection_changed() -> void:
	var entity_id: String = _ship_selection.selected_entity_id
	if entity_id == "":
		_travel_intent.apply_authoritative_ship({})
		ship_label.text = "Selección: —"
		_refresh_travel_controls()
		_refresh_combat_controls()
		return
	var entity: Dictionary = _world_state.get_entity(entity_id)
	if entity.is_empty():
		_travel_intent.select_entity({})
		ship_label.text = "Selección: %s (desconocida)" % entity_id
		_refresh_travel_controls()
		_refresh_combat_controls()
		return
	if entity_id != _travel_intent.selected_entity_id:
		_travel_intent.select_entity(entity)
	else:
		_travel_intent.apply_authoritative_ship(entity)
	var ship: ShipRepresentation = _ship_selection.get_selected_ship()
	var is_own_ship: bool = ship != null and ship.is_owned_by(_player_id)
	ship_label.text = "Selección · kind=%s · entity_id=%s · state=%s · pos=%s%s" % [
		entity.get("kind", ""),
		entity_id,
		entity.get("state", ""),
		str(entity.get("position", [])),
		" · propia" if is_own_ship else "",
	]
	_refresh_travel_controls()
	_refresh_combat_controls()


func _on_attack_pressed() -> void:
	if not _attack_intent.can_attack():
		return
	var request_id: String = sss_connection.request_attack(_attack_intent.target_entity_id)
	if request_id == "":
		combat_status_label.text = "No se pudo enviar attack"
		return
	if not _attack_intent.begin_request(request_id):
		sss_connection.resolve_attack_request(request_id)
		combat_status_label.text = "La selección dejó de ser atacable"
		return
	status_label.text = "attack enviado; esperando combat_result autoritativo"
	_refresh_combat_controls()


func _on_combat_result(payload: Dictionary) -> void:
	_attack_intent.complete_request(str(payload.get("request_id", "")))
	_combat_result_state.apply_result(payload)
	_refresh_combat_controls()


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
	_refresh_world_interaction()
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
	if _travel_intent.selected_own_entity_id != "":
		if ship_state == "ANCHORED":
			travel_label.text = "ANCHORED · toca una coordenada del mapa"
		else:
			travel_label.text = "La nave propia no está disponible para viajar"
		return
	travel_label.text = "Selecciona tu nave para preparar un viaje"


func _refresh_combat_controls() -> void:
	var target_id: String = _attack_intent.target_entity_id
	var selected_id: String = _ship_selection.selected_entity_id
	if target_id != "":
		var target: ShipRepresentation = _world_state.get_ship(target_id)
		var state_text: String = "fuera del AOI" if target == null else target.state
		combat_target_label.text = "Objetivo · entity_id=%s · state=%s" % [target_id, state_text]
	elif selected_id != "":
		var selected_ship: ShipRepresentation = _world_state.get_ship(selected_id)
		if selected_ship != null and selected_ship.is_owned_by(_player_id):
			combat_target_label.text = "Objetivo: la nave propia no es atacable"
		else:
			combat_target_label.text = "Objetivo: selecciona una nave ajena"
	else:
		combat_target_label.text = "Objetivo: selecciona una nave ajena"

	attack_button.disabled = not _attack_intent.can_attack()
	if _attack_intent.awaiting_resolution:
		combat_status_label.text = "Combat pendiente · request_id=%s" % _attack_intent.pending_request_id
	elif _attack_intent.last_rejection_code != "":
		combat_status_label.text = "Combat rechazado · %s · %s" % [
			_attack_intent.last_rejection_code,
			_attack_intent.last_rejection_message,
		]
	else:
		combat_status_label.text = "Combat listo" if _attack_intent.can_attack() else "Combat no disponible"

	if _combat_result_state.combat_id != "":
		combat_result_label.text = (
			"Resultado · combat_id=%s · version=%s · outcome=%s · Bajas atacante=%d defensor=%d"
			% [
				_combat_result_state.combat_id,
				_combat_result_state.combat_version,
				_combat_result_state.outcome,
				_count_casualties(_combat_result_state.casualties.get("attacker", [])),
				_count_casualties(_combat_result_state.casualties.get("defender", [])),
			]
		)
	else:
		combat_result_label.text = "Resultado: —"
	_refresh_world_interaction()


func _count_casualties(raw_stacks: Variant) -> int:
	if not raw_stacks is Array:
		return 0
	var total: int = 0
	for raw_stack: Variant in raw_stacks:
		if raw_stack is Dictionary:
			total += maxi(0, int(raw_stack.get("quantity", 0)))
	return total


func _refresh_world_interaction() -> void:
	world_debug_view.set_tap_actions_enabled(
		not _travel_intent.awaiting_resolution and not _attack_intent.awaiting_resolution
	)


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
	world_debug_view.clear_selection()
	world_debug_view.set_destination_selection_enabled(false)
	world_debug_view.set_provisional_destination(Vector2i.ZERO, false)
	_refresh_travel_controls()


func _clear_transient_combat_ui() -> void:
	sss_connection.resolve_attack_request()
	_attack_intent.reset_transient()
	_refresh_combat_controls()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		# Android: descartamos intención local y reconstruimos la trayectoria
		# autoritativa mediante full_snapshot en la nueva conexión.
		_world_state.clear()
		world_debug_view.clear_selection()
		_clear_transient_travel_ui()
		_clear_transient_combat_ui()
		sss_connection.connect_to_server(_runtime_config)
