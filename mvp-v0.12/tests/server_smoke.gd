extends Node
## Prueba de humo del servidor autoritativo: recorre el bucle completo del MVP
## (minar, cazar, espiar, atacar, entrenar, mejorar, investigar) avanzando el reloj.

const U = preload("res://shared/util.gd")
const GameServerScript = preload("res://server/game_server.gd")

var inbox: Array = []
var srv: Node
var sid: int
var failures: int = 0


func _ready() -> void:
	srv = GameServerScript.new()
	add_child(srv)
	var t0: int = Time.get_ticks_msec()
	srv.start({"persist": false, "fresh": true, "seed": 1234})
	print("world gen ms=", Time.get_ticks_msec() - t0, " entities=", srv.cur["entities"].size(), " players=", srv.state["players"].size())
	sid = srv.open_session(func(m: Dictionary) -> void: inbox.append(m))
	srv.handle_message(sid, {"type": "hello", "protocol": "galactum-mvp-1", "name": "Mateo", "avatar": "p05"})
	var p: Dictionary = srv.player(srv.sessions[sid]["player_id"])
	check(not p.is_empty(), "player created")
	check(_count("welcome") == 1, "welcome sent")
	check(_count("map_delta") >= 1, "map delta sent")
	var base: Dictionary = srv.world.get_entity(p["base_id"])
	var home: Vector2 = U.v2(base["pos"])
	print("base at ", home, " power=", srv.player_power(p))

	# Recolectar producción (avanza 2 min)
	_advance(120)
	var r: Dictionary = intent("collect", {})
	check(r.get("type") == "ack", "collect ok %s" % str(r.get("gained", r)))

	# Minería
	var asts: Array = srv.world.nearest_of_kind(home, "asteroid", 30.0, func(e: Dictionary) -> bool: return e["occupant"] == "")
	check(not asts.is_empty(), "asteroid near spawn")
	var before_res: int = int(p["resources"].get(asts[0]["element"], 0))
	r = intent("march", {"mission": "gather", "target_id": asts[0]["id"], "troops": {"infantry_1": 30, "shields_1": 10}})
	check(r.get("type") == "ack", "gather march %s" % str(r))
	for i: int in range(120):
		_advance(1)
	check(srv.fleets.owned_fleets(p["id"]).is_empty(), "gather fleet returned")
	var after_res: int = int(p["resources"].get(asts[0]["element"], 0))
	print("mined ", after_res - before_res, " of ", asts[0]["element"])
	check(after_res > before_res, "resources delivered")

	# Caza
	var xs: Array = srv.world.nearest_of_kind(home, "xenoform", 40.0, func(e: Dictionary) -> bool: return int(e["level"]) == 1)
	check(not xs.is_empty(), "xeno near spawn")
	var hunt_reports: Array = []
	# Un bot puede abatir la misma xenoforma justo antes de que llegue la flota
	# (entonces no hay informe de caza): se reintenta con otra, hasta 3 veces.
	for attempt: int in range(mini(3, xs.size())):
		r = intent("march", {"mission": "hunt", "target_id": xs[attempt]["id"], "troops": {"drones_1": 30, "pilots_1": 30, "infantry_1": 30}})
		if attempt == 0:
			check(r.get("type") == "ack", "hunt march %s" % str(r))
		for i: int in range(90):
			_advance(1)
		hunt_reports = srv.reports.list_for(p["id"]).filter(func(x: Dictionary) -> bool: return x["type"] == "hunt")
		if not hunt_reports.is_empty():
			break
	check(not hunt_reports.is_empty(), "hunt report")
	if not hunt_reports.is_empty():
		print("hunt: ", hunt_reports[0]["title"], " dmg=", hunt_reports[0]["xeno"]["damage"], " wounded=", hunt_reports[0]["attacker"]["wounded"])

	# Espionaje + ataque a un bot novato
	var enemy_bases: Array = srv.world.nearest_of_kind(home, "base", 60.0, func(e: Dictionary) -> bool:
		var o: Dictionary = srv.player(e["owner"])
		return e["owner"] != p["id"] and o.get("tag", "") != "VGA")
	check(not enemy_bases.is_empty(), "enemy near")
	var target: Dictionary = enemy_bases[0]
	var tp: Dictionary = srv.player(target["owner"])
	print("enemy ", srv.display_name(tp["id"]), " troops=", tp["troops"], " power=", srv.player_power(tp))
	r = intent("march", {"mission": "scout", "target_id": target["id"], "troops": {}})
	check(r.get("type") == "ack", "scout march")
	for i: int in range(40):
		_advance(1)
	var scout_reports: Array = srv.reports.list_for(p["id"]).filter(func(x: Dictionary) -> bool: return x["type"] == "scout")
	check(not scout_reports.is_empty(), "scout report")
	if not scout_reports.is_empty():
		print("scout precision=", scout_reports[0]["scout"]["precision"], " info keys=", scout_reports[0]["scout"].keys())
	r = intent("march", {"mission": "attack", "target_id": target["id"], "troops": {"infantry_1": 40, "drones_1": 20, "pilots_1": 20, "gunners_1": 20, "shields_1": 20}})
	check(r.get("type") == "ack", "attack march %s" % str(r))
	for i: int in range(120):
		_advance(1)
	var atk: Array = srv.reports.list_for(p["id"]).filter(func(x: Dictionary) -> bool: return x["type"] == "attack")
	check(not atk.is_empty(), "attack report")
	if not atk.is_empty():
		var a: Dictionary = atk[0]
		print("attack: ", a["title"], " rounds=", a["rounds"].size(), " loot=", a["loot"], " att losses=", a["attacker"]["losses"], " def losses=", a["defender"]["losses"])
	print("wounded=", p["wounded"], " cryo=", p["cryo"])

	# Entrenamiento / mejora / investigación / curación
	r = intent("train", {"troop": "infantry_1", "qty": 30})
	check(r.get("type") == "ack", "train %s" % str(r))
	r = intent("upgrade_room", {"room": "factory"})
	check(r.get("type") == "ack", "upgrade factory %s" % str(r))
	r = intent("research", {"tech": "kinetic_alloys"})
	check(r.get("type") == "ack", "research %s" % str(r))
	if not p["wounded"].is_empty():
		r = intent("heal", {})
		check(r.get("type") == "ack", "heal %s" % str(r))
	r = intent("help", {"queue": "build"})
	check(r.get("type") == "ack", "help %s" % str(r))
	for i: int in range(60):
		_advance(1)
	check(int(p["rooms"]["factory"]["level"]) == 2, "factory level 2")
	check(int(p["tech"].get("kinetic_alloys", 0)) == 1, "tech done")
	r = intent("claim_mission", {})
	print("claim mission: ", r.get("type"), " ", r.get("message", r.get("reward", "")))
	# Relocate
	r = intent("relocate", {"x": int(home.x) + 12, "y": int(home.y) + 6})
	print("relocate: ", r.get("type"), " ", r.get("message", ""))
	for i: int in range(20):
		_advance(1)
	print("base now ", srv.world.get_entity(p["base_id"])["pos"], " state ", srv.world.get_entity(p["base_id"])["state"])
	# Raid forced
	r = intent("debug_raid", {})
	print("raid: ", r.get("type"), " ", r.get("message",""), " incoming=", srv.fleets.incoming_for(p["id"], U.now_ms()).size())
	for i: int in range(150):
		_advance(1)
	var defs: Array = srv.reports.list_for(p["id"]).filter(func(x: Dictionary) -> bool: return x["type"] == "defense")
	print("defense reports=", defs.size(), (" -> " + defs[0]["title"]) if not defs.is_empty() else "")
	# Salto de Emergencia (aleatorio)
	for i: int in range(60):
		_advance(1)
	var before_pos: Vector2 = U.v2(srv.world.get_entity(p["base_id"])["pos"])
	r = intent("use_item", {"item": "escape_jump"})
	check(r.get("type") == "ack", "escape jump %s" % str(r.get("message", r.get("pos", ""))))
	check(U.v2(srv.world.get_entity(p["base_id"])["pos"]).distance_to(before_pos) >= 60.0, "escape jump moved far")
	# Galaxia multisistema + salto interestelar
	r = intent("galaxy", {})
	check(r.get("type") == "ack" and (r["galaxy"]["systems"] as Array).size() >= 10, "galaxy view")
	var from_sys: String = str(p["system"])
	var target_sys: String = ""
	for sv: Dictionary in r["galaxy"]["systems"]:
		if str(sv["blocked"]).is_empty() and not bool(sv["current"]):
			target_sys = sv["id"]
	var upcoming: Array = (r["galaxy"]["systems"] as Array).filter(func(x: Dictionary) -> bool: return x["status"] == "upcoming")
	check(not upcoming.is_empty() and not str(upcoming[0]["blocked"]).is_empty(), "upcoming system locked")
	var t3: int = Time.get_ticks_msec()
	inbox.clear()
	r = intent("use_item", {"item": "interstellar_jump", "system": target_sys})
	print("jump to ", target_sys, " ms=", Time.get_ticks_msec() - t3)
	check(r.get("type") == "ack", "interstellar jump %s" % str(r.get("message", "")))
	check(str(p["system"]) == target_sys and from_sys != target_sys, "player moved system")
	check(srv.galaxy.system(from_sys)["entities"].get(p["base_id"], {}).is_empty(), "base left old system")
	check(not srv.galaxy.system(target_sys)["entities"].get(p["base_id"], {}).is_empty(), "base in new system")
	for i: int in range(5):
		_advance(1)
	var vet: Dictionary = {"created_ts": 0}
	check(not srv.galaxy.can_enter(vet, srv.galaxy.system(srv.galaxy.newest_open(U.now_ms())), U.now_ms()).is_empty(), "veteran blocked from newest system")
	# Alianza: metas, cofre, objetivo marcado; torneos y métricas
	r = intent("guild", {})
	check(r.get("type") == "ack" and not (r["guild"] as Dictionary).is_empty(), "guild view")
	print("guild points=", r["guild"]["points"], " level=", r["guild"]["level"], " ranking=", (r["ranking"] as Array).size())
	var enemy: Array = srv.world.nearest_of_kind(U.v2(srv.world.get_entity(p["base_id"])["pos"]), "base", 200.0, func(e: Dictionary) -> bool: return str(srv.player(e["owner"]).get("tag", "")) != "VGA")
	r = intent("mark_target", {"target_id": enemy[0]["id"]})
	check(r.get("type") == "ack", "mark target %s" % str(r.get("message", "")))
	for i: int in range(240):
		_advance(1)
	var gv: Dictionary = srv.guild.view(p)
	print("target hits=", gv["target"].get("hits", 0), " hitters=", gv["target"].get("hitters", []), " AP=", gv["points"], " goals=", gv["goals"].map(func(x: Dictionary) -> String: return "%s:%d" % [x["id"], int(x["progress"])]))
	check(int(gv["target"].get("hits", 0)) > 0, "allies hit marked target")
	r = intent("events", {})
	check(r.get("type") == "ack", "events view")
	print("tournament=", r["events"]["tournament"]["name"], " participants=", r["events"]["tournament"]["participants"], " burned=", r["events"]["tournament"]["burned_usd"], " resource=", r["events"]["resource"]["name"])
	r = intent("debug_finish_event", {"which": "tournament"})
	var hist: Array = srv.events.data()["history"]
	check(not hist.is_empty(), "tournament finished with history")
	if not hist.is_empty():
		print("history: ", hist[0]["name"], " pool=", hist[0]["pool_usd"], " burned=", snappedf(hist[0]["burned_usd"], 0.01), " ratio=", snappedf(hist[0]["ratio"], 0.01), " advice=", hist[0]["advice"], " winners=", hist[0]["winners"])
	# Fase 2: construir la Cantina y el Taller; tripulación y canje
	check(not p["rooms"].has("cantina"), "phase 2 room not built at start")
	p["resources"]["dark_matter"] = 5000
	r = intent("upgrade_room", {"room": "cantina"})
	check(r.get("type") == "ack", "build cantina %s" % str(r.get("message", "")))
	for i: int in range(60):
		_advance(1)
	check(int(p["rooms"].get("cantina", {}).get("level", 0)) == 1, "cantina built")
	r = intent("recruit", {"method": "free"})
	check(r.get("type") == "ack", "free recruit %s" % str(r.get("results", r.get("message", ""))))
	r = intent("recruit", {"method": "mo", "count": 10})
	check(r.get("type") == "ack" and (r["results"] as Array).size() == 10, "recruit x10")
	print("recruit x10: ", (r["results"] as Array).map(func(x: Dictionary) -> String: return "%s:%s%s" % [x["id"], x["rarity"].substr(0, 1), "*" if x["new"] else ""]))
	var before_mods: Dictionary = srv.Eco.modifiers(p) if false else {}
	var newc: String = str(r["results"][0]["id"])
	r = intent("crew_assign", {"crew_id": p["crew"]["active"][0], "on": false})
	r = intent("crew_assign", {"crew_id": newc, "on": true})
	check(r.get("type") == "ack" and (p["crew"]["active"] as Array).has(newc), "crew assign")
	print("crew_mods=", p["crew_mods"])
	r = intent("upgrade_room", {"room": "workshop"})
	check(r.get("type") == "ack", "build workshop %s" % str(r.get("message", "")))
	for i: int in range(60):
		_advance(1)
	var cu_before: int = int(p["resources"].get("copper", 0))
	r = intent("exchange", {"from": "ore", "to": "copper", "amount": 50})
	check(r.get("type") == "ack" and int(p["resources"]["copper"]) == cu_before + 50, "workshop exchange rate=%s" % str(r.get("rate", r.get("message", ""))))
	var pv: Dictionary = srv.player_view(p)
	var json_len: int = JSON.stringify(pv).length()
	print("player_view bytes=", json_len, " msgs total=", inbox.size())
	# Save/load roundtrip
	srv.persist = true
	srv.save_path = "user://smoke_save.json"
	var t1: int = Time.get_ticks_msec()
	srv.save()
	print("save ms=", Time.get_ticks_msec() - t1, " size=", FileAccess.get_file_as_string("user://smoke_save.json").length())
	var t2: int = Time.get_ticks_msec()
	check(srv._load(), "load ok")
	print("load ms=", Time.get_ticks_msec() - t2)
	for i: int in range(5):
		_advance(1)
	print("after load tick ok; fleets=", srv.cur["fleets"].size())
	print("FAILURES=", failures)
	get_tree().quit(1 if failures > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func _count(t: String) -> int:
	return inbox.filter(func(m: Dictionary) -> bool: return m.get("type") == t).size()


func _advance(seconds: float) -> void:
	U.debug_offset_ms += int(seconds * 1000.0)
	srv._tick()


func intent(action: String, params: Dictionary) -> Dictionary:
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
