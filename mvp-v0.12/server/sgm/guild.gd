extends RefCounted
## Dinámicas de Alianza (feedback de revisión: "premios para el grupo, incentivos
## para el gremio, sentido de pertenencia").
##
##  - Puntos de Alianza (PA): cada caza, entrega, victoria o ayuda de un miembro
##    suma PA al ciclo diario y experiencia (XP) permanente → nivel de alianza con
##    bonificaciones para todos.
##  - Metas diarias grupales (cazar N entre todos, entregar recursos, ganar PvP).
##  - Cuota por miembro ("caza 5 bichos al día") visible para todo el grupo.
##  - Cofre de Alianza por niveles de PA: lo reclama cada miembro.
##  - Objetivo marcado: "ataquemos entre todos a tal nave" (los aliados de la
##    demo responden con oleadas de ataque; golpear el objetivo da PA extra).
##  - Ranking de alianzas.

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const Resolver = preload("res://server/combat/combat_resolver.gd")

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.events.get("alliance", {})


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func _cycle_ms() -> int:
	return int(float(cfg().get("cycle_hours", 24)) * 3600000.0)


## Estado dinámico de una alianza (se guarda dentro de state.alliances[tag]).
func data(tag: String) -> Dictionary:
	var a: Dictionary = srv.social.alliances().get(tag, {})
	if a.is_empty():
		return {}
	if not a.has("guild"):
		a["guild"] = {"xp": 0, "cycle_start": U.now_ms(), "points": 0, "goals": {}, "contrib": {}, "quota": {}, "chest_claims": {}, "target": {}, "history": []}
		_set_level(a)
	var g: Dictionary = a["guild"]
	if U.now_ms() - int(g["cycle_start"]) >= _cycle_ms():
		new_cycle(tag)
	return g


func new_cycle(tag: String) -> void:
	var a: Dictionary = srv.social.alliances().get(tag, {})
	var g: Dictionary = a["guild"]
	var hist: Array = g.get("history", [])
	hist.push_front({"start": g["cycle_start"], "points": g["points"], "goals_done": _goals_done(g)})
	while hist.size() > 7:
		hist.pop_back()
	g["history"] = hist
	g["cycle_start"] = U.now_ms()
	g["points"] = 0
	g["goals"] = {}
	g["contrib"] = {}
	g["quota"] = {}
	g["chest_claims"] = {}


func _goals_done(g: Dictionary) -> int:
	var n: int = 0
	for goal: Dictionary in cfg().get("goals", []):
		if float(g["goals"].get(goal["id"], 0.0)) >= float(goal["target"]):
			n += 1
	return n


func level_of(xp: int) -> int:
	var lv: int = 1
	var table: Array = cfg().get("level_xp", [0])
	for i: int in range(table.size()):
		if xp >= int(table[i]):
			lv = i + 1
	return lv


func _set_level(a: Dictionary) -> void:
	var g: Dictionary = a["guild"]
	# El nivel inicial del catálogo (alianzas existentes) se respeta como mínimo.
	var table: Array = cfg().get("level_xp", [0])
	var base_lv: int = clampi(int(a.get("level", 1)), 1, table.size())
	if int(g.get("xp", 0)) < int(table[base_lv - 1]):
		g["xp"] = int(table[base_lv - 1])
	a["level"] = level_of(int(g["xp"]))


## Bonificaciones del nivel de alianza para cada miembro (las lee Eco.modifiers).
func perks(level: int) -> Dictionary:
	var out: Dictionary = {}
	var per: Dictionary = cfg().get("level_perks", {})
	for k: String in per:
		out[k] = float(per[k]) * float(level - 1)
	return out


func refresh_member_mods(tag: String) -> void:
	var a: Dictionary = srv.social.alliances().get(tag, {})
	if a.is_empty():
		return
	var pk: Dictionary = perks(int(a.get("level", 1)))
	for m: Dictionary in srv.social.members(tag):
		m["ally_mods"] = pk


# ---------------------------------------------------------------- actividad

