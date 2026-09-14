class_name EntityState
extends RefCounted

var entity_id: String
var kind: String
var position: Vector2i
## Campos específicos del tipo (display_name, ship_id, ...). No contiene entity_id/kind/position.
var payload: Dictionary = {}
## Estado de vida de la entidad (M2-I: "ANCHORED" | "TRAVELING").
var state: String = "ANCHORED"
## Estado del viaje en curso. Solo existe mientras state == "TRAVELING":
## { "origin": [x,y], "destination": [x,y], "depart_ts": int ms, "arrive_ts": int ms }
## Al llegar es null/{} (se limpia).
var travel: Dictionary = {}


func _init(p_entity_id: String = "", p_kind: String = "", p_position: Vector2i = Vector2i.ZERO) -> void:
	entity_id = p_entity_id
	kind = p_kind
	position = p_position


func is_traveling() -> bool:
	return state == "TRAVELING"


## Entidad completa (para added / full_snapshot).
## Incluye state y, si viaja, el bloque travel completo (reconnect reconstruye el viaje).
func to_add_snapshot() -> Dictionary:
	var snapshot: Dictionary = payload.duplicate(true)
	snapshot["entity_id"] = entity_id
	snapshot["kind"] = kind
	snapshot["position"] = [position.x, position.y]
	snapshot["state"] = state
	if is_traveling():
		snapshot["travel"] = travel.duplicate(true)
	return snapshot


## Campos actualizados para un `updated` de map_delta.
## Incluye siempre state; travel solo mientras TRAVELING, sino null (contrato M2-I).
func to_updated_snapshot() -> Dictionary:
	var snap: Dictionary = {
		"entity_id": entity_id,
		"position": [position.x, position.y],
		"state": state,
	}
	if is_traveling():
		snap["travel"] = travel.duplicate(true)
	else:
		snap["travel"] = null
	return snap