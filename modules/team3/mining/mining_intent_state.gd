class_name MiningIntentState
extends RefCounted
## Contexto de acción sobre la selección compartida. Nunca escribe WorldState.

signal result_received(result: Dictionary)

var player_id: String = ""
var actor_entity_id: String = ""
var asteroid_entity_id: String = ""
var choosing_asteroid: bool = false
var last_rejection_code: String = ""
var last_result: Dictionary = {}
var _world: WorldState
var _pending: Dictionary = {}
var _uncertain: Dictionary = {}
var _seen_results: Dictionary = {}


func _init(world: WorldState) -> void:
	_world = world


func set_player_id(value: String) -> void:
	if player_id != value:
		_uncertain.clear()
		_pending.clear()
		_seen_results.clear()
		last_result.clear()
	player_id = value


func observe_selection(selection: ShipSelectionState) -> void:
	_validate_context()
	var selected: ShipRepresentation = selection.get_selected_ship()
	if selected != null:
		actor_entity_id = selected.entity_id if selected.is_owned_by(player_id) else ""
		asteroid_entity_id = ""
		return
	if choosing_asteroid:
		var entity: Dictionary = _world.get_entity(selection.selected_entity_id)
		if str(entity.get("kind", "")) == "asteroid" and _actor() != null:
			asteroid_entity_id = selection.selected_entity_id
			choosing_asteroid = false
			last_rejection_code = ""
	elif selection.selected_entity_id != asteroid_entity_id:
		asteroid_entity_id = ""


func begin_choose_asteroid() -> bool:
	if not can_choose_asteroid():
		return false
	choosing_asteroid = true
	asteroid_entity_id = ""
	last_rejection_code = ""
	return true


func can_choose_asteroid() -> bool:
	var actor: ShipRepresentation = _actor()
	return actor != null and actor.state == "ANCHORED" and _pending.is_empty() and _uncertain.is_empty()


func can_start() -> bool:
	_validate_context()
	var target: Dictionary = _world.get_entity(asteroid_entity_id)
	return (can_choose_asteroid() and not choosing_asteroid
		and str(target.get("kind", "")) == "asteroid"
		and str(target.get("asteroid_state", "")) == "AVAILABLE"
		and _active_mining().is_empty())


func can_stop() -> bool:
	return _pending.is_empty() and _uncertain.is_empty() and not _active_mining().is_empty()


func begin_start(request_id: String) -> Dictionary:
	if not can_start():
		return {}
	_pending = {"type": "start_mining", "request_id": request_id, "asteroid_entity_id": asteroid_entity_id}
	last_rejection_code = ""
	return _pending.duplicate(true)


func begin_stop() -> Dictionary:
	if not can_stop():
		return {}
	_pending = {"type": "stop_mining", "mining_id": _active_mining()["mining_id"]}
	last_rejection_code = ""
	return _pending.duplicate(true)


func begin_retry() -> Dictionary:
	if _uncertain.is_empty() or not _pending.is_empty():
		return {}
	_pending = _uncertain.duplicate(true)
	return _pending.duplicate(true)


func is_pending() -> bool:
	return not _pending.is_empty()


func has_uncertain_request() -> bool:
	return not _uncertain.is_empty()


func fail_send() -> void:
	_pending.clear()
	last_rejection_code = "CLIENT_NOT_CONNECTED"


func apply_authoritative_ship(ship: Dictionary) -> void:
	_validate_context()
	if str(ship.get("player_id", "")) != player_id or player_id.is_empty():
		return
	if _proves_resolution(_pending, ship):
		_pending.clear()
		_uncertain.clear()
	if _proves_resolution(_uncertain, ship):
		_uncertain.clear()
	var result: Variant = ship.get("last_mining_result")
	if result is Dictionary:
		_consume_result(result)


func handle_error(message: Dictionary) -> bool:
	if not str(message.get("error_code", "")).begins_with("MINING_") or not matches_response(_pending, message):
		return false
	last_rejection_code = str(message["error_code"])
	_pending.clear()
	_uncertain.clear()
	return true


func handle_replay(message: Dictionary) -> bool:
	if not matches_response(_pending, message):
		return false
	var result: Variant = message.get("result")
	if not result is Dictionary or str(result.get("mining_id", "")) != str(message.get("mining_id", "")):
		return false
	if str(result.get("status", "")) not in ["COMPLETED", "CANCELLED"]:
		return false
	if _pending["type"] == "start_mining" and result.get("request_id") != _pending["request_id"]:
		return false
	_consume_result(result)
	_pending.clear()
	_uncertain.clear()
	return true


static func matches_response(pending: Dictionary, message: Dictionary) -> bool:
	if pending.is_empty() or str(pending.get("type", "")) != str(message.get("request_type", "")):
		return false
	if pending["type"] == "start_mining":
		return str(pending.get("request_id", "")) == str(message.get("request_id", ""))
	return str(pending.get("mining_id", "")) == str(message.get("mining_id", ""))


func reset_transient() -> void:
	if not _pending.is_empty():
		_uncertain = _pending.duplicate(true)
	_pending.clear()
	actor_entity_id = ""
	asteroid_entity_id = ""
	choosing_asteroid = false
	last_rejection_code = ""


func _actor() -> ShipRepresentation:
	var actor: ShipRepresentation = _world.get_ship(actor_entity_id)
	return actor if actor != null and actor.is_owned_by(player_id) else null


func _validate_context() -> void:
	if _actor() == null:
		actor_entity_id = ""
		asteroid_entity_id = ""
		choosing_asteroid = false
	if _world.get_entity(asteroid_entity_id).is_empty():
		asteroid_entity_id = ""


func _active_mining() -> Dictionary:
	var own: ShipRepresentation = _world.get_ship_for_player(player_id)
	if own == null:
		return {}
	var raw: Variant = own.to_entity().get("mining")
	return raw if raw is Dictionary else {}


func _proves_resolution(action: Dictionary, ship: Dictionary) -> bool:
	if action.is_empty():
		return false
	var active: Variant = ship.get("mining")
	var terminal: Variant = ship.get("last_mining_result")
	if action["type"] == "start_mining":
		return ((active is Dictionary and active.get("request_id") == action["request_id"])
			or (terminal is Dictionary and terminal.get("request_id") == action["request_id"]))
	return terminal is Dictionary and terminal.get("mining_id") == action["mining_id"]


func _consume_result(result: Dictionary) -> void:
	var mining_id: String = str(result.get("mining_id", ""))
	if mining_id.is_empty() or str(result.get("status", "")) not in ["COMPLETED", "CANCELLED"]:
		return
	last_result = result.duplicate(true)
	if not _seen_results.has(mining_id):
		_seen_results[mining_id] = true
		result_received.emit(result.duplicate(true))
