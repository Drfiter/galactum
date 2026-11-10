extends Node
## Capturas de evidencia de las funcionalidades nuevas (una sección por fase).
## Uso: GALACTUM_SHOTS_DIR=/ruta/ godot --path . --resolution 1600x720 res://tests/evidence_fases.tscn [-- --fase=N]

const U = preload("res://shared/util.gd")
var game: Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR") if not OS.get_environment("GALACTUM_SHOTS_DIR").is_empty() else "user://"
var only: int = 0


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--fase="):
			only = int(a.substr(7))
	preload("res://shared/i18n.gd").set_locale("es")
	GameClient.start_local("Mateo", "p05", true)
	game = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(3.0)
	if only == 0 or only == 1:
		await fase1()
	if only == 0 or only == 2:
		await fase2()
	if only == 0 or only == 3:
		await fase3()
	if only == 0 or only == 4:
		await fase4()
	if only == 0 or only == 5:
		await fase5()
	if only == 0 or only == 6:
		await fase6()
	if only == 0 or only == 7:
		await fase7()
	if only == 0 or only == 8:
		await fase8()
	get_tree().quit()


func srv() -> Node:
	return GameClient.local_server


func me_srv() -> Dictionary:
	return srv().player(GameClient.player_id)


func fase1() -> void:
	var p: Dictionary = me_srv()
	var c: Dictionary = srv().crew.ensure(p)
	for cid: String in ["p01", "p07", "p16", "p23", "p30", "p38"]:
		c["owned"][cid] = {"stars": 2, "ts": 0, "level": 1 + randi() % 15, "exp": 40, "grade": 1 + randi() % 3}
	p["items"]["insignia"] = 75
	srv().crew.refresh_mods(p)
	srv().mark_player_dirty(p["id"])
	await _wait(1.0)
	game.open_panel("crew", {"tab": "collection"})
	await _wait(1.0)
	await shot("f1_01_coleccion")
	game.close_all_panels()
	game.show_map()
	await _wait(1.2)
	game.goto_mission({"event": "xeno_hunted"})
	await _wait(0.8)
	var xid: String = game.map_view.selected_id
	game.open_fleet_dialog("hunt", GameClient.entities.get(xid, {}))
	await _wait(1.0)
	var dlg: Node = game.modal_root
	for cid: String in ["p01", "p07", "p16"]:
		var b: Button = dlg.find_child("Crew_" + cid, true, false) as Button
		if b != null:
			b.button_pressed = true
	await _wait(0.5)
	await shot("f1_02_flota_con_tripulantes")
	var send: Button = null
	for ch: Node in dlg.find_children("*", "Button", true, false):
		if (ch as Button).text.contains("Despegar"):
			send = ch
	if send != null:
		send.pressed.emit()
	await _wait(1.0)
	for i: int in range(60):
		U.debug_offset_ms += 1000
		await _wait(0.04)
	await _wait(1.0)
	game.open_panel("reports")
	await _wait(1.0)
	await shot("f1_03_informe_exp")
	game.close_all_panels()


func fase2() -> void:
	var p: Dictionary = me_srv()
	var cmd: RefCounted = srv().commander
	cmd.grant_exp(p, 9000)
	for tid: String in ["c_attack", "c_attack", "c_attack", "c_defense", "c_defense", "c_hp", "e_prod", "e_prod", "l_crew"]:
		cmd.learn(p, tid)
	await _wait(0.8)
	game.open_panel("commander", {"tab": "talents"})
	await _wait(1.0)
	await shot("f2_01_protocolos")
	game.close_all_panels()
	var bot: Dictionary = {}
	for q: Dictionary in srv().state["players"].values():
		if q.get("is_bot", false):
			bot = q
			break
	var old: float = float(Catalog.commander["capture"]["base_chance"])
	Catalog.commander["capture"]["base_chance"] = 1.0
	cmd.try_capture(bot, p, {"infantry_1": 100}, {"infantry_1": 90}, 3)
	var bot2: Dictionary = {}
	for q: Dictionary in srv().state["players"].values():
		if q.get("is_bot", false) and q["id"] != bot["id"]:
			bot2 = q
			break
	cmd.try_capture(p, bot2, {"infantry_1": 100}, {"infantry_1": 90}, 5)
	Catalog.commander["capture"]["base_chance"] = old
	await _wait(0.8)
	game.open_panel("commander", {"tab": "profile"})
	await _wait(1.0)
	await shot("f2_02_capturado")
	game.close_all_panels()
	game.open_panel("commander", {"tab": "prisoners"})
	await _wait(1.0)
	await shot("f2_03_prisioneros")
	game.close_all_panels()
	p["resources"]["credits"] = int(p["resources"].get("credits", 0)) + 50000
	cmd.pay_ransom(p)
	await _wait(0.5)


