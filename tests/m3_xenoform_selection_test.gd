extends SceneTree
## Una selección compartida para todas las entidades, con input y limpieza reales.

var _failures: int = 0
var _destination: Vector2i = Vector2i(-1, -1)


func _initialize() -> void:
	var world := WorldState.new()
	world.apply_full_snapshot(_snapshot())
	var selection := ShipSelectionState.new(world)
	var view := WorldDebugView.new()
	root.add_child(view)
	view.size = Vector2(600, 600)
	view.set_world_state(world)
	view.set_selection_state(selection)
	view.get_camera().set_screen_size(view.size)
	view.destination_selected.connect(func(destination: Vector2i) -> void: _destination = destination)
	for touch: bool in [false, true]:
		_tap(view, Vector2(100, 300), touch)
		_check(selection.get_selected_ship().is_owned_by("player-1"), "nave propia mouse/touch")
		_tap(view, Vector2(230, 300), touch)
		_check(selection.get_selected_ship().player_id == "player-2", "nave ajena mouse/touch")
		_tap(view, Vector2(360, 300), touch)
		_check(selection.selected_entity_id == "rock" and selection.get_selected_ship() == null, "asteroide mouse/touch")
		_tap(view, Vector2(490, 300), touch)
		_check(selection.selected_entity_id == "xeno" and selection.get_selected_ship() == null, "Xenoform mouse/touch")
	_tap(view, Vector2(100, 300), false)
	view.set_destination_selection_enabled(true)
	_tap(view, Vector2(490, 300), true)
	_check(selection.selected_entity_id == "xeno", "entidad tiene prioridad sobre destino de viaje")
	_check(_destination == Vector2i(-1, -1), "tocar enemigo no solicita destino")
	_tap(view, Vector2(420, 340), true)
	_check(_destination == Vector2i(420, 340), "espacio vacío conserva elección de destino M2")
	view.set_tap_actions_enabled(false)
	_tap(view, Vector2(100, 300), false)
	_check(selection.selected_entity_id == "xeno", "solicitud pendiente bloquea cambios por tap")
	view.set_tap_actions_enabled(true)
	view.set_destination_selection_enabled(false)
	_tap(view, Vector2(100, 300), true)
	var drag_origin: Vector2 = view.get_camera().world_to_screen(Vector2(490, 300))
	var drag_press := InputEventScreenTouch.new()
	drag_press.position = drag_origin
	drag_press.pressed = true
	view.call("_gui_input", drag_press)
	var drag := InputEventScreenDrag.new()
	drag.position = drag_origin + Vector2(40, 0)
	drag.relative = Vector2(40, 0)
	view.call("_gui_input", drag)
	var drag_release := InputEventScreenTouch.new()
	drag_release.position = drag.position
	drag_release.pressed = false
	view.call("_gui_input", drag_release)
	_check(selection.selected_entity_id == "own", "arrastre sobre enemigo panea sin seleccionar")
	view.size = Vector2(900, 400)
	view.get_camera().set_screen_size(view.size)
	view.get_camera().zoom_at_screen(view.size * 0.5, 1.5)
	_tap(view, Vector2(490, 300), true)
	_check(selection.selected_entity_id == "xeno", "selección tras resize/zoom")
	if not selection.has_method("get_selected_entity"):
		_check(false, "falta consulta de inspección del sistema compartido")
	else:
		var inspected: Dictionary = selection.call("get_selected_entity")
		_check(inspected.get("kind") == "xenoform", "consulta distingue tipo")
		inspected["xenoform"]["config_id"] = "local-only"
		_check(world.get_entity("xeno")["xenoform"]["config_id"] == "m3-demo-static", "inspección no muta réplica")
	world.apply_map_delta({"seq": 2, "updated": [{"entity_id": "xeno", "display_name": "Updated xeno"}]})
	_check(selection.selected_entity_id == "xeno", "updated conserva selección")
	world.apply_map_delta({"seq": 3, "removed": ["xeno"]})
	_check(selection.selected_entity_id == "" and view.get_selected_entity_id() == "", "salida AOI invalida selección y marcador")
	world.apply_map_delta({"seq": 4, "added": [_snapshot()["added"][3]]})
	_check(selection.selected_entity_id == "", "reentrada no restaura automáticamente selección")
	_tap(view, Vector2(490, 300), false)
	world.apply_full_snapshot({"seq": 5, "map_size": [600, 600], "added": []})
	_check(selection.selected_entity_id == "", "snapshot excluyente invalida selección")
	world.apply_full_snapshot(_snapshot())
	selection.select_entity("xeno")
	world.clear()
	_check(selection.selected_entity_id == "", "clear limpia selección")
	world.apply_full_snapshot(_snapshot())
	view.clear_selection()
	_tap(view, Vector2(100, 300), false)
	_check(selection.get_selected_ship().is_owned_by("player-1"), "selección de nave sigue disponible")
	view.free()
	print("M3_XENOFORM_SELECTION_TEST_OK" if _failures == 0 else "M3_XENOFORM_SELECTION_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _snapshot() -> Dictionary:
	return {"type": "map_delta", "protocol_version": "team3-m2.0", "server_time": 1000,
		"system_id": "system-test", "seq": 1, "full": true, "map_size": [600, 600], "updated": [], "removed": [], "added": [
		{"entity_id": "own", "kind": "ship", "ship_id": "ship-own", "player_id": "player-1", "position": [100, 300], "state": "ANCHORED"},
		{"entity_id": "foreign", "kind": "ship", "ship_id": "ship-foreign", "player_id": "player-2", "position": [230, 300], "state": "ANCHORED"},
		{"entity_id": "rock", "kind": "asteroid", "position": [360, 300]},
		{"entity_id": "xeno", "kind": "xenoform", "position": [490, 300], "state": "IDLE", "display_name": "Demo xeno", "xenoform": {"config_id": "m3-demo-static"}},
	]}


func _tap(view: WorldDebugView, world_position: Vector2, touch: bool) -> void:
	var position: Vector2 = view.get_camera().world_to_screen(world_position)
	for pressed: bool in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.position = position
			event.pressed = pressed
			view.call("_gui_input", event)
		else:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = position
			event.pressed = pressed
			view.call("_gui_input", event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_XENOFORM_SELECTION_TEST_FAILED: %s" % message)