func on_activity(p: Dictionary, kind: String, amount: float, extra: Dictionary = {}) -> void:
	var tag: String = str(p.get("tag", ""))
	if tag.is_empty():
		return
	var g: Dictionary = data(tag)
	if g.is_empty():
		return
	var pts_table: Dictionary = cfg().get("points", {})
	# Los bots representan a otros miembros: aportan menos para que el aporte del
	# jugador sea decisivo en las metas del grupo.
	var w: float = float(cfg().get("bot_weight", 0.35)) if p.get("is_bot", false) else 1.0
	var pts: float = float(pts_table.get(kind, 0.0)) * amount * w
	# Golpear el objetivo marcado vale mucho más (incentivo a coordinar).
	var t: Dictionary = g.get("target", {})
	if kind == "pvp_hit" and not t.is_empty() and str(extra.get("target_owner", "")) == str(t.get("owner", "")) and U.now_ms() < int(t.get("until", 0)):
		pts += float(pts_table.get("target_hit", 100))
		t["hits"] = int(t.get("hits", 0)) + 1
		var hitters: Array = t.get("hitters", [])
		if not hitters.has(p["name"]):
			hitters.append(p["name"])
		t["hitters"] = hitters
		srv.social.post(tag, U.t("Sistema"), U.t("¡%s golpeó el objetivo de la Alianza! (+%d PA)") % [p["name"], int(pts_table.get("target_hit", 100))], "system")
	# Metas grupales y cuota individual
	var goal_amount: Dictionary = {}
	match kind:
		"xeno_kill":
			goal_amount["xeno_kill_count"] = 1.0
		"resources":
			goal_amount["resources"] = amount
		"pvp_win":
			goal_amount["pvp_win"] = amount
	for gk: String in goal_amount:
		for goal: Dictionary in cfg().get("goals", []):
			if str(goal["kind"]) != gk:
				continue
			var before: float = float(g["goals"].get(goal["id"], 0.0))
			var after: float = before + float(goal_amount[gk]) * w
			g["goals"][goal["id"]] = after
			if before < float(goal["target"]) and after >= float(goal["target"]):
				pts += float(goal["points"])
				srv.social.post(tag, U.t("Sistema"), U.t("¡Meta de Alianza cumplida: %s! +%d PA para el cofre.") % [U.t(str(goal["name"])), int(goal["points"])], "system")
		var q: Dictionary = cfg().get("member_quota", {})
		if str(q.get("kind", "")) == gk:
			g["quota"][p["id"]] = int(g["quota"].get(p["id"], 0)) + int(goal_amount[gk])
			if int(g["quota"][p["id"]]) == int(q.get("target", 5)) and not p.get("is_bot", false):
				srv.notify(p["id"], U.t("¡Cumpliste tu cuota diaria de Alianza!"), "success")
	if pts <= 0.0:
		return
	_add_points(tag, p, pts)


func _add_points(tag: String, p: Dictionary, pts: float) -> void:
	var a: Dictionary = srv.social.alliances()[tag]
	var g: Dictionary = a["guild"]
	var before_pts: int = int(g["points"])
	g["points"] = float(g["points"]) + pts
	g["xp"] = float(g["xp"]) + pts
	g["contrib"][p["id"]] = float(g["contrib"].get(p["id"], 0.0)) + pts
	var old_lv: int = int(a.get("level", 1))
	a["level"] = level_of(int(g["xp"]))
	if int(a["level"]) > old_lv:
		refresh_member_mods(tag)
		srv.social.post(tag, U.t("Sistema"), U.t("¡La Alianza subió a nivel %d! Bonificaciones mejoradas para todos.") % int(a["level"]), "system")
	for i: int in range(cfg().get("chest_tiers", []).size()):
		var tier: Dictionary = cfg()["chest_tiers"][i]
		if before_pts < int(tier["points"]) and int(g["points"]) >= int(tier["points"]):
			srv.social.post(tag, U.t("Sistema"), U.t("¡%s desbloqueado! Cada miembro puede reclamarlo en Alianza → Cofre.") % U.t(str(tier["name"])), "system")
	for m: Dictionary in srv.social.members(tag):
		if not m.get("is_bot", false):
			srv.mark_player_dirty(m["id"])


