class_name WorldState
extends RefCounted

signal changed

var protocol_version: String = ""
var seq: int = -1
var server_time: int = 0
var system_id: String = ""
var map_size: Vector2i = Vector2i.ZERO
var entities: Dictionary = {}


func apply_full_snapshot(message: Dictionary) -> bool:
	var incoming_seq: int = int(message.get("seq", -1))
	if incoming_seq < 0:
		return false
	protocol_version = str(message.get("protocol_version", ""))
	seq = incoming_seq
	server_time = int(message.get("server_time", 0))
	system_id = str(message.get("system_id", ""))
	var raw_map_size: Array = message.get("map_size", [0, 0])
	if raw_map_size.size() != 2:
		return false
	map_size = Vector2i(int(raw_map_size[0]), int(raw_map_size[1]))
	entities.clear()
	for raw_entity: Variant in message.get("added", []):
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		var entity_id: String = str(entity.get("entity_id", ""))
		if entity_id != "":
			entities[entity_id] = entity.duplicate(true)
	changed.emit()
	return true


func first_ship() -> Dictionary:
	for entity: Variant in entities.values():
		if entity is Dictionary and str(entity.get("kind", "")) == "ship":
			return entity
	return {}
