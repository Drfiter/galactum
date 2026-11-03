extends RefCounted
## Flotas (marchas) del SSS (Equipo 3 §4-§8).
## Cada flota se modela por (origen, destino, depart_ts, arrive_ts): la posición se
## deriva del tiempo. El cliente solo envía intenciones; aquí se valida todo.
##
## Misiones: gather (minar), hunt (cazar xenoforma), attack (nave anclada o flota
## minera = tile hitting), scout (espionaje). Al terminar, la flota vuelve y su
## carga se abona con clave de idempotencia del viaje (economy.apply).

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const Resolver = preload("res://server/combat/combat_resolver.gd")

const ATTACKER_WOUNDED_SHARE: float = 0.6

var srv: Node


func _init(server: Node) -> void:
	srv = server


func fleets() -> Dictionary:
	return srv.cur["fleets"]


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func owned_fleets(pid: String) -> Array:
	var out: Array = []
	for id: String in fleets():
		if fleets()[id]["owner"] == pid:
			out.append(fleets()[id])
	return out


func troops_in_fleets(pid: String) -> Dictionary:
	var out: Dictionary = {}
	for f: Dictionary in owned_fleets(pid):
		Eco.add_troops(out, f["troops"])
		Eco.add_troops(out, f.get("wounded", {}))
	return out


func position_of(f: Dictionary, now: int) -> Vector2:
	if f["state"] == "working":
		return U.v2(f["target"])
	return U.lerp_path(U.v2(f["origin"]), U.v2(f["target"]), int(f["depart_ts"]), int(f["arrive_ts"]), now)


func _bump(f: Dictionary) -> void:
	f["rev"] = int(f.get("rev", 0)) + 1


# ---------------------------------------------------------------- envío

func start_march(p: Dictionary, mission: String, target_id: String, troops: Dictionary) -> Dictionary:
	var now: int = U.now_ms()
	var base: Dictionary = srv.world.get_entity(p["base_id"])
	if base.is_empty():
		return _err("NO_BASE", U.t("Tu nave no existe"))
	if base["state"] != "ANCHORED":
		return _err("SHIP_NOT_ANCHORED", U.t("La Astronave está en tránsito"))
	if owned_fleets(p["id"]).size() >= Eco.march_slots(p):
		return _err("NO_MARCH_SLOTS", U.t("No tienes flotas libres (mejora el Puente de Mando)"))
	var target: Dictionary = srv.world.get_entity(target_id)
	if target.is_empty():
		return _err("TARGET_NOT_FOUND", U.t("El objetivo ya no existe"))
	var clean: Dictionary = {}
	for k: String in troops:
		var q: int = int(troops[k])
		if q > 0:
			if Catalog.troop_tier(k).is_empty():
				return _err("TROOP_UNKNOWN", U.t("Fuerza desconocida"))
			clean[k] = q
	var mods: Dictionary = Eco.modifiers(p)
	match mission:
		"gather":
			if target["kind"] != "asteroid":
				return _err("INVALID_TARGET", U.t("Solo se puede minar un asteroide"))
			if int(target["remaining"]) <= 0:
				return _err("MINING_DEPLETED", U.t("El asteroide está agotado"))
			var occ: Dictionary = fleets().get(str(target.get("occupant", "")), {})
			if not occ.is_empty():
				return _err("MINING_ASTEROID_OCCUPIED", U.t("Otra flota está minando ese asteroide"))
			for f: Dictionary in owned_fleets(p["id"]):
				if f["target_id"] == target_id and f["mission"] == "gather":
					return _err("ALREADY_SENT", U.t("Ya enviaste una flota a ese asteroide"))
		"hunt":
			if target["kind"] != "xenoform":
				return _err("INVALID_TARGET", U.t("Solo se pueden cazar xenoformas"))
			var cost: int = hunt_energy(int(target["level"]))
			if int(p["resources"].get("energy", 0)) < cost:
				return _err("NO_ENERGY", U.t("Energía insuficiente (%d)") % cost)
		"attack":
			var err: Dictionary = _validate_attack_target(p, target)
			if not err.is_empty():
				return err
		"scout":
			if target["kind"] != "base" or target["owner"] == p["id"]:
				return _err("INVALID_TARGET", U.t("Solo puedes espiar naves de otros comandantes"))
			if not Eco.apply(p, {"credits": -int(Catalog.cfg("scout_cost_credits", 50))}, "scout"):
				return _err("INSUFFICIENT_RESOURCES", U.t("Créditos insuficientes"))
			clean = {}
		_:
			return _err("INVALID_MISSION", U.t("Misión desconocida"))
	if mission != "scout":
		if clean.is_empty():
			return _err("NO_TROOPS", U.t("Selecciona al menos una fuerza"))
		if Eco.troops_total(clean) > Eco.march_capacity(p):
			return _err("CAPACITY", U.t("Supera la capacidad de la flota (%d)") % Eco.march_capacity(p))
		if not Eco.remove_troops(p["troops"], clean):
			return _err("NOT_ENOUGH_TROOPS", U.t("No tienes esas fuerzas en la nave"))
	if mission == "hunt":
		Eco.apply(p, {"energy": -hunt_energy(int(target["level"]))}, "hunt_energy")
	if mission == "attack":
		p["shield_until"] = 0  # Atacar rompe el Campo de Distorsión.
		srv.bump_base_of(p["id"])

	var origin: Vector2 = U.v2(base["pos"])
	var dest: Vector2 = U.v2(target["pos"])
	var speed: float
	if mission == "scout":
		speed = float(Catalog.cfg("scout_speed_tiles_per_sec", 4.0))
	else:
		speed = Resolver.speed_of(clean) * float(Catalog.cfg("march_speed_tiles_per_sec", 1.6)) * (1.0 + float(mods["march_speed"]))
	var travel_ms: int = maxi(2500, int(origin.distance_to(dest) / speed * 1000.0))
	var f: Dictionary = {
		"id": "flt_%s" % U.new_id(),
		"owner": p["id"],
		"mission": mission,
		"target_id": target_id,
		"target_kind": target["kind"],
		"target_owner": str(target.get("owner", "")),
		"origin": U.arr2(origin),
		"target": U.arr2(dest),
		"depart_ts": now,
		"arrive_ts": now + travel_ms,
		"state": "outbound",
		"troops": clean,
		"wounded": {},
		"cargo": {},
		"speed": speed,
		"mods": Eco.combat_mods(p, false),
		"load_bonus": float(mods["load"]),
		"gather_bonus": float(mods["gather_speed"]),
		"rev": 1,
	}
	if target["kind"] == "asteroid" and mission == "attack":
		f["target_fleet"] = str(target.get("occupant", ""))
		var occ2: Dictionary = fleets().get(f["target_fleet"], {})
		f["target_owner"] = str(occ2.get("owner", ""))
	fleets()[f["id"]] = f
	srv.mark_player_dirty(p["id"])
	if not f["target_owner"].is_empty():
		srv.mark_player_dirty(f["target_owner"])
		if mission == "attack":
			srv.notify(f["target_owner"], U.t("¡%s envía una flota de ataque contra ti!") % srv.display_name(p["id"]), "danger")
		elif mission == "scout":
			srv.notify(f["target_owner"], U.t("Sensores: una sonda de %s se aproxima") % srv.display_name(p["id"]), "warning")
	match mission:
		"gather":
			srv.missions.on_event(p, "gather_started", 1)
		"scout":
			pass
	return {"ok": true, "fleet_id": f["id"], "arrive_ts": f["arrive_ts"]}


