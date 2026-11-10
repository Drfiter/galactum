extends RefCounted
## Asedio (rally) y refuerzos — spec Equipo 3: "Asedios (rally con herencia de
## boosts del líder)"; feedback del 26/10: "no hay Asedio ni refuerzos".
##
## Asedio:
## - Un miembro con permiso "rally" (R3+) elige una nave enemiga, aporta sus
##   tropas y abre una ventana de espera (30-120 s en la demo).
## - Los aliados se suman con tropas hasta la capacidad del asedio
##   (capacidad de flota del líder × capacity_mult). Los bots de la alianza se
##   suman solos con cierta probabilidad.
## - Al terminar la espera sale UNA flota conjunta desde la nave del líder con
##   los modificadores del líder (herencia de boosts). El combate lo resuelve el
##   mismo resolver determinista; bajas, heridos y botín se reparten en
##   proporción a lo que aportó cada participante.
## Refuerzos:
## - Un aliado envía tropas a tu nave; quedan estacionadas y defienden con tus
##   tropas. Sus bajas son suyas. Se pueden retirar cuando quiera.
## - Capacidad de refuerzos: base + Muelle de Atraque.

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const Resolver = preload("res://server/combat/combat_resolver.gd")

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.alliance.get("rally", {})


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func rallies() -> Dictionary:
	if not srv.state.has("rallies"):
		srv.state["rallies"] = {}
	return srv.state["rallies"]


func capacity(leader: Dictionary) -> int:
	return int(Eco.march_capacity(leader) * float(cfg().get("capacity_mult", 3.0)))


func _total(r: Dictionary) -> int:
	var n: int = 0
	for pid: String in r["shares"]:
		n += Eco.troops_total(r["shares"][pid])
	return n


func _clean(troops: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: String in troops:
		if int(troops[k]) > 0 and not Catalog.troop_tier(k).is_empty():
			out[k] = int(troops[k])
	return out


# ---------------------------------------------------------------- Asedio

func start(p: Dictionary, target_id: String, troops: Dictionary, wait_sec: int) -> Dictionary:
	if str(p.get("tag", "")).is_empty():
		return _err("NO_ALLIANCE", U.t("Necesitas una Alianza para abrir un Asedio"))
	if not srv.alliance.can(p, "rally"):
		return _err("NO_PERMISSION", U.t("Tu rango no permite abrir Asedios (R3 o superior)"))
	for r: Dictionary in rallies().values():
		if r["leader"] == p["id"] and r["state"] == "gathering":
			return _err("ALREADY", U.t("Ya tienes un Asedio abierto"))
	var target: Dictionary = srv.world.get_entity(target_id)
	if target.is_empty():
		return _err("TARGET_NOT_FOUND", U.t("El objetivo ya no existe"))
	var ok_kind: bool = target["kind"] == "base" or (target["kind"] == "xenoform" and bool(target.get("hive", false)))
	if not ok_kind:
		return _err("INVALID_TARGET", U.t("El Asedio se dirige a una nave enemiga o a una Colmena Xeno"))
	if target["kind"] == "base":
		var err: Dictionary = srv.fleets._validate_attack_target(p, target)
		if not err.is_empty():
			return err
	var base: Dictionary = srv.world.get_entity(p["base_id"])
	if base.is_empty() or base["state"] != "ANCHORED":
		return _err("SHIP_NOT_ANCHORED", U.t("Tu Astronave debe estar anclada"))
	var clean: Dictionary = _clean(troops)
	if clean.is_empty():
		return _err("NO_TROOPS", U.t("Aporta al menos una fuerza"))
	if Eco.troops_total(clean) > capacity(p):
		return _err("CAPACITY", U.t("Supera la capacidad del Asedio (%d)") % capacity(p))
	if not Eco.remove_troops(p["troops"], clean):
		return _err("NOT_ENOUGH_TROOPS", U.t("No tienes esas fuerzas en la nave"))
	var waits: Array = cfg().get("wait_sec", [30, 60, 120])
	if not waits.has(wait_sec):
		wait_sec = int(waits[0])
	var now: int = U.now_ms()
	var r: Dictionary = {
		"id": "rly_%s" % U.new_id(), "tag": p["tag"], "leader": p["id"], "target_id": target_id, "target_kind": target["kind"],
		"target_name": srv.display_name(str(target.get("owner", ""))) if target["kind"] == "base" else U.t("Colmena Xeno"),
		"target_pos": target["pos"], "system": srv.current_system,
		"created": now, "launch_ts": now + wait_sec * 1000, "state": "gathering", "shares": {p["id"]: clean}, "bots_checked": false,
	}
	rallies()[r["id"]] = r
	srv.social.post(str(p["tag"]), p["name"], U.t("¡ASEDIO contra %s! Únete en los próximos %d s desde Alianza → Cuartel → Asedios.") % [r["target_name"], wait_sec], "rally")
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "rally_id": r["id"], "launch_ts": r["launch_ts"]}


