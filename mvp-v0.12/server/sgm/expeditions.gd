extends RefCounted
## Expediciones (feedback del 26/10: "no hay Expediciones"): campaña PvE por
## capítulos que se juega con un equipo de hasta 5 tripulantes.
##
## - 6 capítulos × 8 etapas, cada una con modo Normal y Élite. El capítulo se
##   abre con el nivel del Puente y la etapa anterior ganada; el Élite de un
##   capítulo se abre al terminar su Normal y tiene intentos diarios.
## - El combate es una simulación determinista por rondas (semilla = jugador +
##   etapa + intento) que el cliente reproduce. Estrellas: 3 sin bajas, 2 con
##   pocas bajas, 1 si se gana con más.
## - Cada combate gasta Combustible de Expedición (se regenera con el tiempo).
## - Premios: la primera victoria da Créditos, Insignias de Mando, materiales de
##   xenoforma y Materia Oscura en los jefes; repetir da un premio reducido. Los
##   tripulantes del equipo ganan EXP y el Comandante también.
## - Barrido (auto-batalla): con Licencia de Comandante 6 se repite al instante
##   una etapa ya ganada con 3 estrellas.
## - Cofres de capítulo a las 8, 16 y 24 estrellas.
## - Un tripulante que viaja en una flota no puede ir a la Expedición (doble
##   empleo).

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const DAY_MS: int = 86400000
const MIN_MS: int = 60000

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.expeditions


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func ensure(p: Dictionary) -> Dictionary:
	if not p.has("expedition"):
		p["expedition"] = {"fuel": int(cfg().get("fuel", {}).get("max", 120)), "fuel_ts": U.now_ms(),
			"stars": {}, "elite": {}, "tries": {"day": -1}, "chests": [], "refills": {"day": -1, "n": 0}, "team": []}
	return p["expedition"]


# ---------------------------------------------------------------- catálogo

func chapters() -> Array:
	return cfg().get("chapters", [])


## Devuelve [capítulo, índice de capítulo, índice de etapa] o [] si no existe.
func find_stage(stage_id: String) -> Array:
	var cs: Array = chapters()
	for ci: int in range(cs.size()):
		var st: Array = cs[ci].get("stages", [])
		for si: int in range(st.size()):
			if str(st[si]["id"]) == stage_id:
				return [st[si], ci, si]
	return []


# ---------------------------------------------------------------- combustible

func fuel(p: Dictionary, now: int = -1) -> int:
	if now < 0:
		now = U.now_ms()
	var e: Dictionary = ensure(p)
	var fc: Dictionary = cfg().get("fuel", {})
	var mx: int = int(fc.get("max", 120))
	var step: int = int(fc.get("regen_minutes", 6)) * MIN_MS
	var cur: int = int(e["fuel"])
	if cur >= mx:
		e["fuel_ts"] = now
		return cur
	var gained: int = int((now - int(e["fuel_ts"])) / step)
	if gained > 0:
		cur = mini(mx, cur + gained)
		e["fuel"] = cur
		e["fuel_ts"] = now if cur >= mx else int(e["fuel_ts"]) + gained * step
	return cur


func _spend_fuel(p: Dictionary, n: int) -> bool:
	var cur: int = fuel(p)
	if cur < n:
		return false
	var e: Dictionary = ensure(p)
	if cur >= int(cfg().get("fuel", {}).get("max", 120)):
		e["fuel_ts"] = U.now_ms()
	e["fuel"] = cur - n
	return true


func refill(p: Dictionary) -> Dictionary:
	var fc: Dictionary = cfg().get("fuel", {})
	var e: Dictionary = ensure(p)
	var day: int = int(U.now_ms() / DAY_MS)
	if int(e["refills"].get("day", -1)) != day:
		e["refills"] = {"day": day, "n": 0}
	if int(e["refills"]["n"]) >= int(fc.get("refills_per_day", 3)):
		return _err("LIMIT", U.t("Ya usaste todas las recargas de Combustible de hoy"))
	var cost: int = int(fc.get("refill_mo", 50))
	if not Eco.apply(p, {"dark_matter": -cost}, "expedition_refill", "exp_refill:%d:%d" % [day, int(e["refills"]["n"])]):
		return _err("INSUFFICIENT_RESOURCES", U.t("Materia Oscura insuficiente (%d)") % cost)
	e["refills"]["n"] = int(e["refills"]["n"]) + 1
	e["fuel"] = fuel(p) + int(fc.get("refill_amount", 60))
	srv.on_activity(p, "mo_spent", float(cost))
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


