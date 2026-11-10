extends RefCounted
## LiveOps (feedback del 26/10: "no hay Pase de Expedición, ni Licencia de
## Comandante; solo hay un evento y faltan los Eventos de Singularidad y el
## Festival de la Flota").
##
## - Pase de Expedición: temporada de 30 días y 50 niveles con pista gratuita y
##   premium. Los puntos salen de las actividades (cazar, minar, construir,
##   investigar, entrenar, PvP, gastar MO). La compra premium desbloquea
##   retroactivamente los niveles ya alcanzados (se reclaman uno a uno).
## - Licencia de Comandante: 15 niveles (VIP) por puntos de compra/gasto de MO y
##   un bono diario; sus beneficios entran como `vip_mods`. Nivel 6: auto-batalla
##   en Expediciones.
## - Eventos de Singularidad: ventanas periódicas con su propia tabla de puntos,
##   hitos con premio y clasificación.
## - Festival de la Flota: evento cooperativo semanal de la alianza con misiones
##   colectivas e hitos que premian a cada miembro.
## Todas las compras con dinero son simuladas (no hay pasarela de pago real).

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const DAY_MS: int = 86400000
const HOUR_MS: int = 3600000

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.liveops


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func ensure(p: Dictionary) -> Dictionary:
	if not p.has("liveops"):
		p["liveops"] = {"pass": {"season": -1, "points": 0, "premium": false, "free_claimed": [], "prem_claimed": []},
			"license": {"points": 0, "daily_day": -1}, "sing": {"id": "", "points": 0, "claimed": []}}
	return p["liveops"]


# ---------------------------------------------------------------- puntos de actividad

## Convierte una actividad en puntos según una tabla de puntuación.
static func score(table: Dictionary, kind: String, amount: float) -> int:
	match kind:
		"xeno_kill":
			return int(float(table.get("xeno_kill_per_level", 0)) * amount)
		"resources":
			return int(float(table.get("resources_per_1000", 0)) * amount / 1000.0)
		"pvp_win":
			return int(float(table.get("pvp_win", 0)) * amount)
		"mo_spent":
			return int(float(table.get("mo_spent_per_10", 0)) * amount / 10.0)
		"room_upgraded":
			return int(float(table.get("room_upgraded", 0)) * amount)
		"research_done":
			return int(float(table.get("research_done", 0)) * amount)
		"troops_trained":
			return int(float(table.get("troops_trained_per_10", 0)) * amount / 10.0)
		"power_destroyed":
			return int(float(table.get("power_destroyed_per_100", 0)) * amount / 100.0)
		"expedition_win":
			return int(float(table.get("expedition_win", 0)) * amount)
	return 0


func on_activity(p: Dictionary, kind: String, amount: float) -> void:
	if p.get("is_bot", false):
		return
	var lo: Dictionary = ensure(p)
	_season_roll(p)
	lo["pass"]["points"] = int(lo["pass"]["points"]) + score(cfg().get("points", {}), kind, amount)
	if kind == "mo_spent":
		add_license_points(p, int(amount * float(cfg().get("license", {}).get("points_per_mo", 1))))
	var ev: Dictionary = singularity_now()
	if not ev.is_empty():
		var s: Dictionary = lo["sing"]
		if str(s["id"]) != str(ev["instance"]):
			lo["sing"] = {"id": ev["instance"], "points": 0, "claimed": []}
			s = lo["sing"]
		s["points"] = int(s["points"]) + score(ev["def"].get("scoring", {}), kind, amount)
	_festival_add(p, kind, amount)
	srv.mark_player_dirty(p["id"])


# ---------------------------------------------------------------- Pase de Expedición

func season_index(now: int) -> int:
	return int(now / (int(cfg().get("pass", {}).get("season_days", 30)) * DAY_MS))


func _season_roll(p: Dictionary) -> void:
	var ps: Dictionary = ensure(p)["pass"]
	var s: int = season_index(U.now_ms())
	if int(ps["season"]) != s:
		ensure(p)["pass"] = {"season": s, "points": 0, "premium": false, "free_claimed": [], "prem_claimed": []}


func pass_level(p: Dictionary) -> int:
	var pc: Dictionary = cfg().get("pass", {})
	return mini(int(pc.get("levels", 50)), int(int(ensure(p)["pass"]["points"]) / int(pc.get("points_per_level", 300))))


