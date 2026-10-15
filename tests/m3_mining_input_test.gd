extends SceneTree

var _failures: int = 0
var _destinations: int = 0


func _initialize() -> void:
	var world := WorldState.new()
	world.apply_full_snapshot({"seq": 1, "full": true, "map_size": [600, 600], "added": [
		{"entity_id": "a", "kind": "asteroid", "position": [310, 290]},
		{"entity_id": "own", "kind": "ship", "player_id": "p1", "position": [310, 290], "state": "ANCHORED"},
	]})
	var selection := ShipSelectionState.new(world)
	var view := WorldDebugView.new()
	root.add_child(view)
	view.size = Vector2(600, 600)
	view.set_world_state(world)
	view.set_selection_state(selection)
	view.get_camera().set_screen_size(view.size)
	view.destination_selected.connect(func(_destination: Vector2i) -> void: _destinations += 1)
	view.set_destination_selection_enabled(true)
	view.set_asteroid_selection_enabled(true)
	var point: Vector2 = view.get_camera().world_to_screen(Vector2(310, 290))
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		view.call("_gui_input", event)
	_check(selection.selected_entity_id == "a" and _destinations == 0, "mouse elige asteroide incluso superpuesto con nave")
	selection.clear()
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = pressed
		view.call("_gui_input", event)
	_check(view.get_selected_entity_id() == selection.selected_entity_id and selection.selected_entity_id == "a", "touch comparte selección única")
	view.set_tap_actions_enabled(false)
	view.call("_handle_tap", Vector2.ZERO)
	_check(selection.selected_entity_id == "a", "pending bloquea cambios de input")
	world.apply_map_delta({"seq": 2, "removed": ["a"]})
	_check(view.get_selected_entity_id() == "", "removed limpia selección visible")
	view.set_tap_actions_enabled(true)
	view.set_asteroid_selection_enabled(false)
	view.call("_handle_tap", point)
	_check(_destinations == 1, "modo Travel sigue seleccionando coordenadas")
	view.set_destination_selection_enabled(false)
	world.apply_map_delta({"seq": 3, "added": [{"entity_id": "a", "kind": "asteroid", "position": [310, 290]}]})
	view.call("_handle_tap", point)
	_check(selection.selected_entity_id == "own", "empate de posición en selección normal permite elegir nave")
	view.free()
	print("M3_MINING_INPUT_TEST_OK" if _failures == 0 else "M3_MINING_INPUT_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_MINING_INPUT_TEST_FAILED: %s" % message)
