extends SceneTree
## Inspección del Xenoform autoritativo desde la escena y conexión reales.
## Ejecutar con un SSS de desarrollo nuevo y --port; sin ataques ni Combat.

const SCENE: PackedScene = preload("res://app/main.tscn")
const CONFIG: ClientConnectionConfig = preload("res://config/default_client_connection.tres")
const XENOFORM_ID: String = "018f0000-0000-7000-8000-000000000009"
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
	if not await _wait_for(func() -> bool: return not _app._world_state.get_entity(XENOFORM_ID).is_empty()):
		_check(false, "snapshot recibe entidad PvE autoritativa")
		_finish()
		return
	var entity: Dictionary = _app._world_state.get_entity(XENOFORM_ID)
	_check(entity.get("state") == "IDLE", "estado recibido del SSS")
	for touch: bool in [false, true]:
		_app._ship_selection.clear()
		_tap(Vector2(300, 300), touch)
		_check(_app.ship_label.text.contains("Nave propia"), "nave propia autenticada inspeccionable")
		_tap(Vector2(310, 315), touch)
		_check(_app._ship_selection.selected_entity_id == XENOFORM_ID, "selección mouse/touch de enemigo real desde nave propia")
		_check(_app.ship_label.text.contains(XENOFORM_ID) and _app.ship_label.text.contains("IDLE") and _app.ship_label.text.contains("m3-demo-static"), "panel contiene identidad/estado/configuración del SSS")
		_check(_app.confirm_travel_button.disabled and not _app._travel_intent.can_choose_destination(), "selección PvE no habilita viaje ni acción de ataque")
	var previous_seq: int = _app._world_state.seq
	_app.sss_connection.request_full_snapshot()
	_check(await _wait_for(func() -> bool: return _app._world_state.seq != previous_seq), "snapshot de recuperación recibido")
	_check(_app._ship_selection.selected_entity_id == XENOFORM_ID and _app.ship_label.text.contains(XENOFORM_ID), "snapshot que conserva objetivo conserva selección")
	_app._world_state.clear()
	_check(_app._ship_selection.selected_entity_id == "" and not _app.ship_label.text.contains(XENOFORM_ID), "limpieza retira datos de inspección")
	_app.sss_connection.request_full_snapshot()
	_check(await _wait_for(func() -> bool: return not _app._world_state.get_entity(XENOFORM_ID).is_empty()), "réplica reconstruida por red")
	_check(_app._ship_selection.selected_entity_id == "", "reconstrucción no selecciona automáticamente objetivo anterior")
	_tap(Vector2(310, 315), true)
	_check(_app.ship_label.text.contains(XENOFORM_ID), "objetivo reconstruido vuelve a ser seleccionable")
	_finish()


func _tap(world_position: Vector2, touch: bool) -> void:
	var view: WorldDebugView = _app.world_debug_view
	view.get_camera().set_screen_size(view.size)
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
		push_error("M3_XENOFORM_SCENE_TEST_FAILED: %s" % message)


func _finish() -> void:
	if _app != null:
		_app.sss_connection.disconnect_from_server()
		_app.free()
	print("M3_XENOFORM_SCENE_TEST_OK" if _failures == 0 else "M3_XENOFORM_SCENE_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
