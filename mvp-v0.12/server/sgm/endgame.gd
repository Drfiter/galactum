extends RefCounted
## Endgame y PvE cooperativo (feedback del 26/10: "faltan las Colmenas Xeno,
## las Plataformas Orbitales y los títulos; en el Criosantuario no están las
## Operaciones de Rescate que recuperan el 30%").
##
## Todo vive en el estado del Sistema Solar activo (`srv.cur`):
## - Colmenas Xeno: xenoformas con `hive: true` y vida enorme que solo se
##   atacan con un Asedio de alianza. El daño persiste; cada participante recibe
##   premio según su aporte y, al caer, el premio de derribo.
## - Plataformas Orbitales: 4 estaciones alrededor del Portal de Salto con una
##   guarnición. Se conquistan con un Asedio; la alianza que la controla recibe
##   su bono (`platform_mods`) y queda protegida unos minutos. Las alianzas bot
##   también las disputan.
## - Títulos: la alianza que controla la Ciudadela otorga títulos positivos o
##   negativos (`title_mods`) a comandantes del sistema.
## - Operación de Rescate: temporizador del Criosantuario que al terminar
##   devuelve el 30% de las fuerzas en criostasis (las ayudas lo aceleran).

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const Resolver = preload("res://server/combat/combat_resolver.gd")
const MIN_MS: int = 60000
const HOUR_MS: int = 3600000

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.endgame


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


# ---------------------------------------------------------------- estado del sistema

## Crea las Colmenas y las Plataformas del sistema activo si aún no existen.
func ensure_system() -> void:
	if srv.cur.is_empty() or bool(srv.cur.get("endgame_ready", false)):
		return
	srv.cur["endgame_ready"] = true
	srv.cur["titles"] = {}
	srv.cur["title_cd"] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = U.hash_seed(srv.current_system + ":endgame")
	var hc: Dictionary = cfg().get("hives", {})
	for i: int in range(int(hc.get("per_system", 3))):
		_spawn_hive(1 + i % (hc.get("tiers", []) as Array).size(), rng)
	var pc: Dictionary = cfg().get("platforms", {})
	var ring: float = float(Catalog.cfg("portal_radius", 14)) + float(pc.get("ring_offset", 14))
	var bot_tags: Array = _bot_alliances()
	var idx: int = 0
	for d: Dictionary in pc.get("list", []):
		var ang: float = deg_to_rad(float(d.get("angle", 0)))
		var pos: Vector2 = srv.world.center + Vector2(cos(ang), sin(ang)) * ring
		var holder: String = ""
		# Al empezar, la Ciudadela y una plataforma están en manos de alianzas bot.
		if not bot_tags.is_empty() and (bool(d.get("titles", false)) or idx == 0):
			holder = str(bot_tags[idx % bot_tags.size()])
		# Despeja asteroides y xenoformas que ocupen el sitio de la plataforma.
		for other: Dictionary in srv.world.entities().values().duplicate():
			if str(other.get("kind", "")) in ["asteroid", "xenoform"] and U.v2(other["pos"]).distance_to(pos) < 6.0 and str(other.get("occupant", "")).is_empty():
				srv.world.remove_entity(str(other["id"]))
		var e: Dictionary = {
			"id": "plt_%s_%s" % [srv.current_system, d["id"]], "kind": "platform", "ptype": d["id"],
			"pos": [int(round(pos.x)), int(round(pos.y))], "holder": holder, "shield_until": 0,
			"garrison": _garrison(d, 1.0 if holder.is_empty() else float(pc.get("captured_garrison_ratio", 0.5))),
		}
		srv.world.add_entity(e)
		idx += 1
	srv.cur["next_bot_platform"] = U.now_ms() + int(pc.get("bot_attack_min", 12)) * MIN_MS
	srv.cur["next_bot_titles"] = U.now_ms() + 30000
	if not bot_tags.is_empty():
		_bot_titles(U.now_ms())


func _bot_alliances() -> Array:
	var out: Array = []
	for tag: String in srv.social.alliances():
		var mem: Array = srv.social.members(tag)
		# Solo alianzas 100% bot: las de jugadores conquistan por sí mismas.
		if mem.any(func(m: Dictionary) -> bool: return not m.get("is_bot", false)):
			continue
		if mem.any(func(m: Dictionary) -> bool: return str(m.get("system", "")) == srv.current_system):
			out.append(tag)
	out.sort()
	return out


