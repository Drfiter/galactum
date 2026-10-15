extends SceneTree
## Réplica/selección actuales, sin introducir UI de minería ni protocolo runtime M3.

var _failures: int = 0


func _initialize() -> void:
	var world := WorldState.new()
	var selection := ShipSelectionState.new(world)
	var full: Dictionary = {
		"seq": 1, "server_time": 1780000000000, "full": true,
		"system_id": "system", "map_size": [600, 600],
		"added": [{"entity_id": "a", "kind": "asteroid", "position": [310, 290],
			"resource_type": "demo_ore", "remaining_quantity": 10,
			"asteroid_state": "AVAILABLE", "occupant_entity_id": null}],
		"updated": [], "removed": [],
	}
	_check(world.apply_full_snapshot(full), "snapshot de modelo")
	_check(selection.select_entity("a") and selection.get_selected_ship() == null, "selección existente admite asteroide")
	_check(world.apply_map_delta({"seq": 2, "updated": [{"entity_id": "a",
		"remaining_quantity": 8, "asteroid_state": "OCCUPIED", "occupant_entity_id": "ship"}]}), "update parcial")
	var entity: Dictionary = world.get_entity("a")
	_check(entity["resource_type"] == "demo_ore" and entity["position"] == [310, 290], "merge preserva campos estáticos")
	_check(entity["remaining_quantity"] == 8 and selection.selected_entity_id == "a", "actualización conserva selección")
	world.apply_map_delta({"seq": 3, "updated": [{"entity_id": "a",
		"asteroid_state": "AVAILABLE", "occupant_entity_id": null}]})
	_check(world.get_entity("a")["occupant_entity_id"] == null, "null elimina ocupante anterior")
	world.apply_map_delta({"seq": 4, "removed": ["a"]})
	_check(world.get_entity("a").is_empty() and selection.selected_entity_id == "", "salida AOI invalida selección")
	full["seq"] = 5
	full["added"][0]["remaining_quantity"] = 8
	world.apply_full_snapshot(full)
	_check(world.get_entity("a")["remaining_quantity"] == 8, "snapshot reconstruye estado actual")
	selection.select_entity("a")
	full["seq"] = 6
	full["added"][0]["remaining_quantity"] = 0
	full["added"][0]["asteroid_state"] = "DEPLETED"
	world.apply_full_snapshot(full)
	_check(selection.selected_entity_id == "a" and world.get_entity("a")["asteroid_state"] == "DEPLETED", "agotado visible no equivale a removed")
	world.clear()
	_check(selection.selected_entity_id == "", "reconexión limpia selección")
	print("M3_ASTEROID_REPLICA_TEST_OK" if _failures == 0 else "M3_ASTEROID_REPLICA_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_ASTEROID_REPLICA_TEST_FAILED: %s" % message)
