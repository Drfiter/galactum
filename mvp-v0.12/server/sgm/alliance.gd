extends RefCounted
## Gestión de Alianzas (feedback del 26/10: "no puedes buscar, crear, unirte ni
## salir; todos son R2; faltan Tesorería, Tienda y Bonos; no hay Asedio ni
## refuerzos").
##
## - Crear, buscar, unirse (abierta / por solicitud / por invitación) y salir.
## - Rangos R1-R5 con permisos definidos como datos (catalog_alliance.json):
##   invitar, aceptar, expulsar, ascender, cambiar el modo, Tesorería, Asedio…
## - Tesorería: los miembros donan recursos; R4/R5 retiran con límite diario por
##   rango; cada movimiento queda en el registro de auditoría.
## - Bonos de Alianza (moneda personal "bonds"): se ganan ayudando, donando,
##   participando en Asedios y reforzando; se gastan en la Tienda de Alianza.
## - Asedio (rally) y refuerzos: ver rally_* y reinforce_* más abajo; el
##   combate lo resuelve sss/fleets.gd.

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const DAY_MS: int = 86400000

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.alliance


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func alliances() -> Dictionary:
	return srv.social.alliances()


func _a(tag: String) -> Dictionary:
	var a: Dictionary = alliances().get(tag, {})
	if not a.is_empty():
		for k: String in ["requests", "invites", "treasury", "withdrawn"]:
			if not a.has(k):
				a[k] = {}
		if not a.has("treasury_log"):
			a["treasury_log"] = []
		if not a.has("join_mode"):
			a["join_mode"] = "request"
	return a


func rank_of(p: Dictionary) -> String:
	return str(p.get("rank", "R2"))


func rank_num(rank: String) -> int:
	return int(rank.substr(1)) if rank.length() == 2 else 0


func can(p: Dictionary, perm: String) -> bool:
	return (cfg().get("role_permissions", {}).get(rank_of(p), []) as Array).has(perm)


func max_members(tag: String) -> int:
	var lvl: int = int(_a(tag).get("level", 1))
	return int(cfg().get("max_members_base", 30)) + int(cfg().get("max_members_per_level", 5)) * (lvl - 1)


## Garantiza que cada alianza tenga un líder R5 y algunos oficiales (alianzas
## de la demo que no fueron creadas por un jugador).
func ensure_ranks() -> void:
	for tag: String in alliances():
		var members: Array = srv.social.members(tag)
		if members.is_empty():
			continue
		if members.any(func(m: Dictionary) -> bool: return str(m.get("rank", "")) == "R5"):
			continue
		var bots: Array = members.filter(func(m: Dictionary) -> bool: return m.get("is_bot", false))
		bots.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return srv.player_power(x) > srv.player_power(y))
		for i: int in range(bots.size()):
			bots[i]["rank"] = "R5" if i == 0 else ("R4" if i <= 2 else ("R3" if i <= 5 else "R2"))
		if bots.is_empty():
			members[0]["rank"] = "R5"
		_a(tag)["leader"] = str(members.filter(func(m: Dictionary) -> bool: return str(m.get("rank", "")) == "R5")[0]["id"])


# ---------------------------------------------------------------- crear / buscar / unirse / salir

