extends Node
## Pruebas de regresión de los errores reportados en el feedback del 26/10/2026.
## Arrancan el juego completo (cliente + servidor embebido) y simulan al jugador.
## Ejecutar:  godot --headless --path . res://tests/feedback_checks.tscn

const U = preload("res://shared/util.gd")

var game: Node
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("== Galactum: pruebas del feedback ==")
	GameClient.start_local("Mateo", "p05", true)
	game = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(1.5)
	await test_popup_tap_survives_refresh()
	await test_menu_bar_waits_after_popup()
	await test_coords_follow_relocation()
	test_no_internal_state_names()
	await test_deck_labels_fit()
	print("== %d OK, %d FALLIDAS ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  [OK]   ", name)
	else:
		failed += 1
		print("  [FAIL] ", name)


## Error 1: tocar Cazar debe abrir el envío de flota aunque llegue una
## actualización del servidor entre el toque y el soltar.
func test_popup_tap_survives_refresh() -> void:
	game.show_map()
	await _wait(0.5)
	game.goto_mission({"event": "xeno_hunted"})
	await _wait(0.6)
	var hud: Control = game.hud
	var btn: Button = _find_button(hud.popup, U.t("Cazar"))
	check(btn != null, "la tarjeta de la xenoforma muestra el botón Cazar")
	if btn == null:
		return
	var at: Vector2 = btn.get_global_rect().get_center()
	_mouse(at, true)
	GameClient.player_updated.emit()   # llega una actualización a mitad del toque
	await get_tree().process_frame
	await get_tree().process_frame
	check(is_instance_valid(btn) and btn.is_inside_tree(), "el botón sigue vivo tras la actualización")
	_mouse(at, false)
	await _wait(0.4)
	check(game.modal_root.get_child_count() > 0, "soltar sobre Cazar abre el envío de flota")
	game.close_all_panels()
	hud.hide_popup()
	game.map_view.clear_selection()
	await _wait(0.6)


## Error 1 (b): al cerrar la tarjeta, la barra inferior no reaparece de
## inmediato bajo el dedo.
func test_menu_bar_waits_after_popup() -> void:
	var hud: Control = game.hud
	game.goto_mission({"event": "xeno_hunted"})
	await _wait(0.5)
	hud.hide_popup()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not hud.menu_bar.visible, "la barra inferior sigue oculta justo después de cerrar la tarjeta")
	await _wait(0.6)
	check(hud.menu_bar.visible, "la barra inferior vuelve a aparecer después")


## Error 2: tras reubicar la Astronave, el indicador de coordenadas debe
## mostrar la nueva posición (la cámara acompaña a la nave).
func test_coords_follow_relocation() -> void:
	game.show_map()
	var hud: Control = game.hud
	var home: Vector2 = GameClient.base_pos()
	game.focus_tile(home)
	await _wait(0.8)
	var sent: bool = false
	for off: Vector2i in [Vector2i(14, 6), Vector2i(-12, 8), Vector2i(10, -12), Vector2i(-14, -6), Vector2i(18, 0), Vector2i(0, 18)]:
		var ok: Array = [false]
		var t: Vector2i = Vector2i(home) + off
		GameClient.intent("relocate", {"x": t.x, "y": t.y}, func(success: bool, _p: Dictionary) -> void: ok[0] = success)
		await _wait(0.3)
		if ok[0]:
			sent = true
			break
	check(sent, "la Astronave inicia el viaje")
	for i: int in range(60):
		U.debug_offset_ms += 1000
		await _wait(0.03)
	await _wait(1.5)
	var now_pos: Vector2 = GameClient.base_pos()
	check(now_pos.distance_to(home) > 5.0, "la Astronave llegó a otra posición (%s -> %s)" % [str(home), str(now_pos)])
	var c: Vector2 = game.map_view.center_tiles()
	check(c.distance_to(now_pos) <= 2.0, "el indicador muestra la nueva posición (%s, nave en %s)" % [hud.coords_label.text, str(now_pos)])


## Error 3: ningún texto visible debe mostrar nombres internos de estado
## como "(TRAVELING)".
func test_no_internal_state_names() -> void:
	var re := RegEx.create_from_string("\\((TRAVELING|ANCHORED|OUTBOUND|RETURNING|WORKING)\\)")
	var hits: Array = []
	var f := FileAccess.open("res://data/i18n_en.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	for k: String in d:
		if re.search(k) != null or re.search(str(d[k])) != null:
			hits.append(k)
	for path: String in ["res://ui/game.gd", "res://ui/hud/hud.gd", "res://ui/base/base_view.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		for m: RegExMatch in re.search_all(src):
			hits.append(path + ": " + m.get_string())
	check(hits.is_empty(), "sin nombres internos de estado en textos visibles %s" % str(hits))


## Error 4: los nombres de las salas no deben quedar bajo la barra de colas
## ni bajo la barra inferior.
func test_deck_labels_fit() -> void:
	game.show_base()
	await _wait(0.8)
	var labels: Rect2 = game.deck.labels_screen_rect()
	var top: float = game.base_view.free_area_top()
	var bottom: float = game.hud.menu_bar.get_global_rect().position.y
	var left: float = game.hud.mission_card.get_global_rect().end.x
	print("  cubierta: etiquetas=%s  zona libre: y %d..%d, x desde %d" % [str(labels), int(top), int(bottom), int(left)])
	check(labels.position.y >= top, "ninguna etiqueta queda bajo la barra de colas")
	check(labels.end.y <= bottom, "ninguna etiqueta queda bajo la barra inferior")
	check(labels.position.x >= left, "ninguna etiqueta queda bajo la tarjeta de misiones")


func _mouse(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev, true)


func _find_button(root: Node, text_part: String) -> Button:
	for ch: Node in root.find_children("*", "Button", true, false):
		var b: Button = ch
		if b.is_queued_for_deletion():
			continue
		var txt: String = b.text
		for l: Node in b.find_children("*", "Label", true, false):
			txt += " " + (l as Label).text
		if txt.contains(text_part):
			return b
	return null


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout
