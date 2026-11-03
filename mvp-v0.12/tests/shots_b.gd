extends Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR")
func _ready() -> void:
	preload("res://shared/i18n.gd").set_locale(OS.get_environment("GALACTUM_LOCALE") if not OS.get_environment("GALACTUM_LOCALE").is_empty() else "es")
	Catalog.reload()
	GameClient.start_local("Mateo", "p05", true)
	var game: Node = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await get_tree().create_timer(2.0).timeout
	var srv: Node = GameClient.local_server
	# Avanza la simulación ~6 minutos para que haya actividad de alianza y torneo.
	for i in range(360):
		srv.U.debug_offset_ms += 1000
		srv._tick()
	await get_tree().create_timer(0.5).timeout
	await shot("A0_base_hud")
	game.open_panel("alliance", {"tab": "goals"})
	await get_tree().create_timer(1.2).timeout
	await shot("A1_goals")
	game.close_all_panels()
	game.open_panel("alliance", {"tab": "members"})
	await get_tree().create_timer(1.2).timeout
	await shot("A2_members")
	game.close_all_panels()
	game.open_panel("alliance", {"tab": "ranking"})
	await get_tree().create_timer(1.2).timeout
	await shot("A3_ranking")
	game.close_all_panels()
	game.show_map()
	game.goto_mission({"event": "pvp_win"})
	await get_tree().create_timer(1.0).timeout
	await shot("A4_enemy_card")
	var eid: String = game.map_view.selected_id
	GameClient.intent("mark_target", {"target_id": eid})
	await get_tree().create_timer(1.0).timeout
	game.hud.hide_popup()
	await get_tree().create_timer(0.5).timeout
	await shot("A5_target_map")
	game.open_panel("alliance", {"tab": "target"})
	await get_tree().create_timer(1.2).timeout
	await shot("A6_target_tab")
	game.close_all_panels()
	game.open_panel("events", {"tab": "tournament"})
	await get_tree().create_timer(1.2).timeout
	await shot("A7_tournament")
	game.close_all_panels()
	game.open_panel("events", {"tab": "resource"})
	await get_tree().create_timer(1.0).timeout
	await shot("A8_resource")
	game.close_all_panels()
	GameClient.intent("debug_finish_event", {"which": "tournament"})
	await get_tree().create_timer(0.5).timeout
	game.open_panel("events", {"tab": "profit"})
	await get_tree().create_timer(1.2).timeout
	await shot("A9_profit")
	get_tree().quit()
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
