extends RefCounted
## Galaxia multisistema (SGM). Cada Sistema Solar es un "servidor" SSS
## independiente con su propio mapa, flotas, bots y respawns; el SGM conserva lo
## global: comandantes, alianzas (que se extienden entre sistemas), informes.
##
## Modelo de lanzamiento (feedback de revisión):
##  - Se parte con `launch_systems` sistemas y se abre uno nuevo cada mes.
##  - Los comandantes nuevos nacen en el sistema más nuevo.
##  - Un veterano (cuenta anterior a la apertura) no puede entrar a un sistema
##    nuevo hasta que pase la ventana `veteran_lock_days` (6-8 meses): así los
##    jugadores que pagan mucho no aplastan a los recién llegados.
##  - Al saltar de sistema se conserva la alianza hasta unirse a otra.
## Los sistemas se generan de forma perezosa (la primera vez que alguien entra).

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const DAY_MS: int = 86400000

const PLANET_NAMES: Array = ["Kepler Magna", "Tauro-9", "Nébula Ix", "Hades Prime", "Vesta Rho", "Gliese Azul", "Proxima Ámbar", "Orcus", "Ceres Nova", "Tritón Gris", "Sedna", "Anubis-4", "Eris Velo", "Bóreas", "Talos", "Kuiper Rex"]

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.cfg("galaxy", {})


func data() -> Dictionary:
	return srv.state["galaxy"]


func systems() -> Dictionary:
	return data()["systems"]


func order() -> Array:
	return data()["order"]


func system(id: String) -> Dictionary:
	return systems().get(id, {})


## Crea los metadatos de la galaxia (sin generar los mapas).
func create(seed: int, created_ts: int) -> void:
	var c: Dictionary = cfg()
	var names: Array = c.get("names", [U.t("Helios")])
	var launch_n: int = int(c.get("launch_systems", 10))
	var months: int = int(c.get("months_since_launch", 5))
	var upcoming: int = int(c.get("upcoming", 1))
	var interval: int = int(c.get("new_system_days", 30)) * DAY_MS
	var newest_age: int = int(c.get("newest_age_days", 3)) * DAY_MS
	var launch_ts: int = created_ts - months * interval - newest_age
	var sys: Dictionary = {}
	var ord: Array = []
	for i: int in range(launch_n + months + upcoming):
		var idx: int = i + 1
		var opened: int = launch_ts if i < launch_n else launch_ts + (i - launch_n + 1) * interval
		var id: String = "s%02d" % idx
		var hue: float = fmod(0.61 + idx * 0.137, 1.0)
		sys[id] = {
			"id": id, "index": idx, "name": str(names[i % names.size()]),
			"seed": (seed + idx * 7919) & 0x7fffffff, "opened_ts": opened, "hue": hue,
			"generated": false, "entities": {}, "fleets": {}, "terrain": [], "respawns": [],
		}
		ord.append(id)
	srv.state["galaxy"] = {"systems": sys, "order": ord, "launch_ts": launch_ts}


func is_open(s: Dictionary, now: int) -> bool:
	return int(s.get("opened_ts", 0)) <= now


func age_days(s: Dictionary, now: int) -> int:
	return int(floor(float(now - int(s["opened_ts"])) / DAY_MS))


func newest_open(now: int) -> String:
	var best: String = ""
	var best_ts: int = -1
	for id: String in order():
		var s: Dictionary = system(id)
		if is_open(s, now) and int(s["opened_ts"]) > best_ts:
			best_ts = int(s["opened_ts"])
			best = id
	return best


## Bono de fuerza de los bots según la antigüedad del sistema (los sistemas
## viejos están llenos de veteranos poderosos).
func veteran_bonus(s: Dictionary, now: int) -> float:
	return clampf(float(age_days(s, now)) / 180.0 * 0.45, 0.0, 0.45)


func threat(s: Dictionary, now: int) -> int:
	return clampi(1 + int(round(float(age_days(s, now)) / 40.0)), 1, 5)