func buy_pass(p: Dictionary) -> Dictionary:
	_season_roll(p)
	var ps: Dictionary = ensure(p)["pass"]
	if bool(ps["premium"]):
		return _err("ALREADY", U.t("Ya tienes el Pase premium de esta temporada"))
	var cost: int = int(cfg().get("pass", {}).get("premium_mo", 1000))
	if not Eco.apply(p, {"dark_matter": -cost}, "pass_premium", "pass:%d" % int(ps["season"])):
		return _err("INSUFFICIENT_RESOURCES", U.t("Materia Oscura insuficiente (%d). Compra Materia Oscura en la Tienda (simulado).") % cost)
	ps["premium"] = true
	srv.on_activity(p, "mo_spent", float(cost))
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


func claim_pass(p: Dictionary, level: int, track: String) -> Dictionary:
	_season_roll(p)
	var ps: Dictionary = ensure(p)["pass"]
	if level < 1 or level > pass_level(p):
		return _err("LOCKED", U.t("Aún no alcanzas ese nivel del Pase"))
	if track == "premium" and not bool(ps["premium"]):
		return _err("NOT_PREMIUM", U.t("Esa recompensa es de la pista premium"))
	var key: String = "prem_claimed" if track == "premium" else "free_claimed"
	if (ps[key] as Array).has(level):
		return _err("ALREADY", U.t("Ya reclamaste esa recompensa"))
	var list: Array = cfg().get("pass", {}).get("premium" if track == "premium" else "free", [])
	var reward: Dictionary = list[level - 1].get("reward", {})
	srv.progression.grant(p, reward, "pass:%s:%d" % [track, level], "pass:%d:%s:%d" % [int(ps["season"]), track, level])
	(ps[key] as Array).append(level)
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "reward": reward}


# ---------------------------------------------------------------- Licencia de Comandante

func license_level(p: Dictionary) -> int:
	var pts: int = int(ensure(p)["license"]["points"])
	var table: Array = cfg().get("license", {}).get("points", [0])
	var lvl: int = 0
	for i: int in range(table.size()):
		if pts >= int(table[i]):
			lvl = i + 1
	return lvl


func add_license_points(p: Dictionary, n: int) -> void:
	if n <= 0:
		return
	var before: int = license_level(p)
	ensure(p)["license"]["points"] = int(ensure(p)["license"]["points"]) + n
	refresh_mods(p)
	if license_level(p) > before:
		srv.notify(p["id"], U.t("¡Licencia de Comandante nivel %d! Nuevos beneficios activos.") % license_level(p), "success")


func claim_license_daily(p: Dictionary) -> Dictionary:
	var lic: Dictionary = ensure(p)["license"]
	var day: int = int(U.now_ms() / DAY_MS)
	if int(lic.get("daily_day", -1)) == day:
		return _err("ALREADY", U.t("Ya reclamaste los puntos de Licencia de hoy"))
	lic["daily_day"] = day
	add_license_points(p, int(cfg().get("license", {}).get("daily_points", 60)))
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


func refresh_mods(p: Dictionary) -> void:
	var perks: Array = cfg().get("license", {}).get("perks", [{}])
	var lvl: int = clampi(license_level(p), 0, perks.size() - 1)
	p["vip_mods"] = (perks[lvl] as Dictionary).duplicate()


func has_auto_battle(p: Dictionary) -> bool:
	return license_level(p) >= int(cfg().get("license", {}).get("auto_battle_level", 6))


# ---------------------------------------------------------------- Eventos de Singularidad

## Evento de Singularidad activo ahora (o {} si no hay ninguno).
func singularity_now(now: int = -1) -> Dictionary:
	if now < 0:
		now = U.now_ms()
	var sc: Dictionary = cfg().get("singularity", {})
	var period: int = int(sc.get("period_hours", 8)) * HOUR_MS
	var dur: int = int(sc.get("duration_hours", 3)) * HOUR_MS
	var idx: int = int(now / period)
	var start: int = idx * period
	var events: Array = sc.get("events", [])
	if events.is_empty():
		return {}
	var def: Dictionary = events[idx % events.size()]
	if now - start >= dur:
		return {"active": false, "next_start": start + period, "next": events[(idx + 1) % events.size()]}
	return {"active": true, "instance": "%s:%d" % [def["id"], idx], "def": def, "start": start, "end": start + dur}


