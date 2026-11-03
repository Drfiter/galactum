extends Node
## Capturas en inglés (idioma por defecto).
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR")
func _ready() -> void:
	preload("res://shared/i18n.gd").set_locale(OS.get_environment("GALACTUM_LOCALE") if not OS.get_environment("GALACTUM_LOCALE").is_empty() else "en")
	Catalog.reload()
	var title: Node = load("res://ui/title.tscn").instantiate()
	get_tree().root.add_child.call_deferred(title)
	await get_tree().create_timer(1.2).timeout
	await shot("90_title")
	title.queue_free()
	GameClient.start_local("Mateo", "p05", true)
	var game: Node = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(2.5).timeout
	await shot("91_base")
	game.open_panel("room", {"room": "hangar"})
	await get_tree().create_timer(0.7).timeout
	await shot("92_hangar")
	game.close_all_panels()
	game.show_map()
	game.goto_mission({"event": "xeno_hunted"})
	await get_tree().create_timer(1.0).timeout
	await shot("93_map_card")
	game.hud.hide_popup()
	game.open_panel("galaxy")
	await get_tree().create_timer(1.0).timeout
	await shot("94_galaxy")
	game.close_all_panels()
	game.open_panel("shop", {"tab": "prices"})
	await get_tree().create_timer(0.7).timeout
	await shot("95_prices")
	game.close_all_panels()
	game.open_panel("settings")
	await get_tree().create_timer(0.7).timeout
	await shot("96_settings")
	get_tree().quit()
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
