extends RefCounted
## Economía del jugador (Equipo 1 + Equipo 2): saldos, ledger append-only con
## idempotencia, producción lazy (se calcula al consultar, sin jobs por jugador)
## y modificadores derivados de salas e investigación.
##
## Regla de oro: el cliente nunca informa cantidades; todo se calcula aquí.

const U = preload("res://shared/util.gd")
const LEDGER_KEEP: int = 120

## Efectos del evento de recursos activo (los publica server/sgm/events.gd).
static var event_mods: Dictionary = {}


static func event_factor(key: String) -> float:
	return float(event_mods.get(key, 0.0))


static func event_element_gather(element: String) -> float:
	return float(event_mods.get("element_gather", {}).get(element, 0.0))


static func balance(p: Dictionary, res_id: String) -> int:
	if Catalog.items_by_id.has(res_id):
		return int(p["items"].get(res_id, 0))
	return int(p["resources"].get(res_id, 0))


static func can_afford(p: Dictionary, cost: Dictionary, factor: float = 1.0) -> bool:
	for k: String in cost:
		if balance(p, k) < int(ceil(float(cost[k]) * factor)):
			return false
	return true


static func missing(p: Dictionary, cost: Dictionary, factor: float = 1.0) -> Dictionary:
	var out: Dictionary = {}
	for k: String in cost:
		var need: int = int(ceil(float(cost[k]) * factor))
		var have: int = balance(p, k)
		if have < need:
			out[k] = need - have
	return out


## EconomyService.apply: aplica un delta atómico. Si algún saldo quedara
## negativo, no aplica nada (rollback). `idem_key` evita dobles abonos.
static func apply(p: Dictionary, delta: Dictionary, reason: String, idem_key: String = "") -> bool:
	if not idem_key.is_empty():
		var seen: Dictionary = p.get("idem", {})
		if seen.has(idem_key):
			return true
	for k: String in delta:
		if balance(p, k) + int(delta[k]) < 0:
			return false
	for k: String in delta:
		var amount: int = int(delta[k])
		if amount == 0:
			continue
		if Catalog.items_by_id.has(k):
			p["items"][k] = int(p["items"].get(k, 0)) + amount
			if int(p["items"][k]) <= 0:
				p["items"].erase(k)
		else:
			p["resources"][k] = int(p["resources"].get(k, 0)) + amount
	if not idem_key.is_empty():
		var idem: Dictionary = p.get("idem", {})
		idem[idem_key] = U.now_ms()
		if idem.size() > 300:
			var keys: Array = idem.keys()
			keys.sort_custom(func(x: String, y: String) -> bool: return int(idem[x]) < int(idem[y]))
			for i: int in range(keys.size() - 200):
				idem.erase(keys[i])
		p["idem"] = idem
	var ledger: Array = p.get("ledger", [])
	ledger.append({"ts": U.now_ms(), "reason": reason, "delta": delta.duplicate(), "key": idem_key})
	while ledger.size() > LEDGER_KEEP:
		ledger.pop_front()
	p["ledger"] = ledger
	return true


static func negate(cost: Dictionary, factor: float = 1.0) -> Dictionary:
	var out: Dictionary = {}
	for k: String in cost:
		out[k] = -int(ceil(float(cost[k]) * factor))
	return out


# ---------------------------------------------------------------- salas

static func room_level(p: Dictionary, room_id: String) -> int:
	return int(p["rooms"].get(room_id, {}).get("level", 0))


static func effect(p: Dictionary, room_id: String, effect_id: String) -> float:
	var lvl: int = room_level(p, room_id)
	if lvl <= 0:
		return 0.0
	return Catalog.room_effect(room_id, effect_id, lvl)


static func tech_level(p: Dictionary, tech_id: String) -> int:
	return int(p.get("tech", {}).get(tech_id, 0))


## Fuentes de bonificación que se suman al sistema único de modificadores:
## Alianza, tripulación activa, Protocolos de Mando, equipamiento, Licencia de
## Comandante y títulos. Cada una es un Dictionary efecto -> valor en el jugador.
const MOD_SOURCES: Array = ["ally_mods", "crew_mods", "cmd_mods", "gear_mods", "vip_mods", "title_mods", "platform_mods"]


## Salas cuyo efecto se suma directamente a un modificador.
const ROOM_MODS: Dictionary = {
	"march_speed": [["airlock", "march_speed"]],
	"load": [["cargo_bay", "load"]],
	"vault_bonus": [["cargo_bay", "vault_bonus"], ["cloak", "loot_protect"]],
	"capture_chance": [["containment", "capture_chance"]],
	"capture_resist": [["cloak", "capture_resist"]],
}


