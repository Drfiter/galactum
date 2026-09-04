class_name EntityState
extends RefCounted

var entity_id: String
var kind: String
var position: Vector2i
## Campos específicos del tipo (display_name, ship_id, ...). No contiene entity_id/kind/position.
var payload: Dictionary = {}


func _init(p_entity_id: String = "", p_kind: String = "", p_position: Vector2i = Vector2i.ZERO) -> void:
	entity_id = p_entity_id
	kind = p_kind
	position = p_position


## Entidad completa (para added / full_snapshot).
func to_add_snapshot() -> Dictionary:
	var snapshot: Dictionary = payload.duplicate(true)
	snapshot["entity_id"] = entity_id
	snapshot["kind"] = kind
	snapshot["position"] = [position.x, position.y]
	return snapshot
