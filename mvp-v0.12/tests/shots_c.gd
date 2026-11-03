extends Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR")
func _ready() -> void:
	var loc: String = OS.get_environment("GALACTUM_LOCALE")
	preload("res://shared/i18n.gd").set_locale(loc if not loc.is_empty() else "es")
	Catalog.reload()
	GameClient.start_local("Mateo", "p05", true)
	var game: Node = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(2.0).timeout
	var srv: Node = GameClient.local_server
	var p: Dictionary = srv.player(GameClient.player_id)
	p["resources"]["dark_matter"] = 6000
	for k in p["resources"].keys():
		p["resources"][k] = int(p["resources"][k]) + 8000
	srv.mark_player_dirty(p["id"])
	await get_tree().create_timer(0.6).timeout
	await shot("C0_deck_phase2")
	game.open_panel("room", {"room": "cantina"})
	await get_tree().create_timer(0.8).timeout
	await shot("C1_unlock")
	GameClient.intent("upgrade_room", {"room": "cantina"})
	await get_tree().create_timer(0.3).timeout
	game.close_all_panels()
	for i in range(40):
		srv.U.debug_offset_ms += 1000
		srv._tick()
	await get_tree().create_timer(0.8).timeout
	await shot("C2_cantina_built")
	game.open_panel("crew", {"tab": "recruit"})
	await get_tree().create_timer(0.8).timeout
	await shot("C3_recruit")
	var cp: Node = game._stack[game._stack.size() - 1].get_child(0).get_child(0)
	cp._do_recruit({"method": "mo", "count": 10})
	await get_tree().create_timer(2.2).timeout
	await shot("C4_reveal")
	game.close_all_panels()
	game.open_panel("crew", {"tab": "collection"})
	await get_tree().create_timer(0.8).timeout
	await shot("C5_collection")
	game.close_all_panels()
	game.open_panel("crew", {"tab": "active"})
	await get_tree().create_timer(0.8).timeout
	await shot("C6_active")
	game.close_all_panels()
	# Combate: caza + ataque para tener informes y ver FX en el mapa
	game.show_map()
	var home: Vector2 = GameClient.base_pos()
	var xs: Array = srv.world.nearest_of_kind(home, "xenoform", 40.0, func(e: Dictionary) -> bool: return int(e["level"]) == 1)
	GameClient.intent("march", {"mission": "hunt", "target_id": xs[0]["id"], "troops": {"drones_1": 30, "pilots_1": 30, "infantry_1": 30}})
	var en: Array = srv.world.nearest_of_kind(home, "base", 60.0, func(e: Dictionary) -> bool: return str(srv.player(e["owner"]).get("tag", "")) != "VGA")
	srv.player(en[0]["owner"])["protected_until"] = 0
	GameClient.intent("march", {"mission": "attack", "target_id": en[0]["id"], "troops": {"infantry_1": 40, "gunners_1": 20, "shields_1": 25, "drones_1": 20}})
	await get_tree().create_timer(0.5).timeout
	game.focus_tile(U2.v2(en[0]["pos"]))
	var f: Dictionary = srv.fleets.owned_fleets(p["id"]).filter(func(x: Dictionary) -> bool: return x["mission"] == "attack")[0]
	var wait_ms: int = int(f["arrive_ts"]) - srv.U.now_ms() - 400
	srv.U.debug_offset_ms += wait_ms
	await get_tree().create_timer(0.3).timeout
	srv._tick()
	await get_tree().create_timer(1.15).timeout
	await shot("C7_map_battle_fx")
	await get_tree().create_timer(0.4).timeout
	await shot("C8_map_battle_fx2")
	for i in range(120):
		srv.U.debug_offset_ms += 1000
		srv._tick()
	await get_tree().create_timer(0.5).timeout
	var rep: Dictionary = {}
	for r in GameClient.reports:
		if str(r.get("type", "")) == "attack":
			rep = r
			break
	game.open_panel("battle", {"report": rep})
	await get_tree().create_timer(2.6).timeout
	await shot("C9_battle_a")
	await get_tree().create_timer(2.4).timeout
	await shot("C10_battle_b")
	await get_tree().create_timer(4.5).timeout
	await shot("C11_battle_end")
	game.close_all_panels()
	for r in GameClient.reports:
		if str(r.get("type", "")) == "hunt":
			rep = r
			break
	game.open_panel("battle", {"report": rep})
	await get_tree().create_timer(3.2).timeout
	await shot("C12_hunt_battle")
	get_tree().quit()
const U2 = preload("res://shared/util.gd")
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