# ---------------------------------------------------------------- desbloqueos

func chapter_cleared(p: Dictionary, ci: int, elite: bool) -> bool:
	var book: Dictionary = ensure(p)["elite" if elite else "stars"]
	for st: Dictionary in chapters()[ci].get("stages", []):
		if int(book.get(st["id"], 0)) <= 0:
			return false
	return true


## "" si la etapa está disponible; si no, el motivo.
func locked_reason(p: Dictionary, ci: int, si: int, elite: bool) -> String:
	var ch: Dictionary = chapters()[ci]
	var bridge: int = Eco.room_level(p, "bridge")
	if bridge < int(ch.get("requires_bridge", 1)):
		return U.t("Requiere Puente Nv %d") % int(ch["requires_bridge"])
	if ci > 0 and not chapter_cleared(p, ci - 1, elite):
		return U.t("Termina el capítulo anterior")
	if elite and not chapter_cleared(p, ci, false):
		return U.t("Termina el capítulo en Normal")
	if si > 0:
		var prev: String = str(ch["stages"][si - 1]["id"])
		if int(ensure(p)["elite" if elite else "stars"].get(prev, 0)) <= 0:
			return U.t("Gana la etapa anterior")
	return ""


func elite_tries_left(p: Dictionary, stage_id: String) -> int:
	var e: Dictionary = ensure(p)
	var day: int = int(U.now_ms() / DAY_MS)
	if int(e["tries"].get("day", -1)) != day:
		e["tries"] = {"day": day}
	return int(cfg().get("elite", {}).get("daily_attempts", 3)) - int(e["tries"].get(stage_id, 0))


# ---------------------------------------------------------------- unidades

func role_of(crew_id: String) -> String:
	var stat: String = str(srv.crew.def(crew_id).get("stat", ""))
	return str(cfg().get("unit", {}).get("role_by_stat", {}).get(stat, "especialista"))


func crew_unit(p: Dictionary, crew_id: String) -> Dictionary:
	var uc: Dictionary = cfg().get("unit", {})
	var o: Dictionary = srv.crew.ensure(p)["owned"].get(crew_id, {})
	var d: Dictionary = srv.crew.def(crew_id)
	var role: String = role_of(crew_id)
	var rm: Dictionary = uc.get("roles", {}).get(role, {})
	var mult: float = float(uc.get("rarity", {}).get(str(d.get("rarity", "common")), 1.0))
	mult *= 1.0 + float(uc.get("per_level", 0.08)) * (srv.crew.level_of(o) - 1)
	mult *= 1.0 + float(uc.get("per_grade", 0.2)) * (srv.crew.grade_of(o) - 1)
	mult *= 1.0 + float(uc.get("per_star", 0.12)) * (int(o.get("stars", 1)) - 1)
	var hp: float = float(uc.get("hp_base", 900)) * mult * float(rm.get("hp", 1.0)) * (1.0 + Eco.extra(p, "hp"))
	var atk: float = float(uc.get("atk_base", 95)) * mult * float(rm.get("atk", 1.0)) * (1.0 + Eco.extra(p, "pve_damage"))
	return {"id": crew_id, "role": role, "hp": int(round(hp)), "atk": int(round(atk)), "heal": float(rm.get("heal", 0.0)),
		"level": srv.crew.level_of(o), "rarity": str(d.get("rarity", "common"))}


