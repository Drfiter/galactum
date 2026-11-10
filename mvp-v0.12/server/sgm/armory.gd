extends RefCounted
## Armería y equipamiento (feedback del 26/10: "las cazas no dan ninguno de los
## 150 materiales de equipamiento; sin esto no existe el segundo motor de poder").
##
## - 150 materiales: las cazas sueltan el de la especie (calidad = nivel de la
##   xenoforma) y la minería, los de forja (calidad = nivel del asteroide).
## - 90 equipos (15 conjuntos × 6 ranuras) que se forjan con materiales y
##   Créditos y se mejoran hasta el nivel 5. El nivel de la Armería limita el
##   escalón que se puede forjar.
## - El Comandante equipa una pieza por ranura; sus estadísticas y los bonos de
##   conjunto (3 y 6 piezas) entran al sistema de modificadores como `gear_mods`.
## - Refinar: 4 materiales de una calidad dan 1 de la calidad siguiente.
## Los materiales se guardan como recursos del jugador (ledger con idempotencia).

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.armory


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func ensure(p: Dictionary) -> Dictionary:
	if not p.has("gear"):
		p["gear"] = {"owned": {}, "equipped": {}}
	return p["gear"]


## Escalón máximo que permite forjar la Armería actual (0 = sin construir).
func tier_max(p: Dictionary) -> int:
	var table: Array = cfg().get("tier_by_armory_level", [0])
	var lvl: int = clampi(Eco.room_level(p, "armory"), 0, table.size() - 1)
	return int(table[lvl])


func _scaled(recipe: Dictionary, mult: int) -> Dictionary:
	var out: Dictionary = {}
	for k: String in recipe:
		out[k] = int(recipe[k]) * mult
	return out


func forge_cost(eq: Dictionary) -> Dictionary:
	var cost: Dictionary = (eq.get("recipe", {}) as Dictionary).duplicate()
	cost["credits"] = int(eq.get("credits", 0))
	return cost


## Mejorar del nivel `lvl` al siguiente cuesta la receta × lvl y más Créditos.
func upgrade_cost(eq: Dictionary, lvl: int) -> Dictionary:
	var cost: Dictionary = _scaled(eq.get("recipe", {}), lvl)
	cost["credits"] = int(cfg().get("upgrade_credits", 900)) * int(eq["tier"]) * lvl
	return cost


func forge(p: Dictionary, eq_id: String) -> Dictionary:
	var eq: Dictionary = Catalog.equipment_by_id.get(eq_id, {})
	if eq.is_empty():
		return _err("UNKNOWN_EQUIPMENT", U.t("Equipo desconocido"))
	var g: Dictionary = ensure(p)
	if g["owned"].has(eq_id):
		return _err("ALREADY_OWNED", U.t("Ya tienes ese equipo: mejóralo"))
	if int(eq["tier"]) > tier_max(p):
		return _err("ARMORY_LEVEL", U.t("Mejora la Armería para forjar equipos de escalón %d") % int(eq["tier"]))
	if not Eco.apply(p, Eco.negate(forge_cost(eq)), "armory_forge", "forge:%s" % eq_id):
		return _err("INSUFFICIENT_RESOURCES", U.t("Faltan materiales o Créditos"))
	g["owned"][eq_id] = 1
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "level": 1}


func upgrade(p: Dictionary, eq_id: String) -> Dictionary:
	var eq: Dictionary = Catalog.equipment_by_id.get(eq_id, {})
	var g: Dictionary = ensure(p)
	if eq.is_empty() or not g["owned"].has(eq_id):
		return _err("NOT_OWNED", U.t("No tienes ese equipo"))
	var lvl: int = int(g["owned"][eq_id])
	if lvl >= int(cfg().get("max_level", 5)):
		return _err("MAX_LEVEL", U.t("Ese equipo ya está al nivel máximo"))
	if not Eco.apply(p, Eco.negate(upgrade_cost(eq, lvl)), "armory_upgrade", "upgrade:%s:%d" % [eq_id, lvl + 1]):
		return _err("INSUFFICIENT_RESOURCES", U.t("Faltan materiales o Créditos"))
	g["owned"][eq_id] = lvl + 1
	refresh_mods(p)
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "level": lvl + 1}


func equip(p: Dictionary, eq_id: String) -> Dictionary:
	var eq: Dictionary = Catalog.equipment_by_id.get(eq_id, {})
	var g: Dictionary = ensure(p)
	if eq.is_empty() or not g["owned"].has(eq_id):
		return _err("NOT_OWNED", U.t("No tienes ese equipo"))
	g["equipped"][str(eq["slot"])] = eq_id
	refresh_mods(p)
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