func hunt_energy(level: int) -> int:
	return maxi(1, int(round(float(Catalog.xeno_level(level).get("energy", 10)) * (1.0 + Eco.event_factor("hunt_energy")))))


func _validate_attack_target(p: Dictionary, target: Dictionary) -> Dictionary:
	if target["kind"] == "base":
		if target["owner"] == p["id"]:
			return _err("CANNOT_ATTACK_OWN_SHIP", U.t("No puedes atacar tu propia nave"))
		var other: Dictionary = srv.player(target["owner"])
		if not other.is_empty() and str(other.get("tag", "")) == str(p.get("tag", "")) and str(p.get("tag", "")) != "":
			return _err("SAME_ALLIANCE", U.t("No puedes atacar a un miembro de tu Alianza"))
		if target["state"] != "ANCHORED":
			return _err("TARGET_NOT_ANCHORED", U.t("La nave objetivo está en tránsito (warp)"))
		if int(other.get("shield_until", 0)) > U.now_ms():
			return _err("TARGET_SHIELDED", U.t("La nave tiene un Campo de Distorsión activo"))
		if int(other.get("protected_until", 0)) > U.now_ms():
			return _err("TARGET_PROTECTED", U.t("Comandante novato protegido"))
		return {}
	if target["kind"] == "asteroid":
		var occ: Dictionary = fleets().get(str(target.get("occupant", "")), {})
		if occ.is_empty():
			return _err("NO_OCCUPANT", U.t("No hay ninguna flota minando ahí"))
		if occ["owner"] == p["id"]:
			return _err("CANNOT_ATTACK_OWN_FLEET", U.t("Esa flota es tuya"))
		var other2: Dictionary = srv.player(occ["owner"])
		if str(other2.get("tag", "")) == str(p.get("tag", "")) and str(p.get("tag", "")) != "":
			return _err("SAME_ALLIANCE", U.t("Es una flota de tu Alianza"))
		return {}
	return _err("INVALID_TARGET", U.t("Objetivo no atacable"))


func recall(p: Dictionary, fleet_id: String) -> Dictionary:
	var f: Dictionary = fleets().get(fleet_id, {})
	if f.is_empty() or f["owner"] != p["id"]:
		return _err("FLEET_NOT_FOUND", U.t("Flota no encontrada"))
	var now: int = U.now_ms()
	match f["state"]:
		"outbound":
			_start_return(f, now, position_of(f, now))
		"working":
			_stop_mining(f, now)
			_start_return(f, now, U.v2(f["target"]))
		_:
			return _err("ALREADY_RETURNING", U.t("La flota ya está regresando"))
	return {"ok": true}


# ---------------------------------------------------------------- simulación

func tick(now: int) -> void:
	var ids: Array = fleets().keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(fleets()[a]["arrive_ts"]) < int(fleets()[b]["arrive_ts"]))
	for id: String in ids:
		if not fleets().has(id):
			continue
		var f: Dictionary = fleets()[id]
		match f["state"]:
			"outbound":
				if now >= int(f["arrive_ts"]):
					_arrive(f, int(f["arrive_ts"]))
			"working":
				if now >= int(f["work_end"]):
					_finish_mining(f, int(f["work_end"]))
			"returning":
				if now >= int(f["arrive_ts"]):
					_return_home(f)
	_process_relocations(now)


