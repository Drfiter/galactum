class_name ShipSelectionState
extends RefCounted
## Selección por entity_id de la réplica visible; independiente de UI y acciones.
## Mantiene selección genérica M1; get_selected_ship filtra únicamente naves.

signal changed

var selected_entity_id: String = ""
var _world: WorldState


func _init(world: WorldState) -> void:
	_world = world
	_world.changed.connect(_on_world_changed)


func select_entity(entity_id: String) -> bool:
	var exists: bool = not _world.get_entity(entity_id).is_empty()
	var next_id: String = entity_id if exists else ""
	if next_id != selected_entity_id:
		selected_entity_id = next_id
		changed.emit()
	return exists


func clear() -> void:
	select_entity("")


func get_selected_ship() -> ShipRepresentation:
	return _world.get_ship(selected_entity_id)


func _on_world_changed() -> void:
	if selected_entity_id == "":
		return
	if _world.get_entity(selected_entity_id).is_empty():
		selected_entity_id = ""
	changed.emit()
