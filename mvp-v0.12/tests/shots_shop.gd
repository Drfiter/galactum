extends Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR")
func _ready() -> void:
	GameClient.start_local("Mateo", "p05", true)
	var game: Node = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(2.5).timeout
	await shot("80_base_features")
	game.open_panel("login")
	await get_tree().create_timer(0.8).timeout
	await shot("81_login")
	var lp: Node = game._stack[game._stack.size() - 1].get_child(0).get_child(0)
	GameClient.intent("claim_login", {}, func(ok: bool, p: Dictionary) -> void: game.show_reward(p.get("reward", {}), "Bono del Día %d · valor US$ %.2f" % [int(p.get("day", 1)), float(p.get("value_usd", 1.0))]))
	await get_tree().create_timer(0.9).timeout
	await shot("82_login_reward")
	game.close_all_panels()
	for t in ["offers", "items", "resources", "prices"]:
		game.open_panel("shop", {"tab": t})
		await get_tree().create_timer(0.7).timeout
		await shot("83_shop_" + t)
		game.close_all_panels()
	get_tree().quit()
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