func join(p: Dictionary, rally_id: String, troops: Dictionary) -> Dictionary:
	var r: Dictionary = rallies().get(rally_id, {})
	if r.is_empty() or r["state"] != "gathering":
		return _err("RALLY_CLOSED", U.t("Ese Asedio ya no admite tropas"))
	if str(p.get("tag", "")) != str(r["tag"]):
		return _err("NOT_ALLY", U.t("Ese Asedio es de otra alianza"))
	var clean: Dictionary = _clean(troops)
	if clean.is_empty():
		return _err("NO_TROOPS", U.t("Aporta al menos una fuerza"))
	var leader: Dictionary = srv.player(str(r["leader"]))
	if _total(r) + Eco.troops_total(clean) > capacity(leader):
		return _err("CAPACITY", U.t("El Asedio está lleno (%d)") % capacity(leader))
	if not Eco.remove_troops(p["troops"], clean):
		return _err("NOT_ENOUGH_TROOPS", U.t("No tienes esas fuerzas en la nave"))
	var mine: Dictionary = r["shares"].get(p["id"], {})
	Eco.add_troops(mine, clean)
	r["shares"][p["id"]] = mine
	srv.mark_player_dirty(p["id"])
	srv.mark_player_dirty(leader.get("id", ""))
	return {"ok": true}


func cancel(p: Dictionary, rally_id: String) -> Dictionary:
	var r: Dictionary = rallies().get(rally_id, {})
	if r.is_empty() or r["leader"] != p["id"] or r["state"] != "gathering":
		return _err("INVALID", U.t("No puedes cancelar ese Asedio"))
	for pid: String in r["shares"]:
		var q: Dictionary = srv.player(pid)
		if not q.is_empty():
			Eco.add_troops(q["troops"], r["shares"][pid])
			srv.mark_player_dirty(pid)
	rallies().erase(rally_id)
	srv.social.post(str(r["tag"]), U.t("Sistema"), U.t("El Asedio contra %s fue cancelado.") % r["target_name"], "system")
	return {"ok": true}


func _bots_join(r: Dictionary) -> void:
	r["bots_checked"] = true
	var leader: Dictionary = srv.player(str(r["leader"]))
	var chance: float = float(cfg().get("bot_join_chance", 0.6))
	for m: Dictionary in srv.social.members(str(r["tag"])):
		if not m.get("is_bot", false) or m["id"] == r["leader"] or srv.rng.randf() > chance:
			continue
		var room: int = capacity(leader) - _total(r)
		if room <= 20:
			break
		var give: Dictionary = {}
		var budget: int = mini(room, int(Eco.troops_total(m["troops"]) * 0.3))
		for k: String in m["troops"]:
			if budget <= 0:
				break
			var q: int = mini(int(m["troops"][k]) / 3, budget)
			if q > 0:
				give[k] = q
				budget -= q
		if not give.is_empty():
			join(m, r["id"], give)
			srv.social.post(str(r["tag"]), m["name"], U.t("Me sumo al Asedio con %d tropas.") % Eco.troops_total(give), "rally")


func tick(now: int) -> void:
	for rid: String in rallies().keys():
		var r: Dictionary = rallies()[rid]
		if str(r.get("system", "")) != srv.current_system:
			continue
		if r["state"] == "gathering":
			if not bool(r.get("bots_checked", false)) and now - int(r["created"]) > 4000:
				_bots_join(r)
			if now >= int(r["launch_ts"]):
				_launch(r, now)
		elif r["state"] == "marching" and not srv.fleets.fleets().has(str(r.get("fleet_id", ""))):
			r["state"] = "done"
		if r["state"] == "done" and now - int(r["launch_ts"]) > 600000:
			rallies().erase(rid)