## Suma de un efecto en todas las fuentes de bonificación del jugador:
## investigación, salas, Alianza, tripulación, Protocolos, equipo, Licencia,
## títulos y Plataformas Orbitales.
static func extra(p: Dictionary, key: String) -> float:
	var total: float = 0.0
	for src: String in MOD_SOURCES:
		total += float(p.get(src, {}).get(key, 0.0))
	for tech_id: String in p.get("tech", {}):
		var t: Dictionary = Catalog.tech(tech_id)
		if str(t.get("effect", "")) == key:
			total += float(t.get("per_level", 0.0)) * int(p["tech"][tech_id])
	for pair: Array in ROOM_MODS.get(key, []):
		total += effect(p, str(pair[0]), str(pair[1]))
	return total


## Sistema único de modificadores (contrato con el combate: el snapshot de
## combate de una flota se congela al despegar).
static func modifiers(p: Dictionary) -> Dictionary:
	var m: Dictionary = {
		"attack": 0.0, "defense": 0.0, "hp": 0.0, "gather_speed": 0.0,
		"load": 0.0, "march_speed": 0.0, "pve_damage": 0.0,
	}
	m["defense_base"] = effect(p, "perimeter", "defense_bonus")
	# Alianza, tripulación, Protocolos, equipamiento, Licencia y títulos.
	for k: String in m.keys():
		if k != "defense_base":
			m[k] = float(m[k]) + extra(p, k)
	m["gather_speed"] = float(m["gather_speed"]) + event_factor("gather_speed")
	m["attack"] = float(m["attack"]) + effect(p, "armory", "attack_bonus")
	m["pve_damage"] = float(m["pve_damage"]) + effect(p, "armory", "pve_bonus")
	return m


static func combat_mods(p: Dictionary, at_home: bool) -> Dictionary:
	var m: Dictionary = modifiers(p)
	var out: Dictionary = {"attack": m["attack"], "defense": m["defense"], "hp": m["hp"], "pve_damage": m["pve_damage"]}
	if at_home:
		out["defense"] = float(out["defense"]) + float(m["defense_base"])
	return out


static func march_slots(p: Dictionary) -> int:
	return int(effect(p, "bridge", "march_slots"))


static func march_capacity(p: Dictionary) -> int:
	return int(effect(p, "fleet_hq", "march_capacity") * (1.0 + extra(p, "march_capacity")))


static func vault_protect(p: Dictionary) -> int:
	return int(effect(p, "vault", "vault_protect") * (1.0 + extra(p, "vault_bonus")))


static func medbay_capacity(p: Dictionary) -> int:
	return int(effect(p, "medbay", "medbay_capacity"))


static func cryo_capacity(p: Dictionary) -> int:
	return int(effect(p, "cryo", "cryo_capacity"))


static func perimeter_hp(p: Dictionary) -> int:
	return int(effect(p, "perimeter", "perimeter_hp"))


static func train_batch(p: Dictionary) -> int:
	return int(effect(p, "hangar", "train_batch"))


static func scout_level(p: Dictionary) -> int:
	return int(effect(p, "sensors", "scout_level"))


static func energy_max() -> int:
	return int(Catalog.xeno.get("energy_max", 100))


# ---------------------------------------------------------------- producción lazy

## Acumula producción desde el último cálculo. La nave en TRAVELING no produce.
static func settle(p: Dictionary, now: int, producing: bool = true) -> void:
	for room_id: String in p["rooms"]:
		var r: Dictionary = p["rooms"][room_id]
		var room_def: Dictionary = Catalog.room(room_id)
		if not room_def.has("produces"):
			continue
		var last: int = int(r.get("last_ts", now))
		r["last_ts"] = now
		if not producing or now <= last:
			continue
		var minutes: float = float(now - last) / 60000.0
		var rates: Dictionary = Catalog.room_production(room_id, int(r["level"]))
		var boost: float = 1.0 + event_factor("production") + extra(p, "production")
		for k: String in rates:
			rates[k] = float(rates[k]) * boost
		var cap_minutes: float = float(room_def.get("storage_minutes", 20))
		var pending: Dictionary = r.get("pending", {})
		for res_id: String in rates:
			var cap: float = float(rates[res_id]) * cap_minutes
			pending[res_id] = minf(cap, float(pending.get(res_id, 0.0)) + float(rates[res_id]) * minutes)
		r["pending"] = pending
	# Energía de caza: +1 cada energy_regen_sec, hasta el máximo.
	var regen_ms: int = int(Catalog.xeno.get("energy_regen_sec", 10)) * 1000
	var ets: int = int(p.get("energy_ts", now))
	var energy: int = int(p["resources"].get("energy", 0))
	if energy >= energy_max():
		p["energy_ts"] = now
	elif now - ets >= regen_ms:
		var gained: int = int((now - ets) / regen_ms)
		p["resources"]["energy"] = mini(energy_max(), energy + gained)
		p["energy_ts"] = ets + gained * regen_ms


