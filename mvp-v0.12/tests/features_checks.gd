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