func _arrive(f: Dictionary, now: int) -> void:
	match f["mission"]:
		"gather":
			_arrive_gather(f, now)
		"hunt":
			_arrive_hunt(f, now)
		"attack":
			if f["target_kind"] == "base":
				_arrive_attack_base(f, now)
			else:
				_arrive_tile_hit(f, now)
		"scout":
			_arrive_scout(f, now)
		_:
			_start_return(f, now, U.v2(f["target"]))


func _start_return(f: Dictionary, now: int, from: Vector2) -> void:
	var p: Dictionary = srv.player(f["owner"])
	var base: Dictionary = srv.world.get_entity(str(p.get("base_id", "")))
	var home: Vector2 = U.v2(base.get("pos", [0, 0]))
	if Eco.troops_total(f["troops"]) + Eco.troops_total(f["wounded"]) <= 0 and f["mission"] != "scout":
		# Sin supervivientes: la flota desaparece en el sitio.
		fleets().erase(f["id"])
		srv.mark_player_dirty(f["owner"])
		return
	var speed: float = float(f.get("speed", 1.0))
	if f["mission"] != "scout" and not f["troops"].is_empty():
		speed = Resolver.speed_of(f["troops"]) * float(Catalog.cfg("march_speed_tiles_per_sec", 1.6)) * (1.0 + float(Eco.modifiers(p)["march_speed"]))
	f["origin"] = U.arr2(from)
	f["target"] = U.arr2(home)
	f["depart_ts"] = now
	f["arrive_ts"] = now + maxi(1500, int(from.distance_to(home) / maxf(0.1, speed) * 1000.0))
	f["state"] = "returning"
	_bump(f)
	srv.mark_player_dirty(f["owner"])


func _return_home(f: Dictionary) -> void:
	var p: Dictionary = srv.player(f["owner"])
	fleets().erase(f["id"])
	if p.is_empty():
		return
	Eco.add_troops(p["troops"], f["troops"])
	# Heridos que vuelven: a la Bahía Médica hasta su capacidad, el resto al Criosantuario.
	if not f["wounded"].is_empty():
		Eco.absorb_casualties(p, f["wounded"], 1.0)
	var cargo: Dictionary = f.get("cargo", {})
	if not cargo.is_empty():
		Eco.apply(p, cargo, "fleet_delivery:%s" % f["mission"], "fleet:%s:deliver" % f["id"])
		srv.missions.on_event(p, "resources_delivered", U.sum_values(cargo))
		srv.on_activity(p, "resources", float(U.sum_values(cargo)))
		if f["mission"] == "gather" and not p.get("is_bot", false):
			srv.notify(p["id"], U.t("Flota minera de regreso: +%s") % _cargo_text(cargo), "success")
	srv.mark_player_dirty(p["id"])
	srv.bump_base_of(p["id"])


func _cargo_text(cargo: Dictionary) -> String:
	var parts: Array = []
	for k: String in cargo:
		parts.append("%s %s" % [U.fmt_num(int(cargo[k])), Catalog.res_name(k)])
	return ", ".join(parts)


# ---------------------------------------------------------------- minería

func _arrive_gather(f: Dictionary, now: int) -> void:
	var ast: Dictionary = srv.world.get_entity(f["target_id"])
	if ast.is_empty() or int(ast.get("remaining", 0)) <= 0:
		_note(f, U.t("El asteroide desapareció antes de tu llegada"))
		_start_return(f, now, U.v2(f["target"]))
		return
	var occ: String = str(ast.get("occupant", ""))
	if not occ.is_empty() and fleets().has(occ) and occ != f["id"]:
		_note(f, U.t("Asteroide ocupado por otra flota"))
		_start_return(f, now, U.v2(f["target"]))
		return
	var lvl: Dictionary = Catalog.asteroid_level(int(ast["level"]))
	var rate: float = float(lvl.get("rate", 10)) * (1.0 + float(f.get("gather_bonus", 0.0)) + Eco.event_element_gather(str(ast["element"])))
	var cap: int = Resolver.load_of(f["troops"], float(f.get("load_bonus", 0.0)))
	var amount: int = mini(cap, int(ast["remaining"]))
	ast["occupant"] = f["id"]
	srv.world.bump(ast)
	f["state"] = "working"
	f["work_start"] = now
	f["work_rate"] = rate
	f["work_amount"] = amount
	f["work_end"] = now + int(amount / rate * 1000.0)
	f["element"] = ast["element"]
	_bump(f)
	srv.mark_player_dirty(f["owner"])


func mined_so_far(f: Dictionary, now: int) -> int:
	if f["state"] != "working":
		return 0
	var secs: float = float(now - int(f["work_start"])) / 1000.0
	return mini(int(f["work_amount"]), int(secs * float(f["work_rate"])))


func _stop_mining(f: Dictionary, now: int) -> void:
	var amount: int = mined_so_far(f, now)
	var ast: Dictionary = srv.world.get_entity(f["target_id"])
	_collect_from_asteroid(f, ast, amount)


