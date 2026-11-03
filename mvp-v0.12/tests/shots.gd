extends Node
## Driver de capturas: juega una sesión guionizada y guarda pantallazos.

const U = preload("res://shared/util.gd")
var game: Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR") if not OS.get_environment("GALACTUM_SHOTS_DIR").is_empty() else "user://"
var step: int = 0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var only_title: bool = args.has("--title")
	if only_title:
		var t: Node = load("res://ui/title.tscn").instantiate()
		get_tree().root.add_child.call_deferred(t)
		await _wait(2.0)
		await shot("00_title")
		get_tree().quit()
		return
	GameClient.start_local("Mateo", "p05", true)
	game = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(2.5)
	await shot("01_base")
	game.open_panel("room", {"room": "factory"})
	await _wait(0.8)
	await shot("02_room_factory")
	game.close_all_panels()
	game.open_panel("room", {"room": "hangar"})
	await _wait(0.8)
	await shot("03_hangar")
	game.close_all_panels()
	game.show_map()
	await _wait(1.5)
	await shot("04_map")
	game.goto_mission({"event": "gather_started"})
	await _wait(1.0)
	await shot("05_popup_asteroid")
	var sel: String = game.map_view.selected_id
	var e: Dictionary = GameClient.entities.get(sel, {})
	game.open_fleet_dialog("gather", e)
	await _wait(0.8)
	await shot("06_fleet_dialog")
	game.close_all_panels()
	GameClient.intent("march", {"mission": "gather", "target_id": sel, "troops": {"infantry_1": 30, "gunners_1": 10}})
	game.goto_mission({"event": "xeno_hunted"})
	await _wait(1.0)
	await shot("07_popup_xeno")
	var xsel: String = game.map_view.selected_id
	GameClient.intent("march", {"mission": "hunt", "target_id": xsel, "troops": {"drones_1": 30, "pilots_1": 30, "infantry_1": 20}})
	game.hud.hide_popup()
	game.map_view.clear_selection()
	await _wait(3.0)
	await shot("08_fleets_moving")
	# Avanza el reloj para que lleguen.
	for i: int in range(40):
		U.debug_offset_ms += 1000
		await _wait(0.05)
	await _wait(1.0)
	await shot("09_after_hunt")
	game.open_panel("reports")
	await _wait(0.8)
	await shot("10_report")
	game.close_all_panels()
	game.map_view.set_zoom(0.4)
	await _wait(1.5)
	await shot("11_zoom_out")
	game.map_view.set_zoom(1.6)
	await _wait(1.0)
	await shot("12_zoom_in")
	game.map_view.set_zoom(1.0)
	game.open_panel("missions")
	await _wait(0.6)
	await shot("13_missions")
	game.close_all_panels()
	game.open_panel("alliance")
	await _wait(0.6)
	await shot("14_alliance")
	game.close_all_panels()
	game.open_panel("room", {"room": "lab"})
	await _wait(0.6)
	await shot("15_lab")
	game.close_all_panels()
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(out_dir + name + ".png")
	print("shot ", name)
