extends Node
## Capturas de evidencia para los errores del feedback del 26/10/2026.
## Juega una sesión guionizada en español y guarda pantallazos + un log con
## mediciones (posición de la tarjeta, coordenadas, mensajes de chat, nombres).
## Uso (con pantalla):
##   GALACTUM_SHOTS_DIR=/ruta/ godot --path . --resolution 1600x720 res://tests/evidence_feedback.tscn

const U = preload("res://shared/util.gd")
var game: Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR") if not OS.get_environment("GALACTUM_SHOTS_DIR").is_empty() else "user://"


func _ready() -> void:
	preload("res://shared/i18n.gd").set_locale("es")
	GameClient.start_local("Mateo", "p05", true)
	game = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(2.5)

	# 1) Cubierta de la nave: etiquetas vs barra de colas y menú inferior.
	await shot("04_cubierta")

	# 2) Tarjeta de un objetivo en el mapa: botón Cazar vs barra inferior.
	game.show_map()
	await _wait(1.2)
	game.goto_mission({"event": "xeno_hunted"})
	await _wait(1.0)
	var hud: Control = game.hud
	var pr: Rect2 = hud.popup.get_global_rect()
	log_line("tarjeta: borde inferior=%d alto_pantalla=%d menu_visible=%s" % [int(pr.end.y), int(get_viewport().get_visible_rect().size.y), str(hud.menu_bar.visible)])
	await shot("01_tarjeta_cazar")
	hud.hide_popup()
	game.map_view.clear_selection()
	await _wait(0.4)

	# 3) Reubicar la Astronave: aviso y coordenadas al llegar.
	var home: Vector2 = GameClient.base_pos()
	var mv: Button = null
	for off: Vector2i in [Vector2i(14, 6), Vector2i(-12, 8), Vector2i(10, -12), Vector2i(-14, -6), Vector2i(18, 0), Vector2i(0, 18)]:
		hud.show_tile(Vector2i(int(home.x), int(home.y)) + off)
		await _wait(0.4)
		mv = _find_button(hud.popup, "Mover Astronave")
		if mv != null and not mv.disabled:
			break
	log_line("boton mover encontrado=%s" % str(mv != null))
	if mv != null:
		mv.pressed.emit()
	await _wait(0.7)
	await shot("03_aviso_transito")
	for i: int in range(60):
		U.debug_offset_ms += 1000
		await _wait(0.05)
	await _wait(1.5)
	log_line("nave antes=%s nave despues=%s indicador='%s'" % [str(home), str(GameClient.base_pos()), hud.coords_label.text])
	await shot("02_coordenadas")

	# 4) Chat de la alianza tras un rato de simulación.
	for i: int in range(90):
		U.debug_offset_ms += 10000
		await _wait(0.03)
	await _wait(1.0)
	game.open_panel("alliance", {"tab": "chat"})
	await _wait(0.8)
	await shot("05_chat_alianza")
	game.close_all_panels()

	# 5) Miembros de la alianza (nombre repetido con un tripulante).
	game.open_panel("alliance", {"tab": "members"})
	await _wait(0.8)
	await shot("06_miembros")
	game.close_all_panels()

	# 6) Ajustes (audio).
	game.open_panel("settings")
	await _wait(0.8)
	await shot("07_ajustes")
	game.close_all_panels()
	get_tree().quit()


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


func log_line(text: String) -> void:
	print("EVID ", text)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
	print("shot ", name)
