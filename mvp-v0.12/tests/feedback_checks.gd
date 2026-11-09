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
