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


## Valor de la pasiva de un tripulante (rareza × estrellas × Gestión de Tripulación).
func bonus_of(p: Dictionary, crew_id: String) -> float:
	var d: Dictionary = def(crew_id)
	var owned: Dictionary = ensure(p)["owned"].get(crew_id, {})
	if d.is_empty() or owned.is_empty():
		return 0.0
	var mult: float = float(rarity(str(d["rarity"])).get("mult", 1.0))
	var stars: int = int(owned.get("stars", 1))
	var room_boost: float = 1.0 + Eco.effect(p, "crew", "crew_power")
	return float(cfg().get("base_bonus", 0.03)) * mult * (1.0 + float(cfg().get("star_bonus", 0.2)) * (stars - 1)) * room_boost


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
	for cid: String in c["owned"]:
		owned.append({"id": cid, "stars": int(c["owned"][cid].get("stars", 1)), "bonus": bonus_of(p, cid)})
	return {
		"owned": owned, "active": c["active"], "slots": slots(p), "odds": odds(p),
		"free": free_available(p), "free_ts": int(c.get("free_ts", 0)), "cantina": Eco.room_level(p, "cantina"),
		"mods": p.get("crew_mods", {}),
	}
