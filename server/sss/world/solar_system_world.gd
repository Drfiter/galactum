class_name SolarSystemWorld
extends RefCounted

var system_id: String
var map_size: Vector2i
var tick_count: int = 0
var server_time: int = 0
var _ship: ShipState


func _init(config: SssConfig, seed: MockWorldSeed) -> void:
	system_id = seed.system_id
	map_size = config.map_size
	_ship = ShipState.new(seed)
	_update_server_time()


func tick() -> void:
	tick_count += 1
	_update_server_time()


func full_snapshot_for(player_id: String) -> Dictionary:
	if player_id != _ship.player_id:
		return {
			"system_id": system_id,
			"map_size": [map_size.x, map_size.y],
			"full": true,
			"added": [],
			"updated": [],
			"removed": [],
		}
	return {
		"system_id": system_id,
		"map_size": [map_size.x, map_size.y],
		"full": true,
		"added": [_ship.to_snapshot()],
		"updated": [],
		"removed": [],
	}


func _update_server_time() -> void:
	server_time = int(Time.get_unix_time_from_system() * 1000.0)