func _collect_from_asteroid(f: Dictionary, ast: Dictionary, amount: int) -> void:
	if amount > 0:
		f["cargo"][f["element"]] = int(f["cargo"].get(f["element"], 0)) + amount
	if ast.is_empty():
		return
	ast["remaining"] = maxi(0, int(ast["remaining"]) - amount)
	if str(ast.get("occupant", "")) == f["id"]:
		ast["occupant"] = ""
	srv.world.bump(ast)
	if int(ast["remaining"]) <= 0:
		srv.world.remove_entity(ast["id"])
		srv.world.schedule_respawn(ast, float(Catalog.asteroids.get("respawn_sec", 60)))


func _finish_mining(f: Dictionary, now: int) -> void:
	var ast: Dictionary = srv.world.get_entity(f["target_id"])
	_collect_from_asteroid(f, ast, int(f["work_amount"]))
	_start_return(f, now, U.v2(f["target"]))


# ---------------------------------------------------------------- caza PvE

func _arrive_hunt(f: Dictionary, now: int) -> void:
	var p: Dictionary = srv.player(f["owner"])
	var x: Dictionary = srv.world.get_entity(f["target_id"])
	if x.is_empty() or int(x.get("hp", 0)) <= 0:
		_note(f, U.t("La xenoforma ya fue abatida por otro comandante"))
		var refund: int = 5
		Eco.apply(p, {"energy": refund}, "hunt_refund")
		_start_return(f, now, U.v2(f["target"]))
		return
	var species: Dictionary = Catalog.species_by_id.get(x["species"], {})
	var lvl: int = int(x["level"])
	# Bono por caza consecutiva de la misma especie (spec §8).
	var streak: Dictionary = p.get("hunt_streak", {})
	var count: int = int(streak.get(x["species"], 0))
	var curve: Array = Catalog.xeno.get("consecutive_bonus", [0])
	var bonus: float = float(curve[mini(count, curve.size() - 1)])
	var seed: int = U.hash_seed(f["id"] + ":hunt")
	var res: Dictionary = Resolver.resolve_hunt(f["troops"], f["mods"], str(species.get("weakness", "")), lvl, int(x["hp"]), seed, 1.0 + bonus)
	x["hp"] = int(res["xeno_hp_left"])
	srv.on_activity(p, "troops_lost", Catalog.troops_value_mo(res["wounded"]) * 0.25)
	srv.world.bump(x)
	f["troops"] = res["survivors"]
	Eco.add_troops(f["wounded"], res["wounded"])
	var lvl_data: Dictionary = Catalog.xeno_level(lvl)
	var rewards: Dictionary = {}
	var frac: float = clampf(float(res["damage"]) / float(maxi(1, int(x["max_hp"]))), 0.0, 1.0)
	rewards["credits"] = int(float(lvl_data["rewards"].get("credits", 100)) * 0.35 * frac)
	if res["killed"]:
		for k: String in lvl_data.get("rewards", {}):
			rewards[k] = int(rewards.get(k, 0)) + int(lvl_data["rewards"][k])
		var elem: String = Catalog.mining_element_ids[U.hash_seed(x["id"]) % Catalog.mining_element_ids.size()]
		rewards[elem] = 120 * lvl
		if lvl >= 2:
			rewards["speedup_1m"] = 1
		var hb: float = Eco.event_factor("hunt_reward")
		if hb > 0.0:
			for k2: String in rewards.keys():
				if not Catalog.items_by_id.has(k2):
					rewards[k2] = int(round(int(rewards[k2]) * (1.0 + hb)))
		streak[x["species"]] = count + 1
		p["hunt_streak"] = streak
		srv.world.remove_entity(x["id"])
		srv.world.schedule_respawn(x, float(lvl_data.get("respawn_sec", 90)))
		srv.social.on_xeno_killed(p, x)
		srv.on_activity(p, "xeno_kill", float(lvl))
		srv.missions.on_event(p, "xeno_hunted", 1)
		if lvl >= 3:
			srv.missions.on_event(p, "xeno_hunted_l3", 1)
	srv.progression.grant(p, rewards, "hunt", "fleet:%s:hunt" % f["id"])
	srv.emit_fx(U.v2(f["target"]), "hunt", f["owner"])
	var report: Dictionary = {
		"type": "hunt",
		"title": U.t("%s %s N%d") % [U.t("Caza exitosa:") if res["killed"] else U.t("Caza:"), species.get("name", U.t("Xenoforma")), lvl],
		"outcome": "victory" if res["killed"] else "partial",
		"pos": f["target"],
		"xeno": {"species": x["species"], "name": species.get("name", ""), "level": lvl, "damage": res["damage"], "killed": res["killed"], "hp_left": res["xeno_hp_left"], "max_hp": x["max_hp"], "weakness": species.get("weakness", ""), "streak_bonus": bonus},
		"attacker": {"name": srv.display_name(p["id"]), "avatar": p.get("avatar", "p01"), "initial": res.get("survivors", {}).duplicate(), "survivors": res["survivors"], "wounded": res["wounded"]},
		"rounds": res["rounds"],
		"rewards": rewards,
		"combat_version": res["combat_version"],
		"seed": seed,
	}
	var initial: Dictionary = res["survivors"].duplicate()
	Eco.add_troops(initial, res["wounded"])
	report["attacker"]["initial"] = initial
	srv.reports.add(p["id"], report)
	_start_return(f, now, U.v2(f["target"]))


