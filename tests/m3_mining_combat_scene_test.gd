extends "res://tests/m3_combat_scene_test.gd"
## App real: viajar, minar, atacar y recibir cancelación parcial mediante M3.

var _mining_notifications: int = 0


func _run() -> void:
	var port: int = 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
	if port <= 0:
		_check(false, "requiere fixture y --port")
		_finish()
		return
	var config: ClientConnectionConfig = CONFIG
	var auto_connect: bool = config.auto_connect
	config.auto_connect = false
	_app = SCENE.instantiate()
	root.add_child(_app)
	config.auto_connect = auto_connect
	_app._mining_intent.result_received.connect(func(_result: Dictionary) -> void: _mining_notifications += 1)
	_app.port_edit.value = port
	_app.call("_connect_from_form")
	if not await _wait_for(func() -> bool: return _app._world_ready):
		_check(false, "snapshot inicial")
		_finish()
		return
	var own: ShipRepresentation = _app._world_state.get_ship_for_player(_app._player_id)
	_app._ship_selection.select_entity(own.entity_id)
	_app.call("_on_destination_selected", Vector2i(310, 290))
	_app.confirm_travel_button.pressed.emit()
	if not await _wait_for(func() -> bool:
		var ship: Dictionary = _app._world_state.ship_for_player(_app._player_id)
		var position: Variant = ship.get("position", [])
		return ship.get("state") == "ANCHORED" and position.size() == 2 and int(position[0]) == 310 and int(position[1]) == 290):
		_check(false, "viaje llega al asteroide")
		_finish()
		return
	_app.choose_asteroid_button.pressed.emit()
	_app._ship_selection.select_entity("018f0000-0000-7000-8000-000000000007")
	_app.start_mining_button.pressed.emit()
	if not await _wait_for(func() -> bool:
		var mining: Variant = _app._world_state.ship_for_player(_app._player_id).get("mining")
		return mining is Dictionary and int(mining.get("extracted_quantity", 0)) >= 1):
		_check(false, "progreso antes de combatir")
		_finish()
		return
	_tap_ship(_target_ship().position)
	_check(not _app.attack_button.disabled, "minería activa permite preparar combate")
	_app.attack_button.pressed.emit()
	_check(_app._attack_intent.awaiting_resolution and _app.stop_mining_button.disabled,
		"solicitud Combat bloquea otras intenciones")
	_check(await _wait_for(func() -> bool: return _app._combat_result_state.combat_id != ""),
		"combate autoritativo recibido")
	_check(await _wait_for(func() -> bool: return _app._mining_intent.last_result.get("reason") == "COMBAT_STARTED"),
		"delta publica cancelación minera por combate")
	var result: Dictionary = _app._mining_intent.last_result
	_check(int(result.get("quantity", 0)) > 0 and int(result.get("quantity", 0)) < 10,
		"conserva extracción parcial")
	_check(_app._world_state.ship_for_player(_app._player_id).get("mining") == null,
		"réplica limpia actividad minera")
	_check(_app.mining_result_label.text.contains("cancelado") and _app.combat_result_label.text.contains("combat_id="),
		"UI muestra ambos resultados")
	_app.call("_connect_from_form")
	_check(await _wait_for(func() -> bool: return _app._world_ready), "reconexión reconstruye snapshot")
	_check(_mining_notifications == 1, "reconexión no duplica resultado minero")
	_finish()


func _finish() -> void:
	if _app != null:
		_app.sss_connection.disconnect_from_server()
		_app.free()
	print("M3_MINING_COMBAT_SCENE_TEST_OK" if _failures == 0 else "M3_MINING_COMBAT_SCENE_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