## "" si el comandante puede entrar; si no, el motivo.
func can_enter(p: Dictionary, s: Dictionary, now: int) -> String:
	if s.is_empty():
		return U.t("Sistema desconocido")
	if not is_open(s, now):
		return U.t("Se abre en %d días") % maxi(1, int(ceil(float(int(s["opened_ts"]) - now) / DAY_MS)))
	var lock_ms: int = int(cfg().get("veteran_lock_days", 180)) * DAY_MS
	var opened: int = int(s["opened_ts"])
	if now - opened < lock_ms and int(p.get("created_ts", now)) < opened:
		return U.t("Sistema protegido para comandantes nuevos: los veteranos podrán entrar en %d días") % int(ceil(float(opened + lock_ms - now) / DAY_MS))
	return ""


## Activa (y genera si hace falta) un sistema como contexto del servidor.
func ensure_generated(id: String) -> void:
	srv.use_system(id)
	var s: Dictionary = system(id)
	if bool(s.get("generated", false)):
		return
	srv.world.generate(int(s["seed"]))
	var r := RandomNumberGenerator.new()
	r.seed = int(s["seed"]) + 7
	srv.bots.create_bots(int(Catalog.cfg("bot_count", 60)), r, veteran_bonus(s, U.now_ms()))
	s["generated"] = true
	srv.refresh_alliances()
	srv.log_line("SYSTEM_GENERATED %s (%s) entities=%d" % [id, s["name"], s["entities"].size()])


func planet_names(seed: int) -> Array:
	var pool: Array = PLANET_NAMES.duplicate()
	var r := RandomNumberGenerator.new()
	r.seed = seed
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = r.randi() % (i + 1)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, 4)


## Sistemas con comandantes humanos: son los que se simulan en cada tick.
func active_systems() -> Array:
	var out: Array = []
	for p: Dictionary in srv.state["players"].values():
		if p.get("is_bot", false):
			continue
		var sid: String = str(p.get("system", ""))
		if not sid.is_empty() and not out.has(sid):
			out.append(sid)
	return out


func humans_in(id: String) -> int:
	var n: int = 0
	for p: Dictionary in srv.state["players"].values():
		if not p.get("is_bot", false) and str(p.get("system", "")) == id:
			n += 1
	return n


func info(s: Dictionary) -> Dictionary:
	return {"id": s["id"], "index": int(s["index"]), "name": U.t(str(s["name"])), "hue": float(s.get("hue", 0.6))}


## Vista de la galaxia para el panel del cliente.
func view(p: Dictionary) -> Dictionary:
	var now: int = U.now_ms()
	var list: Array = []
	var newest: String = newest_open(now)
	var lock_days: int = int(cfg().get("veteran_lock_days", 180))
	for id: String in order():
		var s: Dictionary = system(id)
		var status: String = "open"
		if not is_open(s, now):
			status = "upcoming"
		elif id == newest:
			status = "newest"
		elif age_days(s, now) < lock_days:
			status = "protected"
		var bots_n: int = int(Catalog.cfg("bot_count", 60))
		if bool(s.get("generated", false)):
			bots_n = 0
			for q: Dictionary in srv.state["players"].values():
				if q.get("is_bot", false) and str(q.get("system", "")) == id:
					bots_n += 1
		list.append({
			"id": id, "index": int(s["index"]), "name": U.t(str(s["name"])), "hue": float(s.get("hue", 0.6)),
			"opened_ts": int(s["opened_ts"]), "age_days": age_days(s, now), "status": status,
			"threat": threat(s, now), "commanders": bots_n + humans_in(id),
			"current": id == str(p.get("system", "")),
			"blocked": can_enter(p, s, now),
		})
	var base: Dictionary = srv.world.get_entity(str(p.get("base_id", "")))
	var near_portal: bool = false
	if not base.is_empty():
		near_portal = U.v2(base["pos"]).distance_to(srv.world.center) <= float(Catalog.cfg("portal_radius", 14)) + float(cfg().get("portal_jump_range", 40))
	return {
		"systems": list, "current": str(p.get("system", "")), "newest": newest,
		"veteran_lock_days": lock_days, "new_system_days": int(cfg().get("new_system_days", 30)),
		"near_portal": near_portal, "portal_plasma": int(cfg().get("portal_jump_plasma", 80)),
		"portal_range": int(cfg().get("portal_jump_range", 40)),
	}