# ---------------------------------------------------------------- PvP

func _arrive_attack_base(f: Dictionary, now: int) -> void:
	var att: Dictionary = srv.player(f["owner"])
	var base: Dictionary = srv.world.get_entity(f["target_id"])
	if base.is_empty():
		_note(f, U.t("La nave objetivo ya no está"))
		_start_return(f, now, U.v2(f["target"]))
		return
	var def: Dictionary = srv.player(base["owner"])
	if base["state"] != "ANCHORED" or U.v2(base["pos"]).distance_to(U.v2(f["target"])) > 1.5:
		_note(f, U.t("La nave objetivo saltó a warp antes del contacto"))
		_start_return(f, now, U.v2(f["target"]))
		return
	if int(def.get("shield_until", 0)) > now:
		_note(f, U.t("El objetivo activó un Campo de Distorsión"))
		_start_return(f, now, U.v2(f["target"]))
		return
	var att_initial: Dictionary = f["troops"].duplicate()
	var def_initial: Dictionary = def["troops"].duplicate()
	var seed: int = U.hash_seed(f["id"] + ":pvp")
	var res: Dictionary = Resolver.resolve(
		{"stacks": f["troops"], "mods": f["mods"]},
		{"stacks": def["troops"], "mods": Eco.combat_mods(def, true), "perimeter_hp": Eco.perimeter_hp(def)},
		seed,
	)
	var att_cas: Dictionary = _attacker_casualties(att, f, res["attacker"]["losses"])
	f["troops"] = res["attacker"]["survivors"]
	def["troops"] = res["defender"]["survivors"]
	var def_cas: Dictionary = Eco.absorb_casualties(def, res["defender"]["losses"], 1.0)
	var loot: Dictionary = {}
	if res["outcome"] == "attacker_win":
		loot = _take_loot(def, f)
		srv.missions.on_event(att, "pvp_win", 1)
		srv.on_activity(att, "pvp_win", 1.0)
	_combat_activity(att, def, res)
	_track_kills(att, def, res)
	srv.emit_fx(U.v2(f["target"]), "battle", f["owner"])
	srv.bump_base_of(def["id"])
	srv.mark_player_dirty(def["id"])
	var report_base: Dictionary = {
		"pos": f["target"],
		"rounds": res["rounds"],
		"loot": loot,
		"combat_version": res["combat_version"],
		"seed": seed,
		"attacker": _side_report(att, att_initial, res["attacker"], att_cas),
		"defender": _side_report(def, def_initial, res["defender"], def_cas),
	}
	var won: bool = res["outcome"] == "attacker_win"
	var ra: Dictionary = report_base.duplicate(true)
	ra["type"] = "attack"
	ra["outcome"] = "victory" if won else "defeat"
	ra["title"] = (U.t("Victoria contra %s") if won else U.t("Derrota contra %s")) % srv.display_name(def["id"])
	srv.reports.add(att["id"], ra)
	var rd: Dictionary = report_base.duplicate(true)
	rd["type"] = "defense"
	rd["outcome"] = "defeat" if won else "victory"
	rd["title"] = (U.t("Tu nave fue saqueada por %s") if won else U.t("Repeliste el ataque de %s")) % srv.display_name(att["id"])
	srv.reports.add(def["id"], rd)
	srv.social.on_combat(att, def, won)
	if def.get("is_bot", false):
		srv.bots.on_attacked(def, att)
	_start_return(f, now, U.v2(f["target"]))


func _arrive_tile_hit(f: Dictionary, now: int) -> void:
	var att: Dictionary = srv.player(f["owner"])
	var victim: Dictionary = fleets().get(str(f.get("target_fleet", "")), {})
	if victim.is_empty() or victim["state"] != "working":
		_note(f, U.t("La flota minera ya se había retirado"))
		_start_return(f, now, U.v2(f["target"]))
		return
	var def: Dictionary = srv.player(victim["owner"])
	var mined: int = mined_so_far(victim, now)
	var ast: Dictionary = srv.world.get_entity(victim["target_id"])
	var att_initial: Dictionary = f["troops"].duplicate()
	var def_initial: Dictionary = victim["troops"].duplicate()
	var seed: int = U.hash_seed(f["id"] + ":tile")
	var res: Dictionary = Resolver.resolve(
		{"stacks": f["troops"], "mods": f["mods"]},
		{"stacks": victim["troops"], "mods": victim["mods"]},
		seed,
	)
	var att_cas: Dictionary = _attacker_casualties(att, f, res["attacker"]["losses"])
	f["troops"] = res["attacker"]["survivors"]
	victim["troops"] = res["defender"]["survivors"]
	# Defensores fuera de la nave minando: heridos al 100% (viajan con la flota).
	Eco.add_troops(victim["wounded"], res["defender"]["losses"])
	var def_cas: Dictionary = {"wounded": res["defender"]["losses"], "dead": {}, "cryo": {}, "lost": {}}
	var loot: Dictionary = {}
	var won: bool = res["outcome"] == "attacker_win"
	# La flota atacada deja de minar y vuelve con lo que le quede.
	_collect_from_asteroid(victim, ast, mined)
	if won:
		var cap: int = Resolver.load_of(f["troops"], float(f.get("load_bonus", 0.0)))
		for k: String in victim["cargo"].keys():
			var take: int = mini(cap, int(victim["cargo"][k]))
			if take <= 0:
				continue
			loot[k] = take
			cap -= take
			victim["cargo"][k] = int(victim["cargo"][k]) - take
		U.add_into(f["cargo"], loot)
		srv.missions.on_event(att, "pvp_win", 1)
		srv.on_activity(att, "pvp_win", 1.0)
	_start_return(victim, now, U.v2(victim["target"]))
	_combat_activity(att, def, res)
	_track_kills(att, def, res)
	srv.emit_fx(U.v2(f["target"]), "battle", f["owner"])
	var base_report: Dictionary = {
		"pos": f["target"], "rounds": res["rounds"], "loot": loot,
		"combat_version": res["combat_version"], "seed": seed,
		"attacker": _side_report(att, att_initial, res["attacker"], att_cas),
		"defender": _side_report(def, def_initial, res["defender"], def_cas),
	}
	var ra: Dictionary = base_report.duplicate(true)
	ra["type"] = "tile_hit"
	ra["outcome"] = "victory" if won else "defeat"
	ra["title"] = (U.t("Interceptaste la flota minera de %s") if won else U.t("Tu intercepción contra %s fracasó")) % srv.display_name(def["id"])
	srv.reports.add(att["id"], ra)
	var rd: Dictionary = base_report.duplicate(true)
	rd["type"] = "tile_defense"
	rd["outcome"] = "defeat" if won else "victory"
	rd["title"] = (U.t("%s interceptó tu flota minera") if won else U.t("Tu flota minera resistió a %s")) % srv.display_name(att["id"])
	srv.reports.add(def["id"], rd)
	if def.get("is_bot", false):
		srv.bots.on_attacked(def, att)
	_start_return(f, now, U.v2(f["target"]))