func fase3() -> void:
	var p: Dictionary = me_srv()
	var arm: RefCounted = srv().armory
	p["rooms"]["armory"] = {"level": 4}
	p["resources"]["credits"] = int(p["resources"].get("credits", 0)) + 400000
	for eq_id: String in ["eq_01_weapon", "eq_01_armor", "eq_01_visor", "eq_04_module", "eq_02_reactor"]:
		var eq: Dictionary = Catalog.equipment_by_id[eq_id]
		for k: String in eq["recipe"]:
			p["resources"][k] = int(p["resources"].get(k, 0)) + int(eq["recipe"][k]) * 6
		arm.forge(p, eq_id)
		arm.equip(p, eq_id)
	arm.upgrade(p, "eq_01_weapon")
	arm.upgrade(p, "eq_01_weapon")
	for mid: String in ["mat_x_x05_1", "mat_x_x12_2", "mat_f_alloy_2", "mat_f_quantum_3", "mat_x_x20_3"]:
		p["resources"][mid] = int(p["resources"].get(mid, 0)) + 7
	srv().mark_player_dirty(p["id"])
	await _wait(0.8)
	game.open_panel("armory", {"tab": "gear"})
	await _wait(1.0)
	await shot("f3_01_equipo")
	game.close_all_panels()
	game.open_panel("armory", {"tab": "forge"})
	await _wait(1.0)
	await shot("f3_02_forja")
	game.close_all_panels()
	game.open_panel("armory", {"tab": "materials"})
	await _wait(1.0)
	await shot("f3_03_materiales")
	game.close_all_panels()


func fase4() -> void:
	var p: Dictionary = me_srv()
	var s: Node = srv()
	p["troops"]["infantry_1"] = int(p["troops"].get("infantry_1", 0)) + 300
	p["resources"]["credits"] = int(p["resources"].get("credits", 0)) + 50000
	s.alliance.donate(p, "credits", 8000)
	s.alliance.donate(p, "ore", 1000)
	s.alliance.withdraw(p, "credits", 1000)
	p["resources"]["bonds"] = int(p["resources"].get("bonds", 0)) + 6000
	s.state["next_bot_help_req"] = 0
	s.alliance.tick(U.now_ms())
	var enemy: Dictionary = {}
	var home: Vector2 = U.v2(s.world.get_entity(p["base_id"])["pos"])
	var best: float = 1e9
	for q: Dictionary in s.state["players"].values():
		if q.get("is_bot", false) and str(q.get("tag", "")) != "VGA" and str(q.get("system", "")) == str(p.get("system", "")):
			var e: Dictionary = s.world.get_entity(q["base_id"])
			if not e.is_empty() and U.v2(e["pos"]).distance_to(home) < best:
				best = U.v2(e["pos"]).distance_to(home)
				enemy = q
	enemy["protected_until"] = 0
	enemy["shield_until"] = 0
	s.rally.start(p, enemy["base_id"], {"infantry_1": 120}, 120)
	for q: Dictionary in s.social.members("VGA"):
		if q.get("is_bot", false):
			q["troops"]["infantry_1"] = int(q["troops"].get("infantry_1", 0)) + 100
	await _wait(5.5)
	s.mark_player_dirty(p["id"])
	await _wait(0.6)
	game.open_panel("alliance_hq", {"tab": "rallies"})
	await _wait(1.0)
	await shot("f4_01_asedios")
	game.close_all_panels()
	game.open_panel("alliance_hq", {"tab": "manage"})
	await _wait(1.0)
	await shot("f4_02_gestion")
	game.close_all_panels()
	game.open_panel("alliance_hq", {"tab": "treasury"})
	await _wait(1.0)
	await shot("f4_03_tesoreria")
	game.close_all_panels()
	game.open_panel("alliance_hq", {"tab": "shop"})
	await _wait(1.0)
	await shot("f4_04_tienda")
	game.close_all_panels()
	game.open_panel("alliance_hq", {"tab": "search"})
	await _wait(1.5)
	await shot("f4_05_buscar")
	game.close_all_panels()
	game.show_map()
	game.focus_tile(U.v2(s.world.get_entity(enemy["base_id"])["pos"]))
	await _wait(1.2)
	game.hud.show_entity(enemy["base_id"])
	await _wait(0.8)
	await shot("f4_06_mapa_asedio")
	game.hud.hide_popup()