func enemy_units(stage: Dictionary, elite: bool) -> Array:
	var m: float = float(cfg().get("elite", {}).get("power_mult", 1.6)) if elite else 1.0
	var heal: float = float(cfg().get("unit", {}).get("roles", {}).get("especialista", {}).get("heal", 0.5))
	var out: Array = []
	var i: int = 0
	for e: Dictionary in stage.get("enemies", []):
		out.append({"id": "e%d" % i, "species": e["species"], "level": int(e["level"]), "role": e["role"], "boss": bool(e.get("boss", false)),
			"hp": int(round(float(e["hp"]) * m)), "atk": int(round(float(e["atk"]) * m)), "heal": heal if str(e["role"]) == "especialista" else 0.0})
		i += 1
	return out


static func power_of(units: Array) -> int:
	var t: float = 0.0
	for u: Dictionary in units:
		t += sqrt(float(u["hp"]) * float(u["atk"]))
	return int(round(t))


# ---------------------------------------------------------------- simulación

## Combate por rondas. Cada unidad viva actúa en orden (asalto, especialista,
## vanguardia); ataca a la vanguardia enemiga viva primero y si no, a la de
## menos vida. El especialista además cura al aliado más herido. Determinista
## para una semilla dada. Devuelve {win, deaths, rounds, log, a_hp, b_hp}.
static func simulate(team: Array, enemies: Array, seed_val: int, bc: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var sides: Array = [[], []]
	for u: Dictionary in team:
		var c: Dictionary = u.duplicate()
		c["cur"] = int(u["hp"])
		sides[0].append(c)
	for u: Dictionary in enemies:
		var c: Dictionary = u.duplicate()
		c["cur"] = int(u["hp"])
		sides[1].append(c)
	var order_key: Dictionary = {"asalto": 0, "especialista": 1, "vanguardia": 2}
	var events: Array = []
	var rounds: int = 0
	var max_rounds: int = int(bc.get("max_rounds", 15))
	var crit_c: float = float(bc.get("crit_chance", 0.15))
	var crit_m: float = float(bc.get("crit_mult", 1.5))
	var spread: float = float(bc.get("spread", 0.1))
	while rounds < max_rounds and _alive(sides[0]) > 0 and _alive(sides[1]) > 0:
		rounds += 1
		var actors: Array = []
		for s: int in [0, 1]:
			for i: int in range((sides[s] as Array).size()):
				actors.append([s, i])
		actors.sort_custom(func(x: Array, y: Array) -> bool:
			var rx: int = int(order_key.get(str(sides[x[0]][x[1]]["role"]), 1))
			var ry: int = int(order_key.get(str(sides[y[0]][y[1]]["role"]), 1))
			if rx != ry:
				return rx < ry
			if x[1] != y[1]:
				return x[1] < y[1]
			return x[0] < y[0])
		for a: Array in actors:
			var me: Dictionary = sides[a[0]][a[1]]
			if int(me["cur"]) <= 0:
				continue
			var foes: Array = sides[1 - int(a[0])]
			var ti: int = _target(foes)
			if ti < 0:
				break
			var dmg: float = float(me["atk"]) * rng.randf_range(1.0 - spread, 1.0 + spread)
			var crit: bool = rng.randf() < crit_c
			if crit:
				dmg *= crit_m
			var t: Dictionary = foes[ti]
			var d: int = maxi(1, int(round(dmg)))
			t["cur"] = maxi(0, int(t["cur"]) - d)
			events.append({"r": rounds, "s": a[0], "a": a[1], "t": ti, "d": d, "c": crit, "k": int(t["cur"]) == 0})
			if float(me.get("heal", 0.0)) > 0.0:
				var hi: int = _most_hurt(sides[a[0]])
				if hi >= 0:
					var ally: Dictionary = sides[a[0]][hi]
					var h: int = mini(int(ally["hp"]) - int(ally["cur"]), int(round(float(me["atk"]) * float(me["heal"]))))
					if h > 0:
						ally["cur"] = int(ally["cur"]) + h
						events.append({"r": rounds, "s": a[0], "a": a[1], "t": hi, "h": h})
	var win: bool = _alive(sides[1]) == 0 and _alive(sides[0]) > 0
	var deaths: int = (sides[0] as Array).size() - _alive(sides[0])
	return {"win": win, "deaths": deaths, "rounds": rounds, "log": events,
		"a_hp": (sides[0] as Array).map(func(u: Dictionary) -> int: return int(u["cur"])),
		"b_hp": (sides[1] as Array).map(func(u: Dictionary) -> int: return int(u["cur"]))}


static func _alive(side: Array) -> int:
	var n: int = 0
	for u: Dictionary in side:
		if int(u["cur"]) > 0:
			n += 1
	return n


static func _target(foes: Array) -> int:
	var best: int = -1
	for i: int in range(foes.size()):
		if int(foes[i]["cur"]) > 0 and str(foes[i]["role"]) == "vanguardia":
			if best < 0 or int(foes[i]["cur"]) < int(foes[best]["cur"]):
				best = i
	if best >= 0:
		return best
	for i: int in range(foes.size()):
		if int(foes[i]["cur"]) > 0 and (best < 0 or int(foes[i]["cur"]) < int(foes[best]["cur"])):
			best = i
	return best


static func _most_hurt(side: Array) -> int:
	var best: int = -1
	var worst: float = 1.0
	for i: int in range(side.size()):
		var u: Dictionary = side[i]
		if int(u["cur"]) <= 0:
			continue
		var f: float = float(u["cur"]) / float(maxi(1, int(u["hp"])))
		if f < worst:
			worst = f
			best = i
	return best


static func stars_for(sim: Dictionary, bc: Dictionary) -> int:
	if not bool(sim.get("win", false)):
		return 0
	var d: int = int(sim["deaths"])
	if d == 0:
		return 3
	return 2 if d <= int(bc.get("stars", {}).get("max_deaths_2", 2)) else 1


# ---------------------------------------------------------------- acciones

func _validate_team(p: Dictionary, ids: Array) -> Dictionary:
	if ids.is_empty():
		return _err("NO_TEAM", U.t("Elige al menos un tripulante"))
	if ids.size() > int(cfg().get("team_max", 5)):
		return _err("TOO_MANY", U.t("Máximo %d tripulantes por equipo") % int(cfg().get("team_max", 5)))
	var owned: Dictionary = srv.crew.ensure(p)["owned"]
	var busy: Dictionary = srv.crew.deployed(p)
	var seen: Dictionary = {}
	for cid: String in ids:
		if not owned.has(cid):
			return _err("NOT_OWNED", U.t("No tienes a ese tripulante"))
		if seen.has(cid):
			return _err("DUPLICATE", U.t("Un tripulante no puede ir dos veces"))
		seen[cid] = true
		if busy.has(cid):
			return _err("CREW_BUSY", U.t("%s viaja en una flota") % str(Catalog.portraits.get(cid, {}).get("name", cid)))
	return {"ok": true}


func _reward_for(stage: Dictionary, elite: bool, first: bool) -> Dictionary:
	var base: Dictionary = stage.get("first" if first else "repeat", {})
	var m: int = int(cfg().get("elite", {}).get("reward_mult", 2)) if elite else 1
	var out: Dictionary = {}
	for k: String in base:
		out[k] = int(base[k]) * m
	return out


func battle(p: Dictionary, stage_id: String, elite: bool, crew_ids: Array) -> Dictionary:
	var found: Array = find_stage(stage_id)
	if found.is_empty():
		return _err("NOT_FOUND", U.t("Etapa desconocida"))
	var stage: Dictionary = found[0]
	var why: String = locked_reason(p, int(found[1]), int(found[2]), elite)
	if not why.is_empty():
		return _err("LOCKED", why)
	var v: Dictionary = _validate_team(p, crew_ids)
	if not v.get("ok", false):
		return v
	if elite and elite_tries_left(p, stage_id) <= 0:
		return _err("LIMIT", U.t("Sin intentos Élite hoy en esta etapa"))
	var fc: Dictionary = cfg().get("fuel", {})
	var cost: int = int(fc.get("cost_elite" if elite else "cost_normal", 6))
	if not _spend_fuel(p, cost):
		return _err("NO_FUEL", U.t("Combustible de Expedición insuficiente (%d)") % cost)
	var e: Dictionary = ensure(p)
	e["team"] = crew_ids.duplicate()
	e["battles"] = int(e.get("battles", 0)) + 1
	var team: Array = crew_ids.map(func(cid: String) -> Dictionary: return crew_unit(p, cid))
	var foes: Array = enemy_units(stage, elite)
	var bc: Dictionary = cfg().get("battle", {})
	var sim: Dictionary = simulate(team, foes, U.hash_seed("%s:%s:%s:%d" % [p["id"], stage_id, str(elite), int(e["battles"])]), bc)
	var stars: int = stars_for(sim, bc)
	if elite:
		e["tries"][stage_id] = int(e["tries"].get(stage_id, 0)) + 1
	var out: Dictionary = {"ok": true, "stage": stage_id, "elite": elite, "win": sim["win"], "stars": stars,
		"team": team, "enemies": foes, "log": sim["log"], "rounds": sim["rounds"], "reward": {}, "crew_exp": []}
	if sim["win"]:
		out.merge(_grant_win(p, stage, elite, stars, crew_ids), true)
	else:
		# Una derrota devuelve la mitad del combustible y algo de EXP.
		e["fuel"] = int(e["fuel"]) + cost / 2
		out["crew_exp"] = srv.crew.grant_exp(p, crew_ids, int(stage.get("crew_exp", 50)) / 4)
	srv.mark_player_dirty(p["id"])
	return out


func _grant_win(p: Dictionary, stage: Dictionary, elite: bool, stars: int, crew_ids: Array) -> Dictionary:
	var e: Dictionary = ensure(p)
	var book: Dictionary = e["elite" if elite else "stars"]
	var sid: String = str(stage["id"])
	var first: bool = int(book.get(sid, 0)) <= 0
	book[sid] = maxi(int(book.get(sid, 0)), stars)
	var reward: Dictionary = _reward_for(stage, elite, first)
	var idem: String = "exp:%s:%s:%s" % [p["id"], sid, "elite" if elite else "normal"]
	if not first:
		idem += ":%d" % int(e.get("battles", 0))
	srv.progression.grant(p, reward, "expedition", idem)
	var mult: int = 2 if elite else 1
	var cx: Array = srv.crew.grant_exp(p, crew_ids, int(stage.get("crew_exp", 50)) * mult)
	srv.commander.grant_exp(p, int(stage.get("cmd_exp", 30)) * mult)
	srv.on_activity(p, "expedition_win", 1.0)
	return {"reward": reward, "first": first, "crew_exp": cx}


## Barrido (auto-batalla): requiere Licencia de Comandante 6 y 3 estrellas.
func sweep(p: Dictionary, stage_id: String, elite: bool, times: int) -> Dictionary:
	if not srv.liveops.has_auto_battle(p):
		return _err("LICENSE", U.t("El barrido requiere Licencia de Comandante nivel %d") % int(Catalog.liveops.get("license", {}).get("auto_battle_level", 6)))
	if not (cfg().get("sweep_times", [1, 5]) as Array).map(func(x: Variant) -> int: return int(x)).has(times):
		return _err("BAD_TIMES", U.t("Cantidad de barridos no válida"))
	var found: Array = find_stage(stage_id)
	if found.is_empty():
		return _err("NOT_FOUND", U.t("Etapa desconocida"))
	var e: Dictionary = ensure(p)
	if int(e["elite" if elite else "stars"].get(stage_id, 0)) < 3:
		return _err("NEED_3_STARS", U.t("Gana la etapa con 3 estrellas para poder barrerla"))
	if elite and elite_tries_left(p, stage_id) < times:
		return _err("LIMIT", U.t("Sin intentos Élite suficientes hoy"))
	var fc: Dictionary = cfg().get("fuel", {})
	var cost: int = int(fc.get("cost_elite" if elite else "cost_normal", 6)) * times
	if not _spend_fuel(p, cost):
		return _err("NO_FUEL", U.t("Combustible de Expedición insuficiente (%d)") % cost)
	var stage: Dictionary = found[0]
	var team: Array = (e.get("team", []) as Array).filter(func(cid: String) -> bool: return srv.crew.ensure(p)["owned"].has(cid) and not srv.crew.deployed(p).has(cid))
	var total: Dictionary = {}
	for i: int in range(times):
		e["battles"] = int(e.get("battles", 0)) + 1
		var r: Dictionary = _reward_for(stage, elite, false)
		srv.progression.grant(p, r, "expedition_sweep", "exp_sweep:%s:%s:%d" % [p["id"], stage_id, int(e["battles"])])
		for k: String in r:
			total[k] = int(total.get(k, 0)) + int(r[k])
		srv.on_activity(p, "expedition_win", 1.0)
	if elite:
		e["tries"][stage_id] = int(e["tries"].get(stage_id, 0)) + times
	var cx: Array = srv.crew.grant_exp(p, team, int(stage.get("crew_exp", 50)) * times * (2 if elite else 1))
	srv.commander.grant_exp(p, int(stage.get("cmd_exp", 30)) * times * (2 if elite else 1))
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "reward": total, "times": times, "crew_exp": cx}


