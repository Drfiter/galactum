extends RefCounted
## Resolver de combate de Galactum (Equipo 3, §7 de la spec).
## - Determinista: mismo input + seed => mismo output (RandomNumberGenerator sembrado).
## - Puro: no toca inventarios, mundo ni red. Quien lo invoca aplica el resultado.
## - Versionado: cada resultado incluye `combat_version` para replays tras rebalances.
##
## Orden de capas (spec §7): Escudo Perimetral (solo defensor anclado) -> Escudos
## (absorben el primer daño) -> resto de fuerzas, con matriz de ventaja del
## triángulo Infantería > Drones > Pilotos > Infantería (+30%) y Cañoneros de asedio.

const COMBAT_VERSION: String = "galactum-mvp-1.2"
const DEFENSE_K: float = 50.0


## side = {"stacks": {troop_key: qty}, "mods": {"attack": f, "defense": f, "hp": f}, "perimeter_hp": int}
static func resolve(attacker: Dictionary, defender: Dictionary, seed: int, max_rounds: int = 6) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a: Dictionary = _init_side(attacker)
	var d: Dictionary = _init_side(defender)
	var rounds: Array = []
	for r: int in range(1, max_rounds + 1):
		if _alive_total(a) == 0 or _alive_total(d) == 0:
			break
		var to_d: Dictionary = _deal(a, d, rng)
		var to_a: Dictionary = _deal(d, a, rng)
		var killed_d: int = _apply(d, to_d)
		var killed_a: int = _apply(a, to_a)
		rounds.append({
			"round": r,
			"attacker_damage": int(to_d["total"]),
			"defender_damage": int(to_a["total"]),
			"attacker_kills": killed_d,
			"defender_kills": killed_a,
			"perimeter_left": int(d["perimeter"]),
			"attacker_alive": _alive_total(a),
			"defender_alive": _alive_total(d),
		})
	var outcome: String = "defender_win"
	if _alive_total(d) == 0 and _alive_total(a) > 0:
		outcome = "attacker_win"
	elif _alive_total(a) == 0 and _alive_total(d) == 0:
		outcome = "draw"
	return {
		"combat_version": COMBAT_VERSION,
		"seed": seed,
		"outcome": outcome,
		"rounds": rounds,
		"attacker": _side_result(a),
		"defender": _side_result(d),
	}


