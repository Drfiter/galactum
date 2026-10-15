extends SceneTree
## Escena real con mensajes controlados: inspección y viaje conviven sin Combat.

const SCENE: PackedScene = preload("res://app/main.tscn")
const CONFIG: ClientConnectionConfig = preload("res://config/default_client_connection.tres")
var _failures: int = 0
var _app: Control


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config: ClientConnectionConfig = CONFIG
	var auto_connect: bool = config.auto_connect
	config.auto_connect = false
	_app = SCENE.instantiate()
	root.add_child(_app)
	config.auto_connect = auto_connect
	await process_frame
	_app.call("_on_authenticated", {"player_id": "player-1"})
	_app.call("_on_map_delta", _snapshot())
	_tap(Vector2(100, 300), false)
	_check(_app.ship_label.text.contains("Nave propia") and _app.ship_label.text.contains("own"), "panel identifica nave propia")
	_tap(Vector2(420, 340), true)
	_check(_app._travel_intent.has_provisional_destination and not _app.confirm_travel_button.disabled, "tap vacío prepara viaje M2")
	_tap(Vector2(490, 300), true)
	_check(_app._ship_selection.selected_entity_id == "xeno", "cambia de nave a Xenoform durante preparación")
	_check(not _app._travel_intent.has_provisional_destination and _app.confirm_travel_button.disabled, "inspección cancela intención provisional, no habilita viaje enemigo")
	_check(_app.ship_label.text.contains("Xenoform") and _app.ship_label.text.contains("xeno") and _app.ship_label.text.contains("IDLE"), "panel muestra tipo, identidad y estado PvE")
	_check(_app.ship_label.text.contains("m3-demo-static") and _app.ship_label.text.contains("Demo xeno"), "configuración y nombre visibles recibidos")
	_app.call("_on_map_delta", {"seq": 2, "updated": [{"entity_id": "xeno", "display_name": "Updated xeno", "position": [490, 310]}]})
	_check(_app.ship_label.text.contains("Updated xeno") and not _app.ship_label.text.contains("Nave propia"), "delta actualiza objetivo sin sustituirlo por nave propia")
	_app.call("_on_map_delta", {"seq": 3, "removed": ["xeno"]})
	_check(_app._ship_selection.selected_entity_id == "" and not _app.ship_label.text.contains("Updated xeno"), "AOI limpia selección y panel")
	_check(not _app.ship_label.text.to_lower().contains("destruid"), "removed no se presenta como destrucción")
	_app.call("_on_map_delta", _snapshot())
	_tap(Vector2(230, 300), false)
	_check(_app.ship_label.text.contains("Nave ajena") and _app.confirm_travel_button.disabled, "nave ajena diferenciada sin permiso de viaje")
	_tap(Vector2(360, 300), true)
	_check(_app.ship_label.text.contains("Asteroide") and _app.ship_label.text.contains("rock"), "asteroide distinguido")
	_app.call("_on_map_delta", {"seq": 4, "updated": [{"entity_id": "own", "position": [101, 300]}]})
	_check(_app.ship_label.text.contains("Asteroide"), "delta ajeno conserva objetivo inspeccionado")
	_tap(Vector2(490, 300), false)
	_app.call("_on_map_delta", {"seq": 5, "full": true, "map_size": [600, 600], "added": []})
	_check(_app._ship_selection.selected_entity_id == "" and not _app.ship_label.text.contains("Demo xeno"), "snapshot excluyente limpia panel")
	_app.call("_on_map_delta", _snapshot())
	_tap(Vector2(490, 300), true)
	_app._world_state.clear()
	_check(_app._ship_selection.selected_entity_id == "" and not _app.ship_label.text.contains("Demo xeno"), "clear de réplica limpia panel")
	_app.call("_on_map_delta", _snapshot())
	_tap(Vector2(100, 300), false)
	_tap(Vector2(420, 340), false)
	_check(_app._travel_intent.begin_request(), "solicitud de viaje puede comenzar")
	_app.call("_refresh_travel_controls")
	_tap(Vector2(490, 300), true)
	_check(_app._ship_selection.selected_entity_id == "own" and _app._travel_intent.awaiting_resolution, "tap PvE no altera solicitud pendiente")
	_app.call("_on_map_delta", {"seq": 6, "updated": [{"entity_id": "own", "state": "TRAVELING", "travel": {"origin": [100, 300], "destination": [420, 340], "depart_ts": 1000, "arrive_ts": 2000}}]})
	_check(not _app._travel_intent.awaiting_resolution, "confirmación autoritativa M2 sigue funcionando")
	_tap(Vector2(490, 300), false)
	_check(_app.ship_label.text.contains("Xenoform") and _app._world_state.get_entity("own").get("state") == "TRAVELING", "inspeccionar enemigo no cancela viaje aceptado")
	_app.call("_on_map_delta", {"seq": 7, "updated": [{"entity_id": "own", "state": "ANCHORED", "position": [420, 340], "travel": null}]})
	_check(_app.ship_label.text.contains("Xenoform") and _app._world_state.get_entity("own").get("travel") == null, "llegada M2 conserva objetivo inspeccionado")
	_app.sss_connection.disconnect_from_server()
	_app.free()
	print("M3_XENOFORM_INSPECTION_TEST_OK" if _failures == 0 else "M3_XENOFORM_INSPECTION_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _snapshot() -> Dictionary:
	return {"type": "map_delta", "protocol_version": "team3-m2.0", "server_time": 1000,
		"system_id": "system-test", "seq": 1, "full": true, "map_size": [600, 600], "updated": [], "removed": [], "added": [
		{"entity_id": "own", "kind": "ship", "ship_id": "ship-own", "player_id": "player-1", "position": [100, 300], "state": "ANCHORED"},
		{"entity_id": "foreign", "kind": "ship", "ship_id": "ship-foreign", "player_id": "player-2", "position": [230, 300], "state": "ANCHORED"},
		{"entity_id": "rock", "kind": "asteroid", "position": [360, 300]},
		{"entity_id": "xeno", "kind": "xenoform", "position": [490, 300], "state": "IDLE", "display_name": "Demo xeno", "xenoform": {"config_id": "m3-demo-static"}},
	]}


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


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_XENOFORM_INSPECTION_TEST_FAILED: %s" % message)
