extends SceneTree
## Escena real y SSS de fixture: rechazo, viaje, mouse/touch, minería y reconexión.

const SCENE: PackedScene = preload("res://app/main.tscn")
const CONFIG: ClientConnectionConfig = preload("res://config/default_client_connection.tres")
const ASTEROID: String = "018f0000-0000-7000-8000-000000000007"
var _app: Control
var _failures: int = 0
var _notifications: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var port: int = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
	if port <= 0:
		_check(false, "requiere fixture SSS y --port")
		_finish()
		return
	var config: ClientConnectionConfig = CONFIG
	var original_auto: bool = config.auto_connect
	config.auto_connect = false
	_app = SCENE.instantiate()
	root.add_child(_app)
	config.auto_connect = original_auto
	_app.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_app._mining_intent.result_received.connect(func(_result: Dictionary) -> void: _notifications += 1)
	root.size = Vector2i(360, 720)
	_app.size = Vector2(360, 720)
	await process_frame
	await process_frame
	_check(_app.get_node("Margin/Scroll") is ScrollContainer, "contenido accesible por scroll")
	_check(_app.size.x <= 360 and _app.mining_panel.size.x <= 321 and _app.start_mining_button.custom_minimum_size.y >= 48,
		"panel estrecho y acciones táctiles: app=%s panel=%s" % [_app.size, _app.mining_panel.size])
	root.size = Vector2i(1152, 900)
	_app.size = Vector2(1152, 900)
	await process_frame
	_app.port_edit.value = port
	_app.call("_connect_from_form")
	if not await _wait(func() -> bool: return _app._world_ready):
		_check(false, "snapshot M3 inicial")
		_finish()
		return
	_check(_app._world_state.protocol_version == "team3-m3.0", "cliente usa M3 configurable")
	var own: ShipRepresentation = _app._world_state.get_ship_for_player(_app._player_id)
	var target_position := Vector2(310, 290)
	_tap(own.position, false)
	_app.choose_asteroid_button.pressed.emit()
	_tap(target_position, false)
	_check(_app._ship_selection.selected_entity_id == ASTEROID and _app._mining_intent.actor_entity_id == own.entity_id, "mouse prepara actor/objetivo con selección única")
	_app.start_mining_button.pressed.emit()
	_check(_app._mining_intent.is_pending() and _app.confirm_travel_button.disabled, "pending bloquea Travel")
	_check(await _wait(func() -> bool: return _app._mining_intent.last_rejection_code == "MINING_OUT_OF_RANGE"), "rechazo fuera de rango")
	_check(not _app._mining_intent.is_pending() and _app.mining_label.text.contains("Acerca"), "rechazo explicado en UI")
	_tap(own.position, false)
	_tap(target_position, true)
	_app.confirm_travel_button.pressed.emit()
	_check(_app._travel_intent.awaiting_resolution and _app.start_mining_button.disabled, "Travel pendiente bloquea minería")
	_check(await _wait(func() -> bool: return _app._world_state.ship_for_player(_app._player_id).get("state") == "TRAVELING"), "confirmación de viaje preservada")
	_check(await _wait(func() -> bool: return _app._world_state.ship_for_player(_app._player_id).get("state") == "ANCHORED"), "viaje llega al asteroide")
	_app.choose_asteroid_button.pressed.emit()
	_tap(target_position, true)
	_check(_app._ship_selection.selected_entity_id == ASTEROID, "touch elige asteroide superpuesto con nave")
	_app.start_mining_button.pressed.emit()
	_check(await _wait(func() -> bool: return _active_quantity() >= 1), "progreso autoritativo recibido")
	var first_id: String = _own()["mining"]["mining_id"]
	_check(_app.mining_label.text.contains("Minando") and not _app.stop_mining_button.disabled, "UI muestra progreso y permite parar")
	_app.call("_connect_from_form")
	_check(_app._ship_selection.selected_entity_id == "" and not _app._world_ready, "reconexión limpia selección y espera snapshot")
	_check(await _wait(func() -> bool: return _app._world_ready and _active_quantity() >= 1), "reconexión recupera operación activa")
	_check(_own()["mining"]["mining_id"] == first_id, "reconexión no crea otra operación")
	_app.stop_mining_button.pressed.emit()
	_check(await _wait(func() -> bool: return _app._mining_intent.last_result.get("mining_id") == first_id), "parada recibe resultado")
	var first_quantity: int = int(_app._mining_intent.last_result["quantity"])
	_check(_app._mining_intent.last_result["reason"] == "USER_CANCELLED" and first_quantity > 0 and first_quantity < 10, "cancelación parcial visible")
	_app.sss_connection.request_full_snapshot()
	await create_timer(0.3).timeout
	_check(_notifications == 1, "snapshot repetido no duplica resultado")
	_tap(target_position, false)
	_app.choose_asteroid_button.pressed.emit()
	_tap(target_position, true)
	_app.start_mining_button.pressed.emit()
	_check(await _wait(func() -> bool: return _own().get("mining") is Dictionary), "segunda operación comienza")
	_check(await _wait(func() -> bool: return _app._mining_intent.last_result.get("status") == "COMPLETED"), "agotamiento completo desde cliente")
	_check(_notifications == 2 and _app.mining_result_label.text.contains("completado"), "resultado final una sola vez")
	_check(_app._world_state.get_entity(ASTEROID)["remaining_quantity"] == 0, "cliente actualizado sin inventario local")
	_check(int(_app._mining_intent.last_result["quantity"]) + first_quantity == 10, "total extraído coincide con depósito")
	_app.sss_connection.call("_handle_packet", JSON.stringify({"type": "pong", "protocol_version": "team3-m3.0", "seq": _app._world_state.seq + 50, "server_time": _app._world_state.server_time}))
	_check(not _app._world_ready and _app.start_mining_button.disabled, "desync bloquea acción hasta reconstruir")
	_check(await _wait(func() -> bool: return _app._world_ready), "snapshot recupera desync")
	_check(_notifications == 2, "recuperación no repite resultado")
	_finish()


func _own() -> Dictionary:
	return _app._world_state.ship_for_player(_app._player_id)


func _active_quantity() -> int:
	var mining: Variant = _own().get("mining")
	return int(mining.get("extracted_quantity", -1)) if mining is Dictionary else -1


func _tap(world_position: Vector2, touch: bool) -> void:
	var view: WorldDebugView = _app.world_debug_view
	view.get_camera().set_screen_size(view.size)
	var point: Vector2 = view.get_camera().world_to_screen(world_position)
	for pressed: bool in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.position = point
			event.pressed = pressed
			view.call("_gui_input", event)
		else:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = point
			event.pressed = pressed
			view.call("_gui_input", event)


func _wait(condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await process_frame
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_MINING_SCENE_TEST_FAILED: %s" % message)


func _finish() -> void:
	if _app != null:
		_app.sss_connection.disconnect_from_server()
		_app.free()
	print("M3_MINING_SCENE_TEST_OK" if _failures == 0 else "M3_MINING_SCENE_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
