extends RefCounted
## Social y Política (Equipo 4), versión MVP: Alianzas con chat, Ayuda Mutua
## (-1% / mín. 60 s por ayuda) y Cápsulas de Suministro generadas por las cazas
## de los miembros (modelo sin fan-out: abrir todas es un único apunte al ledger).

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")

const CHAT_KEEP: int = 80
const MAX_CAPSULES: int = 100
const CAPSULE_TTL_MS: int = 24 * 3600 * 1000

const BOT_LINES: Array = [
	"¿Alguien caza Xenoformas N3 cerca del cinturón?",
	"Ayudas enviadas a todos!",
	"Cuidado con [XEN], están saqueando el sector norte.",
	"Recuerden mantener la Bóveda Cuántica al día.",
	"Asteroides N4 libres hacia el centro, vayan con escudos.",
	"Gracias por las cápsulas!",
	"Órdenes del Día casi completas, faltan cazas.",
	"Necesito Kliptium, ¿alguien tiene de sobra?",
	"Si les atacan, curen rápido en la Bahía Médica.",
	"Mañana organizamos un asedio a la Colmena.",
	"Los Cañoneros destrozan el Escudo Perimetral, ojo.",
	"Pilotos > Infantería, no lo olviden.",
]

var srv: Node


func _init(server: Node) -> void:
	srv = server


func alliances() -> Dictionary:
	return srv.state["alliances"]


func ensure_alliances() -> void:
	if not srv.state.has("alliances") or srv.state["alliances"].is_empty():
		var out: Dictionary = {}
		for a: Dictionary in Catalog.cfg("alliances", []):
			out[a["tag"]] = {"tag": a["tag"], "name": a["name"], "color": a["color"], "level": a["level"], "chat": []}
		srv.state["alliances"] = out


func members(tag: String) -> Array:
	var out: Array = []
	for p: Dictionary in srv.state["players"].values():
		if str(p.get("tag", "")) == tag:
			out.append(p)
	return out


func post(tag: String, from: String, text: String, kind: String = "chat") -> void:
	var a: Dictionary = alliances().get(tag, {})
	if a.is_empty():
		return
	var msg: Dictionary = {"ts": U.now_ms(), "from": from, "text": text, "kind": kind, "tag": tag}
	var chat: Array = a["chat"]
	chat.append(msg)
	while chat.size() > CHAT_KEEP:
		chat.pop_front()
	for p: Dictionary in members(tag):
		if not p.get("is_bot", false):
			srv.send_to_player(p["id"], {"type": "chat", "message": msg})


func send_chat(p: Dictionary, text: String) -> Dictionary:
	var clean: String = text.strip_edges().substr(0, 200)
	if clean.is_empty():
		return {"ok": false, "code": "EMPTY", "message": U.t("Mensaje vacío")}
	post(str(p.get("tag", "")), str(p["name"]), clean)
	return {"ok": true}


func on_xeno_killed(p: Dictionary, x: Dictionary) -> void:
	var tag: String = str(p.get("tag", ""))
	if tag.is_empty():
		return
	# Las cazas de comandantes bot generan cápsulas con menor frecuencia (economía de la demo).
	if p.get("is_bot", false) and srv.rng.randf() > 0.3:
		return
	var sp: Dictionary = Catalog.species_by_id.get(x["species"], {})
	post(tag, U.t("Sistema"), U.t("%s abatió %s N%d. ¡Cápsula de Suministro para toda la Alianza!") % [p["name"], sp.get("name", U.t("Xenoforma")), int(x["level"])], "system")
	for m: Dictionary in members(tag):
		if m.get("is_bot", false):
			continue
		var caps: Array = m.get("capsules", [])
		if caps.size() >= MAX_CAPSULES:
			continue
		caps.append({"id": "cap_%s" % U.new_id(), "from": p["name"], "level": int(x["level"]), "ts": U.now_ms()})
		m["capsules"] = caps
		srv.mark_player_dirty(m["id"])


func on_combat(att: Dictionary, def: Dictionary, attacker_won: bool) -> void:
	var at: String = str(att.get("tag", ""))
	var dt: String = str(def.get("tag", ""))
	if not at.is_empty():
		post(at, U.t("Sistema"), (U.t("%s saqueó a %s") if attacker_won else U.t("%s fue repelido por %s")) % [att["name"], srv.display_name(def["id"])], "system")
	if not dt.is_empty() and dt != at:
		post(dt, U.t("Sistema"), (U.t("%s sufrió el ataque de %s") if attacker_won else U.t("%s repelió el ataque de %s")) % [def["name"], srv.display_name(att["id"])], "system")


