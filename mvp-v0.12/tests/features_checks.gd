extends Node
## Pruebas de servidor de las funcionalidades pedidas en el feedback del
## 26/10/2026 ("Lo más importante que falta"). Cada fase agrega sus pruebas.
## Ejecutar:  godot --headless --path . res://tests/features_checks.tscn

const U = preload("res://shared/util.gd")
const GameServerScript = preload("res://server/game_server.gd")

var srv: Node
var sid: int
var inbox: Array = []
var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("== Galactum: pruebas de funcionalidades ==")
	srv = GameServerScript.new()
	add_child(srv)
	srv.start({"persist": false, "fresh": true, "seed": 4242})
	sid = srv.open_session(func(m: Dictionary) -> void: inbox.append(m))
	srv.handle_message(sid, {"type": "hello", "protocol": "galactum-mvp-1", "name": "Tester", "avatar": "p05"})
	test_crew_in_fleets()
	test_commander()
	test_armory()
	test_alliances()
	test_rally_and_reinforcements()
	test_progression()
	test_liveops()
	print("== %d OK, %d FALLIDAS ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func me() -> Dictionary:
	return srv.player(srv.sessions[sid]["player_id"])


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  [OK]   ", name)
	else:
		failed += 1
		print("  [FAIL] ", name)


func intent(action: String, params: Dictionary = {}) -> Dictionary:
	var rid: String = "t%d" % randi()
	var msg: Dictionary = params.duplicate()
	msg["type"] = "intent"
	msg["action"] = action
	msg["request_id"] = rid
	inbox.clear()
	srv.handle_message(sid, msg)
	for m: Dictionary in inbox:
		if str(m.get("request_id", "")) == rid:
			return m
	return {}


func advance(seconds: float) -> void:
	U.debug_offset_ms += int(seconds * 1000.0)
	srv._tick()


func nearest(kind: String, filter: Callable = Callable()) -> Dictionary:
	var p: Dictionary = me()
	var home: Vector2 = U.v2(srv.world.get_entity(p["base_id"])["pos"])
	var list: Array = srv.world.nearest_of_kind(home, kind, 60.0, filter if filter.is_valid() else func(_e: Dictionary) -> bool: return true)
	return list[0] if not list.is_empty() else {}


# ---------------------------------------------------------------- fase 1

func test_crew_in_fleets() -> void:
	print(" -- Fase 1: Tripulantes en flotas")
	var p: Dictionary = me()
	var c: Dictionary = srv.crew.ensure(p)
	for cid: String in ["p01", "p02", "p03", "p04", "p05", "p06"]:
		c["owned"][cid] = {"stars": 1, "ts": 0}
	p["troops"]["infantry_1"] = 400
	p["troops"]["drones_1"] = 200
	p["resources"]["energy"] = 100
	var room_crew: String = str((c["active"] as Array)[0])
	var x: Dictionary = nearest("xenoform", func(e: Dictionary) -> bool: return int(e["level"]) == 2)
	if x.is_empty():
		x = nearest("xenoform")
	var r: Dictionary = intent("march", {"mission": "hunt", "target_id": x["id"], "troops": {"infantry_1": 50}, "crew": [room_crew]})
	check(r.get("code", "") == "CREW_IN_ROOM", "doble empleo: un tripulante de sala no puede embarcar")
	r = intent("march", {"mission": "hunt", "target_id": x["id"], "troops": {"infantry_1": 50}, "crew": ["p01", "p02", "p03", "p04", "p05", "p06"]})
	check(r.get("code", "") == "CREW_LIMIT", "máximo 5 tripulantes por flota")
	var base_atk: float = float(preload("res://server/sgm/economy.gd").combat_mods(p, false)["attack"])
	r = intent("march", {"mission": "hunt", "target_id": x["id"], "troops": {"infantry_1": 100, "drones_1": 50}, "crew": ["p01", "p02", "p03"]})
	check(r.get("type") == "ack", "una flota sale con 3 tripulantes %s" % ("" if r.get("type") == "ack" else str(r)))
	var f: Dictionary = srv.fleets.fleets().get(str(r.get("fleet_id", "")), {})
	check((f.get("crew", []) as Array).size() == 3, "la flota lleva a sus tripulantes")
	var crew_atk: float = float(srv.crew.fleet_mods(p, ["p01", "p02", "p03"]).get("attack", 0.0))
	check(absf(float(f.get("mods", {}).get("attack", 0.0)) - (base_atk + crew_atk)) < 0.0001, "el ataque de la flota incluye el bono de sus tripulantes")
	var x2: Dictionary = nearest("xenoform", func(e: Dictionary) -> bool: return e["id"] != x["id"])
	r = intent("march", {"mission": "hunt", "target_id": x2["id"], "troops": {"drones_1": 20}, "crew": ["p01"]})
	check(r.get("code", "") == "CREW_DEPLOYED", "doble empleo: un tripulante no puede ir en dos flotas")
	r = intent("crew_assign", {"crew_id": "p02", "on": true})
	check(r.get("code", "") == "CREW_DEPLOYED", "doble empleo: un tripulante en flota no puede trabajar en una sala")
	var lvl_before: int = int(c["owned"]["p01"].get("level", 1))
	for i: int in range(90):
		advance(1.0)
		if srv.fleets.fleets().get(f["id"], {}).get("state", "") != "outbound":
			break
	var rep: Dictionary = {}
	for rr: Dictionary in srv.reports.list_for(p["id"]):
		if str(rr.get("type", "")) == "hunt":
			rep = rr
			break
	check(not (rep.get("crew", []) as Array).is_empty(), "el informe de caza muestra la EXP de los tripulantes")
	check(int(c["owned"]["p01"].get("exp", 0)) > 0 or int(c["owned"]["p01"].get("level", 1)) > lvl_before, "los tripulantes ganan EXP al cazar")
	var o: Dictionary = c["owned"]["p04"]
	var got: Array = srv.crew.grant_exp(p, ["p04"], 5000)
	check(int(o["level"]) > 10 and bool(got[0]["leveled"]), "con EXP suficiente suben de nivel (nivel %d)" % int(o["level"]))
	check(str(srv.crew.rank_of(int(o["level"]))["name"]) != "Recluta", "al subir de nivel cambian de rango (%s)" % str(srv.crew.rank_of(int(o["level"]))["name"]))
	p["items"].erase("insignia")
	r = intent("crew_promote", {"crew_id": "p05"})
	check(r.get("code", "") == "INSUFFICIENT_RESOURCES", "subir de grado requiere Insignias")
	var bonus_before: float = srv.crew.bonus_of(p, "p05")
	p["items"]["insignia"] = 100
	r = intent("crew_promote", {"crew_id": "p05"})
	check(r.get("type") == "ack" and int(c["owned"]["p05"]["grade"]) == 2, "con Insignias sube a grado 2")
	check(srv.crew.bonus_of(p, "p05") > bonus_before, "el grado aumenta la pasiva del tripulante")
	check(int(p["items"].get("insignia", 0)) == 80, "se descuentan 20 Insignias")
	var v: Dictionary = srv.crew.view(p)
	var row: Dictionary = (v["owned"] as Array).filter(func(e: Dictionary) -> bool: return e["id"] == "p04")[0]
	check(row.has("level") and row.has("rank") and row.has("grade") and row.has("exp_next"), "la vista del cliente incluye nivel, rango, grado y EXP")


# ---------------------------------------------------------------- fase 2

func test_commander() -> void:
	print(" -- Fase 2: Comandante")
	const Eco = preload("res://server/sgm/economy.gd")
	var p: Dictionary = me()
	var c: Dictionary = srv.commander.ensure(p)
	check(int(c["level"]) == 1 and srv.commander.points_free(p) == 1, "el Comandante empieza en nivel 1 con 1 punto de Protocolo")
	var atk0: float = float(Eco.combat_mods(p, false)["attack"])
	var r: Dictionary = intent("talent_learn", {"talent": "c_attack"})
	check(r.get("type") == "ack", "aprende un Protocolo de nivel 0 (Ofensiva Coordinada)")
	check(absf(float(Eco.combat_mods(p, false)["attack"]) - atk0 - 0.02) < 0.0001, "el Protocolo suma +2% de ataque al combate")
	r = intent("talent_learn", {"talent": "c_defense"})
	check(r.get("code", "") == "NO_POINTS", "sin puntos no se puede aprender más")
	var up: int = srv.commander.grant_exp(p, 20000)
	check(up > 5 and srv.commander.points_free(p) == up, "con EXP sube %d niveles y gana %d puntos" % [up, up])
	r = intent("talent_learn", {"talent": "c_hp"})
	check(r.get("code", "") == "TIER_LOCKED", "un Protocolo de nivel 1 exige 5 puntos en su rama")
	for i: int in range(4):
		intent("talent_learn", {"talent": "c_attack"})
	r = intent("talent_learn", {"talent": "c_hp"})
	check(r.get("type") == "ack", "con 5 puntos en Combate se desbloquea el nivel 1")
	var prod0: float = float(Eco.production_rates(p).get("ore", 0.0))
	intent("talent_learn", {"talent": "e_prod"})
	check(float(Eco.production_rates(p).get("ore", 0.0)) > prod0, "Optimización Industrial aumenta la producción")
	var bot: Dictionary = {}
	for q: Dictionary in srv.state["players"].values():
		if q.get("is_bot", false):
			bot = q
			break
	var old_chance: float = float(Catalog.commander["capture"]["base_chance"])
	Catalog.commander["capture"]["base_chance"] = 1.0
	var got: bool = srv.commander.try_capture(bot, p, {"infantry_1": 100}, {"infantry_1": 80}, 7)
	check(got and srv.commander.is_captured(p), "al perder la nave con muchas bajas el Comandante puede ser capturado")
	check((p.get("cmd_mods", {}) as Dictionary).is_empty(), "mientras está capturado sus Protocolos no aplican")
	check(absf(float(Eco.combat_mods(p, false)["attack"]) - atk0) < 0.0001, "el ataque vuelve al valor sin Protocolos")
	check(not srv.commander.try_capture(bot, p, {"infantry_1": 100}, {"infantry_1": 10}, 9), "con pocas bajas no hay captura")
	var bot_cr: int = int(bot["resources"].get("credits", 0))
	p["resources"]["credits"] = 0
	r = intent("pay_ransom", {})
	check(r.get("code", "") == "INSUFFICIENT_RESOURCES", "el rescate cuesta Créditos")
	p["resources"]["credits"] = 100000
	r = intent("pay_ransom", {})
	check(r.get("type") == "ack" and not srv.commander.is_captured(p), "pagar el rescate libera al Comandante")
	check(int(bot["resources"].get("credits", 0)) > bot_cr, "el captor cobra el rescate")
	check(not (p.get("cmd_mods", {}) as Dictionary).is_empty(), "al volver, sus Protocolos aplican otra vez")
	srv.commander.try_capture(bot, p, {"infantry_1": 100}, {"infantry_1": 90}, 11)
	advance(float(Catalog.commander["capture"]["duration_sec"]) + 5.0)
	check(not srv.commander.is_captured(p), "cumplida la condena vuelve solo")
	var cr0: int = int(p["resources"].get("credits", 0))
	srv.commander.try_capture(p, bot, {"infantry_1": 100}, {"infantry_1": 90}, 13)
	check((srv.commander.view(p)["prisoners"] as Array).size() == 1, "capturar al Comandante de un bot lo deja como prisionero")
	advance(310.0)
	check(int(p["resources"].get("credits", 0)) > cr0, "el bot paga el rescate y lo cobras")
	Catalog.commander["capture"]["base_chance"] = old_chance
	r = intent("talent_reset", {})
	check(r.get("type") == "ack" and (srv.commander.ensure(p)["talents"] as Dictionary).is_empty(), "reiniciar Protocolos devuelve los puntos (cuesta Materia Oscura)")
	var v: Dictionary = srv.commander.view(p)
	check(v.has("level") and v.has("points") and v.has("captured") and v.has("prisoners"), "la vista del cliente incluye nivel, puntos, captura y prisioneros")


# ---------------------------------------------------------------- fase 3

func test_armory() -> void:
	print(" -- Fase 3: Armería y equipamiento")
	const Eco = preload("res://server/sgm/economy.gd")
	var p: Dictionary = me()
	check(Catalog.materials_by_id.size() == 150, "el catálogo tiene 150 materiales")
	check(Catalog.equipment_by_id.size() == 90, "el catálogo tiene 90 equipos")
	var drop: Dictionary = srv.armory.hunt_drop("x03", 3, true)
	check(drop.has("mat_x_x03_3") and int(drop["mat_x_x03_3"]) > 0, "cazar una xenoforma N3 suelta su material de calidad III")
	check(not srv.armory.mining_drop("ast_1", 2).is_empty(), "minar suelta material de forja")
	var eq: Dictionary = Catalog.equipment_by_id["eq_01_weapon"]
	p["rooms"].erase("armory")
	var r: Dictionary = intent("armory_forge", {"equipment": "eq_01_weapon"})
	check(r.get("code", "") == "ARMORY_LEVEL", "sin Armería no se puede forjar")
	p["rooms"]["armory"] = {"level": 1}
	r = intent("armory_forge", {"equipment": "eq_01_weapon"})
	check(r.get("code", "") == "INSUFFICIENT_RESOURCES", "forjar exige materiales y Créditos")
	for k: String in eq["recipe"]:
		p["resources"][k] = int(eq["recipe"][k]) * 20
	p["resources"]["credits"] = 500000
	r = intent("armory_forge", {"equipment": "eq_01_weapon"})
	check(r.get("type") == "ack" and int(srv.armory.ensure(p)["owned"].get("eq_01_weapon", 0)) == 1, "con los materiales se forja el Cañón Vanguardia")
	r = intent("armory_forge", {"equipment": "eq_13_weapon"})
	check(r.get("code", "") == "ARMORY_LEVEL", "un equipo de escalón 5 exige una Armería de nivel alto")
	var atk0: float = float(Eco.combat_mods(p, false)["attack"])
	r = intent("armory_equip", {"equipment": "eq_01_weapon"})
	var atk1: float = float(Eco.combat_mods(p, false)["attack"])
	check(r.get("type") == "ack" and absf(atk1 - atk0 - 0.02) < 0.0001, "equiparlo suma +2% de ataque")
	r = intent("armory_upgrade", {"equipment": "eq_01_weapon"})
	check(r.get("type") == "ack" and int(srv.armory.ensure(p)["owned"]["eq_01_weapon"]) == 2, "mejorarlo lo sube a nivel 2")
	check(float(Eco.combat_mods(p, false)["attack"]) > atk1, "el nivel aumenta su bono")
	for k: String in ["eq_01_armor", "eq_01_visor"]:
		var e2: Dictionary = Catalog.equipment_by_id[k]
		for m: String in e2["recipe"]:
			p["resources"][m] = int(p["resources"].get(m, 0)) + int(e2["recipe"][m]) * 5
		intent("armory_forge", {"equipment": k})
		intent("armory_equip", {"equipment": k})
	check(float(srv.armory.ensure(p).get("equipped", {}).size()) == 3.0, "tres piezas del conjunto Vanguardia equipadas")
	check(float(p.get("gear_mods", {}).get("attack", 0.0)) > 0.02 * 1.25 + 0.0001, "el bono de conjunto de 3 piezas suma ataque extra")
	r = intent("armory_unequip", {"slot": "weapon"})
	check(r.get("type") == "ack" and not srv.armory.ensure(p)["equipped"].has("weapon"), "se puede quitar una pieza")
	p["resources"]["mat_x_x01_1"] = 9
	r = intent("armory_refine", {"material": "mat_x_x01_1", "times": 2})
	check(r.get("type") == "ack" and int(p["resources"]["mat_x_x01_1"]) == 1 and int(p["resources"].get("mat_x_x01_2", 0)) >= 2, "refinar: 8 de calidad I dan 2 de calidad II")
	var v: Dictionary = srv.armory.view(p)
	check(v.has("owned") and v.has("equipped") and v.has("materials") and int(v["tier_max"]) >= 1, "la vista del cliente incluye equipo, materiales y escalón máximo")


# ---------------------------------------------------------------- fase 4

func _bot_of(tag: String) -> Dictionary:
	for q: Dictionary in srv.state["players"].values():
		if q.get("is_bot", false) and str(q.get("tag", "")) == tag and str(q.get("rank", "")) != "R5":
			return q
	return {}


func test_alliances() -> void:
	print(" -- Fase 4: Alianzas")
	var p: Dictionary = me()
	var all_lead: bool = true
	for tag: String in srv.social.alliances():
		if not srv.social.members(tag).is_empty() and not srv.social.members(tag).any(func(m: Dictionary) -> bool: return str(m.get("rank", "")) == "R5"):
			all_lead = false
	check(all_lead, "cada alianza tiene un líder R5")
	var r: Dictionary = intent("alliance_search", {"query": "vga"})
	check(r.get("type") == "ack" and (r.get("results", []) as Array).size() >= 1, "buscar alianzas por etiqueta o nombre")
	p["resources"]["credits"] = 100
	r = intent("alliance_create", {"tag": "TST", "name": "Escuadrón de Prueba", "mode": "request"})
	check(r.get("code", "") == "INSUFFICIENT_RESOURCES", "crear una alianza cuesta Créditos y Materia Oscura")
	p["resources"]["credits"] = 900000
	p["resources"]["dark_matter"] = 5000
	r = intent("alliance_create", {"tag": "VGA", "name": "Otra", "mode": "open"})
	check(r.get("code", "") == "TAG_TAKEN", "no se puede repetir una etiqueta")
	r = intent("alliance_create", {"tag": "TST", "name": "Escuadrón de Prueba", "mode": "request"})
	check(r.get("type") == "ack" and p["tag"] == "TST" and p["rank"] == "R5", "crear la alianza [TST]: quedas como líder R5")
	var bot: Dictionary = _bot_of("XEN")
	srv.alliance.join(bot, "TST")
	check(srv.alliance._a("TST")["requests"].has(bot["id"]), "en modo solicitud, unirse deja una solicitud pendiente")
	r = intent("alliance_accept", {"player": bot["id"]})
	check(r.get("type") == "ack" and bot["tag"] == "TST" and bot["rank"] == "R1", "el líder acepta la solicitud y entra como R1")
	r = intent("alliance_rank", {"player": bot["id"], "rank": "R3"})
	check(r.get("type") == "ack" and bot["rank"] == "R3", "el líder asciende a R3")
	r = intent("alliance_rank", {"player": bot["id"], "rank": "R5"})
	check(r.get("code", "") == "RANK_LIMIT", "no se puede asignar un rango igual o mayor al propio")
	check(not srv.alliance.can(bot, "kick") and srv.alliance.can(bot, "rally"), "permisos por rango: R3 abre Asedios pero no expulsa")
	r = intent("alliance_leave", {})
	check(r.get("code", "") == "LEADER_MUST_TRANSFER", "el líder debe transferir el liderazgo antes de salir")
	r = intent("treasury_donate", {"res": "credits", "amount": 5000})
	check(r.get("type") == "ack" and int(srv.alliance._a("TST")["treasury"]["credits"]) == 5000 and int(p["resources"].get("bonds", 0)) >= 500, "donar a la Tesorería da Bonos de Alianza")
	check(not srv.alliance.withdraw(bot, "credits", 100).get("ok", false), "un R3 no puede retirar de la Tesorería")
	r = intent("treasury_withdraw", {"res": "credits", "amount": 2000})
	check(r.get("type") == "ack" and (srv.alliance._a("TST")["treasury_log"] as Array).size() == 2, "el líder retira y queda en el registro de auditoría")
	p["resources"]["bonds"] = 1500
	r = intent("ally_shop_buy", {"item": "insignia"})
	check(r.get("type") == "ack" and int(p["items"].get("insignia", 0)) >= 1, "la Tienda de Alianza vende con Bonos")
	r = intent("alliance_kick", {"player": bot["id"]})
	check(r.get("type") == "ack" and bot["tag"] == "", "el líder expulsa a un miembro")
	srv.alliance.join(bot, "XEN")
	r = intent("alliance_leave", {})
	check(r.get("type") == "ack" and p["tag"] == "" and not srv.social.alliances().has("TST"), "al salir el último miembro la alianza se disuelve")
	r = intent("alliance_join", {"tag": "VGA"})
	check(p["tag"] == "VGA", "volver a unirse a [VGA] (el líder bot acepta la solicitud)")
	srv.state["next_bot_help_req"] = 0
	advance(1.0)
	var b0: int = int(p["resources"].get("bonds", 0))
	r = intent("help_all", {})
	check(r.get("type") == "ack" and int(p["resources"].get("bonds", 0)) > b0, "Ayuda Mutua: ayudar a los aliados da Bonos")


func test_rally_and_reinforcements() -> void:
	print(" -- Fase 4: Asedio y refuerzos")
	var p: Dictionary = me()
	p["rank"] = "R1"
	var enemy: Dictionary = {}
	var home: Vector2 = U.v2(srv.world.get_entity(p["base_id"])["pos"])
	var best: float = 1e9
	for q: Dictionary in srv.state["players"].values():
		if q.get("is_bot", false) and str(q.get("tag", "")) != "VGA" and str(q.get("system", "")) == str(p.get("system", "")):
			var e: Dictionary = srv.world.get_entity(q["base_id"])
			if not e.is_empty() and e["state"] == "ANCHORED" and U.v2(e["pos"]).distance_to(home) < best:
				best = U.v2(e["pos"]).distance_to(home)
				enemy = q
	enemy["protected_until"] = 0
	enemy["shield_until"] = 0
	p["troops"]["infantry_1"] = 400
	p["troops"]["pilots_1"] = 300
	var r: Dictionary = intent("rally_start", {"target_id": enemy["base_id"], "troops": {"infantry_1": 100}, "wait": 30})
	check(r.get("code", "") == "NO_PERMISSION", "un R1 no puede abrir un Asedio")
	p["rank"] = "R4"
	r = intent("rally_start", {"target_id": enemy["base_id"], "troops": {"infantry_1": 150, "pilots_1": 100}, "wait": 30})
	check(r.get("type") == "ack", "un R4 abre un Asedio contra %s" % srv.display_name(enemy["id"]))
	var rid: String = str(r.get("rally_id", ""))
	var ally: Dictionary = _bot_of("VGA")
	ally["troops"]["infantry_1"] = int(ally["troops"].get("infantry_1", 0)) + 200
	var jr: Dictionary = srv.rally.join(ally, rid, {"infantry_1": 120})
	check(bool(jr.get("ok", false)) and (srv.rally.rallies()[rid]["shares"] as Dictionary).size() >= 2, "un aliado se suma al Asedio con sus tropas")
	advance(5.0)
	var parts: int = (srv.rally.rallies()[rid]["shares"] as Dictionary).size()
	advance(30.0)
	var rr: Dictionary = srv.rally.rallies()[rid]
	var f: Dictionary = srv.fleets.fleets().get(str(rr.get("fleet_id", "")), {})
	check(rr["state"] == "marching" and not f.is_empty(), "al terminar la espera sale la flota conjunta (%d participantes)" % parts)
	var lead_atk: float = float(preload("res://server/sgm/economy.gd").combat_mods(p, false)["attack"])
	check(absf(float(f.get("mods", {}).get("attack", -1.0)) - lead_atk) < 0.0001, "la flota del Asedio usa los bonos del líder (herencia de boosts)")
	var inf_before: int = int(p["troops"].get("infantry_1", 0))
	var bonds_before: int = int(p["resources"].get("bonds", 0))
	for i: int in range(200):
		advance(1.0)
		if not srv.fleets.fleets().has(str(rr["fleet_id"])):
			break
	check(not srv.fleets.fleets().has(str(rr["fleet_id"])), "la flota del Asedio combate y vuelve")
	var rep: Array = srv.reports.list_for(p["id"]).filter(func(x: Dictionary) -> bool: return bool(x.get("rally", false)))
	check(not rep.is_empty() and (rep[0].get("participants", []) as Array).size() >= 2, "el informe del Asedio lista a los participantes (los humanos reciben copia)")
	check(int(p["troops"].get("infantry_1", 0)) > inf_before, "los supervivientes vuelven a cada participante (el líder recupera su parte)")
	check(int(p["resources"].get("bonds", 0)) > bonds_before, "participar en el Asedio da Bonos")
	var split: Dictionary = srv.rally.split_by_shares({"infantry_1": 100}, {"a": {"infantry_1": 30}, "b": {"infantry_1": 70}})
	check(int(split["a"]["infantry_1"]) == 30 and int(split["b"]["infantry_1"]) == 70, "bajas y botín se reparten según el aporte (30/70)")
	var host: Dictionary = _bot_of("VGA")
	var hb: Dictionary = srv.world.get_entity(host["base_id"])
	p["troops"]["infantry_1"] = 300
	r = intent("march", {"mission": "reinforce", "target_id": hb["id"], "troops": {"infantry_1": 80}})
	check(r.get("type") == "ack", "enviar refuerzos a la nave de un aliado")
	var rf: Dictionary = srv.fleets.fleets().get(str(r.get("fleet_id", "")), {})
	for i: int in range(600):
		advance(1.0)
		if rf.get("state", "") == "stationed":
			break
	check(rf.get("state", "") == "stationed" and srv.rally.stationed_total(host["id"]) >= 80, "los refuerzos quedan estacionados en la nave aliada")
	var ds: Dictionary = srv.rally.defense_stacks(host)
	check(ds.has(rf["id"]), "los refuerzos defienden junto a las tropas del aliado")
	r = intent("recall", {"fleet_id": rf["id"]})
	check(r.get("type") == "ack" and rf["state"] == "returning", "se pueden retirar los refuerzos")
	var v: Dictionary = srv.player_view(p).get("alliance_hq", {})
	check(v.has("rallies") and v.has("reinforcements_here") and v.has("treasury") and v.has("permissions"), "la vista del cliente incluye Asedios, refuerzos, Tesorería y permisos")


# ---------------------------------------------------------------- fase 5

func test_progression() -> void:
	print(" -- Fase 5: Progresión")
	const Eco = preload("res://server/sgm/economy.gd")
	var p: Dictionary = me()
	check(Catalog.room_max_level() == 25, "las salas llegan a nivel 25")
	var c10: int = int(Catalog.room_cost("bridge", 10).get("ore", 0))
	var c25: int = int(Catalog.room_cost("bridge", 25).get("ore", 0))
	check(c25 > c10 and c25 < c10 * 50, "el costo del Puente sigue creciendo hasta el 25 con curva suave (%d → %d)" % [c10, c25])
	check(int(Catalog.room_effect("bridge", "march_slots", 25)) <= 6, "las flotas simultáneas tienen tope (6)")
	check((Catalog.rooms_data.get("rooms", []) as Array).size() == 24 and (Catalog.rooms_data.get("locked", []) as Array).is_empty(), "24 salas construibles y ninguna de relleno")
	for rid: String in ["dock", "airlock", "cargo_bay", "trade_port", "containment", "cloak", "incubator", "foundry"]:
		check(not Catalog.room(rid).get("unlock", {}).is_empty(), "la sala %s se puede construir" % str(Catalog.room(rid)["name"]))
	var cap0: int = srv.rally.reinforce_capacity(p)
	p["rooms"]["dock"] = {"level": 3}
	check(srv.rally.reinforce_capacity(p) > cap0, "el Muelle de Atraque aumenta la capacidad de refuerzos")
	var vp0: int = Eco.vault_protect(p)
	p["rooms"]["cargo_bay"] = {"level": 3}
	check(Eco.vault_protect(p) > vp0, "la Bahía de Carga protege más recursos en la Bóveda")
	p["rooms"].erase("trade_port")
	var r: Dictionary = intent("trade_sell", {"res": "ore", "amount": 1000})
	check(r.get("code", "") == "ROOM_REQUIRED", "vender requiere el Puerto de Comercio")
	p["rooms"]["trade_port"] = {"level": 2}
	p["resources"]["ore"] = 5000
	var cr0: int = int(p["resources"].get("credits", 0))
	r = intent("trade_sell", {"res": "ore", "amount": 1000})
	check(r.get("type") == "ack" and int(p["resources"]["credits"]) > cr0, "el Puerto de Comercio vende elementos por Créditos")
	var tiers_ok: bool = true
	for k: String in Catalog.troops["types"]:
		if (Catalog.troops["types"][k]["tiers"] as Array).size() != 5:
			tiers_ok = false
	check(tiers_ok, "las 5 fuerzas tienen niveles N1 a N5")
	p["tech"] = {}
	r = intent("train", {"troop": "infantry_3", "qty": 1})
	check(r.get("code", "") == "TECH_REQUIRED", "entrenar N3 requiere el Protocolo de Fuerzas N3")
	check((Catalog.research.get("techs", []) as Array).size() == 30 and (Catalog.research.get("branches", []) as Array).size() == 5, "árbol de investigación de 5 ramas y 30 tecnologías")
	p["rooms"]["lab"] = {"level": 10}
	p["resources"]["credits"] = 900000
	for k2: String in ["ore", "kliptium", "water"]:
		p["resources"][k2] = 900000
	r = intent("research", {"tech": "nanomedicine"})
	check(r.get("code", "") == "TECH_REQUIRED", "Nanomedicina exige Blindaje Ablativo Nv 2 (prerrequisito)")
	p["tech"] = {"ablative_armor": 2}
	r = intent("research", {"tech": "nanomedicine"})
	check(r.get("type") == "ack", "con el prerrequisito se puede investigar")
	p["queues"].erase("research")
	var prod0: float = float(Eco.production_rates(p).get("ore", 0.0))
	p["tech"]["industrial_automation"] = 2
	check(float(Eco.production_rates(p).get("ore", 0.0)) > prod0, "Automatización Industrial aumenta la producción")
	var x: Dictionary = nearest("xenoform")
	p["troops"]["infantry_1"] = 200
	p["resources"]["energy"] = 100
	r = intent("march", {"mission": "hunt", "target_id": x["id"], "troops": {"infantry_1": 20}, "formation": "assault"})
	check(r.get("code", "") == "TECH_REQUIRED", "la formación Asalto se desbloquea investigando")
	r = intent("march", {"mission": "hunt", "target_id": x["id"], "troops": {"infantry_1": 20}, "formation": "hunter"})
	var f: Dictionary = srv.fleets.fleets().get(str(r.get("fleet_id", "")), {})
	var base_pve: float = float(Eco.combat_mods(p, false)["pve_damage"])
	check(r.get("type") == "ack" and f.get("formation", "") == "hunter" and absf(float(f["mods"]["pve_damage"]) - base_pve - 0.15) < 0.0001, "la formación Cacería suma +15%% de daño contra Xenoformas a la flota")


# ---------------------------------------------------------------- fase 6

func test_liveops() -> void:
	print(" -- Fase 6: LiveOps")
	const Eco = preload("res://server/sgm/economy.gd")
	var p: Dictionary = me()
	var lo: Dictionary = srv.liveops.ensure(p)
	var pts0: int = int(lo["pass"]["points"])
	srv.on_activity(p, "xeno_kill", 3.0)
	check(int(srv.liveops.ensure(p)["pass"]["points"]) > pts0, "cazar da puntos de Pase de Expedición")
	srv.liveops.ensure(p)["pass"]["points"] = 300 * 6
	check(srv.liveops.pass_level(p) == 6, "300 puntos por nivel: 1.800 puntos = nivel 6")
	var r: Dictionary = intent("pass_claim", {"level": 5, "track": "free"})
	check(r.get("type") == "ack", "reclamar el nivel 5 de la pista gratuita")
	r = intent("pass_claim", {"level": 5, "track": "free"})
	check(r.get("code", "") == "ALREADY", "no se puede reclamar dos veces")
	r = intent("pass_claim", {"level": 7, "track": "free"})
	check(r.get("code", "") == "LOCKED", "un nivel no alcanzado está bloqueado")
	r = intent("pass_claim", {"level": 3, "track": "premium"})
	check(r.get("code", "") == "NOT_PREMIUM", "la pista premium exige comprar el Pase")
	p["resources"]["dark_matter"] = 5000
	r = intent("pass_buy", {})
	check(r.get("type") == "ack" and bool(srv.liveops.ensure(p)["pass"]["premium"]), "comprar el Pase premium (compra simulada con MO)")
	r = intent("pass_claim", {"level": 3, "track": "premium"})
	check(r.get("type") == "ack", "el premium desbloquea retroactivamente los niveles ya alcanzados")
	var lvl0: int = srv.liveops.license_level(p)
	r = intent("license_daily", {})
	check(r.get("type") == "ack", "reclamar los puntos diarios de Licencia")
	r = intent("license_daily", {})
	check(r.get("code", "") == "ALREADY", "una vez por día")
	srv.liveops.add_license_points(p, 2500)
	check(srv.liveops.license_level(p) >= 6 and srv.liveops.has_auto_battle(p), "la Licencia sube de nivel (%d) y en el 6 activa la auto-batalla" % srv.liveops.license_level(p))
	check(float(p.get("vip_mods", {}).get("production", 0.0)) > 0.0 and Eco.extra(p, "production") >= float(p["vip_mods"]["production"]), "los beneficios de la Licencia entran a los modificadores")
	var period: int = int(Catalog.liveops["singularity"]["period_hours"]) * 3600000
	var now: int = U.now_ms()
	var to_start: int = period - (now % period) + 1000
	advance(float(to_start) / 1000.0)
	var ev: Dictionary = srv.liveops.singularity_now()
	check(bool(ev.get("active", false)), "se abre un Evento de Singularidad (%s)" % str(ev.get("def", {}).get("name", "")))
	for kind: String in ["xeno_kill", "resources", "pvp_win", "room_upgraded", "power_destroyed"]:
		srv.on_activity(p, kind, 50000.0 if kind == "resources" else 20.0)
	check(int(srv.liveops.ensure(p)["sing"]["points"]) >= 600, "las actividades suman puntos a la Singularidad activa")
	r = intent("sing_claim", {"index": 0})
	check(r.get("type") == "ack", "reclamar el primer hito de la Singularidad")
	check(srv.liveops.singularity_ranking(p).size() > 5, "la Singularidad tiene clasificación")
	var fe: Dictionary = srv.liveops.festival(str(p["tag"]))
	fe["progress"] = {}
	var fp0: int = srv.liveops.festival_points(fe)
	srv.on_activity(p, "xeno_kill", 1.0)
	advance(600.0)
	check(srv.liveops.festival_points(srv.liveops.festival(str(p["tag"]))) > fp0, "el Festival suma el aporte del jugador y de los aliados")
	srv.liveops.festival(str(p["tag"]))["progress"]["f_hunt"] = 999.0
	r = intent("fest_claim", {"index": 0})
	check(r.get("type") == "ack", "reclamar un hito colectivo del Festival de la Flota")
	var v: Dictionary = srv.liveops.view(p)
	check(v.has("pass") and v.has("license") and v.has("singularity") and v.has("festival"), "la vista del cliente incluye Pase, Licencia, Singularidad y Festival")
