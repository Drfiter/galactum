extends RefCounted
## Comandantes controlados por el servidor. Hacen que el sistema se sienta vivo en
## la demo de un solo dispositivo: minan, cazan, se defienden, se vengan y lanzan
## incursiones contra los jugadores (también sirven de bots para el soak test).

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const Resolver = preload("res://server/combat/combat_resolver.gd")

const SYL_A: Array = ["Kor", "Vel", "Zan", "Ryn", "Tal", "Mor", "Ix", "Dra", "Nyx", "Sol", "Vex", "Aru", "Kel", "Orn", "Thal", "Zer", "Qua", "Lyr", "Bram", "Cyr"]
const SYL_B: Array = ["ath", "is", "on", "ex", "ara", "uun", "ix", "ion", "or", "ek", "ia", "ux", "en", "ar", "os"]
const SUFFIX: Array = ["", "", "", "_77", "X", " Prime", "-9", "Rex", " II", "Nova", "_V"]

var srv: Node


func _init(server: Node) -> void:
	srv = server


func _name(rng: RandomNumberGenerator) -> String:
	return "%s%s%s" % [SYL_A[rng.randi() % SYL_A.size()], SYL_B[rng.randi() % SYL_B.size()], SUFFIX[rng.randi() % SUFFIX.size()]]


func _avatar(rng: RandomNumberGenerator) -> String:
	return "p%02d" % rng.randi_range(1, 45)


## Genera los comandantes bot. `player_spawn` permite sembrar rivales novatos
## cerca del jugador para que la demo tenga objetivos alcanzables.
func create_bots(count: int, rng: RandomNumberGenerator, veteran_bonus: float = 0.0) -> void:
	var tags: Array = []
	for a: Dictionary in Catalog.cfg("alliances", []):
		tags.append(a["tag"])
	for i: int in range(count):
		var p: Vector2i = Vector2i(-1, -1)
		for _a: int in range(60):
			var ang: float = rng.randf() * TAU
			var dist: float = rng.randf_range(45.0, 280.0)
			var cand: Vector2 = (srv.world.center + Vector2(cos(ang), sin(ang)) * dist).round()
			if srv.world.is_free(cand, 6.0):
				p = Vector2i(cand)
				break
		if p.x < 0:
			continue
		var d: float = Vector2(p).distance_to(srv.world.center)
		var strength: float = clampf(1.0 - (d - 45.0) / 235.0 + veteran_bonus, 0.0, 1.0)  # 1 en el centro
		var tag: String = tags[rng.randi() % tags.size()]
		spawn_bot(rng, p, strength, tag)


func spawn_bot(rng: RandomNumberGenerator, pos: Vector2i, strength: float, tag: String, name_override: String = "") -> Dictionary:
	var name: String = name_override if not name_override.is_empty() else _name(rng)
	var p: Dictionary = srv.new_player(name, _avatar(rng), tag, true, pos)
	var bridge: int = clampi(1 + int(round(strength * 8.0 + rng.randf_range(-1.0, 1.0))), 1, 10)
	for room_id: String in p["rooms"]:
		p["rooms"][room_id]["level"] = clampi(bridge + rng.randi_range(-2, 0), 1, bridge)
	p["rooms"]["bridge"]["level"] = bridge
	var army: int = int(lerpf(110.0, 1600.0, pow(strength, 1.3)) * rng.randf_range(0.8, 1.2))
	var weights: Array = [rng.randf_range(0.6, 1.4), rng.randf_range(0.6, 1.4), rng.randf_range(0.6, 1.4), rng.randf_range(0.3, 0.9), rng.randf_range(0.2, 0.8)]
	var wsum: float = 0.0
	for w: float in weights:
		wsum += w
	var troops: Dictionary = {}
	var tier: int = 2 if strength > 0.55 else 1
	for i: int in range(Catalog.troop_order.size()):
		var q: int = int(army * weights[i] / wsum)
		if q > 0:
			troops[Catalog.troop_key(Catalog.troop_order[i], tier)] = q
	p["troops"] = troops
	p["bot"] = {
		"strength": strength,
		"target_army": troops.duplicate(),
		"next_action": U.now_ms() + rng.randi_range(2000, 30000),
		"aggression": rng.randf(),
	}
	for e: String in Catalog.element_ids:
		p["resources"][e] = int(lerpf(1400.0, 9000.0, strength) * rng.randf_range(0.6, 1.4))
	p["resources"]["credits"] = int(lerpf(600.0, 5000.0, strength))
	p["resources"]["energy"] = 100
	p["tech"]["kinetic_alloys"] = int(round(strength * 4))
	p["tech"]["ablative_armor"] = int(round(strength * 3))
	if tier == 2:
		p["tech"]["tier2_protocol"] = 1
	return p


