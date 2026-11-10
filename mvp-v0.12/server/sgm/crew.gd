extends RefCounted
## Tripulación (feedback de revisión: "selección de la tripulación", "ir
## incorporando tripulantes", "reclutar un tripulante nuevo").
##
## Los 45 personajes del catálogo de retratos son tripulantes reclutables con
## rareza (Común → Legendario) y una pasiva según su rol. El comandante elige a
## los tripulantes activos (los espacios dependen de Gestión de Tripulación) y
## sus pasivas se suman a los modificadores de combate y economía.
## La Cantina mejora la suerte del reclutamiento y da un reclutamiento gratis al día.

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const DAY_MS: int = 86400000

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.crew


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func def(crew_id: String) -> Dictionary:
	for c: Dictionary in cfg().get("crew", []):
		if str(c["id"]) == crew_id:
			return c
	return {}


func rarity(rid: String) -> Dictionary:
	for r: Dictionary in cfg().get("rarities", []):
		if str(r["id"]) == rid:
			return r
	return {}


func ensure(p: Dictionary) -> Dictionary:
	if not p.has("crew"):
		var owned: Dictionary = {}
		for cid: String in cfg().get("starter", []):
			owned[cid] = {"stars": 1, "ts": U.now_ms()}
		p["crew"] = {"owned": owned, "active": (cfg().get("starter", []) as Array).slice(0, int(cfg().get("base_slots", 2))), "free_ts": 0, "recruits": 0}
		refresh_mods(p)
	return p["crew"]


func slots(p: Dictionary) -> int:
	var crew_lvl: int = Eco.room_level(p, "crew")
	if crew_lvl <= 0:
		return int(cfg().get("base_slots", 2))
	return int(Eco.effect(p, "crew", "crew_slots"))


## Valor de la pasiva de un tripulante: rareza × estrellas × grado × nivel ×
## rango × Gestión de Tripulación.
func bonus_of(p: Dictionary, crew_id: String) -> float:
	var d: Dictionary = def(crew_id)
	var owned: Dictionary = ensure(p)["owned"].get(crew_id, {})
	if d.is_empty() or owned.is_empty():
		return 0.0
	var mult: float = float(rarity(str(d["rarity"])).get("mult", 1.0))
	var stars: int = int(owned.get("stars", 1))
	var room_boost: float = 1.0 + Eco.effect(p, "crew", "crew_power") + Eco.extra(p, "crew_power")
	var grade_mult: float = 1.0 + float(cfg().get("grades", {}).get("bonus_per_grade", 0.25)) * (grade_of(owned) - 1)
	var level_mult: float = 1.0 + float(cfg().get("levels", {}).get("bonus_per_level", 0.02)) * (level_of(owned) - 1)
	var rank_mult: float = 1.0 + float(rank_of(level_of(owned)).get("bonus", 0.0))
	return float(cfg().get("base_bonus", 0.03)) * mult * (1.0 + float(cfg().get("star_bonus", 0.2)) * (stars - 1)) * grade_mult * level_mult * rank_mult * room_boost


# ---------------------------------------------------------------- nivel, rango y grado

func level_of(owned: Dictionary) -> int:
	return int(owned.get("level", 1))


func grade_of(owned: Dictionary) -> int:
	return int(owned.get("grade", 1))


## EXP necesaria para pasar del nivel `lvl` al siguiente (0 en el máximo).
func exp_to_next(lvl: int) -> int:
	var lv: Dictionary = cfg().get("levels", {})
	if lvl >= int(lv.get("max", 50)):
		return 0
	return int(round(float(lv.get("exp_base", 100)) * pow(float(lv.get("exp_growth", 1.12)), lvl - 1)))


## Rango según el nivel (Recluta, Cabo, Sargento, Teniente, Capitán).
func rank_of(lvl: int) -> Dictionary:
	var best: Dictionary = {"name": "Recluta", "bonus": 0.0, "min_level": 1}
	for r: Dictionary in cfg().get("ranks", []):
		if lvl >= int(r["min_level"]):
			best = r
	return best


## Suma EXP a varios tripulantes. Devuelve [{id, exp, level, leveled}] para el informe.
func grant_exp(p: Dictionary, ids: Array, amount: int) -> Array:
	var out: Array = []
	amount = int(round(amount * (1.0 + Eco.extra(p, "crew_exp"))))
	if amount <= 0:
		return out
	var owned_all: Dictionary = ensure(p)["owned"]
	for cid: String in ids:
		var o: Dictionary = owned_all.get(cid, {})
		if o.is_empty():
			continue
		var lvl: int = level_of(o)
		var xp: int = int(o.get("exp", 0)) + amount
		var start: int = lvl
		while exp_to_next(lvl) > 0 and xp >= exp_to_next(lvl):
			xp -= exp_to_next(lvl)
			lvl += 1
		if exp_to_next(lvl) == 0:
			xp = 0
		o["level"] = lvl
		o["exp"] = xp
		out.append({"id": cid, "exp": amount, "level": lvl, "leveled": lvl > start})
	refresh_mods(p)
	return out


