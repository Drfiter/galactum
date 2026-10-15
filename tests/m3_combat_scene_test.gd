extends SceneTree
## TEAM3-M3 ETAPA 4: escena real cliente -> WebSocket -> SSS -> resolver -> UI.

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
	if not await _wait_for(func() -> bool: return _target_ship() != null):
		_check(false, "snapshot inicial contiene nave propia y objetivo")
		_finish()
		return

	var target: ShipRepresentation = _target_ship()
	_tap_ship(target.position)
	_check(_app._ship_selection.selected_entity_id == target.entity_id,
		"touch selecciona objetivo mediante WorldDebugView")
	_check(not _app.attack_button.disabled and _app._attack_intent.can_attack(),
		"selección ajena habilita Atacar")
	_app.call("_on_attack_pressed")
	_check(_app._attack_intent.awaiting_resolution, "UI muestra solicitud pendiente")
	if not await _wait_for(func() -> bool: return _app._combat_result_state.combat_id != ""):
		_check(false, "combat_result autoritativo recibido")
		_finish()
		return

	_check(not _app._attack_intent.awaiting_resolution, "resultado limpia intención")
	_check(_app._combat_result_state.defender.get("entity_id") == target.entity_id,
		"resultado corresponde al objetivo seleccionado")
	_check(not _app._combat_result_state.outcome.is_empty(), "resultado contiene outcome")
	_check(_app.combat_result_label.text.contains("combat_id="), "UI presenta combat_id")
	_check(_app.combat_result_label.text.contains("Bajas"), "UI presenta resumen de bajas")
	_check(_app._world_state.get_ship(target.entity_id) != null,
		"resultado no destruye ni retira la nave de WorldState")
	_finish()


func _target_ship() -> ShipRepresentation:
	if _app == null:
		return null
	var own: ShipRepresentation = _app._world_state.get_ship_for_player(_app._player_id)
	if own == null:
		return null
	for raw_entity: Variant in _app._world_state.entities.values():
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		if str(entity.get("kind", "")) != "ship":
			continue
		var ship := ShipRepresentation.new(entity)
		if not ship.is_owned_by(_app._player_id):
			return ship
	return null


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
		push_error("M3_COMBAT_SCENE_TEST_FAILED: %s" % message)


func _finish() -> void:
	if _app != null:
		_app.sss_connection.disconnect_from_server()
		_app.free()
	print("M3_COMBAT_SCENE_TEST_OK" if _failures == 0 else "M3_COMBAT_SCENE_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