func fase5() -> void:
	var p: Dictionary = me_srv()
	p["rooms"]["bridge"]["level"] = 16
	p["rooms"]["lab"]["level"] = 9
	for rid: String in ["dock", "airlock", "cargo_bay", "trade_port", "containment", "cloak"]:
		p["rooms"][rid] = {"level": 2, "last_ts": U.now_ms(), "pending": {}}
	p["tech"] = {"kinetic_alloys": 3, "ablative_armor": 2, "nanomedicine": 1, "tier2_protocol": 1, "tier3_protocol": 1, "assisted_mining": 2, "ion_drives": 2, "neural_link": 1}
	for k: String in ["ore", "kliptium", "water", "credits", "copper"]:
		p["resources"][k] = int(p["resources"].get(k, 0)) + 200000
	srv().mark_player_dirty(p["id"])
	game.close_all_panels()
	game.show_base()
	await _wait(2.0)
	await shot("f5_01_cubierta_24_salas")
	game.open_panel("research")
	await _wait(1.2)
	await shot("f5_02_arbol_investigacion")
	game.close_all_panels()
	game.open_panel("room", {"room": "hangar"})
	await _wait(1.0)
	await shot("f5_03_hangar_n1_n5")
	game.close_all_panels()
	game.open_panel("room", {"room": "trade_port"})
	await _wait(1.0)
	await shot("f5_04_puerto_comercio")
	game.close_all_panels()
	game.show_map()
	await _wait(1.0)
	game.goto_mission({"event": "xeno_hunted"})
	await _wait(0.8)
	game.open_fleet_dialog("attack", GameClient.entities.get(game.map_view.selected_id, {}))
	await _wait(1.0)
	await shot("f5_05_formaciones")
	game.close_all_panels()


func fase6() -> void:
	var p: Dictionary = me_srv()
	var s: Node = srv()
	var lo: RefCounted = s.liveops
	p["resources"]["dark_matter"] = int(p["resources"].get("dark_matter", 0)) + 3000
	for kind: String in ["xeno_kill", "room_upgraded", "research_done", "pvp_win"]:
		s.on_activity(p, kind, 12.0)
	lo.buy_pass(p)
	lo.claim_pass(p, 1, "free")
	lo.claim_pass(p, 1, "premium")
	lo.claim_pass(p, 2, "free")
	lo.add_license_points(p, 2600)
	s.mark_player_dirty(p["id"])
	await _wait(0.8)
	game.close_all_panels()
	game.show_base()
	await _wait(4.5)
	game.open_panel("liveops", {"tab": "pass"})
	await _wait(1.2)
	await shot("f6_01_pase_expedicion")
	game.close_all_panels()
	game.open_panel("liveops", {"tab": "license"})
	await _wait(1.0)
	await shot("f6_02_licencia")
	game.close_all_panels()
	# Avanzar el reloj hasta la próxima Singularidad.
	var ev: Dictionary = lo.singularity_now()
	if not bool(ev.get("active", false)):
		U.debug_offset_ms += int(ev["next_start"]) - U.now_ms() + 60000
	for kind: String in ["xeno_kill", "room_upgraded"]:
		s.on_activity(p, kind, 15.0)
	lo.claim_singularity(p, 0)
	s.mark_player_dirty(p["id"])
	await _wait(1.0)
	game.open_panel("liveops", {"tab": "singularity"})
	await _wait(1.0)
	await shot("f6_03_singularidad")
	game.close_all_panels()
	var fe: Dictionary = lo.festival(str(p["tag"]))
	fe["progress"] = {"f_hunt": 95.0, "f_mine": 310.0, "f_build": 22.0, "f_war": 8.0}
	fe["contrib"][p["id"]] = 46.0
	lo.claim_festival(p, 0)
	s.mark_player_dirty(p["id"])
	await _wait(0.8)
	game.open_panel("liveops", {"tab": "festival"})
	await _wait(1.0)
	await shot("f6_04_festival")
	game.close_all_panels()