func create(p: Dictionary, tag: String, name: String, mode: String) -> Dictionary:
	tag = tag.strip_edges().to_upper()
	name = name.strip_edges().substr(0, 28)
	if tag.length() != int(cfg().get("tag_length", 3)) or not _alnum(tag):
		return _err("BAD_TAG", U.t("La etiqueta debe tener 3 letras o números"))
	if name.length() < 3:
		return _err("BAD_NAME", U.t("El nombre debe tener al menos 3 caracteres"))
	if alliances().has(tag):
		return _err("TAG_TAKEN", U.t("Ya existe una alianza con la etiqueta [%s]") % tag)
	for t: String in alliances():
		if str(alliances()[t].get("name", "")).to_lower() == name.to_lower():
			return _err("NAME_TAKEN", U.t("Ya existe una alianza con ese nombre"))
	if not (cfg().get("join_modes", []) as Array).has(mode):
		mode = "request"
	var err: Dictionary = _can_leave(p)
	if not err.is_empty():
		return err
	if not Eco.apply(p, Eco.negate(cfg().get("create_cost", {})), "alliance_create", "alliance_create:%s" % tag):
		return _err("INSUFFICIENT_RESOURCES", U.t("Crear una alianza cuesta %s Créditos y %s Materia Oscura") % [U.fmt_int(int(cfg()["create_cost"].get("credits", 0))), U.fmt_int(int(cfg()["create_cost"].get("dark_matter", 0)))])
	_leave_current(p)
	var colors: Array = ["#ffb347", "#7fd1ff", "#c77dff", "#5ce08a", "#ff6680", "#ffe14d"]
	alliances()[tag] = {"tag": tag, "name": name, "color": colors[U.hash_seed(tag) % colors.size()], "level": 1, "chat": [],
		"leader": p["id"], "join_mode": mode, "created_by_player": true, "requests": {}, "invites": {}, "treasury": {}, "treasury_log": [], "withdrawn": {}}
	_set_member(p, tag, "R5")
	srv.guild.data(tag)
	srv.social.post(tag, U.t("Sistema"), U.t("%s fundó la Alianza [%s] %s.") % [p["name"], tag, name], "system")
	return {"ok": true, "tag": tag}


func _alnum(s: String) -> bool:
	for ch: String in s:
		if not ((ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			return false
	return true


func search(p: Dictionary, query: String, only_open: bool) -> Dictionary:
	var q: String = query.strip_edges().to_lower()
	var out: Array = []
	for tag: String in alliances():
		var a: Dictionary = _a(tag)
		if not q.is_empty() and not (tag.to_lower().contains(q) or str(a["name"]).to_lower().contains(q)):
			continue
		if only_open and str(a["join_mode"]) != "open":
			continue
		var members: Array = srv.social.members(tag)
		var pw: int = 0
		for m: Dictionary in members:
			pw += srv.player_power(m)
		out.append({"tag": tag, "name": U.t(str(a["name"])), "color": a.get("color", "#ffffff"), "level": int(a.get("level", 1)),
			"members": members.size(), "max": max_members(tag), "power": pw, "mode": a["join_mode"],
			"requested": a["requests"].has(p["id"]), "invited": a["invites"].has(p["id"]), "mine": tag == str(p.get("tag", ""))})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["power"]) > int(y["power"]))
	return {"ok": true, "results": out}


func join(p: Dictionary, tag: String) -> Dictionary:
	var a: Dictionary = _a(tag)
	if a.is_empty():
		return _err("NOT_FOUND", U.t("Alianza no encontrada"))
	if tag == str(p.get("tag", "")):
		return _err("ALREADY_MEMBER", U.t("Ya eres miembro"))
	if srv.social.members(tag).size() >= max_members(tag):
		return _err("FULL", U.t("La alianza está llena"))
	var err: Dictionary = _can_leave(p)
	if not err.is_empty():
		return err
	var invited: bool = a["invites"].has(p["id"])
	match str(a["join_mode"]):
		"open":
			pass
		"request":
			if not invited:
				a["requests"][p["id"]] = U.now_ms()
				srv.social.post(tag, U.t("Sistema"), U.t("%s pidió unirse a la Alianza.") % p["name"], "system")
				_auto_review(tag)
				srv.mark_player_dirty(p["id"])
				return {"ok": true, "pending": not a["requests"].is_empty() and a["requests"].has(p["id"]), "joined": str(p.get("tag", "")) == tag}
		"invite":
			if not invited:
				return _err("INVITE_ONLY", U.t("Esta alianza solo admite por invitación"))
	_leave_current(p)
	_set_member(p, tag, str(cfg().get("default_rank", "R1")))
	a["invites"].erase(p["id"])
	a["requests"].erase(p["id"])
	srv.social.post(tag, U.t("Sistema"), U.t("%s se unió a la Alianza. ¡Bienvenido, comandante!") % p["name"], "system")
	return {"ok": true, "joined": true}