## Actividad de combate para alianzas y torneos: golpe al objetivo, poder
## destruido por cada lado y valor de las tropas perdidas ("valor quemado").
func _combat_activity(att: Dictionary, def: Dictionary, res: Dictionary) -> void:
	var la: Dictionary = res["attacker"]["losses"]
	var ld: Dictionary = res["defender"]["losses"]
	srv.on_activity(att, "pvp_hit", 1.0, {"target_owner": def.get("id", "")})
	srv.on_activity(att, "power_destroyed", float(Resolver.power_of(ld)))
	srv.on_activity(def, "power_destroyed", float(Resolver.power_of(la)))
	srv.on_activity(att, "troops_lost", Catalog.troops_value_mo(la))
	srv.on_activity(def, "troops_lost", Catalog.troops_value_mo(ld))


func _attacker_casualties(owner: Dictionary, f: Dictionary, losses: Dictionary) -> Dictionary:
	# Atacante fuera de casa: 60% heridos (viajan con la flota), 40% muertos.
	var wounded: Dictionary = {}
	var dead: Dictionary = {}
	for k: String in losses:
		var w: int = int(round(int(losses[k]) * ATTACKER_WOUNDED_SHARE))
		if w > 0:
			wounded[k] = w
		if int(losses[k]) - w > 0:
			dead[k] = int(losses[k]) - w
	Eco.add_troops(f["wounded"], wounded)
	var cryo: Dictionary = {}
	var lost: Dictionary = {}
	var cryo_free: int = maxi(0, Eco.cryo_capacity(owner) - Eco.troops_total(owner.get("cryo", {})))
	for k: String in dead:
		var c: int = mini(int(floor(int(dead[k]) * 0.8)), cryo_free)
		cryo_free -= c
		if c > 0:
			cryo[k] = c
		if int(dead[k]) - c > 0:
			lost[k] = int(dead[k]) - c
	Eco.add_troops(owner["cryo"], cryo)
	return {"wounded": wounded, "dead": dead, "cryo": cryo, "lost": lost}


func _take_loot(def: Dictionary, f: Dictionary) -> Dictionary:
	var cap: int = Resolver.load_of(f["troops"], float(f.get("load_bonus", 0.0)))
	var avail: Dictionary = Eco.lootable(def)
	var total: int = U.sum_values(avail)
	var loot: Dictionary = {}
	if cap <= 0 or total <= 0:
		return loot
	var ratio: float = minf(1.0, float(cap) / float(total))
	for k: String in avail:
		var take: int = int(floor(int(avail[k]) * ratio))
		if take > 0:
			loot[k] = take
	Eco.apply(def, Eco.negate(loot), "plundered", "fleet:%s:plunder" % f["id"])
	U.add_into(f["cargo"], loot)
	return loot


func _track_kills(att: Dictionary, def: Dictionary, res: Dictionary) -> void:
	att["stats"] = att.get("stats", {})
	def["stats"] = def.get("stats", {})
	att["stats"]["kills"] = int(att["stats"].get("kills", 0)) + Eco.troops_total(res["defender"]["losses"])
	def["stats"]["kills"] = int(def["stats"].get("kills", 0)) + Eco.troops_total(res["attacker"]["losses"])


