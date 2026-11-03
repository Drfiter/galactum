extends Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR")
func _ready() -> void:
	GameClient.start_local("Mateo", "p05", true)
	var game: Node = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(2.5).timeout
	game.show_map()
	await get_tree().create_timer(0.6).timeout
	game.hud.show_entity(GameClient.me["base_id"])
	await get_tree().create_timer(0.5).timeout
	await shot("70_map_system")
	game.hud.hide_popup()
	game.open_panel("galaxy")
	await get_tree().create_timer(1.2).timeout
	await shot("71_galaxy")
	var gp: Node = game._stack[game._stack.size() - 1].get_child(0).get_child(0)
	gp.select_system("s14")
	await get_tree().create_timer(0.4).timeout
	await shot("72_galaxy_sel")
	gp.select_system("s16")
	await get_tree().create_timer(0.3).timeout
	await shot("73_galaxy_upcoming")
	game.close_all_panels()
	game.interstellar_jump("s14", "item", "Sistema 14 · Aquila")
	await get_tree().create_timer(1.3).timeout
	await shot("74_hyperspace")
	await get_tree().create_timer(2.5).timeout
	await shot("75_new_system")
	game.escape_jump()
	await get_tree().create_timer(0.5).timeout
	await shot("76_escape_confirm")
	get_tree().quit()
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
