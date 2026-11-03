extends Node
## Flujo real: título -> partida -> volver al título -> continuar partida guardada.
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR") if not OS.get_environment("GALACTUM_SHOTS_DIR").is_empty() else "user://"

func _ready() -> void:
	var t: Node = load("res://ui/title.tscn").instantiate()
	get_tree().root.add_child.call_deferred(t)
	await _wait(0.3)
	get_tree().current_scene = t
	await _wait(1.2)
	var title: Node = get_tree().current_scene
	title.get("_name").text = "Lucas"
	title._play(false, true)
	await _wait(3.0)
	await shot("40_game_from_title")
	var game: Node = get_tree().current_scene
	print("scene=", game.name, " connected=", GameClient.connected, " me=", GameClient.me.get("name"))
	GameClient.intent("train", {"troop": "infantry_1", "qty": 10})
	await _wait(1.0)
	game.back_to_title()
	await _wait(1.5)
	await shot("41_back_title")
	title = get_tree().current_scene
	title._play(false, false)
	await _wait(3.0)
	print("reloaded me=", GameClient.me.get("name"), " train_queue=", GameClient.queue("train").get("label", "none"))
	await shot("42_reloaded")
	get_tree().quit()

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
	print("shot ", name)