## Sube un grado a un tripulante gastando Insignias de Mando.
func promote(p: Dictionary, crew_id: String) -> Dictionary:
	var o: Dictionary = ensure(p)["owned"].get(crew_id, {})
	if o.is_empty():
		return _err("NOT_OWNED", U.t("No tienes a ese tripulante"))
	var g: int = grade_of(o)
	var gcfg: Dictionary = cfg().get("grades", {})
	if g >= int(gcfg.get("max", 5)):
		return _err("MAX_GRADE", U.t("Ese tripulante ya tiene el grado máximo"))
	var cost: int = int((gcfg.get("insignia_cost", []) as Array)[g - 1])
	if not Eco.apply(p, {"insignia": -cost}, "crew_promote", "crew:%s:grade:%d" % [crew_id, g + 1]):
		return _err("INSUFFICIENT_RESOURCES", U.t("Insignias de Mando insuficientes (%d)") % cost)
	o["grade"] = g + 1
	refresh_mods(p)
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "grade": g + 1}


func promote_cost(owned: Dictionary) -> int:
	var g: int = grade_of(owned)
	var costs: Array = cfg().get("grades", {}).get("insignia_cost", [])
	return int(costs[g - 1]) if g - 1 < costs.size() else 0


# ---------------------------------------------------------------- tripulantes en flotas

## Tripulantes que viajan ahora en alguna flota del comandante.
func deployed(p: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for f: Dictionary in srv.fleets.owned_fleets(p["id"]):
		for cid: String in f.get("crew", []):
			out[cid] = f["id"]
	return out


## Regla de doble empleo: un tripulante trabaja en una sala o viaja en una
## flota, nunca en las dos a la vez, ni en dos flotas.
func validate_fleet_crew(p: Dictionary, ids: Array) -> Dictionary:
	var c: Dictionary = ensure(p)
	var max_n: int = int(cfg().get("fleet", {}).get("max_per_fleet", 5))
	if ids.size() > max_n:
		return _err("CREW_LIMIT", U.t("Máximo %d tripulantes por flota") % max_n)
	var busy: Dictionary = deployed(p)
	var seen: Dictionary = {}
	for cid: String in ids:
		if seen.has(cid):
			return _err("CREW_DUPLICATE", U.t("Tripulante repetido"))
		seen[cid] = true
		if not c["owned"].has(cid):
			return _err("NOT_OWNED", U.t("No tienes a ese tripulante"))
		if (c["active"] as Array).has(cid):
			return _err("CREW_IN_ROOM", U.t("%s trabaja en una sala: retíralo de la tripulación activa para embarcarlo") % U.t(str(Catalog.portraits.get(cid, {}).get("name", cid))))
		if busy.has(cid):
			return _err("CREW_DEPLOYED", U.t("%s ya viaja en otra flota") % U.t(str(Catalog.portraits.get(cid, {}).get("name", cid))))
	return {}


## Modificadores que aportan los tripulantes de una flota (pasiva × fleet_mult).
func fleet_mods(p: Dictionary, ids: Array) -> Dictionary:
	var mods: Dictionary = {}
	var fm: float = float(cfg().get("fleet", {}).get("fleet_mult", 1.5))
	for cid: String in ids:
		var d: Dictionary = def(cid)
		if d.is_empty():
			continue
		mods[d["stat"]] = float(mods.get(d["stat"], 0.0)) + bonus_of(p, cid) * fm
	return mods


func refresh_mods(p: Dictionary) -> void:
	var mods: Dictionary = {}
	for cid: String in p.get("crew", {}).get("active", []):
		var d: Dictionary = def(cid)
		if d.is_empty():
			continue
		mods[d["stat"]] = float(mods.get(d["stat"], 0.0)) + bonus_of(p, cid)
	p["crew_mods"] = mods


## Probabilidades por rareza según el nivel de la Cantina.
func odds(p: Dictionary) -> Dictionary:
	var lvl: int = Eco.room_level(p, "cantina")
	var luck: Dictionary = cfg().get("luck_per_level", {})
	var out: Dictionary = {}
	var total_shift: float = 0.0
	for r: Dictionary in cfg().get("rarities", []):
		var w: float = float(r["weight"])
		if str(r["id"]) != "common":
			var add: float = float(luck.get(r["id"], 0.0)) * lvl
			w += add
			total_shift += add
		out[r["id"]] = w
	out["common"] = maxf(5.0, float(out.get("common", 60.0)) - total_shift)
	var s: float = 0.0
	for k: String in out:
		s += float(out[k])
	for k: String in out:
		out[k] = float(out[k]) / s * 100.0
	return out


func free_available(p: Dictionary) -> bool:
	return Eco.room_level(p, "cantina") > 0 and U.now_ms() >= int(ensure(p).get("free_ts", 0))


## method: "free" (Cantina, 1 al día), "ticket" (Contrato) o "mo" (Materia Oscura).
func recruit(p: Dictionary, count: int, method: String) -> Dictionary:
	var c: Dictionary = ensure(p)
	count = 10 if count >= 10 else 1
	match method:
		"free":
			if not free_available(p):
				return _err("NOT_YET", U.t("El reclutamiento gratis de la Cantina aún no está disponible"))
			count = 1
			c["free_ts"] = U.now_ms() + DAY_MS
		"ticket":
			count = 1
			if not Eco.apply(p, {"recruit_ticket": -1}, "recruit"):
				return _err("NO_ITEM", U.t("No tienes Contratos de Tripulante"))
		_:
			var cost: int = int(cfg().get("recruit10_cost_mo", 1350)) if count == 10 else int(cfg().get("recruit_cost_mo", 150))
			if not Eco.apply(p, {"dark_matter": -cost}, "recruit"):
				return _err("INSUFFICIENT_RESOURCES", U.t("Materia Oscura insuficiente (%d)") % cost)
			srv.on_activity(p, "mo_spent", float(cost))
	var od: Dictionary = odds(p)
	var r := RandomNumberGenerator.new()
	r.seed = U.hash_seed("%s:recruit:%d:%d" % [p["id"], int(c.get("recruits", 0)), U.now_ms()])
	var results: Array = []
	var refund: int = 0
	for i: int in range(count):
		var roll: float = r.randf() * 100.0
		var rid: String = "common"
		var acc: float = 0.0
		for rr: Dictionary in cfg().get("rarities", []):
			acc += float(od.get(rr["id"], 0.0))
			if roll <= acc:
				rid = str(rr["id"])
				break
		# Garantía del x10: al menos un Raro o superior.
		if count == 10 and i == 9 and results.all(func(x: Dictionary) -> bool: return x["rarity"] == "common") and rid == "common":
			rid = "rare"
		var pool: Array = (cfg().get("crew", []) as Array).filter(func(x: Dictionary) -> bool: return str(x["rarity"]) == rid)
		var pick: Dictionary = pool[r.randi() % pool.size()]
		var cid: String = str(pick["id"])
		var owned: Dictionary = c["owned"]
		var is_new: bool = not owned.has(cid)
		var stars: int = 1
		if is_new:
			owned[cid] = {"stars": 1, "ts": U.now_ms()}
		else:
			var cur: int = int(owned[cid].get("stars", 1))
			if cur < int(cfg().get("max_stars", 5)):
				owned[cid]["stars"] = cur + 1
				stars = cur + 1
			else:
				stars = cur
				refund += int(cfg().get("dup_refund_credits", {}).get(rid, 100))
		results.append({"id": cid, "rarity": rid, "new": is_new, "stars": stars})
		c["recruits"] = int(c.get("recruits", 0)) + 1
	if refund > 0:
		Eco.apply(p, {"credits": refund}, "recruit_refund")
	refresh_mods(p)
	srv.missions.on_event(p, "crew_recruited", count)
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "results": results, "refund": refund}