func unequip(p: Dictionary, slot: String) -> Dictionary:
	ensure(p)["equipped"].erase(slot)
	refresh_mods(p)
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


func refine(p: Dictionary, mat_id: String, times: int = 1) -> Dictionary:
	var m: Dictionary = Catalog.materials_by_id.get(mat_id, {})
	if m.is_empty():
		return _err("UNKNOWN_MATERIAL", U.t("Material desconocido"))
	if int(m["grade"]) >= 5:
		return _err("MAX_GRADE", U.t("Ese material ya tiene la calidad máxima"))
	times = clampi(times, 1, 100)
	var n_in: int = int(cfg().get("refine_in", 4))
	var next_id: String = "mat_%s_%d" % [m["family"], int(m["grade"]) + 1]
	if not Eco.apply(p, {mat_id: -n_in * times, next_id: times}, "armory_refine"):
		return _err("INSUFFICIENT_RESOURCES", U.t("Necesitas %d de ese material por cada refinado") % n_in)
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "made": next_id, "count": times}


## Estadísticas del equipo puesto y bonos de conjunto -> gear_mods.
func refresh_mods(p: Dictionary) -> void:
	var g: Dictionary = ensure(p)
	var mods: Dictionary = {}
	var step: float = float(cfg().get("level_step", 0.25))
	var per_set: Dictionary = {}
	for slot: String in g["equipped"]:
		var eq_id: String = str(g["equipped"][slot])
		var eq: Dictionary = Catalog.equipment_by_id.get(eq_id, {})
		if eq.is_empty() or not g["owned"].has(eq_id):
			continue
		var mult: float = 1.0 + step * (int(g["owned"][eq_id]) - 1)
		for k: String in eq.get("stats", {}):
			mods[k] = float(mods.get(k, 0.0)) + float(eq["stats"][k]) * mult
		per_set[eq["set"]] = int(per_set.get(eq["set"], 0)) + 1
	for set_id: String in per_set:
		var tier: int = _set_tier(set_id)
		for b: Dictionary in cfg().get("set_bonus", []):
			if int(per_set[set_id]) >= int(b["pieces"]):
				mods[b["effect"]] = float(mods.get(b["effect"], 0.0)) + float(b["per_tier"]) * tier
	p["gear_mods"] = mods
	if p.has("crew"):
		srv.crew.refresh_mods(p)


func _set_tier(set_id: String) -> int:
	for s: Dictionary in cfg().get("sets", []):
		if str(s["id"]) == set_id:
			return int(s["tier"])
	return 1


# ---------------------------------------------------------------- botín

## Material de la especie al cazar (calidad = nivel de la xenoforma).
func hunt_drop(species: String, level: int, killed: bool) -> Dictionary:
	var counts: Array = cfg().get("drops", {}).get("hunt_count", [2, 3, 3, 4, 5])
	var n: int = int(counts[clampi(level, 1, counts.size()) - 1])
	if not killed:
		n = int(n / 2)
	if n <= 0:
		return {}
	return {"mat_x_%s_%d" % [species, clampi(level, 1, 5)]: n}


## Material de forja al terminar de minar (calidad = nivel del asteroide).
func mining_drop(asteroid_id: String, level: int) -> Dictionary:
	var forge: Array = (cfg().get("families", []) as Array).filter(func(f: Dictionary) -> bool: return str(f.get("source", "")) == "mining")
	if forge.is_empty():
		return {}
	var counts: Array = cfg().get("drops", {}).get("mining_count", [1, 2, 2, 3, 3])
	var fam: Dictionary = forge[U.hash_seed(asteroid_id) % forge.size()]
	return {"mat_%s_%d" % [fam["id"], clampi(level, 1, 5)]: int(counts[clampi(level, 1, counts.size()) - 1])}


# ---------------------------------------------------------------- vista

func view(p: Dictionary) -> Dictionary:
	var g: Dictionary = ensure(p)
	var mats: Dictionary = {}
	for k: String in p["resources"]:
		if str(k).begins_with("mat_") and int(p["resources"][k]) > 0:
			mats[k] = int(p["resources"][k])
	return {"owned": g["owned"], "equipped": g["equipped"], "mods": p.get("gear_mods", {}), "tier_max": tier_max(p), "materials": mats}
