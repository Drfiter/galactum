extends SceneTree
## TEAM3-M3 ETAPA 4: resultado tipado de cliente y deduplicación por combat_id.

var _failures: int = 0
var _changes: int = 0


func _initialize() -> void:
	var world := WorldState.new()
	world.apply_full_snapshot({
		"seq": 1,
		"map_size": [600, 600],
		"added": [{"entity_id": "target", "kind": "ship", "position": [340, 300]}],
	})
	var world_before: Dictionary = world.get_entity("target")
	var state := CombatResultState.new()
	state.changed.connect(func() -> void: _changes += 1)
	var first: Dictionary = _result("combat-1", "attacker_win", 10, 1000)

	_check(state.apply_result(first), "primer combat_result se aplica")
	_check(state.combat_id == "combat-1" and state.combat_version == "m3-provisional-1",
		"conserva IDs y versión de negocio")
	_check(state.outcome == "attacker_win", "conserva outcome")
	_check(state.casualties.get("defender", [])[0].get("quantity") == 1, "conserva bajas")
	_check(state.result_count() == 1 and _changes == 1, "registra un único resultado")

	var duplicate: Dictionary = _result("combat-1", "defender_win", 99, 9999)
	_check(not state.apply_result(duplicate), "combat_id repetido se deduplica")
	_check(state.outcome == "attacker_win" and state.result_count() == 1 and _changes == 1,
		"duplicado no vuelve a mostrar ni reemplazar resultado")
	_check(world.get_entity("target") == world_before, "CombatResultState no muta WorldState")

	first["casualties"]["defender"][0]["quantity"] = 999
	_check(state.casualties.get("defender", [])[0].get("quantity") == 1,
		"estado conserva copia profunda independiente del envelope")
	_check(state.apply_result(_result("combat-2", "draw", 11, 1001)), "otro combat_id sí se aplica")
	_check(state.combat_id == "combat-2" and state.result_count() == 2 and _changes == 2,
		"segundo combate actualiza presentación una sola vez")
	_finish()


func _result(combat_id: String, outcome: String, seq: int, server_time: int) -> Dictionary:
	return {
		"type": "combat_result",
		"protocol_version": "team3-m2.0",
		"seq": seq,
		"server_time": server_time,
		"request_id": "request-1",
		"combat_id": combat_id,
		"combat_version": "m3-provisional-1",
		"resolved_ts": 900,
		"attacker": {"entity_id": "own", "ship_id": "ship-own"},
		"defender": {"entity_id": "target", "ship_id": "ship-target"},
		"outcome": outcome,
		"casualties": {"attacker": [], "defender": [{"unit_type_id": "mock_unit", "quantity": 1}]},
		"remaining_forces": {"attacker": [], "defender": []},
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_COMBAT_RESULT_STATE_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("M3_COMBAT_RESULT_STATE_TEST_OK" if _failures == 0 else "M3_COMBAT_RESULT_STATE_TEST_FAILED failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)