## Caza PvE (spec §8): defensor sintético con HP persistente. Las bajas del
## jugador son heridos (van a la Bahía Médica), nunca muertes.
static func resolve_hunt(stacks: Dictionary, mods: Dictionary, weakness: String, level: int, xeno_hp: int, seed: int, bonus_mult: float = 1.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var lvl: Dictionary = Catalog.xeno_level(level)
	var weak_mult: float = float(Catalog.xeno.get("weakness_multiplier", 1.5))
	var rounds_total: int = int(Catalog.xeno.get("rounds", 3))
	var side: Dictionary = _init_side({"stacks": stacks, "mods": mods})
	var hp_left: float = float(xeno_hp)
	var dealt_total: float = 0.0
	var rounds: Array = []
	for r: int in range(1, rounds_total + 1):
		if hp_left <= 0.0 or _alive_total(side) == 0:
			break
		var dmg: float = 0.0
		for key: String in _sorted_keys(side["alive"]):
			var qty: int = int(side["alive"][key])
			if qty <= 0:
				continue
			var type_id: String = Catalog.split_troop_key(key)[0]
			var cls: String = str(Catalog.troop_type(type_id).get("damage_class", "fisica"))
			var hit: float = Catalog.troop_stat(key, "attack") * qty
			hit *= (1.0 + float(mods.get("attack", 0.0)) + float(mods.get("pve_damage", 0.0)))
			hit *= rng.randf_range(0.92, 1.08) * bonus_mult
			if cls == weakness:
				hit *= weak_mult
			dmg += hit
		dmg = minf(dmg, hp_left)
		# El contraataque de la xenoforma es simultáneo.
		var incoming: float = float(lvl.get("attack", 50)) * rng.randf_range(0.9, 1.1)
		var dist: Dictionary = _distribute_plain(side, incoming)
		var wounded_now: int = _apply(side, dist)
		hp_left -= dmg
		dealt_total += dmg
		rounds.append({"round": r, "damage": int(dmg), "xeno_damage": int(incoming), "wounded": wounded_now, "xeno_hp": int(maxf(hp_left, 0.0))})
	var result: Dictionary = _side_result(side)
	return {
		"combat_version": COMBAT_VERSION,
		"seed": seed,
		"damage": int(dealt_total),
		"killed": hp_left <= 0.0,
		"xeno_hp_left": int(maxf(hp_left, 0.0)),
		"rounds": rounds,
		"survivors": result["survivors"],
		"wounded": result["losses"],
	}


# ------------------------------------------------------------------ helpers

static func _init_side(spec: Dictionary) -> Dictionary:
	var alive: Dictionary = {}
	var raw: Dictionary = spec.get("stacks", {})
	for key: String in raw:
		var q: int = int(raw[key])
		if q > 0 and not Catalog.troop_tier(key).is_empty():
			alive[key] = q
	var mods: Dictionary = spec.get("mods", {})
	return {
		"initial": alive.duplicate(),
		"alive": alive,
		"carry": {},
		"losses": {},
		"mods": mods,
		"perimeter": float(spec.get("perimeter_hp", 0)),
		"perimeter_initial": int(spec.get("perimeter_hp", 0)),
	}


static func _sorted_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys


static func _alive_total(side: Dictionary) -> int:
	var t: int = 0
	for k: String in side["alive"]:
		t += int(side["alive"][k])
	return t


static func _type_of(key: String) -> String:
	return str(Catalog.split_troop_key(key)[0])


static func _hp_pool(side: Dictionary, keys: Array) -> float:
	var pool: float = 0.0
	for k: String in keys:
		pool += Catalog.troop_stat(k, "hp") * int(side["alive"][k])
	return pool


static func _defense_factor(side: Dictionary, key: String) -> float:
	var def: float = Catalog.troop_stat(key, "defense") * (1.0 + float(side["mods"].get("defense", 0.0)))
	return DEFENSE_K / (DEFENSE_K + def)


## Daño que `src` inflige a `dst` en una ronda. Devuelve daño por stack destino.
static func _deal(src: Dictionary, dst: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var tri_bonus: float = float(Catalog.troops.get("triangle_bonus", 0.3))
	var siege_mult: float = float(Catalog.troops.get("siege_multiplier", 2.5))
	var siege_vs_tri: float = float(Catalog.troops.get("siege_vs_triangle", 0.75))
	var absorb_share: float = float(Catalog.troops.get("shield_absorb_share", 0.6))
	var out: Dictionary = {"stacks": {}, "perimeter": 0.0, "total": 0.0}
	var perimeter_virtual: float = float(dst["perimeter"])

	var shield_keys: Array = []
	var other_keys: Array = []
	for k: String in _sorted_keys(dst["alive"]):
		if int(dst["alive"][k]) <= 0:
			continue
		if _type_of(k) == "shields":
			shield_keys.append(k)
		else:
			other_keys.append(k)
	var shield_pool: float = _hp_pool(dst, shield_keys)
	var other_pool: float = _hp_pool(dst, other_keys)

	for key: String in _sorted_keys(src["alive"]):
		var qty: int = int(src["alive"][key])
		if qty <= 0:
			continue
		var type_id: String = _type_of(key)
		var raw: float = Catalog.troop_stat(key, "attack") * qty
		raw *= (1.0 + float(src["mods"].get("attack", 0.0))) * rng.randf_range(0.88, 1.12)

		# 1) Escudo Perimetral del defensor anclado.
		if perimeter_virtual > 0.0:
			var pmult: float = siege_mult if type_id == "gunners" else 1.0
			var absorbed: float = minf(raw * pmult, perimeter_virtual)
			perimeter_virtual -= absorbed
			out["perimeter"] += absorbed
			out["total"] += absorbed
			raw -= absorbed / pmult
			if raw <= 0.01:
				continue

		# 2) Escudos absorben primero (los Cañoneros los apuntan por completo).
		var to_shields: float = 0.0
		if not shield_keys.is_empty():
			if type_id == "gunners" or other_keys.is_empty():
				to_shields = raw
			else:
				to_shields = raw * absorb_share
		var to_others: float = raw - to_shields

		if to_shields > 0.0 and shield_pool > 0.0:
			var smult: float = siege_mult if type_id == "gunners" else 1.0
			for sk: String in shield_keys:
				var share: float = Catalog.troop_stat(sk, "hp") * int(dst["alive"][sk]) / shield_pool
				var dmg: float = to_shields * share * smult * _defense_factor(dst, sk)
				out["stacks"][sk] = float(out["stacks"].get(sk, 0.0)) + dmg
				out["total"] += dmg
		# 3) Resto de fuerzas con la matriz de ventaja.
		if to_others > 0.0 and other_pool > 0.0:
			var beats: String = str(Catalog.troop_type(type_id).get("beats", ""))
			for ok: String in other_keys:
				var target_type: String = _type_of(ok)
				var mult: float = 1.0
				if beats == target_type:
					mult += tri_bonus
				elif type_id == "gunners" and target_type in ["infantry", "drones", "pilots"]:
					mult = siege_vs_tri
				var share2: float = Catalog.troop_stat(ok, "hp") * int(dst["alive"][ok]) / other_pool
				var dmg2: float = to_others * share2 * mult * _defense_factor(dst, ok)
				out["stacks"][ok] = float(out["stacks"].get(ok, 0.0)) + dmg2
				out["total"] += dmg2
	return out


## Reparto simple proporcional al HP (contraataque de xenoformas).
static func _distribute_plain(dst: Dictionary, amount: float) -> Dictionary:
	var out: Dictionary = {"stacks": {}, "perimeter": 0.0, "total": amount}
	var keys: Array = []
	for k: String in _sorted_keys(dst["alive"]):
		if int(dst["alive"][k]) > 0:
			keys.append(k)
	var pool: float = _hp_pool(dst, keys)
	if pool <= 0.0:
		return out
	for k: String in keys:
		var share: float = Catalog.troop_stat(k, "hp") * int(dst["alive"][k]) / pool
		out["stacks"][k] = amount * share * _defense_factor(dst, k)
	return out


## Aplica el daño acumulado: convierte daño en bajas con arrastre determinista.
static func _apply(side: Dictionary, dmg: Dictionary) -> int:
	side["perimeter"] = maxf(0.0, float(side["perimeter"]) - float(dmg.get("perimeter", 0.0)))
	var killed_total: int = 0
	var stacks: Dictionary = dmg.get("stacks", {})
	for key: String in _sorted_keys(stacks):
		var qty: int = int(side["alive"].get(key, 0))
		if qty <= 0:
			continue
		var unit_hp: float = Catalog.troop_stat(key, "hp") * (1.0 + float(side["mods"].get("hp", 0.0)))
		var pool: float = float(stacks[key]) + float(side["carry"].get(key, 0.0))
		var kills: int = mini(qty, int(floor(pool / unit_hp)))
		side["carry"][key] = 0.0 if kills >= qty else pool - kills * unit_hp
		side["alive"][key] = qty - kills
		side["losses"][key] = int(side["losses"].get(key, 0)) + kills
		killed_total += kills
	return killed_total


static func _side_result(side: Dictionary) -> Dictionary:
	var survivors: Dictionary = {}
	for k: String in side["alive"]:
		if int(side["alive"][k]) > 0:
			survivors[k] = int(side["alive"][k])
	var losses: Dictionary = {}
	for k: String in side["losses"]:
		if int(side["losses"][k]) > 0:
			losses[k] = int(side["losses"][k])
	return {
		"initial": side["initial"],
		"survivors": survivors,
		"losses": losses,
		"perimeter_initial": side["perimeter_initial"],
		"perimeter_left": int(side["perimeter"]),
	}


static func power_of(stacks: Dictionary) -> int:
	var p: int = 0
	for k: String in stacks:
		p += int(Catalog.troop_tier(k).get("power", 0)) * int(stacks[k])
	return p


static func load_of(stacks: Dictionary, load_bonus: float = 0.0) -> int:
	var l: float = 0.0
	for k: String in stacks:
		l += Catalog.troop_stat(k, "load") * int(stacks[k])
	return int(l * (1.0 + load_bonus))


static func speed_of(stacks: Dictionary) -> float:
	var s: float = INF
	for k: String in stacks:
		if int(stacks[k]) > 0:
			s = minf(s, Catalog.troop_stat(k, "speed"))
	return 1.0 if s == INF else s