func chapter_stars(p: Dictionary, ci: int) -> int:
	var n: int = 0
	var book: Dictionary = ensure(p)["stars"]
	for st: Dictionary in chapters()[ci].get("stages", []):
		n += int(book.get(st["id"], 0))
	return n


func claim_chest(p: Dictionary, ci: int, idx: int) -> Dictionary:
	if ci < 0 or ci >= chapters().size():
		return _err("NOT_FOUND", U.t("Capítulo desconocido"))
	var chests: Array = chapters()[ci].get("chests", [])
	if idx < 0 or idx >= chests.size():
		return _err("NOT_FOUND", U.t("Cofre desconocido"))
	var key: String = "%d:%d" % [ci, idx]
	var e: Dictionary = ensure(p)
	if (e["chests"] as Array).has(key):
		return _err("ALREADY", U.t("Ya abriste ese cofre"))
	if chapter_stars(p, ci) < int(chests[idx]["stars"]):
		return _err("LOCKED", U.t("Necesitas %d estrellas en el capítulo") % int(chests[idx]["stars"]))
	srv.progression.grant(p, chests[idx]["reward"], "expedition_chest", "exp_chest:%s:%s" % [p["id"], key])
	(e["chests"] as Array).append(key)
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "reward": chests[idx]["reward"]}


