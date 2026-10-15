extends SceneTree
## TEAM3-M3 ETAPA 4: intención de ataque sobre selección compartida mouse/touch.

var _failures: int = 0


func _initialize() -> void:
	var world := WorldState.new()
	world.apply_full_snapshot(_snapshot())
	var selection := ShipSelectionState.new(world)
	var intent := AttackIntentState.new(world, selection)
	intent.set_player_id("player-own")

	selection.select_entity("own")
	_check(intent.target_entity_id == "" and not intent.can_attack(), "nave propia no es objetivo")
	selection.select_entity("foreign")
	_check(intent.target_entity_id == "foreign" and intent.can_attack(), "nave ajena ANCHORED habilita ataque")
	_check(intent.begin_request("request-1"), "crea intención pendiente correlacionada")
	_check(intent.awaiting_resolution and intent.pending_request_id == "request-1", "conserva request_id pendiente")
	_check(not intent.begin_request("request-2"), "no permite segunda intención pendiente")

	world.apply_map_delta({"seq": 2, "removed": ["foreign"]})
	_check(selection.selected_entity_id == "", "salida AOI limpia selección compartida")
	_check(intent.awaiting_resolution and intent.target_entity_id == "foreign",
		"salida AOI posterior al envío no inventa resultado ni pierde correlación")
	_check(not intent.can_attack(), "solicitud pendiente nunca habilita otro ataque")
	_check(intent.complete_request("request-1"), "resultado correlacionado limpia pendiente")
	_check(not intent.awaiting_resolution and intent.pending_request_id == "" and intent.target_entity_id == "",
		"intención queda limpia tras resultado")

	world.apply_full_snapshot(_snapshot(3))
	selection.select_entity("foreign")
	world.apply_map_delta({"seq": 4, "removed": ["foreign"]})
	_check(intent.target_entity_id == "" and not intent.can_attack(),
		"objetivo que sale del AOI antes de enviar deja de estar disponible")

	world.apply_full_snapshot(_snapshot(5))
	selection.select_entity("foreign-traveling")
	_check(intent.target_entity_id == "foreign-traveling" and not intent.can_attack(),
		"objetivo TRAVELING se muestra pero no habilita ataque")

	var view := WorldDebugView.new()
	root.add_child(view)
	view.size = Vector2(600, 600)
	view.set_world_state(world)
	view.set_selection_state(selection)
	view.get_camera().set_screen_size(view.size)
	_send_mouse_tap(view, Vector2(340, 300))
	_check(selection.selected_entity_id == "foreign" and intent.can_attack(),
		"mouse reutiliza WorldDebugView y habilita objetivo ajeno")
	_send_touch_tap(view, Vector2(300, 300))
	_check(selection.selected_entity_id == "own" and not intent.can_attack(),
		"touch reutiliza la misma selección y no permite autoataque")

	selection.select_entity("foreign")
	_check(intent.begin_request("request-rejected"), "prepara solicitud para rechazo Combat")
	_check(intent.reject_request("request-rejected", "TARGET_NOT_VISIBLE", "Target left AOI"),
		"rechazo correlacionado limpia la solicitud")
	_check(not intent.awaiting_resolution and intent.last_rejection_code == "TARGET_NOT_VISIBLE",
		"estado conserva el error Combat para presentarlo")

	_check(intent.begin_request("request-reconnect"), "prepara pendiente para reconexión")
	intent.reset_transient()
	_check(not intent.awaiting_resolution and intent.pending_request_id == "",
		"reconexión descarta pendiente local no reconstruible")

	view.free()
	_finish()


func _snapshot(seq: int = 1) -> Dictionary:
	return {
		"type": "map_delta",
		"protocol_version": "team3-m2.0",
		"seq": seq,
		"server_time": 1780000000000,
		"full": true,
		"system_id": "system-1",
		"map_size": [600, 600],
		"added": [
			{"entity_id": "own", "ship_id": "ship-own", "player_id": "player-own", "kind": "ship", "state": "ANCHORED", "position": [300, 300]},
			{"entity_id": "foreign", "ship_id": "ship-foreign", "player_id": "player-foreign", "kind": "ship", "state": "ANCHORED", "position": [340, 300]},
			{"entity_id": "foreign-traveling", "ship_id": "ship-traveling", "player_id": "player-traveling", "kind": "ship", "state": "TRAVELING", "position": [380, 300]},
			{"entity_id": "rock", "kind": "asteroid", "position": [320, 340]},
		],
		"updated": [],
		"removed": [],
	}


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
	press.position = position
	press.pressed = true
	view.call("_gui_input", press)
	var release := InputEventScreenTouch.new()
	release.position = position
	release.pressed = false
	view.call("_gui_input", release)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_ATTACK_INTENT_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("M3_ATTACK_INTENT_TEST_OK" if _failures == 0 else "M3_ATTACK_INTENT_TEST_FAILED failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)
