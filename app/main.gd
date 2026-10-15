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
@onready var mining_panel: VBoxContainer = %MiningPanel
@onready var mining_label: Label = %MiningLabel
@onready var mining_result_label: Label = %MiningResultLabel
@onready var choose_asteroid_button: Button = %ChooseAsteroidButton
@onready var start_mining_button: Button = %StartMiningButton
@onready var stop_mining_button: Button = %StopMiningButton
@onready var retry_mining_button: Button = %RetryMiningButton

var _world_state := WorldState.new()
var _ship_selection := ShipSelectionState.new(_world_state)
var _mining_intent := MiningIntentState.new(_world_state)
var _travel_intent: RefCounted = TRAVEL_INTENT_STATE.new()
var _attack_intent: RefCounted = ATTACK_INTENT_STATE.new(_world_state, _ship_selection)
var _combat_result_state: RefCounted = COMBAT_RESULT_STATE.new()
var _runtime_config: ClientConnectionConfig
var _player_id: String = ""
var _world_ready: bool = false


func _ready() -> void:
	_runtime_config = DEFAULT_CONFIG.duplicate(true) as ClientConnectionConfig
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--protocol="):
			var version: String = argument.trim_prefix("--protocol=")
			if version in [SssConnection.PROTOCOL_VERSION, SssConnection.MINING_PROTOCOL_VERSION]:
				_runtime_config.protocol_version = version
	mining_panel.visible = _runtime_config.protocol_version == SssConnection.MINING_PROTOCOL_VERSION
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
	sss_connection.mining_replay_received.connect(_on_mining_replay)
	_mining_intent.result_received.connect(_on_mining_result)
	_ship_selection.changed.connect(_on_ship_selection_changed)
	_attack_intent.changed.connect(_refresh_combat_controls)
	world_debug_view.destination_selected.connect(_on_destination_selected)
	confirm_travel_button.pressed.connect(_on_confirm_travel)
	cancel_travel_button.pressed.connect(_on_cancel_travel)
	attack_button.pressed.connect(_on_attack_pressed)

	choose_asteroid_button.pressed.connect(_on_choose_asteroid)
	start_mining_button.pressed.connect(_on_start_mining)
	stop_mining_button.pressed.connect(_on_stop_mining)
	retry_mining_button.pressed.connect(_on_retry_mining)
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

	_world_state.clear()
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

		_world_state.clear()