func _garrison(d: Dictionary, ratio: float) -> Dictionary:
	var g: Dictionary = {}
	for k: String in d.get("garrison", {}):
		g[k] = maxi(1, int(round(float(d["garrison"][k]) * ratio)))
	return g


func platform_def(ptype: String) -> Dictionary:
	for d: Dictionary in cfg().get("platforms", {}).get("list", []):
		if str(d["id"]) == ptype:
			return d
	return {}


func hive_tier(tier: int) -> Dictionary:
	for t: Dictionary in cfg().get("hives", {}).get("tiers", []):
		if int(t["tier"]) == tier:
			return t
	return {}


func _spawn_hive(tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var hc: Dictionary = cfg().get("hives", {})
	var pos: Vector2i = srv.world.find_free_near(srv.world.center, float(hc.get("min_dist", 45)), float(hc.get("max_dist", 120)), rng, 6.0)
	if pos.x < 0:
		return {}
	var hp: int = int(hive_tier(tier).get("hp", 60000))
	var e: Dictionary = {"id": "hiv_%s" % U.new_id(), "kind": "xenoform", "hive": true, "tier": tier, "level": 5,
		"species": str(hc.get("species", "x24")), "pos": [pos.x, pos.y], "hp": hp, "max_hp": hp, "last_hit": 0, "damage_by": {}}
	srv.world.add_entity(e)
	return e


func platforms() -> Array:
	var out: Array = []
	for e: Dictionary in srv.world.entities().values():
		if str(e.get("kind", "")) == "platform":
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out


func hives() -> Array:
	var out: Array = []
	for e: Dictionary in srv.world.entities().values():
		if str(e.get("kind", "")) == "xenoform" and bool(e.get("hive", false)):
			out.append(e)
	return out


func citadel() -> Dictionary:
	for e: Dictionary in platforms():
		if bool(platform_def(str(e["ptype"])).get("titles", false)):
			return e
	return {}


# ---------------------------------------------------------------- Colmenas

## Llega un Asedio a una Colmena: combate PvE con daño persistente.
func arrive_hive(f: Dictionary, now: int) -> void:
	var x: Dictionary = srv.world.get_entity(str(f["target_id"]))
	var shares: Dictionary = f.get("shares", {f["owner"]: f["troops"]})
	if x.is_empty() or int(x.get("hp", 0)) <= 0:
		for pid: String in shares:
			srv.notify(pid, U.t("La Colmena ya fue destruida: el Asedio regresa."), "info")
		srv.fleets._start_return(f, now, U.v2(f["target"]))
		return
	var species: Dictionary = Catalog.species_by_id.get(str(x["species"]), {})
	var seed: int = U.hash_seed(str(f["id"]) + ":hive")
	var initial: Dictionary = (f["troops"] as Dictionary).duplicate()
	var res: Dictionary = Resolver.resolve_hunt(f["troops"], f["mods"], str(species.get("weakness", "")), 5, int(x["hp"]), seed, 1.0)
	x["hp"] = int(res["xeno_hp_left"])
	x["last_hit"] = now
	srv.world.bump(x)
	f["troops"] = res["survivors"]
	Eco.add_troops(f["wounded"], res["wounded"])
	var tier: Dictionary = hive_tier(int(x.get("tier", 1)))
	var dmg: int = int(res["damage"])
	var total_share: int = 0
	for pid: String in shares:
		total_share += Eco.troops_total(shares[pid])
	var killed: bool = bool(res["killed"])
	for pid: String in shares:
		var q: Dictionary = srv.player(pid)
		if q.is_empty():
			continue
		var frac: float = float(Eco.troops_total(shares[pid])) / float(maxi(1, total_share))
		var my_dmg: int = int(round(dmg * frac))
		x["damage_by"][pid] = int(x["damage_by"].get(pid, 0)) + my_dmg
		var reward: Dictionary = {}
		for k: String in tier.get("reward_per_10k", {}):
			var n: int = int(floor(float(tier["reward_per_10k"][k]) * my_dmg / 10000.0))
			if n > 0:
				reward[k] = n
		if killed:
			# Premio de derribo: cada participante recibe al menos el 30%.
			var kf: float = clampf(0.3 + 0.7 * frac, 0.3, 1.0)
			for k2: String in tier.get("kill", {}):
				reward[k2] = int(reward.get(k2, 0)) + maxi(1, int(round(float(tier["kill"][k2]) * kf)))
		if not q.get("is_bot", false):
			srv.progression.grant(q, reward, "hive", "hive:%s:%s" % [f["id"], pid])
			srv.commander.grant_exp(q, int(my_dmg / 200))
			srv.on_activity(q, "xeno_kill", 5.0 if killed else 1.0)
			srv.reports.add(pid, {
				"type": "hunt", "outcome": "victory" if killed else "partial", "pos": f["target"],
				"title": (U.t("¡Colmena destruida! %s") if killed else U.t("Asedio a la %s")) % U.t(str(tier.get("name", "Colmena Xeno"))),
				"xeno": {"species": x["species"], "name": U.t(str(tier.get("name", ""))), "level": 5, "damage": dmg, "killed": killed,
					"hp_left": res["xeno_hp_left"], "max_hp": x["max_hp"], "weakness": species.get("weakness", ""), "streak_bonus": 0.0},
				"attacker": {"name": srv.display_name(str(f["owner"])) + U.t(" (Asedio)"), "avatar": srv.player(str(f["owner"])).get("avatar", "p01"),
					"initial": initial, "survivors": res["survivors"], "wounded": res["wounded"]},
				"rounds": res["rounds"], "rewards": reward, "crew": [], "combat_version": res["combat_version"], "seed": seed,
			})
		srv.mark_player_dirty(pid)
	var tag: String = str(srv.player(str(f["owner"])).get("tag", ""))
	srv.emit_fx(U.v2(f["target"]), "hunt", f["owner"])
	if killed:
		srv.world.remove_entity(x["id"])
		var list: Array = srv.cur.get("hive_respawns", [])
		list.append({"tier": int(x.get("tier", 1)), "at": now + int(cfg().get("hives", {}).get("respawn_min", 20)) * MIN_MS})
		srv.cur["hive_respawns"] = list
		if not tag.is_empty():
			srv.social.post(tag, U.t("Sistema"), U.t("¡La alianza destruyó una %s! Premios repartidos a %d comandantes.") % [U.t(str(tier.get("name", ""))), shares.size()], "rally")
	elif not tag.is_empty():
		srv.social.post(tag, U.t("Sistema"), U.t("El Asedio dañó la Colmena: le queda %s de vida.") % U.fmt_num(int(x["hp"])), "rally")
	srv.fleets._start_return(f, now, U.v2(f["target"]))


# ---------------------------------------------------------------- Plataformas

## "" si la alianza de `p` puede atacar la plataforma; si no, el motivo.
func platform_block(p: Dictionary, e: Dictionary) -> String:
	if str(e.get("holder", "")) == str(p.get("tag", "")) and not str(p.get("tag", "")).is_empty():
		return U.t("Tu alianza ya controla esta plataforma")
	if int(e.get("shield_until", 0)) > U.now_ms():
		return U.t("La plataforma está protegida tras su conquista")
	return ""


func arrive_platform(f: Dictionary, now: int) -> void:
	var e: Dictionary = srv.world.get_entity(str(f["target_id"]))
	var leader: Dictionary = srv.player(str(f["owner"]))
	var tag: String = str(leader.get("tag", ""))
	var shares: Dictionary = f.get("shares", {f["owner"]: f["troops"]})
	if e.is_empty() or tag.is_empty() or not platform_block(leader, e).is_empty():
		for pid: String in shares:
			srv.notify(pid, U.t("La plataforma ya no se puede atacar: el Asedio regresa."), "info")
		srv.fleets._start_return(f, now, U.v2(f["target"]))
		return
	var d: Dictionary = platform_def(str(e["ptype"]))
	var seed: int = U.hash_seed(str(f["id"]) + ":platform")
	var res: Dictionary = Resolver.resolve({"stacks": f["troops"], "mods": f["mods"]}, {"stacks": e["garrison"], "mods": {}}, seed)
	var win: bool = str(res["outcome"]) == "attacker_win"
	f["troops"] = res["attacker"]["survivors"]
	# En las plataformas las bajas del atacante van a la Bahía Médica.
	Eco.add_troops(f["wounded"], res["attacker"]["losses"])
	var prev: String = str(e.get("holder", ""))
	if win:
		_capture(e, tag, now)
	else:
		e["garrison"] = res["defender"]["survivors"]
		srv.world.bump(e)
	var pname: String = U.t(str(d.get("name", "")))
	for pid: String in shares:
		var q: Dictionary = srv.player(pid)
		if q.is_empty() or q.get("is_bot", false):
			continue
		srv.reports.add(pid, {
			"type": "attack", "outcome": "victory" if win else "defeat", "pos": f["target"],
			"title": (U.t("Plataforma conquistada: %s") if win else U.t("Asalto fallido a %s")) % pname,
			"attacker": {"name": srv.display_name(str(f["owner"])) + U.t(" (Asedio)"), "avatar": leader.get("avatar", "p01"),
				"initial": res["attacker"]["initial"], "losses": res["attacker"]["losses"], "wounded": res["attacker"]["losses"]},
			"defender": {"name": (("[%s] " % prev) if not prev.is_empty() else "") + U.t("Guarnición de %s") % pname, "avatar": "p01",
				"initial": res["defender"]["initial"], "losses": res["defender"]["losses"]},
			"rounds": res["rounds"], "combat_version": res["combat_version"], "seed": seed,
		})
		srv.mark_player_dirty(pid)
	srv.social.post(tag, U.t("Sistema"), (U.t("¡La alianza conquistó la %s!") if win else U.t("El Asedio no pudo tomar la %s.")) % pname, "rally")
	if win and not prev.is_empty() and prev != tag:
		srv.social.post(prev, U.t("Sistema"), U.t("¡[%s] nos arrebató la %s!") % [tag, pname], "rally")
	srv.fleets._start_return(f, now, U.v2(f["target"]))


func _capture(e: Dictionary, tag: String, now: int) -> void:
	var pc: Dictionary = cfg().get("platforms", {})
	var d: Dictionary = platform_def(str(e["ptype"]))
	var prev: String = str(e.get("holder", ""))
	e["holder"] = tag
	e["shield_until"] = now + int(pc.get("shield_min", 20)) * MIN_MS
	e["garrison"] = _garrison(d, float(pc.get("captured_garrison_ratio", 0.5)))
	srv.world.bump(e)
	# Al cambiar de dueño la Ciudadela, los títulos vigentes se revocan.
	if bool(d.get("titles", false)) and prev != tag:
		srv.cur["titles"] = {}
		srv.cur["title_cd"] = {}
	refresh_all()


# ---------------------------------------------------------------- títulos

func title_def(tid: String) -> Dictionary:
	for t: Dictionary in cfg().get("titles", {}).get("list", []):
		if str(t["id"]) == tid:
			return t
	return {}


func can_grant(p: Dictionary) -> bool:
	var c: Dictionary = citadel()
	return not c.is_empty() and not str(p.get("tag", "")).is_empty() and str(c.get("holder", "")) == str(p["tag"]) \
		and srv.alliance.rank_of(p) in ["R5", "R4"]


func grant_title(p: Dictionary, tid: String, target_pid: String) -> Dictionary:
	ensure_system()
	if not can_grant(p):
		return _err("NO_PERMISSION", U.t("Solo el líder u oficiales de la alianza que controla la Ciudadela otorgan títulos"))
	var t: Dictionary = title_def(tid)
	if t.is_empty():
		return _err("NOT_FOUND", U.t("Título desconocido"))
	var target: Dictionary = srv.player(target_pid)
	if target.is_empty() or str(target.get("system", "")) != srv.current_system:
		return _err("TARGET_NOT_FOUND", U.t("Ese comandante no está en este sistema"))
	var now: int = U.now_ms()
	var cd: Dictionary = srv.cur.get("title_cd", {})
	if int(cd.get(tid, 0)) > now:
		return _err("COOLDOWN", U.t("Ese título se reasigna en %s") % U.fmt_time(float(int(cd[tid]) - now) / 1000.0))
	_assign(tid, target_pid, str(p["id"]), now)
	srv.notify(target_pid, (U.t("¡Recibiste el título %s!") if bool(t.get("positive", true)) else U.t("Te impusieron el título %s.")) % U.t(str(t["name"])), "success" if bool(t.get("positive", true)) else "danger")
	return {"ok": true}


func _assign(tid: String, target_pid: String, by: String, now: int) -> void:
	var tc: Dictionary = cfg().get("titles", {})
	var titles: Dictionary = srv.cur.get("titles", {})
	# Un comandante lleva un solo título: se le quita el anterior.
	for k: String in titles.keys():
		if str(titles[k].get("pid", "")) == target_pid:
			titles.erase(k)
	var old: String = str(titles.get(tid, {}).get("pid", ""))
	titles[tid] = {"pid": target_pid, "by": by, "until": now + int(tc.get("hours", 24)) * HOUR_MS}
	srv.cur["titles"] = titles
	var cd: Dictionary = srv.cur.get("title_cd", {})
	cd[tid] = now + int(tc.get("cooldown_sec", 60)) * 1000
	srv.cur["title_cd"] = cd
	for pid: String in [old, target_pid]:
		var q: Dictionary = srv.player(pid)
		if not q.is_empty():
			refresh(q)
			srv.mark_player_dirty(pid)


func revoke_title(p: Dictionary, tid: String) -> Dictionary:
	if not can_grant(p):
		return _err("NO_PERMISSION", U.t("Solo el líder u oficiales de la alianza que controla la Ciudadela otorgan títulos"))
	var titles: Dictionary = srv.cur.get("titles", {})
	if not titles.has(tid):
		return _err("NOT_FOUND", U.t("Ese título está libre"))
	var pid: String = str(titles[tid]["pid"])
	titles.erase(tid)
	var q: Dictionary = srv.player(pid)
	if not q.is_empty():
		refresh(q)
		srv.mark_player_dirty(pid)
	return {"ok": true}


func cur_titles() -> Dictionary:
	return srv.cur.get("titles", {})


# ---------------------------------------------------------------- modificadores

func refresh(p: Dictionary) -> void:
	var pm: Dictionary = {}
	var tm: Dictionary = {}
	if str(p.get("system", "")) == srv.current_system and not srv.cur.is_empty():
		var tag: String = str(p.get("tag", ""))
		if not tag.is_empty():
			for e: Dictionary in platforms():
				if str(e.get("holder", "")) == tag:
					_add_mods(pm, platform_def(str(e["ptype"])).get("buff", {}))
		var now: int = U.now_ms()
		for tid: String in srv.cur.get("titles", {}):
			var t: Dictionary = srv.cur["titles"][tid]
			if str(t["pid"]) == str(p["id"]) and int(t["until"]) > now:
				_add_mods(tm, title_def(tid).get("mods", {}))
	p["platform_mods"] = pm
	p["title_mods"] = tm


static func _add_mods(target: Dictionary, mods: Dictionary) -> void:
	for k: String in mods:
		target[k] = float(target.get(k, 0.0)) + float(mods[k])


func refresh_all() -> void:
	for p: Dictionary in srv.state["players"].values():
		if str(p.get("system", "")) == srv.current_system:
			refresh(p)
			if not p.get("is_bot", false):
				srv.mark_player_dirty(p["id"])


# ---------------------------------------------------------------- tick por sistema

func tick(now: int) -> void:
	ensure_system()
	var hc: Dictionary = cfg().get("hives", {})
	# Reaparición de Colmenas.
	var keep: Array = []
	for r: Dictionary in srv.cur.get("hive_respawns", []):
		if int(r["at"]) > now:
			keep.append(r)
		else:
			_spawn_hive(int(r["tier"]), srv.rng)
	srv.cur["hive_respawns"] = keep
	# Las Colmenas que nadie ataca se regeneran.
	for x: Dictionary in hives():
		if int(x["hp"]) < int(x["max_hp"]) and now - int(x.get("last_hit", 0)) > int(hc.get("regen_after_min", 30)) * MIN_MS:
			x["hp"] = int(x["max_hp"])
			x["damage_by"] = {}
			srv.world.bump(x)
	# Títulos vencidos.
	var titles: Dictionary = srv.cur.get("titles", {})
	for tid: String in titles.keys():
		if int(titles[tid]["until"]) <= now:
			var q: Dictionary = srv.player(str(titles[tid]["pid"]))
			titles.erase(tid)
			if not q.is_empty():
				refresh(q)
	# Las alianzas bot disputan las plataformas y reparten títulos.
	if now >= int(srv.cur.get("next_bot_platform", 0)):
		srv.cur["next_bot_platform"] = now + int(cfg().get("platforms", {}).get("bot_attack_min", 12)) * MIN_MS
		_bot_platform_attack(now)
	if now >= int(srv.cur.get("next_bot_titles", 0)):
		srv.cur["next_bot_titles"] = now + 15 * MIN_MS
		_bot_titles(now)
	if now >= int(srv.cur.get("next_mod_refresh", 0)):
		srv.cur["next_mod_refresh"] = now + 5000
		refresh_all()


func _bot_platform_attack(now: int) -> void:
	var tags: Array = _bot_alliances()
	if tags.is_empty():
		return
	var targets: Array = platforms().filter(func(e: Dictionary) -> bool: return int(e.get("shield_until", 0)) <= now)
	if targets.is_empty():
		return
	var e: Dictionary = targets[srv.rng.randi() % targets.size()]
	var tag: String = str(tags[srv.rng.randi() % tags.size()])
	if tag == str(e.get("holder", "")):
		return
	var army: Dictionary = {}
	var power: float = srv.rng.randf_range(0.7, 1.5)
	for k: String in e["garrison"]:
		army[k] = int(round(float(e["garrison"][k]) * power))
	var res: Dictionary = Resolver.resolve({"stacks": army, "mods": {}}, {"stacks": e["garrison"], "mods": {}}, U.hash_seed("%s:%d" % [e["id"], now]))
	var prev: String = str(e.get("holder", ""))
	var pname: String = U.t(str(platform_def(str(e["ptype"])).get("name", "")))
	if str(res["outcome"]) == "attacker_win":
		_capture(e, tag, now)
		if not prev.is_empty():
			srv.social.post(prev, U.t("Sistema"), U.t("¡[%s] nos arrebató la %s!") % [tag, pname], "rally")
	else:
		e["garrison"] = res["defender"]["survivors"]
		if (e["garrison"] as Dictionary).is_empty():
			e["garrison"] = _garrison(platform_def(str(e["ptype"])), 0.2)
		srv.world.bump(e)
		if not prev.is_empty():
			srv.social.post(prev, U.t("Sistema"), U.t("La guarnición de la %s resistió un ataque de [%s].") % [pname, tag], "rally")


func _bot_titles(now: int) -> void:
	var c: Dictionary = citadel()
	var holder: String = str(c.get("holder", ""))
	if holder.is_empty():
		return
	var mem: Array = srv.social.members(holder)
	if mem.is_empty() or mem.any(func(m: Dictionary) -> bool: return not m.get("is_bot", false) and srv.alliance.rank_of(m) in ["R5", "R4"]):
		return
	var own: Array = mem.filter(func(m: Dictionary) -> bool: return str(m.get("system", "")) == srv.current_system)
	var rivals: Array = srv.state["players"].values().filter(func(m: Dictionary) -> bool: return m.get("is_bot", false) and str(m.get("tag", "")) != holder and str(m.get("system", "")) == srv.current_system)
	var titles: Dictionary = srv.cur.get("titles", {})
	for t: Dictionary in cfg().get("titles", {}).get("list", []):
		if titles.has(t["id"]):
			continue
		var pool: Array = own if bool(t.get("positive", true)) else rivals
		if pool.is_empty():
			continue
		var who: Dictionary = pool[srv.rng.randi() % pool.size()]
		_assign(str(t["id"]), str(who["id"]), str(mem[0]["id"]), now)


# ---------------------------------------------------------------- Operación de Rescate

func rescue_start(p: Dictionary) -> Dictionary:
	if Eco.room_level(p, "cryo") <= 0:
		return _err("NO_ROOM", U.t("Necesitas el Criosantuario"))
	if not (p["queues"].get("rescue", {}) as Dictionary).is_empty():
		return _err("QUEUE_BUSY", U.t("Ya hay una Operación de Rescate en curso"))
	if Eco.troops_total(p.get("cryo", {})) <= 0:
		return _err("NOTHING", U.t("No hay fuerzas en criostasis que rescatar"))
	var rc: Dictionary = cfg().get("rescue", {})
	srv.progression._start_queue(p, "rescue", float(rc.get("minutes", 120)) * 60.0, {"label": U.t("Operación de Rescate")})
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


## Al terminar: devuelve `ratio` de cada pila en criostasis.
func rescue_complete(p: Dictionary) -> Dictionary:
	var ratio: float = float(cfg().get("rescue", {}).get("ratio", 0.3))
	var back: Dictionary = {}
	var cryo: Dictionary = p.get("cryo", {})
	for k: String in cryo.keys():
		var n: int = int(floor(int(cryo[k]) * ratio))
		if n > 0:
			back[k] = n
			cryo[k] = int(cryo[k]) - n
			if int(cryo[k]) <= 0:
				cryo.erase(k)
	Eco.add_troops(p["troops"], back)
	return back


# ---------------------------------------------------------------- vista

func view(p: Dictionary) -> Dictionary:
	if srv.cur.is_empty():
		return {}
	ensure_system()
	var now: int = U.now_ms()
	var pls: Array = []
	for e: Dictionary in platforms():
		var d: Dictionary = platform_def(str(e["ptype"]))
		pls.append({"id": e["id"], "ptype": e["ptype"], "name": U.t(str(d.get("name", ""))), "desc": U.t(str(d.get("desc", ""))),
			"buff": d.get("buff", {}), "holder": e.get("holder", ""), "shield_until": int(e.get("shield_until", 0)),
			"garrison": e["garrison"], "pos": e["pos"], "titles": bool(d.get("titles", false))})
	var hvs: Array = []
	for x: Dictionary in hives():
		var t: Dictionary = hive_tier(int(x.get("tier", 1)))
		hvs.append({"id": x["id"], "tier": int(x.get("tier", 1)), "name": U.t(str(t.get("name", ""))), "hp": int(x["hp"]), "max_hp": int(x["max_hp"]),
			"pos": x["pos"], "kill": t.get("kill", {}), "my_damage": int(x.get("damage_by", {}).get(p["id"], 0))})
	var tl: Array = []
	var titles: Dictionary = srv.cur.get("titles", {})
	for t: Dictionary in cfg().get("titles", {}).get("list", []):
		var cur_t: Dictionary = titles.get(t["id"], {})
		tl.append({"id": t["id"], "name": U.t(str(t["name"])), "positive": bool(t.get("positive", true)), "mods": t.get("mods", {}),
			"pid": str(cur_t.get("pid", "")), "holder_name": srv.display_name(str(cur_t.get("pid", ""))) if not cur_t.is_empty() else "",
			"until": int(cur_t.get("until", 0)), "cooldown": int(srv.cur.get("title_cd", {}).get(t["id"], 0))})
	var cands: Array = []
	if can_grant(p):
		for q: Dictionary in srv.state["players"].values():
			if str(q.get("system", "")) == srv.current_system:
				cands.append({"id": q["id"], "name": srv.display_name(q["id"]), "tag": str(q.get("tag", "")), "power": srv.player_power(q), "avatar": q.get("avatar", "p01")})
		cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["power"]) > int(b["power"]))
		cands = cands.slice(0, 40)
	var rescue: Dictionary = p["queues"].get("rescue", {})
	return {"platforms": pls, "hives": hvs, "titles": tl, "can_grant": can_grant(p), "citadel_holder": str(citadel().get("holder", "")),
		"rescue": rescue, "rescue_ratio": float(cfg().get("rescue", {}).get("ratio", 0.3)), "rescue_minutes": int(cfg().get("rescue", {}).get("minutes", 120)),
		"platform_mods": p.get("platform_mods", {}), "title_mods": p.get("title_mods", {}), "candidates": cands}
