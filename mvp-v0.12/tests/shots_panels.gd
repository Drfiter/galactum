extends Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR")
func _ready() -> void:
	GameClient.start_local("Mateo", "p05", true)
	var game: Node = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(2.5).timeout
	await shot("60_base")
	game.open_panel("room", {"room": "hangar"})
	await get_tree().create_timer(0.8).timeout
	await shot("61_hangar")
	game.close_all_panels()
	game.show_map()
	game.goto_mission({"event": "gather_started"})
	await get_tree().create_timer(1.0).timeout
	await shot("62_popup")
	var e: Dictionary = GameClient.entities.get(game.map_view.selected_id, {})
	game.open_fleet_dialog("gather", e)
	await get_tree().create_timer(0.8).timeout
	await shot("63_fleet")
	get_tree().quit()
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