func _side_report(p: Dictionary, initial: Dictionary, side: Dictionary, cas: Dictionary) -> Dictionary:
	return {
		"id": p["id"],
		"name": srv.display_name(p["id"]),
		"avatar": p.get("avatar", "p01"),
		"initial": initial,
		"survivors": side["survivors"],
		"losses": side["losses"],
		"wounded": cas.get("wounded", {}),
		"dead": cas.get("dead", {}),
		"cryo": cas.get("cryo", {}),
		"lost": cas.get("lost", {}),
		"power_lost": Resolver.power_of(side["losses"]),
		"perimeter_initial": side.get("perimeter_initial", 0),
		"perimeter_left": side.get("perimeter_left", 0),
	}


func _note(f: Dictionary, text: String) -> void:
	srv.notify(f["owner"], text, "warning")


# ---------------------------------------------------------------- espionaje

func _arrive_scout(f: Dictionary, now: int) -> void:
	var p: Dictionary = srv.player(f["owner"])
	var base: Dictionary = srv.world.get_entity(f["target_id"])
	if base.is_empty() or base["state"] != "ANCHORED":
		_note(f, U.t("La sonda no encontró la nave objetivo"))
		_start_return(f, now, U.v2(f["target"]))
		return
	var def: Dictionary = srv.player(base["owner"])
	if int(def.get("shield_until", 0)) > now:
		_note(f, U.t("Un Campo de Distorsión bloqueó la sonda"))
		_start_return(f, now, U.v2(f["target"]))
		return
	# Precisión según Sala de Sensores propia vs. la del objetivo (spec §6).
	var precision: int = clampi(Eco.scout_level(p) - Eco.scout_level(def) + 3, 1, 5)
	var rng := RandomNumberGenerator.new()
	rng.seed = U.hash_seed(f["id"])
	var info: Dictionary = {"precision": precision, "power": srv.player_power(def)}
	if precision >= 2:
		var res: Dictionary = {}
		for e: String in Catalog.element_ids:
			res[e] = int(def["resources"].get(e, 0))
		info["resources"] = res
		info["lootable"] = Eco.lootable(def)
	if precision >= 3:
		var total: int = Eco.troops_total(def["troops"])
		info["troops_total"] = total if precision >= 5 else int(round(total * rng.randf_range(0.85, 1.15)))
	if precision >= 4:
		var by_type: Dictionary = {}
		for k: String in def["troops"]:
			by_type[k] = int(def["troops"][k]) if precision >= 5 else int(round(int(def["troops"][k]) * rng.randf_range(0.9, 1.1)))
		info["troops"] = by_type
		info["perimeter_hp"] = Eco.perimeter_hp(def)
	if precision >= 5:
		info["rooms"] = {}
		for r: String in def["rooms"]:
			info["rooms"][r] = int(def["rooms"][r]["level"])
	srv.reports.add(p["id"], {
		"type": "scout",
		"title": U.t("Informe de espionaje: %s") % srv.display_name(def["id"]),
		"outcome": "info",
		"pos": f["target"],
		"target": {"id": def["id"], "name": srv.display_name(def["id"]), "avatar": def.get("avatar", "p01"), "base_id": base["id"]},
		"scout": info,
	})
	srv.missions.on_event(p, "scout_done", 1)
	if not def.get("is_bot", false):
		srv.notify(def["id"], U.t("Tu nave fue espiada por %s") % srv.display_name(p["id"]), "warning")
	_start_return(f, now, U.v2(f["target"]))


# ---------------------------------------------------------------- viaje de la Astronave

func relocate_cost(p: Dictionary, dest: Vector2) -> int:
	var base: Dictionary = srv.world.get_entity(p["base_id"])
	var d: float = U.v2(base.get("pos", [0, 0])).distance_to(dest)
	return int(Catalog.cfg("relocate_plasma_base", 10)) + int(ceil(d * float(Catalog.cfg("relocate_plasma_per_tile", 0.25))))


func relocate(p: Dictionary, dest: Vector2i, warp: bool) -> Dictionary:
	var base: Dictionary = srv.world.get_entity(p["base_id"])
	if base["state"] != "ANCHORED":
		return _err("SHIP_NOT_ANCHORED", U.t("La nave ya está en tránsito"))
	if not owned_fleets(p["id"]).is_empty():
		return _err("FLEETS_OUT", U.t("Espera a que todas tus flotas regresen"))
	var destf := Vector2(dest)
	if destf.distance_to(U.v2(base["pos"])) < 1.0:
		return _err("INVALID_DESTINATION", U.t("Ese ya es tu punto de anclaje"))
	if srv.world.is_blocked(destf, 2.0):
		return _err("INVALID_DESTINATION", U.t("Zona no ocupable (Portal o gigante gaseoso)"))
	for id: String in srv.world.hash.query_radius(destf, 2.5):
		if id != base["id"]:
			return _err("DESTINATION_OCCUPIED", U.t("Ese punto está ocupado"))
	var now: int = U.now_ms()
	if warp:
		if not Eco.apply(p, {"warp_jump": -1}, "warp"):
			return _err("NO_ITEM", U.t("No tienes Salto Warp"))
		srv.world.move_entity(base["id"], dest)
		srv.notify(p["id"], U.t("Salto Warp completado"), "success")
	else:
		var cost: int = relocate_cost(p, destf)
		if not Eco.apply(p, {"plasma": -cost}, "relocate"):
			return _err("INSUFFICIENT_RESOURCES", U.t("Plasma de Fusión insuficiente (%d)") % cost)
		srv.settle_player(p)
		var speed: float = float(Catalog.cfg("relocate_speed_tiles_per_sec", 6.0)) * (1.0 + float(Eco.modifiers(p)["march_speed"]))
		var dur: int = maxi(2000, int(destf.distance_to(U.v2(base["pos"])) / speed * 1000.0))
		base["state"] = "TRAVELING"
		base["travel"] = {"origin": base["pos"].duplicate(), "target": [dest.x, dest.y], "depart_ts": now, "arrive_ts": now + dur}
		srv.world.bump(base)
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


