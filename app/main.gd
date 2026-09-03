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
	sss_connection.full_snapshot_received.connect(_on_full_snapshot)
	sss_connection.latency_updated.connect(_on_latency_updated)
	sss_connection.protocol_error.connect(_on_protocol_error)
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


func _on_full_snapshot(payload: Dictionary) -> void:
	if not _world_state.apply_full_snapshot(payload):
		_on_protocol_error("El full_snapshot no pudo aplicarse")
		return
	status_label.text = "SSS: full_snapshot recibido"
	metadata_label.text = "protocol=%s · seq=%d · server_time=%d · system_id=%s" % [
		_world_state.protocol_version,
		_world_state.seq,
		_world_state.server_time,
		_world_state.system_id,
	]
	var ship: Dictionary = _world_state.first_ship()
	if ship.is_empty():
		ship_label.text = "Nave dummy: no encontrada"
		return
	ship_label.text = "Nave dummy visible · entity_id=%s · ship_id=%s · player_id=%s · pos=%s" % [
		ship.get("entity_id", ""),
		ship.get("ship_id", ""),
		ship.get("player_id", ""),
		str(ship.get("position", [])),
	]
	print("CLIENT_M0_SNAPSHOT_OK protocol=%s seq=%d entity_id=%s" % [
		_world_state.protocol_version,
		_world_state.seq,
		ship.get("entity_id", ""),
	])


func _on_latency_updated(milliseconds: int) -> void:
	status_label.text = "SSS: conectado · ping %d ms" % milliseconds


func _on_protocol_error(message: String) -> void:
	status_label.text = "SSS error: %s" % message


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		sss_connection.connect_to_server(_runtime_config)