func fase7() -> void:
	var p: Dictionary = me_srv()
	var s: Node = srv()
	var c: Dictionary = s.crew.ensure(p)
	var lv: Array = [9, 8, 8, 7, 7, 5, 4]
	var ids: Array = ["p01", "p07", "p16", "p23", "p30", "p38", "p12"]
	for i: int in range(ids.size()):
		var o: Dictionary = c["owned"].get(ids[i], {"stars": 2, "ts": 0, "exp": 0, "grade": 2})
		o["level"] = lv[i]
		c["owned"][ids[i]] = o
	s.crew.refresh_mods(p)
	var X: RefCounted = s.expeditions
	for sid: String in ["1-1", "1-2", "1-3", "1-4"]:
		X.ensure(p)["stars"][sid] = 3
	X.ensure(p)["stars"]["1-5"] = 2
	s.mark_player_dirty(p["id"])
	game.close_all_panels()
	game.show_base()
	await _wait(1.5)
	await shot("f7_00_hud_expedicion")
	game.open_panel("expedition")
	await _wait(1.2)
	await shot("f7_01_campana")
	var dlg: Node = game.modal_root
	var fight: Button = dlg.find_child("Fight", true, false) as Button
	if fight != null:
		fight.pressed.emit()
	await _wait(2.2)
	await shot("f7_02_combate")
	await _wait(12.0)
	var skip: Button = dlg.find_child("Skip", true, false) as Button
	if skip != null:
		skip.pressed.emit()
	await _wait(1.0)
	await shot("f7_03_resultado")
	game.close_all_panels()
	for st: Dictionary in Catalog.expeditions["chapters"][0]["stages"]:
		X.ensure(p)["stars"][st["id"]] = 3
	X.ensure(p)["elite"]["1-1"] = 3
	X.ensure(p)["elite"]["1-2"] = 1
	s.liveops.add_license_points(p, 2400)
	s.mark_player_dirty(p["id"])
	await _wait(0.8)
	game.open_panel("expedition")
	await _wait(1.0)
	var eb: Button = dlg.find_child("Mode_elite", true, false) as Button
	if eb != null:
		eb.pressed.emit()
	await _wait(0.6)
	var s2: Button = dlg.find_child("Stage_1-1", true, false) as Button
	if s2 != null:
		s2.pressed.emit()
	await _wait(0.8)
	await shot("f7_04_elite_barrido")
	game.close_all_panels()


func fase8() -> void:
	var p: Dictionary = me_srv()
	var s: Node = srv()
	var E: RefCounted = s.endgame
	s.use_player_system(p)
	E.ensure_system()
	p["rank"] = "R5"
	var hive: Dictionary = E.hives()[0]
	hive["hp"] = int(hive["max_hp"] * 0.62)
	hive["damage_by"][p["id"]] = 9400
	hive["last_hit"] = U.now_ms()
	s.world.bump(hive)
	var ext: Dictionary = {}
	for e: Dictionary in E.platforms():
		if str(e["ptype"]) == "extraction":
			ext = e
	E._capture(ext, str(p["tag"]), U.now_ms())
	game.close_all_panels()
	game.show_map()
	await _wait(1.0)
	game.focus_tile(U.v2(ext["pos"]))
	await _wait(1.5)
	await shot("f8_01_plataformas_mapa")
	game.hud.show_entity(E.citadel()["id"])
	await _wait(0.8)
	await shot("f8_02_ciudadela")
	game.hud.hide_popup()
	game.focus_tile(U.v2(hive["pos"]))
	await _wait(1.5)
	game.hud.show_entity(hive["id"])
	await _wait(0.8)
	await shot("f8_03_colmena")
	game.hud.hide_popup()
	game.open_panel("endgame", {"tab": "platforms"})
	await _wait(1.0)
	await shot("f8_04_guerra_plataformas")
	game.close_all_panels()
	game.open_panel("endgame", {"tab": "hives"})
	await _wait(1.0)
	await shot("f8_05_guerra_colmenas")
	game.close_all_panels()
	E._capture(E.citadel(), str(p["tag"]), U.now_ms())
	E.grant_title(p, "admiral", p["id"])
	s.mark_player_dirty(p["id"])
	await _wait(0.8)
	game.open_panel("endgame", {"tab": "titles"})
	await _wait(1.0)
	var gb: Button = game.modal_root.find_child("Grant_deserter", true, false) as Button
	if gb != null:
		gb.pressed.emit()
	await _wait(0.8)
	await shot("f8_06_titulos")
	game.close_all_panels()
	p["rooms"]["cryo"] = {"level": 3, "last_ts": U.now_ms(), "pending": {}}
	p["cryo"] = {"infantry_1": 180, "drones_1": 90, "pilots_1": 60}
	s.endgame.rescue_start(p)
	s.mark_player_dirty(p["id"])
	game.show_base()
	await _wait(1.2)
	game.open_panel("room", {"room": "cryo"})
	await _wait(1.0)
	await shot("f8_07_rescate")
	game.close_all_panels()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
	print("shot ", name)
