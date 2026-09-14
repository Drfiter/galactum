extends SceneTree
## Selección por mouse y destino por touch sobre la vista diagnóstica.

var _failures: int = 0
var _selected_entity_id: String = ""
var _destination: Vector2i = Vector2i(-1, -1)


func _initialize() -> void:
	var world := WorldState.new()
	world.apply_full_snapshot({
		"type": "map_delta",
		"protocol_version": "team3-m2.0",
		"seq": 1,
		"server_time": 1780000000000,
		"full": true,
		"system_id": "system-1",
		"map_size": [600, 600],
		"added": [{
			"entity_id": "own",
			"kind": "ship",
			"player_id": "player-1",
			"state": "ANCHORED",
			"position": [300, 300],
		}],
		"updated": [],
		"removed": [],
	})
	var view := WorldDebugView.new()
	root.add_child(view)
	view.size = Vector2(600, 600)
	view.set_world_state(world)
	view.get_camera().set_screen_size(view.size)
	view.entity_selected.connect(_on_entity_selected)
	view.destination_selected.connect(_on_destination_selected)

	_send_mouse_tap(view, Vector2(300, 300))
	_check(_selected_entity_id == "own", "mouse selecciona nave en screen-space")

	view.set_destination_selection_enabled(true)
	_send_touch_tap(view, Vector2(420, 180))
	_check(_destination == Vector2i(420, 180), "touch selecciona coordenada de destino")

	view.free()
	if _failures == 0:
		print("M2_WORLD_DEBUG_VIEW_TEST_OK")
		quit(0)
	else:
		print("M2_WORLD_DEBUG_VIEW_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _send_mouse_tap(view: WorldDebugView, position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.pressed = true
	view.call("_gui_input", press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = position
	release.pressed = false
	view.call("_gui_input", release)


func _send_touch_tap(view: WorldDebugView, position: Vector2) -> void:
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = position
	press.pressed = true
	view.call("_gui_input", press)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = position
	release.pressed = false
	view.call("_gui_input", release)


func _on_entity_selected(entity_id: String) -> void:
	_selected_entity_id = entity_id


func _on_destination_selected(destination: Vector2i) -> void:
	_destination = destination


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M2_WORLD_DEBUG_VIEW_TEST_FAILED: %s" % message)
