extends SceneTree
## Detecta selección obsoleta, dependencia de UI y pérdida de selección en updates.

var _failures: int = 0
var _changes: int = 0


func _initialize() -> void:
	var path: String = "res://modules/team3/ships/ship_selection_state.gd"
	if not ResourceLoader.exists(path):
		_check(false, "falta selección independiente de UI")
		_finish()
		return
	var script: Script = load(path)
	var world := WorldState.new()
	world.apply_full_snapshot(_snapshot())
	var selection: RefCounted = script.new(world)
	selection.changed.connect(func() -> void: _changes += 1)
	_check(selection.select_entity("own"), "selección por entity_id")
	_check(selection.get_selected_ship().ship_id == "ship-1", "consumidor obtiene ship_id distinto")
	world.apply_map_delta({"seq": 2, "updated": [{"entity_id": "own", "position": [120, 100]}]})
	_check(selection.selected_entity_id == "own" and selection.get_selected_ship().position == Vector2(120, 100), "update conserva selección con datos frescos")
	world.apply_map_delta({"seq": 3, "removed": ["own"]})
	_check(selection.selected_entity_id == "" and selection.get_selected_ship() == null, "salida AOI invalida selección")
	_check(_changes == 3, "señales de selección, actualización e invalidación")
	world.apply_full_snapshot(_snapshot())
	selection.select_entity("own")
	world.apply_full_snapshot({"seq": 5, "map_size": [600, 600], "added": []})
	_check(selection.selected_entity_id == "", "snapshot excluyente invalida selección")
	_check(not selection.select_entity("missing"), "ID ausente no se selecciona")
	world.apply_full_snapshot(_snapshot())
	selection.select_entity("rock")
	_check(selection.selected_entity_id == "rock" and selection.get_selected_ship() == null, "selección genérica M1 preservada")
	selection.clear()
	_check(selection.selected_entity_id == "", "clear explícito")
	selection.select_entity("own")
	world.clear()
	_check(selection.selected_entity_id == "", "resume limpia selección")
	_finish()


func _snapshot() -> Dictionary:
	return {"seq": 1, "map_size": [600, 600], "added": [
		{"entity_id": "own", "ship_id": "ship-1", "player_id": "player-1", "kind": "ship", "position": [100, 100], "state": "ANCHORED"},
		{"entity_id": "rock", "kind": "asteroid", "position": [110, 100]},
	]}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_SHIP_SELECTION_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("M3_SHIP_SELECTION_TEST_OK" if _failures == 0 else "M3_SHIP_SELECTION_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