## Los líderes bot aceptan solicitudes de inmediato si el poder alcanza.
func _auto_review(tag: String) -> void:
	var a: Dictionary = _a(tag)
	var leader: Dictionary = srv.player(str(a.get("leader", "")))
	if leader.is_empty() or not leader.get("is_bot", false):
		return
	for pid: String in a["requests"].keys():
		var cand: Dictionary = srv.player(pid)
		if not cand.is_empty():
			accept(leader, pid)


func _can_leave(p: Dictionary) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	if tag.is_empty():
		return {}
	if rank_of(p) == "R5" and srv.social.members(tag).size() > 1:
		return _err("LEADER_MUST_TRANSFER", U.t("Eres el líder: transfiere el liderazgo antes de salir"))
	return {}


func _leave_current(p: Dictionary) -> void:
	var tag: String = str(p.get("tag", ""))
	if tag.is_empty():
		return
	p["tag"] = ""
	p["rank"] = ""
	p["ally_mods"] = {}
	if srv.social.members(tag).is_empty() and bool(_a(tag).get("created_by_player", false)):
		alliances().erase(tag)
	else:
		srv.social.post(tag, U.t("Sistema"), U.t("%s dejó la Alianza.") % p["name"], "system")
	srv.refresh_alliances()
	srv.mark_player_dirty(p["id"])
	srv.bump_base_of(p["id"])


func _set_member(p: Dictionary, tag: String, rank: String) -> void:
	p["tag"] = tag
	p["rank"] = rank
	srv.guild.refresh_member_mods(tag)
	srv.refresh_alliances()
	srv.mark_player_dirty(p["id"])
	srv.bump_base_of(p["id"])


func leave(p: Dictionary) -> Dictionary:
	if str(p.get("tag", "")).is_empty():
		return _err("NO_ALLIANCE", U.t("No perteneces a una Alianza"))
	var err: Dictionary = _can_leave(p)
	if not err.is_empty():
		return err
	_leave_current(p)
	return {"ok": true}


# ---------------------------------------------------------------- miembros, rangos y permisos

func _same(p: Dictionary, pid: String) -> Dictionary:
	var t: Dictionary = srv.player(pid)
	if t.is_empty() or str(t.get("tag", "")) != str(p.get("tag", "")) or str(p.get("tag", "")).is_empty():
		return {}
	return t


func accept(p: Dictionary, pid: String) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	if not can(p, "accept"):
		return _err("NO_PERMISSION", U.t("Tu rango no permite aceptar solicitudes"))
	var a: Dictionary = _a(tag)
	if not a["requests"].has(pid):
		return _err("NO_REQUEST", U.t("No hay solicitud de ese comandante"))
	var cand: Dictionary = srv.player(pid)
	a["requests"].erase(pid)
	if cand.is_empty() or not _can_leave(cand).is_empty():
		return _err("CANNOT_JOIN", U.t("Ese comandante no puede unirse ahora"))
	_leave_current(cand)
	_set_member(cand, tag, str(cfg().get("default_rank", "R1")))
	srv.notify(pid, U.t("Fuiste aceptado en la Alianza [%s]") % tag, "success")
	srv.social.post(tag, U.t("Sistema"), U.t("%s se unió a la Alianza. ¡Bienvenido, comandante!") % cand["name"], "system")
	return {"ok": true}


func reject(p: Dictionary, pid: String) -> Dictionary:
	if not can(p, "accept"):
		return _err("NO_PERMISSION", U.t("Tu rango no permite gestionar solicitudes"))
	_a(str(p.get("tag", "")))["requests"].erase(pid)
	return {"ok": true}