## Salto interestelar: la Astronave abandona su sistema y aparece en otro.
## `method`: "portal" (cerca del Portal de Salto, cuesta Plasma) o "item"
## (Motor de Salto Interestelar, desde cualquier punto).
func jump(p: Dictionary, target_id: String, method: String) -> Dictionary:
	var now: int = U.now_ms()
	var from_id: String = str(p.get("system", ""))
	if target_id == from_id:
		return _err("SAME_SYSTEM", U.t("Ya estás en ese sistema"))
	var target: Dictionary = system(target_id)
	var why: String = can_enter(p, target, now)
	if not why.is_empty():
		return _err("SYSTEM_LOCKED", why)
	srv.use_system(from_id)
	var base: Dictionary = srv.world.get_entity(str(p["base_id"]))
	if base.is_empty() or base["state"] != "ANCHORED":
		return _err("SHIP_NOT_ANCHORED", U.t("La Astronave debe estar anclada"))
	if not srv.fleets.owned_fleets(p["id"]).is_empty():
		return _err("FLEETS_OUT", U.t("Todas tus flotas deben estar en la nave para saltar"))
	var portal_r: float = float(Catalog.cfg("portal_radius", 14)) + float(cfg().get("portal_jump_range", 40))
	match method:
		"portal":
			if U.v2(base["pos"]).distance_to(srv.world.center) > portal_r:
				return _err("FAR_FROM_PORTAL", U.t("Acerca la Astronave al Portal de Salto (a %d casillas o menos)") % int(cfg().get("portal_jump_range", 40)))
			var cost: int = int(cfg().get("portal_jump_plasma", 80))
			if not Eco.apply(p, {"plasma": -cost}, "interstellar_jump"):
				return _err("INSUFFICIENT_RESOURCES", U.t("Plasma de Fusión insuficiente (%d)") % cost)
		"item":
			if not Eco.apply(p, {"interstellar_jump": -1}, "interstellar_jump"):
				return _err("NO_ITEM", U.t("No tienes Motor de Salto Interestelar"))
		_:
			return _err("INVALID_METHOD", U.t("Método de salto desconocido"))
	srv.settle_player(p)
	srv.world.remove_entity(base["id"])
	ensure_generated(target_id)
	var r := RandomNumberGenerator.new()
	r.randomize()
	var spawn: Vector2i = spawn_point(r)
	base["pos"] = [spawn.x, spawn.y]
	base["state"] = "ANCHORED"
	base.erase("travel")
	srv.world.add_entity(base)
	p["system"] = target_id
	p["protected_until"] = maxi(int(p.get("protected_until", 0)), now + int(cfg().get("arrival_protection_sec", 300)) * 1000)
	p["jumps"] = int(p.get("jumps", 0)) + 1
	p["next_raid"] = now + 240000
	var tag: String = str(p.get("tag", ""))
	if not tag.is_empty():
		srv.social.post(tag, U.t("Sistema"), U.t("%s saltó del sistema %s a %s. Sigue siendo parte de la Alianza.") % [p["name"], U.t(str(system(from_id).get("name", "?"))), U.t(str(target["name"]))], "system")
	srv.missions.on_event(p, "interstellar_jump", 1)
	srv.on_player_jumped(p)
	return {"ok": true, "system": info(target)}


func spawn_point(r: RandomNumberGenerator) -> Vector2i:
	for _i: int in range(200):
		var ang: float = r.randf() * TAU
		var d: float = r.randf_range(185.0, 240.0)
		var cand: Vector2 = (srv.world.center + Vector2(cos(ang), sin(ang)) * d).round()
		if srv.world.is_free(cand, 7.0):
			return Vector2i(cand)
	return srv.world.find_free_near(srv.world.center, 150.0, 280.0, r, 5.0)


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