func tick(now: int) -> void:
	for p: Dictionary in srv.state["players"].values():
		if not p.get("is_bot", false) or str(p.get("system", "")) != srv.current_system:
			continue
		var b: Dictionary = p["bot"]
		if now < int(b["next_action"]):
			continue
		b["next_action"] = now + srv.rng.randi_range(8000, 26000)
		_regen(p)
		_act(p, now)
	_raids(now)


func _regen(p: Dictionary) -> void:
	# Recupera tropas y recursos lentamente (simula su economía sin simularla entera).
	var target: Dictionary = p["bot"]["target_army"]
	var home_total: Dictionary = p["troops"].duplicate()
	Eco.add_troops(home_total, srv.fleets.troops_in_fleets(p["id"]))
	for k: String in target:
		var missing: int = int(target[k]) - int(home_total.get(k, 0))
		if missing > 0:
			Eco.add_troops(p["troops"], {k: maxi(1, int(ceil(missing * 0.12)))})
	if not p.get("wounded", {}).is_empty():
		Eco.add_troops(p["troops"], p["wounded"])
		p["wounded"] = {}
	var cap: int = int(lerpf(2500.0, 12000.0, float(p["bot"]["strength"])))
	for e: String in Catalog.element_ids:
		p["resources"][e] = mini(cap, int(p["resources"].get(e, 0)) + srv.rng.randi_range(20, 90))
	p["resources"]["energy"] = 100


func _act(p: Dictionary, now: int) -> void:
	var base: Dictionary = srv.world.get_entity(p["base_id"])
	if base.is_empty() or base["state"] != "ANCHORED":
		return
	if srv.fleets.owned_fleets(p["id"]).size() >= Eco.march_slots(p):
		return
	var home: Vector2 = U.v2(base["pos"])
	var roll: float = srv.rng.randf()
	if roll < 0.62:
		var asts: Array = srv.world.nearest_of_kind(home, "asteroid", 38.0, func(e: Dictionary) -> bool: return str(e.get("occupant", "")) == "" and int(e["remaining"]) > 0)
		if asts.is_empty():
			return
		var target: Dictionary = asts[mini(srv.rng.randi() % 3, asts.size() - 1)]
		var troops: Dictionary = _pick_troops(p, 0.25, ["infantry", "shields", "gunners", "pilots", "drones"])
		if not troops.is_empty():
			srv.fleets.start_march(p, "gather", target["id"], troops)
	elif roll < 0.9:
		var max_lvl: int = clampi(1 + int(float(p["bot"]["strength"]) * 4.5), 1, 5)
		var xs: Array = srv.world.nearest_of_kind(home, "xenoform", 40.0, func(e: Dictionary) -> bool: return int(e["level"]) <= max_lvl)
		if xs.is_empty():
			return
		var troops2: Dictionary = _pick_troops(p, 0.35, ["drones", "pilots", "infantry", "gunners"])
		if not troops2.is_empty():
			srv.fleets.start_march(p, "hunt", xs[0]["id"], troops2)
	else:
		# Escaramuzas entre bots de distintas alianzas: el mapa tiene combates visibles.
		var bases: Array = srv.world.nearest_of_kind(home, "base", 70.0, func(e: Dictionary) -> bool: return _is_bot_rival(p, e, now))
		if bases.is_empty():
			return
		var troops3: Dictionary = _pick_troops(p, 0.5, ["infantry", "drones", "pilots", "gunners", "shields"])
		if not troops3.is_empty():
			srv.fleets.start_march(p, "attack", bases[0]["id"], troops3)


func _pick_troops(p: Dictionary, share: float, prefer: Array) -> Dictionary:
	var cap: int = Eco.march_capacity(p)
	var out: Dictionary = {}
	var total: int = 0
	var keys: Array = p["troops"].keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return prefer.find(Catalog.split_troop_key(a)[0]) < prefer.find(Catalog.split_troop_key(b)[0]))
	for k: String in keys:
		var q: int = mini(int(int(p["troops"][k]) * share), cap - total)
		if q > 0:
			out[k] = q
			total += q
		if total >= cap:
			break
	return out


# ---------------------------------------------------------------- incursiones