func invite(p: Dictionary, pid: String) -> Dictionary:
	if not can(p, "invite"):
		return _err("NO_PERMISSION", U.t("Tu rango no permite invitar"))
	var t: Dictionary = srv.player(pid)
	if t.is_empty() or str(t.get("tag", "")) == str(p.get("tag", "")):
		return _err("INVALID", U.t("No puedes invitar a ese comandante"))
	_a(str(p["tag"]))["invites"][pid] = U.now_ms()
	srv.notify(pid, U.t("%s te invitó a la Alianza [%s]") % [p["name"], p["tag"]], "info")
	# Los bots sin alianza propia aceptan la invitación si su alianza es pequeña.
	if t.get("is_bot", false) and srv.social.members(str(t.get("tag", ""))).size() > 3 and rank_of(t) != "R5":
		join(t, str(p["tag"]))
	return {"ok": true}


func set_rank(p: Dictionary, pid: String, rank: String) -> Dictionary:
	var t: Dictionary = _same(p, pid)
	if t.is_empty():
		return _err("NOT_MEMBER", U.t("No es miembro de tu alianza"))
	if not can(p, "promote"):
		return _err("NO_PERMISSION", U.t("Tu rango no permite cambiar rangos"))
	var mine: int = rank_num(rank_of(p))
	if rank_num(rank) < 1 or rank_num(rank) >= mine or rank_num(rank_of(t)) >= mine:
		return _err("RANK_LIMIT", U.t("Solo puedes asignar rangos inferiores al tuyo"))
	t["rank"] = rank
	srv.notify(pid, U.t("Tu rango en la Alianza ahora es %s") % rank, "info")
	srv.social.post(str(p["tag"]), U.t("Sistema"), U.t("%s ahora es %s (%s).") % [t["name"], rank, U.t(rank_name(rank))], "system")
	srv.mark_player_dirty(pid)
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


func transfer(p: Dictionary, pid: String) -> Dictionary:
	var t: Dictionary = _same(p, pid)
	if t.is_empty():
		return _err("NOT_MEMBER", U.t("No es miembro de tu alianza"))
	if not can(p, "transfer"):
		return _err("NO_PERMISSION", U.t("Solo el líder puede transferir el liderazgo"))
	t["rank"] = "R5"
	p["rank"] = "R4"
	_a(str(p["tag"]))["leader"] = pid
	srv.social.post(str(p["tag"]), U.t("Sistema"), U.t("%s es el nuevo líder de la Alianza.") % t["name"], "system")
	srv.mark_player_dirty(pid)
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


func kick(p: Dictionary, pid: String) -> Dictionary:
	var t: Dictionary = _same(p, pid)
	if t.is_empty():
		return _err("NOT_MEMBER", U.t("No es miembro de tu alianza"))
	if not can(p, "kick") or rank_num(rank_of(t)) >= rank_num(rank_of(p)):
		return _err("NO_PERMISSION", U.t("No puedes expulsar a ese miembro"))
	var tag: String = str(p["tag"])
	_leave_current(t)
	srv.notify(pid, U.t("Fuiste expulsado de la Alianza [%s]") % tag, "danger")
	return {"ok": true}


func set_mode(p: Dictionary, mode: String) -> Dictionary:
	if not can(p, "set_mode") or not (cfg().get("join_modes", []) as Array).has(mode):
		return _err("NO_PERMISSION", U.t("No puedes cambiar el modo de ingreso"))
	_a(str(p["tag"]))["join_mode"] = mode
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


func rank_name(rank: String) -> String:
	for r: Dictionary in cfg().get("ranks", []):
		if str(r["id"]) == rank:
			return str(r["name"])
	return rank


# ---------------------------------------------------------------- Tesorería

func donate(p: Dictionary, res: String, amount: int) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	if tag.is_empty():
		return _err("NO_ALLIANCE", U.t("No perteneces a una Alianza"))
	if not (cfg().get("treasury_resources", []) as Array).has(res) or amount <= 0:
		return _err("INVALID", U.t("Recurso no válido"))
	if not Eco.apply(p, {res: -amount}, "treasury_donate"):
		return _err("INSUFFICIENT_RESOURCES", U.t("No tienes esa cantidad"))
	var a: Dictionary = _a(tag)
	a["treasury"][res] = int(a["treasury"].get(res, 0)) + amount
	_log(a, p, "donate", res, amount)
	var bonds: int = int(amount / maxi(1, int(cfg().get("bonds", {}).get("donate_per", 10))))
	if bonds > 0:
		Eco.apply(p, {"bonds": bonds}, "bonds_donate")
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "bonds": bonds}