func claim_singularity(p: Dictionary, idx: int) -> Dictionary:
	var ev: Dictionary = singularity_now()
	if not bool(ev.get("active", false)):
		return _err("NO_EVENT", U.t("No hay un Evento de Singularidad activo"))
	var s: Dictionary = ensure(p)["sing"]
	if str(s["id"]) != str(ev["instance"]):
		return _err("NO_POINTS", U.t("Aún no tienes puntos en este evento"))
	var ms: Array = ev["def"].get("milestones", [])
	if idx < 0 or idx >= ms.size() or int(s["points"]) < int(ms[idx]["points"]):
		return _err("LOCKED", U.t("Aún no alcanzas ese hito"))
	if (s["claimed"] as Array).has(idx):
		return _err("ALREADY", U.t("Ya reclamaste ese hito"))
	srv.progression.grant(p, ms[idx]["reward"], "singularity", "sing:%s:%d" % [ev["instance"], idx])
	(s["claimed"] as Array).append(idx)
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "reward": ms[idx]["reward"]}


## Clasificación: el jugador y comandantes rivales simulados.
func singularity_ranking(p: Dictionary) -> Array:
	var ev: Dictionary = singularity_now()
	if not bool(ev.get("active", false)):
		return []
	var out: Array = [{"name": srv.display_name(p["id"]), "points": int(ensure(p)["sing"].get("points", 0)) if str(ensure(p)["sing"]["id"]) == str(ev["instance"]) else 0, "me": true}]
	var elapsed: float = float(U.now_ms() - int(ev["start"])) / float(int(ev["end"]) - int(ev["start"]))
	var n: int = 0
	for q: Dictionary in srv.state["players"].values():
		if not q.get("is_bot", false):
			continue
		n += 1
		if n > 14:
			break
		var base: int = 600 + U.hash_seed(str(q["id"]) + str(ev["instance"])) % 4200
		out.append({"name": srv.display_name(q["id"]), "points": int(base * elapsed), "me": false})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["points"]) > int(b["points"]))
	return out


# ---------------------------------------------------------------- Festival de la Flota

func festival_cycle(now: int = -1) -> int:
	if now < 0:
		now = U.now_ms()
	return int(now / (int(cfg().get("festival", {}).get("cycle_days", 7)) * DAY_MS))


func festival(tag: String) -> Dictionary:
	var a: Dictionary = srv.social.alliances().get(tag, {})
	if a.is_empty():
		return {}
	var cyc: int = festival_cycle()
	if int(a.get("festival", {}).get("cycle", -1)) != cyc:
		a["festival"] = {"cycle": cyc, "progress": {}, "contrib": {}, "claimed": {}, "bot_ts": U.now_ms()}
	return a["festival"]


func _festival_add(p: Dictionary, kind: String, amount: float) -> void:
	var tag: String = str(p.get("tag", ""))
	if tag.is_empty():
		return
	var fe: Dictionary = festival(tag)
	var key: String = "resources_k" if kind == "resources" else kind
	var add: float = amount / 1000.0 if kind == "resources" else (1.0 if kind == "xeno_kill" else amount)
	for m: Dictionary in cfg().get("festival", {}).get("missions", []):
		if str(m["kind"]) == key:
			fe["progress"][m["id"]] = float(fe["progress"].get(m["id"], 0.0)) + add
			fe["contrib"][p["id"]] = float(fe["contrib"].get(p["id"], 0.0)) + add


func festival_points(fe: Dictionary) -> int:
	var pts: int = 0
	for m: Dictionary in cfg().get("festival", {}).get("missions", []):
		var frac: float = clampf(float(fe["progress"].get(m["id"], 0.0)) / float(m["target"]), 0.0, 1.0)
		pts += int(float(m["points"]) * frac)
	return pts


func claim_festival(p: Dictionary, idx: int) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	if tag.is_empty():
		return _err("NO_ALLIANCE", U.t("El Festival de la Flota es de tu Alianza: únete a una"))
	var fe: Dictionary = festival(tag)
	var ms: Array = cfg().get("festival", {}).get("milestones", [])
	if idx < 0 or idx >= ms.size() or festival_points(fe) < int(ms[idx]["points"]):
		return _err("LOCKED", U.t("La alianza aún no alcanza ese hito"))
	var claimed: Array = fe["claimed"].get(p["id"], [])
	if claimed.has(idx):
		return _err("ALREADY", U.t("Ya reclamaste ese hito"))
	srv.progression.grant(p, ms[idx]["reward"], "festival", "fest:%s:%d:%d" % [tag, int(fe["cycle"]), idx])
	claimed.append(idx)
	fe["claimed"][p["id"]] = claimed
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "reward": ms[idx]["reward"]}


