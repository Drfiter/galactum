class_name WorldChangeSet
extends RefCounted

## ChangeSet compartido de UN tick del mundo. Vive en el mundo y es filtrado por
## cada sesión según su propio AOI; NINGUNA sesión lo drena ni lo borra, para que
## un cliente no consuma cambios que otro todavía necesita.
##
## - added:   Array[EntityState] entidades nuevas (completas al emitir)
## - updated: Array[EntityState] entidades modificadas (entity_id + campos cambiados al emitir)
## - removed: Array[Dictionary] { "entity_id": String, "position": Vector2i } — la posición
##   se conserva para que cada sesión pueda filtrar por AOI, pero se emite solo el id.

var _added: Array[EntityState] = []
var _updated: Array[EntityState] = []
var _removed: Array[Dictionary] = []


func clear() -> void:
	_added.clear()
	_updated.clear()
	_removed.clear()


func add_entity(entity: EntityState) -> void:
	_added.append(entity)


func update_entity(entity: EntityState) -> void:
	_updated.append(entity)


## position = última posición conocida de la entidad antes de eliminarla.
func remove_entity(entity_id: String, position: Vector2i) -> void:
	_removed.append({"entity_id": entity_id, "position": position})


func has_changes() -> bool:
	return not _added.is_empty() or not _updated.is_empty() or not _removed.is_empty()


func added() -> Array[EntityState]:
	return _added


func updated() -> Array[EntityState]:
	return _updated


## Array[Dictionary] { entity_id, position }
func removed() -> Array[Dictionary]:
	return _removed