func claim_chest(p: Dictionary, tier_index: int) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	var g: Dictionary = data(tag)
	if g.is_empty():
		return _err("NO_ALLIANCE", U.t("No perteneces a una Alianza"))
	var tiers: Array = cfg().get("chest_tiers", [])
	if tier_index < 0 or tier_index >= tiers.size():
		return _err("INVALID", U.t("Cofre inválido"))
	if int(g["points"]) < int(tiers[tier_index]["points"]):
		return _err("LOCKED", U.t("La Alianza aún no junta los puntos de este cofre"))
	var claims: Array = g["chest_claims"].get(p["id"], [])
	if claims.has(tier_index) or claims.has(float(tier_index)):
		return _err("CLAIMED", U.t("Ya reclamaste este cofre"))
	claims.append(tier_index)
	g["chest_claims"][p["id"]] = claims
	var reward: Dictionary = tiers[tier_index]["reward"]
	srv.progression.grant(p, reward, "alliance_chest:%d" % tier_index)
	return {"ok": true, "reward": reward, "name": U.t(str(tiers[tier_index]["name"]))}


# ---------------------------------------------------------------- objetivo marcado

func mark_target(p: Dictionary, target_id: String) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	var g: Dictionary = data(tag)
	if g.is_empty():
		return _err("NO_ALLIANCE", U.t("No perteneces a una Alianza"))
	if not str(p.get("rank", "R1")) in ["R4", "R5"]:
		return _err("RANK", U.t("Solo los oficiales R4/R5 pueden marcar objetivos"))
	var base: Dictionary = srv.world.get_entity(target_id)
	if base.is_empty() or base["kind"] != "base":
		return _err("INVALID_TARGET", U.t("Solo se pueden marcar naves enemigas"))
	var owner: Dictionary = srv.player(base["owner"])
	if owner.is_empty() or str(owner.get("tag", "")) == tag:
		return _err("INVALID_TARGET", U.t("Solo se pueden marcar naves enemigas"))
	var now: int = U.now_ms()
	var mins: int = int(cfg().get("target_minutes", 30))
	g["target"] = {
		"id": target_id, "owner": owner["id"], "name": srv.display_name(owner["id"]), "system": srv.current_system,
		"set_by": p["name"], "since": now, "until": now + mins * 60000, "hits": 0, "hitters": [],
		"power": srv.player_power(owner), "pos": base["pos"].duplicate(),
	}
	srv.social.post(tag, p["name"], U.t("OBJETIVO DE ALIANZA: %s en X:%d Y:%d. ¡Ataquemos todos durante los próximos %d minutos!") % [srv.display_name(owner["id"]), int(base["pos"][0]), int(base["pos"][1]), mins], "rally")
	_schedule_waves(tag, g, base)
	return {"ok": true}


## En la demo, los aliados bot cercanos responden al llamado con oleadas.
func _schedule_waves(tag: String, g: Dictionary, base: Dictionary) -> void:
	var waves: Array = []
	var allies: Array = []
	for m: Dictionary in srv.social.members(tag):
		if m.get("is_bot", false) and str(m.get("system", "")) == srv.current_system:
			var mb: Dictionary = srv.world.get_entity(str(m.get("base_id", "")))
			if not mb.is_empty():
				allies.append([U.v2(mb["pos"]).distance_to(U.v2(base["pos"])), m["id"]])
	allies.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var now: int = U.now_ms()
	var n: int = mini(int(cfg().get("target_bot_waves", 4)), allies.size())
	for i: int in range(n):
		waves.append({"pid": allies[i][1], "at": now + 4000 + i * srv.rng.randi_range(9000, 20000)})
	g["target"]["waves"] = waves


func clear_target(p: Dictionary) -> Dictionary:
	var g: Dictionary = data(str(p.get("tag", "")))
	if g.is_empty():
		return _err("NO_ALLIANCE", U.t("No perteneces a una Alianza"))
	g["target"] = {}
	return {"ok": true}