func _raids(now: int) -> void:
	for p: Dictionary in srv.state["players"].values():
		if p.get("is_bot", false) or str(p.get("system", "")) != srv.current_system:
			continue
		if not srv.is_player_online(p["id"]):
			continue
		var next: int = int(p.get("next_raid", 0))
		if next == 0:
			p["next_raid"] = now + _raid_interval()
			continue
		if now < next:
			continue
		p["next_raid"] = now + _raid_interval()
		# Respeta la protección de novato, el escudo y el avance del onboarding.
		if int(p.get("protected_until", 0)) > now or int(p.get("shield_until", 0)) > now:
			continue
		if int(p.get("missions", {}).get("index", 0)) < 4:
			continue
		var why: String = launch_raid(p, now, srv.rng.randf() < 0.3)
		if not why.is_empty() and srv.verbose:
			print("raid skipped: ", why)


func _raid_interval() -> int:
	var r: Array = Catalog.cfg("raid_interval_sec", [300, 480])
	return srv.rng.randi_range(int(r[0]), int(r[1])) * 1000


## Lanza una incursión de un bot cercano de otra alianza contra el jugador
## (o contra una de sus flotas mineras: tile hitting).
func launch_raid(target: Dictionary, now: int, prefer_fleet: bool = false) -> String:
	var base: Dictionary = srv.world.get_entity(target["base_id"])
	if base.is_empty() or base["state"] != "ANCHORED":
		return U.t("La nave objetivo no está anclada")
	var target_power: int = Resolver.power_of(target["troops"])
	var home: Vector2 = U.v2(base["pos"])
	var candidates: Array = srv.world.nearest_of_kind(home, "base", 130.0, func(e: Dictionary) -> bool: return _is_raider(target, e, home))
	if candidates.is_empty():
		return U.t("No hay comandantes hostiles cerca")
	var bot: Dictionary = {}
	for c: Dictionary in candidates.slice(0, 8):
		var o: Dictionary = srv.player(c["owner"])
		if srv.fleets.owned_fleets(o["id"]).size() < Eco.march_slots(o):
			bot = o
			break
	if bot.is_empty():
		return U.t("Los hostiles cercanos tienen sus flotas ocupadas")
	# Ejército a la medida: desafiante pero vencible con buena defensa.
	var budget_power: int = int(maxf(140.0, target_power * srv.rng.randf_range(0.55, 0.95)))
	var troops: Dictionary = {}
	var cap: int = Eco.march_capacity(bot)
	var per_type: int = maxi(8, int(budget_power / 2.0 / 4.0))
	var mix: Array = ["infantry", "drones", "pilots", "gunners"]
	for t: String in mix:
		troops[Catalog.troop_key(t, 1)] = mini(per_type, cap / 4)
	Eco.add_troops(bot["troops"], troops)  # refuerzo para garantizar la incursión
	var target_id: String = target["base_id"]
	if prefer_fleet:
		for f: Dictionary in srv.fleets.owned_fleets(target["id"]):
			if f["state"] == "working":
				target_id = f["target_id"]
				break
	var res: Dictionary = srv.fleets.start_march(bot, "attack", target_id, troops)
	return "" if bool(res.get("ok", false)) else str(res.get("message", "error"))


func on_attacked(bot: Dictionary, attacker: Dictionary) -> void:
	if attacker.get("is_bot", false):
		return
	if srv.rng.randf() < 0.5:
		var at: int = U.now_ms() + srv.rng.randi_range(60000, 120000)
		var next: int = int(attacker.get("next_raid", 0))
		attacker["next_raid"] = mini(next, at) if next > 0 else at
		srv.social.post(str(bot.get("tag", "")), bot["name"], U.t("%s nos atacó. Prepararé una respuesta.") % attacker["name"])


func _is_bot_rival(p: Dictionary, e: Dictionary, now: int) -> bool:
	if e["owner"] == p["id"] or e["state"] != "ANCHORED":
		return false
	var o: Dictionary = srv.player(e["owner"])
	return bool(o.get("is_bot", false)) and str(o.get("tag", "")) != str(p.get("tag", "")) and int(o.get("shield_until", 0)) <= now


func _is_raider(target: Dictionary, e: Dictionary, home: Vector2) -> bool:
	var o: Dictionary = srv.player(e["owner"])
	return bool(o.get("is_bot", false)) and str(o.get("tag", "")) != str(target.get("tag", "")) and U.v2(e["pos"]).distance_to(home) >= 35.0
