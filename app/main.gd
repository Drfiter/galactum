extends Control

const DEFAULT_CONFIG: ClientConnectionConfig = preload("res://config/default_client_connection.tres")

@onready var sss_connection: SssConnection = %SssConnection
@onready var host_edit: LineEdit = %HostEdit
@onready var port_edit: SpinBox = %PortEdit
@onready var connect_button: Button = %ConnectButton
@onready var status_label: Label = %StatusLabel
@onready var metadata_label: Label = %MetadataLabel
@onready var ship_label: Label = %ShipLabel
@onready var world_debug_view: WorldDebugView = %WorldDebugView

var _world_state := WorldState.new()
var _runtime_config: ClientConnectionConfig


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
	sss_connection.protocol_error.connect(_on_protocol_error)
	sss_connection.desync_detected.connect(_on_desync_detected)
	world_debug_view.entity_selected.connect(_on_entity_selected)
	status_label.text = "SSS: desconectado"
	if _runtime_config.auto_connect:
		_connect_from_form()


func _connect_from_form() -> void:
	_runtime_config.host = host_edit.text.strip_edges()
	_runtime_config.port = int(port_edit.value)
	status_label.text = "SSS: conectando a %s" % _runtime_config.websocket_url()
	sss_connection.connect_to_server(_runtime_config)


func _on_connection_state_changed(state: String) -> void:
	status_label.text = "SSS: %s" % state
	connect_button.text = "Reconectar" if state != "disconnected" else "Conectar"


func _on_authenticated(payload: Dictionary) -> void:
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
		_refresh_ship_label()
	else:
		if not _world_state.apply_map_delta(payload):
			_on_protocol_error("El map_delta no pudo aplicarse (desincronización local)")
			return
		status_label.text = "SSS: world_delta aplicado"
	metadata_label.text = "protocol=%s · seq=%d · server_time=%d · system_id=%s · entidades=%d" % [
		_world_state.protocol_version,
		_world_state.seq,
		_world_state.server_time,
		_world_state.system_id,
		_world_state.entities.size(),
	]


func _refresh_ship_label() -> void:
	var ship: Dictionary = _world_state.first_ship()
	if ship.is_empty():
		ship_label.text = "Nave: no encontrada en la réplica"
		return
	ship_label.text = "Nave · entity_id=%s · ship_id=%s · player_id=%s · pos=%s" % [
		ship.get("entity_id", ""),
		ship.get("ship_id", ""),
		ship.get("player_id", ""),
		str(ship.get("position", [])),
	]
	print("CLIENT_M1_SNAPSHOT_OK protocol=%s seq=%d entidades=%d" % [
		_world_state.protocol_version,
		_world_state.seq,
		_world_state.entities.size(),
	])


func _on_latency_updated(milliseconds: int) -> void:
	status_label.text = "SSS: conectado · ping %d ms" % milliseconds


func _on_protocol_error(message: String) -> void:
	status_label.text = "SSS error: %s" % message


func _on_desync_detected() -> void:
	status_label.text = "SSS: secuencia desincronizada — solicitando full_snapshot"


func _on_entity_selected(entity_id: String) -> void:
	if entity_id == "":
		ship_label.text = "Selección: —"
		return
	var entity: Dictionary = _world_state.get_entity(entity_id)
	if entity.is_empty():
		ship_label.text = "Selección: %s (desconocida)" % entity_id
		return
	ship_label.text = "Selección · kind=%s · entity_id=%s · pos=%s" % [
		entity.get("kind", ""),
		entity_id,
		str(entity.get("position", [])),
	]


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		# Android: al reanudar, reconectamos y el SSS reconstruirá la réplica
		# con un full_snapshot en la nueva conexión.
		_world_state.clear()
		sss_connection.connect_to_server(_runtime_config)