func tick(now: int) -> void:
	for tag: String in srv.social.alliances():
		var a: Dictionary = srv.social.alliances()[tag]
		if not a.has("guild"):
			continue
		var g: Dictionary = data(tag)
		var t: Dictionary = g.get("target", {})
		if t.is_empty():
			continue
		if now >= int(t.get("until", 0)):
			srv.social.post(tag, U.t("Sistema"), U.t("Objetivo de Alianza finalizado: %d golpes de %d comandantes.") % [int(t.get("hits", 0)), (t.get("hitters", []) as Array).size()], "system")
			g["target"] = {}
			continue
		if str(t.get("system", "")) != srv.current_system:
			continue
		var keep: Array = []
		for w: Dictionary in t.get("waves", []):
			if int(w["at"]) > now:
				keep.append(w)
				continue
			var bot: Dictionary = srv.player(str(w["pid"]))
			if bot.is_empty():
				continue
			var tb: Dictionary = srv.world.get_entity(str(t["id"]))
			if tb.is_empty():
				continue
			var troops: Dictionary = {}
			for k: String in bot["troops"]:
				var q: int = int(int(bot["troops"][k]) * 0.45)
				if q > 0:
					troops[k] = q
			var res: Dictionary = srv.fleets.start_march(bot, "attack", str(t["id"]), troops)
			if bool(res.get("ok", false)):
				srv.social.post(tag, bot["name"], U.t("¡Voy contra %s! Flota en camino.") % str(t.get("name", "")), "rally")
			elif int(w.get("tries", 0)) < 6:
				# Flotas ocupadas: reintenta en unos segundos.
				w["tries"] = int(w.get("tries", 0)) + 1
				w["at"] = now + 8000
				keep.append(w)
		t["waves"] = keep


# ---------------------------------------------------------------- vistas

func view(p: Dictionary) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	var g: Dictionary = data(tag)
	if g.is_empty():
		return {}
	var a: Dictionary = srv.social.alliances()[tag]
	var table: Array = cfg().get("level_xp", [0])
	var lv: int = int(a.get("level", 1))
	var goals: Array = []
	for goal: Dictionary in cfg().get("goals", []):
		goals.append({"id": goal["id"], "name": U.t(str(goal["name"])), "desc": U.t(str(goal["desc"])), "icon": goal.get("icon", "star"),
			"target": goal["target"], "progress": float(g["goals"].get(goal["id"], 0.0)), "points": goal["points"]})
	var quota: Dictionary = cfg().get("member_quota", {})
	var members: Array = []
	for m: Dictionary in srv.social.members(tag):
		members.append({"id": m["id"], "name": m["name"], "bot": m.get("is_bot", false), "quota": int(g["quota"].get(m["id"], 0)), "contrib": int(g["contrib"].get(m["id"], 0.0)),
			"system": U.t(str(srv.galaxy.system(str(m.get("system", ""))).get("name", "?")))})
	members.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["contrib"]) > int(y["contrib"]))
	var t: Dictionary = g.get("target", {}).duplicate()
	t.erase("waves")
	return {
		"xp": int(g["xp"]), "level": lv, "next_xp": int(table[mini(lv, table.size() - 1)]), "cur_xp": int(table[lv - 1]),
		"perks": perks(lv), "points": int(g["points"]), "cycle_end": int(g["cycle_start"]) + _cycle_ms(),
		"goals": goals, "quota": {"label": U.t(str(quota.get("label", ""))), "target": int(quota.get("target", 5))},
		"members": members, "chest_tiers": cfg().get("chest_tiers", []),
		"chest_claimed": g["chest_claims"].get(p["id"], []), "target": t,
		"my_contrib": int(g["contrib"].get(p["id"], 0.0)), "my_quota": int(g["quota"].get(p["id"], 0)),
	}


func ranking() -> Array:
	var out: Array = []
	for tag: String in srv.social.alliances():
		var a: Dictionary = srv.social.alliances()[tag]
		var g: Dictionary = data(tag)
		var pw: int = 0
		var n: int = 0
		for m: Dictionary in srv.social.members(tag):
			pw += srv.player_power(m)
			n += 1
		out.append({"tag": tag, "name": U.t(str(a["name"])), "color": a.get("color", "#ffffff"), "level": int(a.get("level", 1)), "points": int(g.get("points", 0)), "xp": int(g.get("xp", 0)), "power": pw, "members": n})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["points"]) > int(y["points"]) if int(x["points"]) != int(y["points"]) else int(x["power"]) > int(y["power"]))
	return out