## Sale la flota conjunta desde la nave del líder, con los modificadores del líder.
func _launch(r: Dictionary, now: int) -> void:
	var leader: Dictionary = srv.player(str(r["leader"]))
	var target: Dictionary = srv.world.get_entity(str(r["target_id"]))
	var base: Dictionary = srv.world.get_entity(str(leader.get("base_id", "")))
	if leader.is_empty() or target.is_empty() or base.is_empty():
		_refund(r)
		r["state"] = "done"
		srv.social.post(str(r["tag"]), U.t("Sistema"), U.t("El objetivo del Asedio desapareció: las tropas vuelven a casa."), "system")
		return
	var troops: Dictionary = {}
	for pid: String in r["shares"]:
		Eco.add_troops(troops, r["shares"][pid])
	var origin: Vector2 = U.v2(base["pos"])
	var dest: Vector2 = U.v2(target["pos"])
	var mods: Dictionary = Eco.modifiers(leader)
	var speed: float = Resolver.speed_of(troops) * float(Catalog.cfg("march_speed_tiles_per_sec", 1.6)) * (1.0 + float(mods["march_speed"]))
	var f: Dictionary = {
		"id": "flt_%s" % U.new_id(), "owner": leader["id"], "mission": "attack", "target_id": r["target_id"],
		"target_kind": target["kind"], "target_owner": str(target.get("owner", "")),
		"origin": U.arr2(origin), "target": U.arr2(dest), "depart_ts": now,
		"arrive_ts": now + maxi(3000, int(origin.distance_to(dest) / speed * 1000.0)), "state": "outbound",
		"troops": troops, "wounded": {}, "cargo": {}, "speed": speed,
		"mods": Eco.combat_mods(leader, false), "crew": [], "load_bonus": float(mods["load"]), "gather_bonus": 0.0, "rev": 1,
		"rally": r["id"], "shares": r["shares"].duplicate(true),
	}
	srv.fleets.fleets()[f["id"]] = f
	r["fleet_id"] = f["id"]
	r["state"] = "marching"
	var pids: Array = r["shares"].keys()
	srv.social.post(str(r["tag"]), U.t("Sistema"), U.t("¡El Asedio contra %s despega con %d tropas de %d comandantes!") % [r["target_name"], Eco.troops_total(troops), pids.size()], "rally")
	if not str(f["target_owner"]).is_empty():
		srv.notify(str(f["target_owner"]), U.t("¡ASEDIO de la alianza [%s] en camino contra tu nave!") % r["tag"], "danger")
		srv.mark_player_dirty(str(f["target_owner"]))
	for pid: String in pids:
		srv.mark_player_dirty(pid)


func _refund(r: Dictionary) -> void:
	for pid: String in r["shares"]:
		var q: Dictionary = srv.player(pid)
		if not q.is_empty():
			Eco.add_troops(q["troops"], r["shares"][pid])
			srv.mark_player_dirty(pid)


