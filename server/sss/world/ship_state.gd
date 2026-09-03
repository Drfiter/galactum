class_name ShipState
extends RefCounted

var entity_id: String
var ship_id: String
var player_id: String
var system_id: String
var display_name: String
var position: Vector2i


func _init(seed: MockWorldSeed) -> void:
	entity_id = seed.entity_id
	ship_id = seed.ship_id
	player_id = seed.player_id
	system_id = seed.system_id
	display_name = seed.ship_name
	position = seed.ship_position


func to_snapshot() -> Dictionary:
	return {
		"entity_id": entity_id,
		"ship_id": ship_id,
		"player_id": player_id,
		"system_id": system_id,
		"kind": "ship",
		"display_name": display_name,
		"position": [position.x, position.y],
	}