func assign(p: Dictionary, crew_id: String, on: bool) -> Dictionary:
	var c: Dictionary = ensure(p)
	if not c["owned"].has(crew_id):
		return _err("NOT_OWNED", U.t("No tienes a ese tripulante"))
	var active: Array = c["active"]
	if on:
		if active.has(crew_id):
			return {"ok": true}
		if deployed(p).has(crew_id):
			return _err("CREW_DEPLOYED", U.t("Ese tripulante viaja en una flota: podrá trabajar en una sala cuando vuelva"))
		if active.size() >= slots(p):
			return _err("NO_SLOTS", U.t("No hay espacios libres: mejora Gestión de Tripulación o retira a alguien"))
		active.append(crew_id)
	else:
		active.erase(crew_id)
	refresh_mods(p)
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


func view(p: Dictionary) -> Dictionary:
	var c: Dictionary = ensure(p)
	# Ajusta los activos si se perdieron espacios.
	while (c["active"] as Array).size() > slots(p):
		(c["active"] as Array).pop_back()
	var owned: Array = []
	var busy: Dictionary = deployed(p)
	for cid: String in c["owned"]:
		var o: Dictionary = c["owned"][cid]
		var lvl: int = level_of(o)
		owned.append({
			"id": cid, "stars": int(o.get("stars", 1)), "bonus": bonus_of(p, cid),
			"level": lvl, "exp": int(o.get("exp", 0)), "exp_next": exp_to_next(lvl), "rank": rank_of(lvl).get("name", ""),
			"grade": grade_of(o), "promote_cost": promote_cost(o), "fleet": str(busy.get(cid, "")),
		})
	return {
		"owned": owned, "active": c["active"], "slots": slots(p), "odds": odds(p),
		"fleet_max": int(cfg().get("fleet", {}).get("max_per_fleet", 5)), "fleet_mult": float(cfg().get("fleet", {}).get("fleet_mult", 1.5)),
		"free": free_available(p), "free_ts": int(c.get("free_ts", 0)), "cantina": Eco.room_level(p, "cantina"),
		"mods": p.get("crew_mods", {}),
	}