func open_capsules(p: Dictionary) -> Dictionary:
	var caps: Array = p.get("capsules", [])
	var now: int = U.now_ms()
	var reward: Dictionary = {}
	var opened: int = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = U.hash_seed(p["id"] + str(now))
	for c: Dictionary in caps:
		if now - int(c.get("ts", now)) > CAPSULE_TTL_MS:
			continue
		var lvl: int = int(c.get("level", 1))
		opened += 1
		reward["credits"] = int(reward.get("credits", 0)) + rng.randi_range(60, 140) * lvl
		var e: String = Catalog.element_ids[rng.randi() % Catalog.element_ids.size()]
		reward[e] = int(reward.get(e, 0)) + rng.randi_range(50, 120) * lvl
		if rng.randf() < 0.35:
			reward["dark_matter"] = int(reward.get("dark_matter", 0)) + rng.randi_range(3, 8) * lvl
		if rng.randf() < 0.25:
			reward["speedup_1m"] = int(reward.get("speedup_1m", 0)) + 1
		if rng.randf() < 0.15:
			reward["energy"] = int(reward.get("energy", 0)) + 5
	p["capsules"] = []
	if opened == 0:
		return {"ok": false, "code": "NO_CAPSULES", "message": U.t("No hay cápsulas")}
	# Un único apunte al ledger para "abrir todas".
	srv.progression.grant(p, reward, "capsules:%d" % opened)
	srv.missions.on_event(p, "capsule_opened", opened)
	return {"ok": true, "reward": reward, "opened": opened}


## Pide ayuda a la Alianza para un temporizador. Los compañeros (bots en la demo)
## responden durante los siguientes segundos.
func request_help(p: Dictionary, queue: String) -> Dictionary:
	var job: Variant = p["queues"].get(queue)
	if not (job is Dictionary) or (job as Dictionary).is_empty():
		return {"ok": false, "code": "NO_JOB", "message": U.t("No hay temporizador activo")}
	if bool(job.get("help_requested", false)):
		return {"ok": false, "code": "ALREADY", "message": U.t("Ya pediste ayuda para esto")}
	var tag: String = str(p.get("tag", ""))
	if tag.is_empty():
		return {"ok": false, "code": "NO_ALLIANCE", "message": U.t("No perteneces a una Alianza")}
	job["help_requested"] = true
	var helpers: Array = members(tag).filter(func(m: Dictionary) -> bool: return m["id"] != p["id"])
	helpers.shuffle()
	var pending: Array = srv.state.get("pending_helps", [])
	var now: int = U.now_ms()
	for i: int in range(mini(helpers.size(), 10)):
		pending.append({"pid": p["id"], "queue": queue, "from": helpers[i]["name"], "at": now + srv.rng.randi_range(1500, 12000), "job_start": job["start"]})
	srv.state["pending_helps"] = pending
	post(tag, p["name"], U.t("¡Necesito ayuda con %s!") % job.get("label", queue), "help")
	return {"ok": true}


func tick(now: int) -> void:
	var pending: Array = srv.state.get("pending_helps", [])
	if not pending.is_empty():
		var keep: Array = []
		for h: Dictionary in pending:
			if int(h["at"]) > now:
				keep.append(h)
				continue
			var p: Dictionary = srv.player(h["pid"])
			if p.is_empty():
				continue
			var job: Variant = p["queues"].get(h["queue"])
			if not (job is Dictionary) or (job as Dictionary).is_empty() or int(job["start"]) != int(h["job_start"]):
				continue
			if int(job.get("helps", 0)) >= 10:
				continue
			srv.progression.apply_help(p, h["queue"])
			srv.notify(p["id"], U.t("%s te ayudó (-%s)") % [h["from"], U.fmt_duration_short(maxi(60000, int(int(job["total"]) * 0.01)) / 1000.0)], "help")
			srv.mark_player_dirty(p["id"], true)
		srv.state["pending_helps"] = keep
	# Charla ocasional de los compañeros de alianza para dar vida al chat.
	var next_chat: int = int(srv.state.get("next_bot_chat", 0))
	if now >= next_chat:
		srv.state["next_bot_chat"] = now + srv.rng.randi_range(35000, 80000)
		for tag: String in alliances():
			var bots: Array = members(tag).filter(func(m: Dictionary) -> bool: return m.get("is_bot", false))
			var humans: Array = members(tag).filter(func(m: Dictionary) -> bool: return not m.get("is_bot", false))
			if bots.is_empty() or humans.is_empty():
				continue
			var b: Dictionary = bots[srv.rng.randi() % bots.size()]
			post(tag, b["name"], U.t(BOT_LINES[srv.rng.randi() % BOT_LINES.size()]))


func alliance_view(p: Dictionary) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	var a: Dictionary = alliances().get(tag, {})
	if a.is_empty():
		return {}
	var list: Array = []
	for m: Dictionary in members(tag):
		list.append({"id": m["id"], "name": m["name"], "avatar": m.get("avatar", "p01"), "power": srv.player_power(m), "bot": m.get("is_bot", false), "rank": m.get("rank", "R2")})
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["power"]) > int(y["power"]))
	return {"tag": tag, "name": a["name"], "color": a["color"], "level": a["level"], "members": list}