func withdraw(p: Dictionary, res: String, amount: int) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	if not can(p, "treasury"):
		return _err("NO_PERMISSION", U.t("Tu rango no permite retirar de la Tesorería"))
	var a: Dictionary = _a(tag)
	if amount <= 0 or int(a["treasury"].get(res, 0)) < amount:
		return _err("INSUFFICIENT_RESOURCES", U.t("La Tesorería no tiene esa cantidad"))
	var limit: int = int(cfg().get("treasury_daily_limit", {}).get(rank_of(p), 0))
	var day: int = int(U.now_ms() / DAY_MS)
	var w: Dictionary = a["withdrawn"].get(p["id"], {})
	if int(w.get("day", -1)) != day:
		w = {"day": day, "amount": 0}
	if limit >= 0 and int(w["amount"]) + amount > limit:
		return _err("DAILY_LIMIT", U.t("Superas tu límite diario de retiro (%s)") % U.fmt_int(limit))
	a["treasury"][res] = int(a["treasury"][res]) - amount
	w["amount"] = int(w["amount"]) + amount
	a["withdrawn"][p["id"]] = w
	Eco.apply(p, {res: amount}, "treasury_withdraw")
	_log(a, p, "withdraw", res, amount)
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


## Registro de auditoría de la Tesorería (últimos 60 movimientos).
func _log(a: Dictionary, p: Dictionary, kind: String, res: String, amount: int) -> void:
	var log: Array = a["treasury_log"]
	log.append({"ts": U.now_ms(), "who": p["name"], "rank": rank_of(p), "kind": kind, "res": res, "amount": amount})
	while log.size() > 60:
		log.pop_front()


# ---------------------------------------------------------------- Bonos y Tienda de Alianza

func shop_buy(p: Dictionary, item_id: String) -> Dictionary:
	if str(p.get("tag", "")).is_empty():
		return _err("NO_ALLIANCE", U.t("No perteneces a una Alianza"))
	var entry: Dictionary = {}
	for e: Dictionary in cfg().get("shop", []):
		if str(e["id"]) == item_id:
			entry = e
	if entry.is_empty():
		return _err("NOT_FOUND", U.t("Artículo no disponible"))
	var day: int = int(U.now_ms() / DAY_MS)
	var bought: Dictionary = p.get("ally_shop", {})
	if int(bought.get("day", -1)) != day:
		bought = {"day": day}
	if int(bought.get(item_id, 0)) >= int(entry.get("daily", 1)):
		return _err("DAILY_LIMIT", U.t("Límite diario alcanzado para este artículo"))
	if not Eco.apply(p, {"bonds": -int(entry["cost"]), item_id: 1}, "ally_shop"):
		return _err("INSUFFICIENT_RESOURCES", U.t("Bonos de Alianza insuficientes (%s)") % U.fmt_int(int(entry["cost"])))
	bought[item_id] = int(bought.get(item_id, 0)) + 1
	p["ally_shop"] = bought
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


## Ayuda Mutua dada: ayuda a todas las peticiones abiertas de la alianza.
## Cada ayuda da Bonos (con tope diario anti-abuso).
func help_all(p: Dictionary) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	if tag.is_empty():
		return _err("NO_ALLIANCE", U.t("No perteneces a una Alianza"))
	var a: Dictionary = _a(tag)
	var reqs: Array = a.get("help_requests", [])
	var bcfg: Dictionary = cfg().get("bonds", {})
	var day: int = int(U.now_ms() / DAY_MS)
	var hd: Dictionary = p.get("help_given", {})
	if int(hd.get("day", -1)) != day:
		hd = {"day": day, "n": 0}
	var helped: int = 0
	for r: Dictionary in reqs:
		if int(hd["n"]) >= int(bcfg.get("help_daily_cap", 20)):
			break
		if (r.get("helpers", []) as Array).has(p["id"]) or str(r["pid"]) == p["id"]:
			continue
		(r["helpers"] as Array).append(p["id"])
		hd["n"] = int(hd["n"]) + 1
		helped += 1
		var who: Dictionary = srv.player(str(r["pid"]))
		if not who.is_empty() and not who.get("is_bot", false):
			srv.progression.apply_help(who, str(r.get("queue", "")))
	p["help_given"] = hd
	if helped == 0:
		return _err("NOTHING", U.t("No hay peticiones de ayuda pendientes (o alcanzaste el tope diario)"))
	var bonds: int = helped * int(bcfg.get("help_given", 800))
	Eco.apply(p, {"bonds": bonds}, "bonds_help")
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "helped": helped, "bonds": bonds}


