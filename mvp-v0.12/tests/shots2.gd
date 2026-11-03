extends Node
## Segunda sesión guionizada: tutorial, PvP con efectos, incursión enemiga, viaje.

const U = preload("res://shared/util.gd")
var game: Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR") if not OS.get_environment("GALACTUM_SHOTS_DIR").is_empty() else "user://"
var last_ack: Dictionary = {}


func _ready() -> void:
	GameClient.start_local("Mateo", "p05", true)
	game = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(2.0)
	_advance(70)
	await _wait(2.5)
	await shot("20_base_bubbles")
	await _intent("collect", {"room": "factory"})
	await _wait(2.3)
	await shot("21_mission_claimable")
	game.claim_story()
	await _wait(1.0)
	await shot("22_reward")
	game.close_all_panels()
	await _intent("upgrade_room", {"room": "factory"})
	await _intent("help", {"queue": "build"})
	await _wait(1.2)
	_advance(4)
	await _wait(2.5)
	await shot("23_upgrading_help")
	# PvP
	game.show_map()
	await _wait(1.0)
	var target: Dictionary = _nearest_enemy()
	print("target ", target.get("name"), " power ", target.get("power"))
	await _intent("march", {"mission": "scout", "target_id": target["id"], "troops": {}})
	await _intent("march", {"mission": "attack", "target_id": target["id"], "troops": {"infantry_1": 50, "drones_1": 30, "pilots_1": 30, "gunners_1": 20, "shields_1": 20}})
	var arrive: int = int(last_ack.get("arrive_ts", 0))
	game.focus_tile(GameClient.entity_position(target))
	await _wait(1.0)
	await shot("24_attack_enroute")
	U.debug_offset_ms += maxi(0, arrive - U.now_ms() - 300)
	await _wait(0.9)
	await shot("25_battle_fx")
	await _wait(1.5)
	game.open_panel("reports")
	await _wait(0.8)
	await shot("26_battle_report")
	game.close_all_panels()
	# Esperar regreso
	for i: int in range(60):
		_advance(1)
		await _wait(0.03)
	await _wait(1.0)
	# Incursión enemiga
	await _intent("debug_raid", {})
	await _wait(2.5)
	game.focus_tile(GameClient.base_pos())
	game.map_view.set_zoom(0.7)
	await _wait(1.5)
	await shot("27_incoming_raid")
	for i: int in range(120):
		_advance(1)
		await _wait(0.02)
	await _wait(1.5)
	game.open_panel("reports")
	await _wait(0.8)
	await shot("28_defense_report")
	game.close_all_panels()
	game.map_view.set_zoom(1.0)
	var bp: Vector2 = GameClient.base_pos()
	game.hud.show_tile(Vector2i(int(bp.x) + 8, int(bp.y) + 5))
	game.map_view.set_destination_marker(Vector2i(int(bp.x) + 8, int(bp.y) + 5))
	await _wait(0.8)
	await shot("29_tile_card")
	game.hud.hide_popup()
	await _intent("relocate", {"x": int(bp.x) + 8, "y": int(bp.y) + 5})
	await _wait(1.0)
	await shot("30_relocating")
	game.open_panel("elements")
	await _wait(0.7)
	await shot("31_elements")
	game.close_all_panels()
	game.open_panel("inventory")
	await _wait(0.7)
	await shot("32_inventory")
	game.close_all_panels()
	game.open_panel("settings")
	await _wait(0.7)
	await shot("33_settings")
	game.close_all_panels()
	game.show_base()
	game.open_panel("room", {"room": "medbay"})
	await _wait(0.7)
	await shot("34_medbay")
	get_tree().quit()


func _nearest_enemy() -> Dictionary:
	var best: Dictionary = {}
	var bd: float = INF
	for id: String in GameClient.entities:
		var e: Dictionary = GameClient.entities[id]
		if e.get("kind") != "base" or GameClient.relation_of(str(e.get("owner", "")), str(e.get("tag", ""))) != "enemy":
			continue
		var d: float = GameClient.entity_position(e).distance_to(GameClient.base_pos())
		if d < bd:
			bd = d
			best = e
	return best


func _intent(action: String, params: Dictionary) -> void:
	var done: Array = [false]
	GameClient.intent(action, params, func(ok: bool, payload: Dictionary) -> void:
		last_ack = payload
		print(action, " -> ", ok, " ", payload.get("message", ""))
		done[0] = true)
	for i: int in range(40):
		if done[0]:
			break
		await _wait(0.05)


func _advance(s: float) -> void:
	U.debug_offset_ms += int(s * 1000)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
	print("shot ", name)