func tick(now: int) -> void:
	# Los compañeros bot aportan al Festival de su alianza con el tiempo.
	var rate: float = float(cfg().get("festival", {}).get("bot_rate_per_hour", 45))
	for tag: String in srv.social.alliances():
		var bots: Array = srv.social.members(tag).filter(func(m: Dictionary) -> bool: return m.get("is_bot", false))
		if bots.is_empty():
			continue
		var fe: Dictionary = festival(tag)
		var dt_h: float = float(now - int(fe.get("bot_ts", now))) / float(HOUR_MS)
		if dt_h < 0.02:
			continue
		fe["bot_ts"] = now
		var missions: Array = cfg().get("festival", {}).get("missions", [])
		for m: Dictionary in missions:
			var gain: float = rate * dt_h * float(bots.size()) / 20.0 * float(m["target"]) / 120.0
			fe["progress"][m["id"]] = float(fe["progress"].get(m["id"], 0.0)) + gain


# ---------------------------------------------------------------- vista

func view(p: Dictionary) -> Dictionary:
	_season_roll(p)
	var lo: Dictionary = ensure(p)
	var pc: Dictionary = cfg().get("pass", {})
	var now: int = U.now_ms()
	var season_end: int = (season_index(now) + 1) * int(pc.get("season_days", 30)) * DAY_MS
	var ev: Dictionary = singularity_now(now)
	var sing: Dictionary = {"active": bool(ev.get("active", false))}
	if sing["active"]:
		sing.merge({"name": U.t(str(ev["def"]["name"])), "desc": U.t(str(ev["def"].get("desc", ""))), "end": ev["end"], "milestones": ev["def"].get("milestones", []),
			"points": int(lo["sing"]["points"]) if str(lo["sing"]["id"]) == str(ev["instance"]) else 0,
			"claimed": lo["sing"]["claimed"] if str(lo["sing"]["id"]) == str(ev["instance"]) else [], "ranking": singularity_ranking(p).slice(0, 10)})
	else:
		sing.merge({"next_start": ev.get("next_start", 0), "next_name": U.t(str(ev.get("next", {}).get("name", "")))})
	var fest: Dictionary = {}
	var tag: String = str(p.get("tag", ""))
	if not tag.is_empty():
		var fe: Dictionary = festival(tag)
		var ms: Array = []
		for m: Dictionary in cfg().get("festival", {}).get("missions", []):
			ms.append({"id": m["id"], "name": U.t(str(m["name"])), "desc": U.t(str(m["desc"])), "target": m["target"], "progress": float(fe["progress"].get(m["id"], 0.0)), "points": m["points"]})
		fest = {"points": festival_points(fe), "missions": ms, "milestones": cfg().get("festival", {}).get("milestones", []),
			"claimed": fe["claimed"].get(p["id"], []), "my_contrib": float(fe["contrib"].get(p["id"], 0.0)),
			"end": (festival_cycle(now) + 1) * int(cfg().get("festival", {}).get("cycle_days", 7)) * DAY_MS}
	var lic_table: Array = cfg().get("license", {}).get("points", [0])
	var ll: int = license_level(p)
	return {
		"pass": {"points": int(lo["pass"]["points"]), "level": pass_level(p), "premium": bool(lo["pass"]["premium"]),
			"free_claimed": lo["pass"]["free_claimed"], "prem_claimed": lo["pass"]["prem_claimed"], "season_end": season_end,
			"points_per_level": int(pc.get("points_per_level", 300)), "premium_mo": int(pc.get("premium_mo", 1000))},
		"license": {"level": ll, "points": int(lo["license"]["points"]), "next": int(lic_table[ll]) if ll < lic_table.size() else -1,
			"daily_ready": int(lo["license"].get("daily_day", -1)) != int(now / DAY_MS), "mods": p.get("vip_mods", {}), "auto_battle": has_auto_battle(p)},
		"singularity": sing, "festival": fest,
	}