## Salto de Emergencia: la nave aparece al instante en un punto ALEATORIO y
## lejano del sistema (las flotas enemigas en camino pierden el objetivo).
func escape_jump(p: Dictionary) -> Dictionary:
	var base: Dictionary = srv.world.get_entity(p["base_id"])
	if base["state"] != "ANCHORED":
		return _err("SHIP_NOT_ANCHORED", U.t("La nave ya está en tránsito"))
	if not owned_fleets(p["id"]).is_empty():
		return _err("FLEETS_OUT", U.t("Espera a que todas tus flotas regresen"))
	var home: Vector2 = U.v2(base["pos"])
	var min_d: float = float(Catalog.cfg("escape_jump_min_dist", 60))
	var dest := Vector2i(-1, -1)
	for _i: int in range(300):
		var cand: Vector2i = srv.galaxy.spawn_point(srv.rng) if srv.rng.randf() < 0.5 else srv.world.find_free_near(srv.world.center, 60.0, 270.0, srv.rng, 6.0, 4)
		if cand.x >= 0 and Vector2(cand).distance_to(home) >= min_d:
			dest = cand
			break
	if dest.x < 0:
		return _err("NO_SPACE", U.t("No se encontró un punto libre; inténtalo de nuevo"))
	if not Eco.apply(p, {"escape_jump": -1}, "escape_jump"):
		return _err("NO_ITEM", U.t("No tienes Salto de Emergencia"))
	srv.world.move_entity(base["id"], dest)
	var incoming: int = 0
	for f: Dictionary in fleets().values():
		if f["state"] == "outbound" and str(f.get("target_owner", "")) == p["id"] and f["target_kind"] == "base":
			incoming += 1
	srv.mark_player_dirty(p["id"])
	srv.notify(p["id"], U.t("¡Salto de Emergencia! Nueva posición X:%d Y:%d") % [dest.x, dest.y] + ((U.t(" · %d flota(s) hostil(es) perdieron tu rastro") % incoming) if incoming > 0 else ""), "success")
	return {"ok": true, "pos": [dest.x, dest.y], "evaded": incoming}


func _process_relocations(now: int) -> void:
	for p: Dictionary in srv.state["players"].values():
		if str(p.get("system", "")) != srv.current_system:
			continue
		var base: Dictionary = srv.world.get_entity(str(p.get("base_id", "")))
		if base.is_empty() or base["state"] != "TRAVELING":
			continue
		var tr: Dictionary = base.get("travel", {})
		if now < int(tr.get("arrive_ts", 0)):
			continue
		srv.settle_player(p)
		var dest: Vector2i = Vector2i(U.v2(tr["target"]))
		if srv.world.hash.query_radius(Vector2(dest), 2.0).filter(func(i: String) -> bool: return i != base["id"]).size() > 0:
			# Destino ocupado al llegar: se reubica en el hueco libre más cercano.
			var alt: Vector2i = srv.world.find_free_near(Vector2(dest), 3.0, 12.0, srv.rng, 2.5)
			if alt.x >= 0:
				dest = alt
		base["state"] = "ANCHORED"
		base.erase("travel")
		srv.world.move_entity(base["id"], dest)
		srv.mark_player_dirty(p["id"])
		srv.notify(p["id"], U.t("La Astronave llegó a destino y quedó anclada"), "success")


# ---------------------------------------------------------------- vistas

func incoming_for(pid: String, now: int) -> Array:
	var out: Array = []
	for id: String in fleets():
		var f: Dictionary = fleets()[id]
		if f["state"] != "outbound" or f["owner"] == pid:
			continue
		if f["mission"] in ["attack", "scout"] and str(f.get("target_owner", "")) == pid:
			out.append({
				"fleet_id": f["id"], "mission": f["mission"], "from": srv.display_name(f["owner"]),
				"arrive_ts": f["arrive_ts"], "troops": Eco.troops_total(f["troops"]),
				"target_kind": f["target_kind"],
			})
	return out


func fleet_view(f: Dictionary, now: int) -> Dictionary:
	var v: Dictionary = {
		"id": f["id"], "kind": "fleet", "owner": f["owner"], "owner_name": srv.display_name(f["owner"]),
		"tag": str(srv.player(f["owner"]).get("tag", "")),
		"mission": f["mission"], "state": f["state"], "target_id": f["target_id"], "target_kind": f["target_kind"],
		"origin": f["origin"], "target": f["target"], "depart_ts": f["depart_ts"], "arrive_ts": f["arrive_ts"],
		"troops_total": Eco.troops_total(f["troops"]), "wounded_total": Eco.troops_total(f["wounded"]),
		"rev": f.get("rev", 1),
	}
	if f["state"] == "working":
		v["work_start"] = f["work_start"]
		v["work_end"] = f["work_end"]
		v["work_amount"] = f["work_amount"]
		v["element"] = f.get("element", "")
	return v
