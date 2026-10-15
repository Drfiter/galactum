extends SceneTree
## Demo automatizada con escena real y SSS M2 en un puerto dado por --port.
## Selección, cancelación, viaje, reconexión durante viaje y llegada.

const SCENE: PackedScene = preload("res://app/main.tscn")
const CONFIG: ClientConnectionConfig = preload("res://config/default_client_connection.tres")
var _failures: int = 0
var _app: Control


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var port: int = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
	if port <= 0:
		_check(false, "requiere SSS y --port")
		_finish()
		return
	var config: ClientConnectionConfig = CONFIG
	var auto_connect: bool = config.auto_connect
	config.auto_connect = false
	_app = SCENE.instantiate()
	root.add_child(_app)
	config.auto_connect = auto_connect
	_app.port_edit.value = port
	_app.call("_connect_from_form")
	if not await _wait_for(func() -> bool: return _app._world_state.get_ship_for_player(_app._player_id) != null):
		_check(false, "snapshot inicial recibido")
		_finish()
		return
	var own: ShipRepresentation = _app._world_state.get_ship_for_player(_app._player_id)
	_tap_ship(own.position)
	_check(_app._ship_selection.get_selected_ship().ship_id == own.ship_id, "escena selecciona identidad nave")
	_app.call("_on_destination_selected", Vector2i(301, 300))
	_app.call("_on_cancel_travel")
	_check(not _app._travel_intent.has_provisional_destination, "escena cancela destino")
	_app.call("_on_destination_selected", Vector2i(301, 300))
	_app.call("_on_confirm_travel")
	_check(_app._travel_intent.awaiting_resolution, "espera aceptación autoritativa")
	_check(await _wait_for(func() -> bool: return _app._world_state.get_ship(own.entity_id).state == "TRAVELING"), "map_delta confirma viaje")
	_check(not _app._travel_intent.awaiting_resolution, "TRAVELING resuelve intención")
	_check(_app._ship_selection.selected_entity_id == own.entity_id, "delta no pierde selección")
	_app.call("_connect_from_form")
	_check(_app._ship_selection.selected_entity_id == "" and not _app._travel_intent.can_choose_destination(), "reconexión limpia selección e intención")
	var previous_world_seq: int = _app._world_state.seq
	_check(await _wait_for(func() -> bool: return _app._world_state.seq != previous_world_seq and _app._world_state.get_ship(own.entity_id).state == "TRAVELING"), "snapshot reconstruye viaje tras reconexión")
	var restored: ShipRepresentation = _app._world_state.get_ship(own.entity_id)
	_check(TravelProjection.has_valid_travel(restored.to_entity()), "ruta y ETA reconstruibles")
	_check(await _wait_for(func() -> bool: return _app._world_state.get_ship(own.entity_id).state == "ANCHORED"), "SSS publica llegada")
	var arrived: ShipRepresentation = _app._world_state.get_ship(own.entity_id)
	_check(arrived.position == Vector2(301, 300) and arrived.to_entity().get("travel") == null, "llegada exacta sin travel residual")
	_finish()


func _tap_ship(position: Vector2) -> void:
	var view: WorldDebugView = _app.world_debug_view
	view.get_camera().set_screen_size(view.size)
	var screen_position: Vector2 = view.get_camera().world_to_screen(position)
	for pressed: bool in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = screen_position
		event.pressed = pressed
		view.call("_gui_input", event)


func _wait_for(condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_SHIP_SCENE_TEST_FAILED: %s" % message)


func _finish() -> void:
	if _app != null:
		_app.sss_connection.disconnect_from_server()
		_app.free()
	print("M3_SHIP_SCENE_TEST_OK" if _failures == 0 else "M3_SHIP_SCENE_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
