class_name EntityRegistry
extends RefCounted

## Registro simple de entidades del mundo. Sin ECS, sin framework genérico.
## Encapsula el almacenamiento y las 5 operaciones: add/get/update/erase/enumerate.

var _entities: Dictionary = {}   # entity_id -> EntityState
var _order: Array[String] = []   # orden de inserción (determinista)


func add(entity: EntityState) -> void:
	if entity.entity_id == "":
		push_error("EntityRegistry.add: entity_id vacío")
		return
	if _entities.has(entity.entity_id):
		push_error("EntityRegistry.add: entity_id duplicado: %s" % entity.entity_id)
		return
	_entities[entity.entity_id] = entity
	_order.append(entity.entity_id)


## get_entity(entity_id: String) -> EntityState | null
func get_entity(entity_id: String) -> EntityState:
	if not _entities.has(entity_id):
		return null
	return _entities[entity_id]


func has(entity_id: String) -> bool:
	return _entities.has(entity_id)


## mutator(entity: EntityState) -> void
func update(entity_id: String, mutator: Callable) -> void:
	var entity: EntityState = get_entity(entity_id)
	if entity == null:
		push_error("EntityRegistry.update: entity_id no existe: %s" % entity_id)
		return
	mutator.call(entity)


func erase(entity_id: String) -> void:
	if _entities.has(entity_id):
		_entities.erase(entity_id)
		_order.erase(entity_id)


func all() -> Array[EntityState]:
	var out: Array[EntityState] = []
	for eid: String in _order:
		out.append(_entities[eid] as EntityState)
	return out


func ids() -> Array[String]:
	return _order.duplicate()


func count() -> int:
	return _entities.size()