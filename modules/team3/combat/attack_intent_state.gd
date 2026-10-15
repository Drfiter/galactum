class_name AttackIntentState
extends RefCounted
## Estado local y no autoritativo de la intencion de ataque.
## El objetivo proviene de ShipSelectionState; el atacante siempre lo deriva el SSS.

signal changed

var player_id: String = ""
var target_entity_id: String = ""
var pending_request_id: String = ""
var awaiting_resolution: bool = false
var last_rejection_code: String = ""
var last_rejection_message: String = ""

var _world: WorldState
var _selection: ShipSelectionState


func _init(world: WorldState, selection: ShipSelectionState) -> void:
	_world = world
	_selection = selection
	_world.changed.connect(_on_world_changed)
	_selection.changed.connect(_on_selection_changed)
	_refresh_target_from_selection()


func set_player_id(value: String) -> void:
	if player_id == value:
		return
	player_id = value
	if not awaiting_resolution:
		_refresh_target_from_selection()
	changed.emit()


func can_attack() -> bool:
	if awaiting_resolution or player_id == "" or target_entity_id == "":
		return false
	var attacker: ShipRepresentation = _world.get_ship_for_player(player_id)
	var target: ShipRepresentation = _world.get_ship(target_entity_id)
	if attacker == null or target == null:
		return false
	if attacker.entity_id == target.entity_id or target.is_owned_by(player_id):
		return false
	return attacker.state == "ANCHORED" and target.state == "ANCHORED"


func begin_request(request_id: String) -> bool:
	if request_id == "" or not can_attack():
		return false
	pending_request_id = request_id
	awaiting_resolution = true
	last_rejection_code = ""
	last_rejection_message = ""
	changed.emit()
	return true


func complete_request(request_id: String) -> bool:
	if not _matches_pending_request(request_id):
		return false
	_clear_pending()
	_refresh_target_from_selection()
	changed.emit()
	return true


func reject_request(request_id: String, error_code: String, message: String) -> bool:
	if not _matches_pending_request(request_id):
		return false
	_clear_pending()
	last_rejection_code = error_code
	last_rejection_message = message
	_refresh_target_from_selection()
	changed.emit()
	return true


## Una conexion nueva no permite reconstruir con seguridad una solicitud en vuelo.
## No se reenvia ni se inventa un resultado; el replay historico queda pendiente.
func reset_transient() -> void:
	var had_state: bool = (awaiting_resolution or pending_request_id != ""
		or target_entity_id != "" or last_rejection_code != ""
		or last_rejection_message != "")
	_clear_pending()
	target_entity_id = ""
	last_rejection_code = ""
	last_rejection_message = ""
	if had_state:
		changed.emit()


func _matches_pending_request(request_id: String) -> bool:
	return awaiting_resolution and (request_id == "" or request_id == pending_request_id)


func _clear_pending() -> void:
	pending_request_id = ""
	awaiting_resolution = false


func _on_selection_changed() -> void:
	if awaiting_resolution:
		return
	_refresh_target_from_selection()
	last_rejection_code = ""
	last_rejection_message = ""
	changed.emit()


func _on_world_changed() -> void:
	if not awaiting_resolution:
		_refresh_target_from_selection()
	changed.emit()


func _refresh_target_from_selection() -> void:
	var selected_ship: ShipRepresentation = _selection.get_selected_ship()
	if selected_ship == null or selected_ship.is_owned_by(player_id):
		target_entity_id = ""
		return
	target_entity_id = selected_ship.entity_id