func _on_authenticated(payload: Dictionary) -> void:
	_player_id = str(payload.get("player_id", ""))
	_travel_intent.set_player_id(_player_id)
	_attack_intent.set_player_id(_player_id)

	_mining_intent.set_player_id(_player_id)
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
		_world_ready = true
		status_label.text = "SSS: full_snapshot aplicado"
	else:
		if not _world_state.apply_map_delta(payload):
			_world_ready = false
			_on_protocol_error("El map_delta no pudo aplicarse (desincronización local)")
			sss_connection.request_full_snapshot()
			return
		status_label.text = "SSS: world_delta aplicado"

	var own_ship: Dictionary = _world_state.ship_for_player(_player_id)
	_travel_intent.apply_authoritative_ship(own_ship)
	if str(own_ship.get("state", "")) == "TRAVELING":
		sss_connection.resolve_start_travel_request()
	_mining_intent.apply_authoritative_ship(own_ship)
	if not _mining_intent.is_pending():
		sss_connection.resolve_mining_request()
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
	var marker: String = "CLIENT_M3_SNAPSHOT_OK" if _world_state.protocol_version == SssConnection.MINING_PROTOCOL_VERSION else "CLIENT_M2_SNAPSHOT_OK"
	print("%s protocol=%s seq=%d entidades=%d" % [
		marker,
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
		_refresh_travel_controls()
		return
	if error_code.begins_with("MINING_"):
		if _mining_intent.handle_error(payload):
			sss_connection.resolve_mining_request()
			status_label.text = _mining_error_text(error_code)
		_refresh_travel_controls()
		return
	if SssConnection.TRAVEL_ERROR_CODES.has(error_code):
		_travel_intent.reject_request(error_code)
		status_label.text = "SSS rechazó start_travel: %s" % error_code
		travel_label.text = "Viaje rechazado · %s · %s" % [error_code, message]
		_refresh_travel_controls(true)
		return
	status_label.text = "SSS error: %s · %s" % [error_code, message]


func _on_desync_detected() -> void:
	_clear_transient_combat_ui()
	_world_ready = false
	_mining_intent.reset_transient()
	sss_connection.resolve_mining_request()
	world_debug_view.clear_selection()
	_refresh_travel_controls()
	status_label.text = "SSS: secuencia desincronizada — solicitando full_snapshot"


func _on_ship_selection_changed() -> void:
	_mining_intent.observe_selection(_ship_selection)
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
	if not _world_ready or sss_connection.is_action_pending() or _mining_intent.has_uncertain_request() or not _attack_intent.can_attack():
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
	_refresh_travel_controls()


func _on_combat_result(payload: Dictionary) -> void:
	_attack_intent.complete_request(str(payload.get("request_id", "")))
	_combat_result_state.apply_result(payload)
	_refresh_travel_controls()


func _on_destination_selected(destination: Vector2i) -> void:
	if not _world_ready or _attack_intent.awaiting_resolution or _mining_intent.is_pending() or _mining_intent.has_uncertain_request() or _mining_intent.choosing_asteroid:
		return
	if not _travel_intent.choose_destination(destination, _world_state.map_size):
		return
	status_label.text = "Destino provisional seleccionado; confirma o cancela"
	_refresh_travel_controls()


func _on_confirm_travel() -> void:
	if not _world_ready or _mining_intent.is_pending() or _mining_intent.has_uncertain_request():
		return
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
	_refresh_mining_controls()
	_refresh_combat_controls()
	var own_ship: Dictionary = _world_state.ship_for_player(_player_id)
	var ship_state: String = str(own_ship.get("state", ""))
	var may_pick_destination: bool = (_travel_intent.can_choose_destination() and _world_ready
		and not _mining_intent.is_pending() and not _mining_intent.has_uncertain_request()
		and not _mining_intent.choosing_asteroid and not _attack_intent.awaiting_resolution)
	_refresh_world_interaction()
	world_debug_view.set_destination_selection_enabled(may_pick_destination)
	world_debug_view.set_asteroid_selection_enabled(_mining_intent.choosing_asteroid)
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

	attack_button.disabled = (not _world_ready or sss_connection.is_action_pending()
		or _mining_intent.has_uncertain_request() or not _attack_intent.can_attack())
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
		_world_ready and not _travel_intent.awaiting_resolution and not _attack_intent.awaiting_resolution
		and not sss_connection.is_action_pending() and not _mining_intent.is_pending()
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
	_world_ready = false
	_mining_intent.reset_transient()
	sss_connection.resolve_mining_request()
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

func _on_choose_asteroid() -> void:
	if not _may_send_mining() or not _mining_intent.begin_choose_asteroid():
		return
	_travel_intent.cancel_destination()
	_refresh_travel_controls()


func _on_start_mining() -> void:
	if _may_send_mining():
		_send_mining_action(_mining_intent.begin_start(_new_request_id()))


func _on_stop_mining() -> void:
	if _may_send_mining():
		_send_mining_action(_mining_intent.begin_stop())


func _on_retry_mining() -> void:
	if _may_send_mining():
		_send_mining_action(_mining_intent.begin_retry())


func _may_send_mining() -> bool:
	return (_world_ready and _runtime_config.protocol_version == SssConnection.MINING_PROTOCOL_VERSION
		and not _travel_intent.awaiting_resolution and not sss_connection.is_action_pending())


func _send_mining_action(action: Dictionary) -> void:
	if action.is_empty():
		return
	if not sss_connection.request_mining(action):
		_mining_intent.fail_send()
	_refresh_travel_controls()


func _on_mining_replay(payload: Dictionary) -> void:
	if _mining_intent.handle_replay(payload):
		sss_connection.resolve_mining_request()
	_refresh_travel_controls()


func _on_mining_result(result: Dictionary) -> void:
	print("CLIENT_M3_MINING_RESULT_OK mining_id=%s quantity=%d reason=%s" % [
		result.get("mining_id", ""), int(result.get("quantity", 0)), result.get("reason", ""),
	])


func _refresh_mining_controls() -> void:
	var may_send: bool = _may_send_mining()
	choose_asteroid_button.disabled = not may_send or not _mining_intent.can_choose_asteroid()
	start_mining_button.disabled = not may_send or not _mining_intent.can_start()
	stop_mining_button.disabled = not may_send or not _mining_intent.can_stop()
	retry_mining_button.disabled = not may_send or not _mining_intent.has_uncertain_request()
	retry_mining_button.visible = _mining_intent.has_uncertain_request()
	var ship: ShipRepresentation = _world_state.get_ship_for_player(_player_id)
	var mining: Variant = null if ship == null else ship.to_entity().get("mining")
	if not _world_ready:
		mining_label.text = "Minería: esperando sincronización del servidor"
	elif _mining_intent.is_pending():
		mining_label.text = "Minería: esperando respuesta del servidor"
	elif _mining_intent.has_uncertain_request():
		mining_label.text = "Hay una solicitud sin confirmar. Recupera su resultado antes de otra acción."
	elif not _mining_intent.last_rejection_code.is_empty():
		mining_label.text = _mining_error_text(_mining_intent.last_rejection_code)
	elif mining is Dictionary:
		mining_label.text = "Minando · extraído %d · tasa %d/s" % [
			int(mining.get("extracted_quantity", 0)), int(mining.get("rate_units_per_second", 0)),
		]
	elif _mining_intent.choosing_asteroid:
		mining_label.text = "Toca un asteroide para elegirlo como objetivo"
	elif not _mining_intent.asteroid_entity_id.is_empty():
		var target: Dictionary = _world_state.get_entity(_mining_intent.asteroid_entity_id)
		mining_label.text = "Asteroide · disponible %d · %s" % [
			int(target.get("remaining_quantity", 0)), "ocupado" if target.get("occupant_entity_id") != null else "libre",
		]
	else:
		mining_label.text = "Selecciona tu nave y pulsa Elegir asteroide"
	var result: Dictionary = _mining_intent.last_result
	mining_result_label.text = "Resultado: —" if result.is_empty() else "Resultado: %d de %s · %s" % [
		int(result.get("quantity", 0)), result.get("resource_type", ""),
		"completado" if result.get("status") == "COMPLETED" else "cancelado",
	]


func _mining_error_text(code: String) -> String:
	var messages: Dictionary = {
		"MINING_OUT_OF_RANGE": "Acerca la nave al asteroide mediante un viaje antes de minar.",
		"MINING_ASTEROID_OCCUPIED": "Otra nave está minando ese asteroide.",
		"MINING_DEPLETED": "El asteroide está agotado.",
		"MINING_SHIP_NOT_ANCHORED": "Espera a que la nave termine el viaje.",
		"MINING_ALREADY_ACTIVE": "Tu nave ya está minando.",
		"MINING_LIMIT_REACHED": "Se alcanzó el límite de solicitudes de esta demostración.",
		"CLIENT_NOT_CONNECTED": "No se pudo enviar la solicitud. Comprueba la conexión.",
	}
	return str(messages.get(code, "El servidor rechazó la solicitud de minería."))


func _new_request_id() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		# Android: descartamos intención local y reconstruimos la trayectoria
		# autoritativa mediante full_snapshot en la nueva conexión.
		_world_state.clear()
		world_debug_view.clear_selection()
		_clear_transient_travel_ui()
		_clear_transient_combat_ui()
		sss_connection.connect_to_server(_runtime_config)