func open_help_requests(p: Dictionary) -> int:
	var n: int = 0
	for r: Dictionary in _a(str(p.get("tag", ""))).get("help_requests", []):
		if not (r.get("helpers", []) as Array).has(p["id"]) and str(r["pid"]) != p["id"]:
			n += 1
	return n


func grant_bonds(p: Dictionary, kind: String) -> void:
	var n: int = int(cfg().get("bonds", {}).get(kind, 0))
	if n > 0 and not p.is_empty():
		Eco.apply(p, {"bonds": n}, "bonds_" + kind)


func tick(now: int) -> void:
	# Los compañeros bot publican peticiones de Ayuda Mutua de vez en cuando.
	if now < int(srv.state.get("next_bot_help_req", 0)):
		return
	srv.state["next_bot_help_req"] = now + srv.rng.randi_range(40000, 90000)
	for tag: String in alliances():
		var a: Dictionary = _a(tag)
		var reqs: Array = a.get("help_requests", [])
		reqs = reqs.filter(func(r: Dictionary) -> bool: return now - int(r["ts"]) < 30 * 60000)
		var bots: Array = srv.social.members(tag).filter(func(m: Dictionary) -> bool: return m.get("is_bot", false))
		if not bots.is_empty() and reqs.size() < 12:
			var b: Dictionary = bots[srv.rng.randi() % bots.size()]
			reqs.append({"pid": b["id"], "name": b["name"], "queue": "build", "ts": now, "helpers": []})
		a["help_requests"] = reqs


# ---------------------------------------------------------------- vista

func view(p: Dictionary) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	var out: Dictionary = {"tag": tag, "rank": rank_of(p) if not tag.is_empty() else "", "permissions": cfg().get("role_permissions", {}).get(rank_of(p), []) if not tag.is_empty() else [],
		"bonds": int(p["resources"].get("bonds", 0)), "help_open": open_help_requests(p) if not tag.is_empty() else 0, "invites": []}
	for t: String in alliances():
		if _a(t)["invites"].has(p["id"]):
			(out["invites"] as Array).append({"tag": t, "name": U.t(str(alliances()[t]["name"]))})
	if tag.is_empty():
		return out
	var a: Dictionary = _a(tag)
	var reqs: Array = []
	for pid: String in a["requests"]:
		var c: Dictionary = srv.player(pid)
		if not c.is_empty():
			reqs.append({"id": pid, "name": c["name"], "power": srv.player_power(c)})
	var shop_bought: Dictionary = p.get("ally_shop", {})
	if int(shop_bought.get("day", -1)) != int(U.now_ms() / DAY_MS):
		shop_bought = {}
	out.merge({"name": U.t(str(a["name"])), "mode": a["join_mode"], "leader": srv.display_name(str(a.get("leader", ""))),
		"treasury": a["treasury"], "treasury_log": (a["treasury_log"] as Array).slice(maxi(0, (a["treasury_log"] as Array).size() - 20)),
		"requests": reqs, "max_members": max_members(tag), "shop_bought": shop_bought,
		"withdraw_limit": int(cfg().get("treasury_daily_limit", {}).get(rank_of(p), 0)),
		"withdrawn_today": int(a["withdrawn"].get(p["id"], {}).get("amount", 0)) if int(a["withdrawn"].get(p["id"], {}).get("day", -1)) == int(U.now_ms() / DAY_MS) else 0})
	return out
