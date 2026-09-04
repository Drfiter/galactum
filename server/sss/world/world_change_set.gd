class_name WorldChangeSet
extends RefCounted

## ChangeSet compartido de UN tick del mundo. Vive en el mundo y es filtrado por
## cada sesión según su propio AOI; NINGUNA sesión lo drena ni lo borra, para que
## un cliente no consuma cambios que otro todavía necesita.
##
## - added:   Array[EntityState] entidades nuevas en el mundo
## - updated: Array[Dictionary] { "entity": EntityState, "previous_position": Vector2i }
## - removed: Array[Dictionary] { "entity_id": String, "position": Vector2i }

var _added: Array[EntityState] = []
var _updated: Array[Dictionary] = []
var _removed: Array[Dictionary] = []


func clear() -> void:
	_added.clear()
	_updated.clear()
	_removed.clear()


func add_entity(entity: EntityState) -> void:
	_added.append(entity)


func update_entity(entity: EntityState, previous_position: Vector2i = Vector2i(-1, -1)) -> void:
	var prev: Vector2i = previous_position
	if prev == Vector2i(-1, -1):
		prev = entity.position
	_updated.append({
		"entity": entity,
		"previous_position": prev,
	})


## position = última posición conocida de la entidad antes de eliminarla.
func remove_entity(entity_id: String, position: Vector2i) -> void:
	_removed.append({"entity_id": entity_id, "position": position})


func has_changes() -> bool:
	return not _added.is_empty() or not _updated.is_empty() or not _removed.is_empty()


func added() -> Array[EntityState]:
	return _added


## Array[Dictionary] con { "entity": EntityState, "previous_position": Vector2i }
func updated() -> Array[Dictionary]:
	return _updated


## Array[Dictionary] con { "entity_id": String, "position": Vector2i }
func removed() -> Array[Dictionary]:
	return _removed
