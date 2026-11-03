extends Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR") if not OS.get_environment("GALACTUM_SHOTS_DIR").is_empty() else "user://"
func _ready() -> void:
	var tag: String = "x"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.trim_prefix("--tag=")
	GameClient.start_local("Mateo", "p05", true)
	var game: Node = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(2.5).timeout
	await shot("50_%s_base" % tag)
	game.show_map()
	game.goto_mission({"event": "xeno_hunted"})
	await get_tree().create_timer(1.2).timeout
	await shot("51_%s_map" % tag)
	game.open_panel("room", {"room": "hangar"})
	await get_tree().create_timer(0.8).timeout
	await shot("52_%s_panel" % tag)
	get_tree().quit()
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