static func collect(p: Dictionary, room_id: String = "") -> Dictionary:
	var gained: Dictionary = {}
	for rid: String in p["rooms"]:
		if not room_id.is_empty() and rid != room_id:
			continue
		var r: Dictionary = p["rooms"][rid]
		var pending: Dictionary = r.get("pending", {})
		for res_id: String in pending.keys():
			var whole: int = int(floor(float(pending[res_id])))
			if whole <= 0:
				continue
			gained[res_id] = int(gained.get(res_id, 0)) + whole
			pending[res_id] = float(pending[res_id]) - whole
	if not gained.is_empty():
		apply(p, gained, "collect")
	return gained


static func production_rates(p: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for room_id: String in p["rooms"]:
		var room_def: Dictionary = Catalog.room(room_id)
		if not room_def.has("produces"):
			continue
		var rates: Dictionary = Catalog.room_production(room_id, int(p["rooms"][room_id]["level"]))
		for k: String in rates:
			out[k] = float(out.get(k, 0.0)) + float(rates[k]) * (1.0 + event_factor("production") + extra(p, "production"))
	return out


# ---------------------------------------------------------------- tropas

static func troops_total(stacks: Dictionary) -> int:
	return U.sum_values(stacks)


static func add_troops(target: Dictionary, stacks: Dictionary, factor: float = 1.0) -> void:
	for k: String in stacks:
		var v: int = int(target.get(k, 0)) + int(round(float(stacks[k]) * factor))
		if v > 0:
			target[k] = v
		else:
			target.erase(k)


static func remove_troops(target: Dictionary, stacks: Dictionary) -> bool:
	for k: String in stacks:
		if int(target.get(k, 0)) < int(stacks[k]):
			return false
	for k: String in stacks:
		var v: int = int(target.get(k, 0)) - int(stacks[k])
		if v > 0:
			target[k] = v
		else:
			target.erase(k)
	return true


## Reparto de bajas (spec §7.4): heridos a la Bahía Médica hasta su capacidad
## (el exceso cuenta como muertes); de los muertos el 80% entra al Criosantuario.
## Devuelve {wounded, dead, cryo, lost}.
static func absorb_casualties(p: Dictionary, losses: Dictionary, wounded_share: float) -> Dictionary:
	var result: Dictionary = {"wounded": {}, "dead": {}, "cryo": {}, "lost": {}}
	var med_free: int = maxi(0, medbay_capacity(p) - troops_total(p.get("wounded", {})))
	var keys: Array = losses.keys()
	keys.sort()
	for k: String in keys:
		var total: int = int(losses[k])
		var w: int = int(round(total * wounded_share))
		var take: int = mini(w, med_free)
		med_free -= take
		var dead: int = total - take
		if take > 0:
			result["wounded"][k] = take
		if dead > 0:
			result["dead"][k] = dead
	add_troops(p["wounded"], result["wounded"])
	# Criosantuario: 80% de las bajas mortales queda en criostasis.
	var cryo_free: int = maxi(0, cryo_capacity(p) - troops_total(p.get("cryo", {})))
	for k: String in result["dead"]:
		var dead_k: int = int(result["dead"][k])
		var c: int = mini(int(floor(dead_k * 0.8)), cryo_free)
		cryo_free -= c
		if c > 0:
			result["cryo"][k] = c
		if dead_k - c > 0:
			result["lost"][k] = dead_k - c
	add_troops(p["cryo"], result["cryo"])
	return result


static func lootable(p: Dictionary) -> Dictionary:
	var protect: int = vault_protect(p)
	var out: Dictionary = {}
	for e: String in Catalog.element_ids:
		var amount: int = int(p["resources"].get(e, 0)) - protect
		if amount > 0:
			out[e] = amount
	return out
