class_name ShipRepresentation
extends RefCounted
## Copia tipada de una nave visible. No tiene autoridad ni ejecuta acciones.
## Consultar de nuevo WorldState tras un delta; no retener como estado vivo.

var entity_id: String = ""
var ship_id: String = ""
var player_id: String = ""
var system_id: String = ""
var display_name: String = ""
var position: Vector2 = Vector2.ZERO
var state: String = ""
var _entity: Dictionary = {}


func _init(entity: Dictionary) -> void:
	_entity = entity.duplicate(true)
	entity_id = str(entity.get("entity_id", ""))
	ship_id = str(entity.get("ship_id", ""))
	player_id = str(entity.get("player_id", ""))
	system_id = str(entity.get("system_id", ""))
	display_name = str(entity.get("display_name", ""))
	state = str(entity.get("state", ""))
	var raw_position: Variant = entity.get("position")
	if raw_position is Array and raw_position.size() == 2:
		position = Vector2(float(raw_position[0]), float(raw_position[1]))


func is_owned_by(authenticated_player_id: String) -> bool:
	return authenticated_player_id != "" and player_id == authenticated_player_id


## Copia compatible con TravelProjection, incluido travel ausente o null.
## No sintetiza IDs, estadísticas ni nuevos estados.
func to_entity() -> Dictionary:
	var result: Dictionary = _entity.duplicate(true)
	result["entity_id"] = entity_id
	result["ship_id"] = ship_id
	result["player_id"] = player_id
	result["system_id"] = system_id
	result["display_name"] = display_name
	result["position"] = [position.x, position.y]
	result["state"] = state
	return result