# ---------------------------------------------------------------- vista

func view(p: Dictionary) -> Dictionary:
	var e: Dictionary = ensure(p)
	var fc: Dictionary = cfg().get("fuel", {})
	var cur: int = fuel(p)
	var chs: Array = []
	for ci: int in range(chapters().size()):
		chs.append({"stars": chapter_stars(p, ci), "locked": locked_reason(p, ci, 0, false), "elite_locked": locked_reason(p, ci, 0, true)})
	var tries: Dictionary = {}
	var day: int = int(U.now_ms() / DAY_MS)
	if int(e["tries"].get("day", -1)) == day:
		tries = e["tries"]
	var units: Dictionary = {}
	for cid: String in srv.crew.ensure(p)["owned"]:
		var u: Dictionary = crew_unit(p, cid)
		units[cid] = {"role": u["role"], "hp": u["hp"], "atk": u["atk"], "power": power_of([u])}
	return {
		"fuel": cur, "fuel_max": int(fc.get("max", 120)), "fuel_next": int(e["fuel_ts"]) + int(fc.get("regen_minutes", 6)) * MIN_MS if cur < int(fc.get("max", 120)) else 0,
		"refills_left": int(fc.get("refills_per_day", 3)) - (int(e["refills"].get("n", 0)) if int(e["refills"].get("day", -1)) == day else 0),
		"stars": e["stars"], "elite": e["elite"], "elite_tries": tries, "chests": e["chests"], "team": e.get("team", []),
		"chapters": chs, "units": units, "auto_battle": srv.liveops.has_auto_battle(p),
	}