## Reparte un Dictionary tropa->cantidad entre participantes según su aporte.
static func split_by_shares(amounts: Dictionary, shares: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for pid: String in shares:
		out[pid] = {}
	for k: String in amounts:
		var total_k: int = 0
		for pid: String in shares:
			total_k += int(shares[pid].get(k, 0))
		if total_k <= 0:
			continue
		var left: int = int(amounts[k])
		var best: String = ""
		var best_q: int = -1
		for pid: String in shares:
			var q: int = int(shares[pid].get(k, 0))
			if q <= 0:
				continue
			var part: int = int(floor(float(amounts[k]) * q / total_k))
			if part > 0:
				out[pid][k] = part
				left -= part
			if q > best_q:
				best_q = q
				best = pid
		if left > 0 and not best.is_empty():
			out[best][k] = int(out[best].get(k, 0)) + left
	return out


## La flota del Asedio vuelve: cada participante recibe su parte de las tropas,
## los heridos y el botín.
func on_return(f: Dictionary) -> void:
	var shares: Dictionary = f.get("shares", {})
	var surv: Dictionary = split_by_shares(f["troops"], shares)
	var wnd: Dictionary = split_by_shares(f["wounded"], shares)
	var total: int = 0
	for pid: String in shares:
		total += Eco.troops_total(shares[pid])
	for pid: String in shares:
		var q: Dictionary = srv.player(pid)
		if q.is_empty():
			continue
		Eco.add_troops(q["troops"], surv.get(pid, {}))
		if not (wnd.get(pid, {}) as Dictionary).is_empty():
			Eco.absorb_casualties(q, wnd[pid], 1.0)
		if not (f["cargo"] as Dictionary).is_empty() and total > 0:
			var part: Dictionary = {}
			var ratio: float = float(Eco.troops_total(shares[pid])) / float(total)
			for k: String in f["cargo"]:
				var n: int = int(floor(int(f["cargo"][k]) * ratio))
				if n > 0:
					part[k] = n
			if not part.is_empty():
				Eco.apply(q, part, "rally_loot", "rally:%s:%s" % [f["rally"], pid])
		srv.mark_player_dirty(pid)


# ---------------------------------------------------------------- refuerzos

func reinforce_capacity(host: Dictionary) -> int:
	return int(Catalog.alliance.get("reinforce", {}).get("base_capacity", 600)) + int(Eco.effect(host, "dock", "reinforce_capacity"))


func stationed_at(host_id: String) -> Array:
	var out: Array = []
	for f: Dictionary in srv.fleets.fleets().values():
		if f.get("mission", "") == "reinforce" and f.get("state", "") == "stationed" and str(f.get("host", "")) == host_id:
			out.append(f)
	return out


func stationed_total(host_id: String) -> int:
	var n: int = 0
	for f: Dictionary in stationed_at(host_id):
		n += Eco.troops_total(f["troops"])
	return n


## Validación al enviar una flota de refuerzo (mission "reinforce").
func validate_reinforce(p: Dictionary, target: Dictionary, troops: Dictionary) -> Dictionary:
	if target["kind"] != "base" or target["owner"] == p["id"]:
		return _err("INVALID_TARGET", U.t("Solo puedes reforzar la nave de un aliado"))
	var host: Dictionary = srv.player(target["owner"])
	if str(host.get("tag", "")) != str(p.get("tag", "")) or str(p.get("tag", "")).is_empty():
		return _err("NOT_ALLY", U.t("Solo puedes reforzar a miembros de tu Alianza"))
	if stationed_total(host["id"]) + Eco.troops_total(troops) > reinforce_capacity(host):
		return _err("CAPACITY", U.t("La nave aliada no admite más refuerzos (%d)") % reinforce_capacity(host))
	return {}


func on_arrive(f: Dictionary, now: int) -> void:
	var host: Dictionary = srv.player(str(f.get("target_owner", "")))
	var base: Dictionary = srv.world.get_entity(str(f["target_id"]))
	if host.is_empty() or base.is_empty() or U.v2(base["pos"]).distance_to(U.v2(f["target"])) > 1.5:
		srv.fleets._note(f, U.t("La nave aliada ya no está ahí: los refuerzos vuelven"))
		srv.fleets._start_return(f, now, U.v2(f["target"]))
		return
	f["state"] = "stationed"
	f["host"] = host["id"]
	srv.fleets._bump(f)
	var owner: Dictionary = srv.player(f["owner"])
	srv.alliance.grant_bonds(owner, "reinforce")
	srv.notify(host["id"], U.t("%s envió %d tropas de refuerzo a tu nave") % [srv.display_name(f["owner"]), Eco.troops_total(f["troops"])], "success")
	srv.notify(f["owner"], U.t("Tus refuerzos llegaron a la nave de %s") % srv.display_name(host["id"]), "success")
	srv.mark_player_dirty(host["id"])
	srv.mark_player_dirty(f["owner"])


## Bots aliados que refuerzan la nave de un humano atacado.
func maybe_bot_reinforce(host: Dictionary) -> void:
	if host.get("is_bot", false) or str(host.get("tag", "")).is_empty():
		return
	var chance: float = float(Catalog.alliance.get("reinforce", {}).get("bot_reinforce_chance", 0.5))
	if srv.rng.randf() > chance or stationed_total(host["id"]) >= reinforce_capacity(host):
		return
	var base: Dictionary = srv.world.get_entity(host["base_id"])
	for m: Dictionary in srv.social.members(str(host["tag"])):
		if not m.get("is_bot", false):
			continue
		var give: Dictionary = {}
		var room: int = mini(reinforce_capacity(host) - stationed_total(host["id"]), int(Eco.troops_total(m["troops"]) * 0.25))
		for k: String in m["troops"]:
			var q: int = mini(int(m["troops"][k]) / 4, room)
			if q > 0:
				give[k] = q
				room -= q
		if not give.is_empty():
			var r: Dictionary = srv.fleets.start_march(m, "reinforce", base["id"], give)
			if bool(r.get("ok", false)):
				srv.social.post(str(host["tag"]), m["name"], U.t("Te envío refuerzos, %s. ¡Aguanta!") % host["name"], "rally")
				return


## Combina defensores: tropas propias + refuerzos estacionados.
func defense_stacks(def: Dictionary) -> Dictionary:
	var shares: Dictionary = {def["id"]: def["troops"].duplicate()}
	for f: Dictionary in stationed_at(def["id"]):
		shares[f["id"]] = f["troops"].duplicate()
	return shares


## Tras el combate, reparte supervivientes y bajas entre el defensor y cada
## flota de refuerzo. Devuelve las bajas del defensor propio.
func apply_defense_result(def: Dictionary, shares: Dictionary, survivors: Dictionary, losses: Dictionary, now: int) -> Dictionary:
	var surv: Dictionary = split_by_shares(survivors, shares)
	var loss: Dictionary = split_by_shares(losses, shares)
	def["troops"] = surv.get(def["id"], {})
	for fid: String in shares:
		if fid == def["id"]:
			continue
		var f: Dictionary = srv.fleets.fleets().get(fid, {})
		if f.is_empty():
			continue
		f["troops"] = surv.get(fid, {})
		var owner: Dictionary = srv.player(f["owner"])
		if not (loss.get(fid, {}) as Dictionary).is_empty() and not owner.is_empty():
			Eco.absorb_casualties(owner, loss[fid], 1.0)
			srv.notify(owner["id"], U.t("Tus refuerzos defendieron la nave de %s y perdieron %d tropas") % [srv.display_name(def["id"]), Eco.troops_total(loss[fid])], "warning")
		if Eco.troops_total(f["troops"]) <= 0:
			srv.fleets.fleets().erase(fid)
		srv.mark_player_dirty(f["owner"])
	return loss.get(def["id"], {})


func view(p: Dictionary) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	var list: Array = []
	for r: Dictionary in rallies().values():
		if str(r["tag"]) != tag or r["state"] == "done":
			continue
		var leader: Dictionary = srv.player(str(r["leader"]))
		var parts: Array = []
		for pid: String in r["shares"]:
			parts.append({"name": srv.display_name(pid), "troops": Eco.troops_total(r["shares"][pid])})
		list.append({"id": r["id"], "leader": srv.display_name(str(r["leader"])), "mine": r["leader"] == p["id"], "joined": r["shares"].has(p["id"]),
			"target": r["target_name"], "target_pos": r["target_pos"], "state": r["state"], "launch_ts": r["launch_ts"],
			"troops": _total(r), "capacity": capacity(leader), "participants": parts})
	var here: Array = []
	for f: Dictionary in stationed_at(p["id"]):
		here.append({"id": f["id"], "from": srv.display_name(f["owner"]), "troops": Eco.troops_total(f["troops"])})
	var mine: Array = []
	for f: Dictionary in srv.fleets.owned_fleets(p["id"]):
		if f.get("mission", "") == "reinforce":
			mine.append({"id": f["id"], "to": srv.display_name(str(f.get("target_owner", ""))), "troops": Eco.troops_total(f["troops"]), "state": f["state"]})
	return {"rallies": list, "reinforcements_here": here, "reinforce_capacity": reinforce_capacity(p), "my_reinforcements": mine,
		"rally_capacity": capacity(p), "waits": cfg().get("wait_sec", [30, 60, 120])}
