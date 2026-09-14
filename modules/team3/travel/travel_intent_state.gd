class_name TravelIntentState
extends RefCounted
## Estado transitorio de UI para preparar una intención start_travel.
## ANCHORED/TRAVELING nunca se deciden aquí: solo se reflejan desde la réplica.

var player_id: String = ""
var selected_entity_id: String = ""
var selected_own_ship_id: String = ""
var authoritative_state: String = ""
var provisional_destination: Vector2i = Vector2i.ZERO
var has_provisional_destination: bool = false
var awaiting_resolution: bool = false
var last_rejection_code: String = ""


func set_player_id(value: String) -> void:
	player_id = value


func select_entity(entity: Dictionary) -> bool:
	if awaiting_resolution:
		return false
	selected_entity_id = str(entity.get("entity_id", ""))
	selected_own_ship_id = ""
	authoritative_state = str(entity.get("state", ""))
	clear_destination()
	if str(entity.get("kind", "")) != "ship":
		return false
	if player_id == "" or str(entity.get("player_id", "")) != player_id:
		return false
	selected_own_ship_id = selected_entity_id
	return true


func can_choose_destination() -> bool:
	return (selected_own_ship_id != ""
		and authoritative_state == "ANCHORED"
		and not awaiting_resolution)


func choose_destination(destination: Vector2i, map_size: Vector2i) -> bool:
	if not can_choose_destination():
		return false
	if destination.x < 0 or destination.y < 0:
		return false
	if destination.x >= map_size.x or destination.y >= map_size.y:
		return false
	provisional_destination = destination
	has_provisional_destination = true
	last_rejection_code = ""
	return true


func cancel_destination() -> bool:
	if awaiting_resolution or not has_provisional_destination:
		return false
	clear_destination()
	return true


func begin_request() -> bool:
	if not can_choose_destination() or not has_provisional_destination:
		return false
	awaiting_resolution = true
	last_rejection_code = ""
	return true


func reject_request(error_code: String) -> bool:
	if not awaiting_resolution:
		return false
	awaiting_resolution = false
	last_rejection_code = error_code
	return true


func apply_authoritative_ship(ship: Dictionary) -> void:
	if ship.is_empty() or str(ship.get("entity_id", "")) != selected_own_ship_id:
		return
	authoritative_state = str(ship.get("state", ""))
	if authoritative_state == "TRAVELING":
		awaiting_resolution = false
		clear_destination()
		last_rejection_code = ""


func reset_transient() -> void:
	awaiting_resolution = false
	clear_destination()
	last_rejection_code = ""


func clear_destination() -> void:
	provisional_destination = Vector2i.ZERO
	has_provisional_destination = false
