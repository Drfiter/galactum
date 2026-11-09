extends Node
## Servidor autoritativo de Galactum.
##
## Une, como módulos separados por contrato, lo que en producción son dos servicios:
##  - SGM (Servidor Galáctico Maestro): economía, salas, tropas, misiones, alianza.
##  - SSS (Servidor de Sistema Solar): mundo 600×600, flotas, minería, combate.
## Puede correr EMBEBIDO en el cliente (modo local / Android, sin red) o como
## proceso DEDICADO headless con WebSocket (`--server`). El cliente es idéntico en
## ambos casos: solo envía intenciones y recibe estado (nunca informa resultados).

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const Resolver = preload("res://server/combat/combat_resolver.gd")
const WorldMod = preload("res://server/sss/world.gd")
const FleetsMod = preload("res://server/sss/fleets.gd")
const BotsMod = preload("res://server/sss/bots.gd")
const ProgressionMod = preload("res://server/sgm/progression.gd")
const MissionsMod = preload("res://server/sgm/missions.gd")
const SocialMod = preload("res://server/social.gd")
const ReportsMod = preload("res://server/reports.gd")
const GalaxyMod = preload("res://server/sgm/galaxy.gd")
const ShopMod = preload("res://server/sgm/shop.gd")
const GuildMod = preload("res://server/sgm/guild.gd")
const EventsMod = preload("res://server/sgm/events.gd")
const CrewMod = preload("res://server/sgm/crew.gd")
const SpatialHash = preload("res://server/sss/spatial_hash.gd")

const PROTOCOL_VERSION: String = "galactum-mvp-1"
const SAVE_VERSION: int = 5

signal ready_to_serve

var state: Dictionary = {}
var rng := RandomNumberGenerator.new()
var world: RefCounted
var fleets: RefCounted
var bots: RefCounted
var progression: RefCounted
var missions: RefCounted
var social: RefCounted
var reports: RefCounted
var galaxy: RefCounted
var shop: RefCounted
var guild: RefCounted
var events: RefCounted
var crew: RefCounted
## Sistema Solar activo (contexto SSS): entidades, flotas, terreno y respawns.
var cur: Dictionary = {}
var current_system: String = ""
var _hashes: Dictionary = {}       # system_id -> SpatialHash

var save_path: String = "user://galactum_save.json"
var persist: bool = true
var sessions: Dictionary = {}        # session_id -> session
var _next_session: int = 1
var _tick_timer: Timer
var _last_save: int = 0
var _dirty_players: Dictionary = {}  # pid -> true
var verbose: bool = false


func _init() -> void:
	world = WorldMod.new(self)
	fleets = FleetsMod.new(self)
	bots = BotsMod.new(self)
	progression = ProgressionMod.new(self)
	missions = MissionsMod.new(self)
	social = SocialMod.new(self)
	reports = ReportsMod.new(self)
	galaxy = GalaxyMod.new(self)
	shop = ShopMod.new(self)
	guild = GuildMod.new(self)
	events = EventsMod.new(self)
	crew = CrewMod.new(self)


func start(options: Dictionary = {}) -> void:
	save_path = str(options.get("save_path", save_path))
	persist = bool(options.get("persist", true))
	verbose = bool(options.get("verbose", false))
	var loaded: bool = false
	if persist and not bool(options.get("fresh", false)):
		loaded = _load()
	if not loaded:
		_new_world(int(options.get("seed", int(Time.get_unix_time_from_system()) & 0xffffff)))
	rng.seed = int(state.get("seed", 1)) ^ (U.now_ms() & 0xffff)
	_tick_timer = Timer.new()
	_tick_timer.wait_time = 1.0 / float(Catalog.cfg("tick_hz", 2))
	_tick_timer.autostart = true
	_tick_timer.timeout.connect(_tick)
	add_child(_tick_timer)
	_last_save = U.now_ms()
	_log("SSS_READY protocol=%s systems=%d entities=%d players=%d" % [PROTOCOL_VERSION, galaxy.order().size(), cur.get("entities", {}).size(), state["players"].size()])
	ready_to_serve.emit()


func _log(text: String) -> void:
	print(text)


func refresh_alliances() -> void:
	for tag: String in social.alliances():
		guild.data(tag)
		guild.refresh_member_mods(tag)


func log_line(text: String) -> void:
	_log(text)


## Cambia el contexto SSS al sistema indicado (cada sistema es un "servidor").
func use_system(id: String) -> void:
	if id == current_system and not cur.is_empty():
		return
	var s: Dictionary = galaxy.system(id)
	if s.is_empty():
		return
	cur = s
	current_system = id
	if not _hashes.has(id):
		_hashes[id] = SpatialHash.new(16)
		world.hash = _hashes[id]
		world.rebuild_index()
	world.hash = _hashes[id]


## Punto único de actividad (cazas, entregas, combates, gasto): alimenta las
## dinámicas de alianza y los torneos (incluye a los bots, que compiten).
func on_activity(p: Dictionary, kind: String, amount: float, extra: Dictionary = {}) -> void:
	if p.is_empty():
		return
	guild.on_activity(p, kind, amount, extra)
	events.on_activity(p, kind, amount, extra)


func use_player_system(p: Dictionary) -> void:
	var sid: String = str(p.get("system", ""))
	if not sid.is_empty():
		use_system(sid)


func _new_world(seed: int) -> void:
	var now: int = U.now_ms()
	state = {
		"save_version": SAVE_VERSION, "seed": seed, "created_ts": now,
		"players": {}, "reports": {}, "alliances": {}, "pending_helps": [],
	}
	cur = {}
	current_system = ""
	_hashes.clear()
	galaxy.create(seed, now)
	social.ensure_alliances()
	galaxy.ensure_generated(galaxy.newest_open(now))
	refresh_alliances()


# ---------------------------------------------------------------- jugadores

func player(pid: String) -> Dictionary:
	return state["players"].get(pid, {})


## Aliado veterano que acompaña al jugador nuevo. No debe coincidir con el
## nombre de ningún tripulante (antes se llamaba "Comandante Kael", igual que
## el tripulante n.º 1).
const ALLY_MENTOR_NAME: String = "Comandante Arvel"


func display_name(pid: String) -> String:
	var p: Dictionary = player(pid)
	if p.is_empty():
		return U.t("Desconocido")
	var tag: String = str(p.get("tag", ""))
	return ("[%s] %s" % [tag, p["name"]]) if not tag.is_empty() else str(p["name"])


func new_player(name: String, avatar: String, tag: String, is_bot: bool, pos: Vector2i) -> Dictionary:
	var pid: String = ("bot_" if is_bot else "plr_") + U.new_id()
	var now: int = U.now_ms()
	var rooms: Dictionary = {}
	for room_id: String in Catalog.room_order:
		# Las salas de Fase 2 (con "unlock") se construyen después: dos etapas de la nave.
		if Catalog.room(room_id).has("unlock"):
			continue
		rooms[room_id] = {"level": 1, "pending": {}, "last_ts": now}
	var start_cfg: Dictionary = Catalog.cfg("starting", {})
	var p: Dictionary = {
		"id": pid, "name": name, "avatar": avatar, "tag": tag, "is_bot": is_bot, "system": current_system,
		"rank": "R2", "created_ts": now, "last_seen": now,
		"resources": (start_cfg.get("resources", {}) as Dictionary).duplicate(),
		"energy_ts": now,
		"rooms": rooms,
		"queues": {"build": {}, "research": {}, "train": {}, "heal": {}, "revive": {}},
		"tech": {},
		"troops": (start_cfg.get("troops", {}) as Dictionary).duplicate(),
		"wounded": {}, "cryo": {},
		"items": {} if is_bot else (start_cfg.get("items", {}) as Dictionary).duplicate(),
		"shield_until": 0,
		"protected_until": 0 if is_bot else now + int(Catalog.cfg("newbie_protection_sec", 150)) * 1000,
		"capsules": [], "hunt_streak": {}, "stats": {}, "idem": {}, "ledger": [],
	}
	var base: Dictionary = {"id": "base_%s" % U.new_id(), "kind": "base", "owner": pid, "pos": [pos.x, pos.y], "state": "ANCHORED"}
	world.add_entity(base)
	p["base_id"] = base["id"]
	state["players"][pid] = p
	if not is_bot:
		missions.ensure(p)
		crew.ensure(p)
		state["reports"][pid] = []
	return p


func create_human(name: String, avatar: String) -> Dictionary:
	# Los comandantes nuevos nacen en el sistema más nuevo de la galaxia.
	galaxy.ensure_generated(galaxy.newest_open(U.now_ms()))
	var r := RandomNumberGenerator.new()
	r.randomize()
	var spawn := Vector2i(-1, -1)
	# Multijugador: los comandantes nuevos aparecen en el vecindario del último
	# humano conectado, para que puedan verse, espiarse y combatir desde el inicio.
	var latest: Dictionary = {}
	for other: Dictionary in state["players"].values():
		if not other.get("is_bot", false) and str(other.get("system", "")) == current_system and int(other.get("created_ts", 0)) > int(latest.get("created_ts", -1)):
			latest = other
	if not latest.is_empty():
		var lb: Dictionary = world.get_entity(str(latest.get("base_id", "")))
		if not lb.is_empty():
			spawn = world.find_free_near(U.v2(lb["pos"]), 18.0, 30.0, r, 7.0)
	for _i: int in range(200):
		if spawn.x >= 0:
			break
		var ang: float = r.randf() * TAU
		var d: float = r.randf_range(195.0, 235.0)
		var cand: Vector2 = (world.center + Vector2(cos(ang), sin(ang)) * d).round()
		if world.is_free(cand, 7.0):
			spawn = Vector2i(cand)
			break
	if spawn.x < 0:
		spawn = Vector2i(world.find_free_near(world.center, 150.0, 280.0, r, 5.0))
	var p: Dictionary = new_player(name, avatar, "VGA", false, spawn)
	p["rank"] = "R4"
	p["rooms"]["bridge"]["level"] = int(Catalog.cfg("starting", {}).get("bridge_level", 2))
	# Vecindario de inicio: asteroides y xenoformas N1-N2 y rivales novatos al alcance.
	for i: int in range(6):
		var ap: Vector2i = world.find_free_near(Vector2(spawn), 7.0, 18.0, r, 3.0)
		if ap.x >= 0:
			world.spawn_asteroid(1 if i < 4 else 2, ap, r)
	for i: int in range(5):
		var xp: Vector2i = world.find_free_near(Vector2(spawn), 9.0, 22.0, r, 3.0)
		if xp.x >= 0:
			world.spawn_xenoform(1 if i < 3 else 2, xp, r)
	var rival_tags: Array = ["XEN", "ORI", "KRT"]
	for i: int in range(3):
		var bp: Vector2i = world.find_free_near(Vector2(spawn), 20.0, 34.0, r, 6.0)
		if bp.x >= 0:
			var bot: Dictionary = bots.spawn_bot(r, bp, 0.0, rival_tags[i])
			# Rivales novatos: pocas tropas y recursos saqueables.
			for k: String in bot["troops"].keys():
				bot["troops"][k] = maxi(4, int(int(bot["troops"][k]) * (0.45 + 0.2 * i)))
			bot["bot"]["target_army"] = bot["troops"].duplicate()
			for e: String in Catalog.element_ids:
				bot["resources"][e] = r.randi_range(1800, 3200)
	var ally_pos: Vector2i = world.find_free_near(Vector2(spawn), 14.0, 26.0, r, 6.0)
	if ally_pos.x >= 0:
		bots.spawn_bot(r, ally_pos, 0.15, "VGA", U.t(ALLY_MENTOR_NAME))
	social.post("VGA", U.t("Sistema"), U.t("%s se unió a la Alianza. ¡Bienvenido, comandante!") % name, "system")
	guild.refresh_member_mods("VGA")
	return p


func find_human_by_name(name: String) -> Dictionary:
	for p: Dictionary in state["players"].values():
		if not p.get("is_bot", false) and str(p["name"]).to_lower() == name.to_lower():
			return p
	return {}


func player_power(p: Dictionary) -> int:
	var pw: int = 0
	for room_id: String in p["rooms"]:
		pw += int(Catalog.room(room_id).get("power", 30)) * int(p["rooms"][room_id]["level"])
	for t: String in p.get("tech", {}):
		pw += 40 * int(p["tech"][t])
	pw += Resolver.power_of(p["troops"])
	# Tropas en flotas: se buscan en el sistema del comandante (puede no ser el activo).
	var sys_fleets: Dictionary = galaxy.system(str(p.get("system", ""))).get("fleets", {})
	for fid: String in sys_fleets:
		var f: Dictionary = sys_fleets[fid]
		if f["owner"] == p["id"]:
			pw += Resolver.power_of(f["troops"]) + Resolver.power_of(f.get("wounded", {}))
	return pw


func settle_player(p: Dictionary) -> void:
	var base: Dictionary = world.get_entity(str(p.get("base_id", "")))
	Eco.settle(p, U.now_ms(), base.get("state", "ANCHORED") == "ANCHORED")


func bump_base_of(pid: String) -> void:
	var p: Dictionary = player(pid)
	var base: Dictionary = world.get_entity(str(p.get("base_id", "")))
	if not base.is_empty():
		world.bump(base)


func mark_player_dirty(pid: String, _urgent: bool = false) -> void:
	_dirty_players[pid] = true


func is_player_online(pid: String) -> bool:
	for s: Dictionary in sessions.values():
		if s["player_id"] == pid:
			return true
	return false


# ---------------------------------------------------------------- simulación

func _tick() -> void:
	var now: int = U.now_ms()
	# Cada sistema con comandantes humanos se simula como un SSS independiente.
	for sid: String in galaxy.active_systems():
		use_system(sid)
		world.process_respawns(now)
		fleets.tick(now)
		bots.tick(now)
		guild.tick(now)
	social.tick(now)
	events.tick(now)
	for p: Dictionary in state["players"].values():
		if p.get("is_bot", false):
			continue
		for ev: Array in progression.complete_due(p, now):
			missions.on_event(p, ev[0], int(ev[1]), ev[2])
	for sid: int in sessions.keys():
		_flush(sessions[sid])
	_dirty_players.clear()
	if persist and now - _last_save >= int(Catalog.cfg("save_interval_sec", 30)) * 1000:
		save()


# ---------------------------------------------------------------- sesiones / red

## `sink` es un Callable(msg: Dictionary) que entrega el mensaje al cliente
## (llamada directa en modo local, WebSocket en modo dedicado).
func open_session(sink: Callable) -> int:
	var sid: int = _next_session
	_next_session += 1
	sessions[sid] = {
		"id": sid, "sink": sink, "player_id": "", "view_center": Vector2(300, 300), "view_radius": 40.0,
		"sent": {}, "last_player_ms": 0, "authenticated": false,
	}
	return sid


func close_session(sid: int) -> void:
	var s: Dictionary = sessions.get(sid, {})
	if not s.is_empty() and not str(s["player_id"]).is_empty():
		var p: Dictionary = player(s["player_id"])
		if not p.is_empty():
			p["last_seen"] = U.now_ms()
	sessions.erase(sid)
	if persist:
		save()


func _send(s: Dictionary, msg: Dictionary) -> void:
	(s["sink"] as Callable).call(msg)


func send_to_player(pid: String, msg: Dictionary) -> void:
	for s: Dictionary in sessions.values():
		if s["player_id"] == pid:
			_send(s, msg)


func notify(pid: String, text: String, kind: String = "info") -> void:
	var p: Dictionary = player(pid)
	if p.is_empty() or p.get("is_bot", false):
		return
	send_to_player(pid, {"type": "toast", "text": text, "kind": kind})


func emit_fx(pos: Vector2, kind: String, source_pid: String) -> void:
	for s: Dictionary in sessions.values():
		if str(player(s["player_id"]).get("system", "")) != current_system:
			continue
		var c: Vector2 = s["view_center"]
		var r: float = float(s["view_radius"]) + 4.0
		if absf(pos.x - c.x) <= r and absf(pos.y - c.y) <= r:
			_send(s, {"type": "fx", "kind": kind, "pos": U.arr2(pos), "own": s["player_id"] == source_pid})


func handle_message(sid: int, msg: Dictionary) -> void:
	var s: Dictionary = sessions.get(sid, {})
	if s.is_empty():
		return
	var t: String = str(msg.get("type", ""))
	if t == "hello":
		_on_hello(s, msg)
		return
	if not bool(s["authenticated"]):
		_send(s, {"type": "error", "code": "NOT_AUTHENTICATED", "message": U.t("Envía hello primero")})
		return
	match t:
		"view":
			var r: float = clampf(float(msg.get("r", 40)), 10.0, float(Catalog.cfg("aoi_max_radius", 90)))
			s["view_center"] = Vector2(float(msg.get("x", 300)), float(msg.get("y", 300)))
			s["view_radius"] = r
			_flush(s)
		"intent":
			_on_intent(s, msg)
		"ping":
			_send(s, {"type": "pong", "t": msg.get("t", 0), "server_time": U.now_ms()})
		_:
			_send(s, {"type": "error", "code": "UNKNOWN_MESSAGE", "message": t})


func _on_hello(s: Dictionary, msg: Dictionary) -> void:
	if str(msg.get("protocol", "")) != PROTOCOL_VERSION:
		_send(s, {"type": "error", "code": "PROTOCOL_MISMATCH", "message": U.t("Versión de protocolo incompatible")})
		return
	var name: String = str(msg.get("name", U.t("Comandante"))).strip_edges().substr(0, 18)
	if name.is_empty():
		name = U.t("Comandante")
	var p: Dictionary = find_human_by_name(name)
	if p.is_empty():
		p = create_human(name, str(msg.get("avatar", "p01")))
	elif msg.has("avatar"):
		p["avatar"] = str(msg["avatar"])
	missions.ensure(p)
	s["player_id"] = p["id"]
	s["authenticated"] = true
	use_player_system(p)
	_send_welcome(s, p)
	_send(s, {"type": "reports", "list": reports.list_for(p["id"]).slice(0, 40)})
	var chat: Array = social.alliances().get(str(p.get("tag", "")), {}).get("chat", [])
	_send(s, {"type": "chat_history", "list": chat.slice(maxi(0, chat.size() - 40))})
	mark_player_dirty(p["id"])
	_flush(s)


func _send_welcome(s: Dictionary, p: Dictionary) -> void:
	s["sent"] = {}
	var base: Dictionary = world.get_entity(p["base_id"])
	s["view_center"] = U.v2(base["pos"])
	var alliances_info: Array = []
	for a: Dictionary in Catalog.cfg("alliances", []):
		alliances_info.append({"tag": a["tag"], "name": a["name"], "color": a["color"]})
	_send(s, {
		"type": "welcome", "protocol": PROTOCOL_VERSION, "player_id": p["id"], "server_time": U.now_ms(),
		"map_size": world.map_size, "terrain": cur.get("terrain", []), "alliances": alliances_info,
		"base_pos": base["pos"], "system": galaxy.info(cur),
	})


## Tras un salto interestelar el cliente recibe el nuevo sistema como si se
## reconectara a otro SSS (otro "servidor").
func on_player_jumped(p: Dictionary) -> void:
	use_player_system(p)
	mark_player_dirty(p["id"])
	for s: Dictionary in sessions.values():
		if s["player_id"] == p["id"]:
			_send_welcome(s, p)


func _on_intent(s: Dictionary, msg: Dictionary) -> void:
	var p: Dictionary = player(s["player_id"])
	use_player_system(p)
	var rid: String = str(msg.get("request_id", ""))
	var action: String = str(msg.get("action", ""))
	settle_player(p)
	progression.complete_due(p, U.now_ms())
	var res: Dictionary = _dispatch(p, action, msg)
	if bool(res.get("ok", false)):
		var ack: Dictionary = {"type": "ack", "request_id": rid, "action": action}
		ack.merge(res)
		_send(s, ack)
	else:
		_send(s, {"type": "error", "request_id": rid, "action": action, "code": res.get("code", "ERROR"), "message": res.get("message", "Error")})
	mark_player_dirty(p["id"])
	bump_base_of(p["id"])
	_flush(s)


func _dispatch(p: Dictionary, action: String, msg: Dictionary) -> Dictionary:
	match action:
		"collect":
			var gained: Dictionary = Eco.collect(p, str(msg.get("room", "")))
			if gained.is_empty():
				return {"ok": false, "code": "NOTHING", "message": U.t("Aún no hay producción para recolectar")}
			missions.on_event(p, "collect", 1)
			return {"ok": true, "gained": gained}
		"upgrade_room":
			var r: Dictionary = progression.upgrade_room(p, str(msg.get("room", "")))
			if r["ok"]:
				missions.on_event(p, "room_upgrade_started", 1)
			return r
		"research":
			var r2: Dictionary = progression.start_research(p, str(msg.get("tech", "")))
			if r2["ok"]:
				missions.on_event(p, "research_started", 1)
			return r2
		"train":
			return progression.train(p, str(msg.get("troop", "")), int(msg.get("qty", 0)))
		"heal":
			return progression.heal(p)
		"revive":
			return progression.revive(p)
		"speedup":
			var r3: Dictionary = progression.speedup(p, str(msg.get("queue", "")), str(msg.get("method", "")))
			for ev: Array in progression.complete_due(p, U.now_ms()):
				missions.on_event(p, ev[0], int(ev[1]), ev[2])
			return r3
		"help":
			return social.request_help(p, str(msg.get("queue", "")))
		"march":
			var troops: Dictionary = msg.get("troops", {}) if msg.get("troops", {}) is Dictionary else {}
			return fleets.start_march(p, str(msg.get("mission", "")), str(msg.get("target_id", "")), troops)
		"recall":
			return fleets.recall(p, str(msg.get("fleet_id", "")))
		"relocate":
			return fleets.relocate(p, Vector2i(int(msg.get("x", -1)), int(msg.get("y", -1))), false)
		"use_item":
			var r4: Dictionary = progression.use_item(p, str(msg.get("item", "")), msg)
			for ev2: Array in progression.complete_due(p, U.now_ms()):
				missions.on_event(p, ev2[0], int(ev2[1]), ev2[2])
			return r4
		"claim_mission":
			return missions.claim_story(p)
		"claim_daily":
			return missions.claim_daily(p, int(msg.get("tier", -1)))
		"open_capsules":
			return social.open_capsules(p)
		"chat":
			return social.send_chat(p, str(msg.get("text", "")))
		"read_report":
			reports.mark_read(p["id"], str(msg.get("report_id", "")))
			return {"ok": true}
		"galaxy":
			return {"ok": true, "galaxy": galaxy.view(p)}
		"buy_item":
			return shop.buy_item(p, str(msg.get("item", "")), int(msg.get("qty", 1)))
		"buy_bundle":
			return shop.buy_bundle(p, str(msg.get("bundle", "")))
		"buy_pack":
			return shop.buy_pack(p, str(msg.get("pack", "")))
		"claim_login":
			return shop.claim_login(p)
		"debug_next_day":
			return shop.debug_next_day(p)
		"guild":
			return {"ok": true, "guild": guild.view(p), "ranking": guild.ranking()}
		"claim_chest":
			return guild.claim_chest(p, int(msg.get("tier", -1)))
		"mark_target":
			return guild.mark_target(p, str(msg.get("target_id", "")))
		"clear_target":
			return guild.clear_target(p)
		"events":
			return {"ok": true, "events": events.view(p)}
		"debug_finish_event":
			return events.debug_finish(str(msg.get("which", "tournament")))
		"recruit":
			return crew.recruit(p, int(msg.get("count", 1)), str(msg.get("method", "mo")))
		"crew_assign":
			return crew.assign(p, str(msg.get("crew_id", "")), bool(msg.get("on", true)))
		"exchange":
			return progression.exchange(p, str(msg.get("from", "")), str(msg.get("to", "")), int(msg.get("amount", 0)))
		"debug_guild_cycle":
			guild.new_cycle(str(p.get("tag", "")))
			return {"ok": true}
		"jump":
			return galaxy.jump(p, str(msg.get("system", "")), str(msg.get("method", "item")))
		"debug_raid":
			# Solo para demos: fuerza una incursión inmediata contra el jugador.
			var why: String = bots.launch_raid(p, U.now_ms(), bool(msg.get("fleet", false)))
			return {"ok": why.is_empty(), "code": "NO_RAID", "message": why}
	return {"ok": false, "code": "UNKNOWN_ACTION", "message": U.t("Acción desconocida: %s") % action}


# ---------------------------------------------------------------- replicación AOI

func _flush(s: Dictionary) -> void:
	if not bool(s["authenticated"]):
		return
	var pid: String = s["player_id"]
	var p: Dictionary = player(pid)
	if p.is_empty():
		return
	use_player_system(p)
	var now: int = U.now_ms()
	var center: Vector2 = s["view_center"]
	var radius: float = s["view_radius"]
	var current: Dictionary = {}
	for id: String in world.query_view(center, radius):
		current[id] = _signature(world.get_entity(id))
	current[p["base_id"]] = _signature(world.get_entity(p["base_id"]))
	for fid: String in cur["fleets"]:
		var f: Dictionary = cur["fleets"][fid]
		if f["owner"] == pid or str(f.get("target_owner", "")) == pid or _segment_near(U.v2(f["origin"]), U.v2(f["target"]), center, radius * 1.42):
			current[fid] = "%d" % int(f.get("rev", 1))
	var sent: Dictionary = s["sent"]
	var added: Array = []
	var updated: Array = []
	var removed: Array = []
	for id: String in current:
		if not sent.has(id):
			added.append(_entity_view(id, now))
		elif sent[id] != current[id]:
			updated.append(_entity_view(id, now))
	for id: String in sent:
		if not current.has(id):
			removed.append(id)
	s["sent"] = current
	if not added.is_empty() or not updated.is_empty() or not removed.is_empty():
		_send(s, {"type": "map_delta", "server_time": now, "added": added, "updated": updated, "removed": removed})
	if _dirty_players.has(pid) or now - int(s["last_player_ms"]) >= 2000:
		s["last_player_ms"] = now
		settle_player(p)
		_send(s, {"type": "player", "server_time": now, "data": player_view(p)})


func _segment_near(a: Vector2, b: Vector2, c: Vector2, r: float) -> bool:
	var closest: Vector2 = Geometry2D.get_closest_point_to_segment(c, a, b)
	return closest.distance_to(c) <= r


func _signature(e: Dictionary) -> String:
	if e.is_empty():
		return ""
	if e["kind"] == "base":
		var o: Dictionary = player(e["owner"])
		var shield: bool = int(o.get("shield_until", 0)) > U.now_ms() or int(o.get("protected_until", 0)) > U.now_ms()
		return "%d:%d:%s:%s" % [int(e.get("rev", 1)), player_power(o) / 10, str(shield), e["state"]]
	return "%d" % int(e.get("rev", 1))


func _entity_view(id: String, now: int) -> Dictionary:
	if cur["fleets"].has(id):
		return fleets.fleet_view(cur["fleets"][id], now)
	var e: Dictionary = world.get_entity(id)
	var v: Dictionary = e.duplicate(true)
	v.erase("rev")
	if e["kind"] == "base":
		var o: Dictionary = player(e["owner"])
		v["name"] = o.get("name", "?")
		v["tag"] = o.get("tag", "")
		v["avatar"] = o.get("avatar", "p01")
		v["power"] = player_power(o)
		v["level"] = Eco.room_level(o, "bridge")
		v["is_bot"] = o.get("is_bot", false)
		v["shield"] = int(o.get("shield_until", 0)) > now
		v["protected"] = int(o.get("protected_until", 0)) > now
	elif e["kind"] == "asteroid":
		var occ: Dictionary = cur["fleets"].get(str(e.get("occupant", "")), {})
		v["occupant_owner"] = str(occ.get("owner", ""))
		v["occupant_name"] = display_name(occ["owner"]) if not occ.is_empty() else ""
	return v


func player_view(p: Dictionary) -> Dictionary:
	var now: int = U.now_ms()
	var base: Dictionary = world.get_entity(p["base_id"])
	var rooms: Dictionary = {}
	for room_id: String in p["rooms"]:
		var r: Dictionary = p["rooms"][room_id]
		rooms[room_id] = {"level": int(r["level"]), "pending": r.get("pending", {})}
	var own_fleets: Array = []
	for f: Dictionary in fleets.owned_fleets(p["id"]):
		own_fleets.append(fleets.fleet_view(f, now))
	var m: Dictionary = missions.current(p)
	var story: Dictionary = {}
	if not m.is_empty():
		story = m.duplicate()
		story["progress"] = int(p["missions"]["progress"])
		story["index"] = int(p["missions"]["index"])
		story["total"] = missions.story().size()
	var daily_def: Dictionary = missions.daily_def()
	var caps: Array = []
	for c: Dictionary in p.get("capsules", []):
		caps.append({"from": c["from"], "level": c["level"]})
	return {
		"id": p["id"], "name": p["name"], "avatar": p.get("avatar", "p01"), "tag": p.get("tag", ""), "rank": p.get("rank", "R2"),
		"power": player_power(p), "server_time": now,
		"resources": p["resources"], "rates": Eco.production_rates(p), "rooms": rooms,
		"queues": p["queues"], "troops": p["troops"], "wounded": p["wounded"], "cryo": p["cryo"],
		"in_fleets": fleets.troops_in_fleets(p["id"]),
		"tech": p["tech"], "items": p["items"],
		"energy_max": Eco.energy_max(), "energy_ts": p.get("energy_ts", now),
		"caps": {
			"march_slots": Eco.march_slots(p), "march_capacity": Eco.march_capacity(p),
			"vault": Eco.vault_protect(p), "medbay": Eco.medbay_capacity(p), "cryo": Eco.cryo_capacity(p),
			"perimeter_hp": Eco.perimeter_hp(p), "train_batch": Eco.train_batch(p), "scout_level": Eco.scout_level(p),
		},
		"mods": Eco.modifiers(p),
		"base_id": p["base_id"], "base_pos": base.get("pos", [0, 0]), "base_state": base.get("state", ""),
		"base_travel": base.get("travel", {}),
		"fleets": own_fleets,
		"incoming": fleets.incoming_for(p["id"], now),
		"story": story,
		"daily": {"name": daily_def.get("name", ""), "points": int(p["daily"]["points"]), "tiers": daily_def.get("tiers", []), "claimed": p["daily"]["claimed"], "ends_at": missions.daily_ends_at(p)},
		"capsules": caps,
		"shield_until": int(p.get("shield_until", 0)), "protected_until": int(p.get("protected_until", 0)),
		"unread_reports": reports.unread(p["id"]),
		"heal_cost": progression.heal_cost(p), "revive_cost": progression.revive_cost(p),
		"alliance": social.alliance_view(p),
		"stats": p.get("stats", {}),
		"relocate_plasma_per_tile": Catalog.cfg("relocate_plasma_per_tile", 0.25),
		"system": galaxy.info(galaxy.system(str(p.get("system", "")))),
		"created_ts": int(p.get("created_ts", now)),
		"shop": shop.view(p),
		"crew": crew.view(p),
		"guild_brief": _guild_brief(p),
		"event_brief": _event_brief(p),
	}


func _guild_brief(p: Dictionary) -> Dictionary:
	var tag: String = str(p.get("tag", ""))
	var g: Dictionary = guild.data(tag)
	if g.is_empty():
		return {}
	var claimable: int = 0
	var claims: Array = g["chest_claims"].get(p["id"], [])
	var tiers: Array = guild.cfg().get("chest_tiers", [])
	for i: int in range(tiers.size()):
		if int(g["points"]) >= int(tiers[i]["points"]) and not claims.has(i) and not claims.has(float(i)):
			claimable += 1
	var t: Dictionary = g.get("target", {})
	return {"points": int(g["points"]), "chests": claimable, "target_id": str(t.get("id", "")), "target_until": int(t.get("until", 0)),
		"quota": int(g["quota"].get(p["id"], 0)), "quota_target": int(guild.cfg().get("member_quota", {}).get("target", 5))}


func _event_brief(p: Dictionary) -> Dictionary:
	var d: Dictionary = events.data()
	return {"resource": str(events.resource_def().get("name", "")), "resource_end": int(d["resource"].get("end", 0)),
		"tournament": str(events.tournament_def().get("name", "")), "tournament_end": int(d["tournament"].get("end", 0)),
		"my_rank": events.rank_of(p["id"]), "my_points": int(d["tournament"].get("scores", {}).get(p["id"], 0.0))}


# ---------------------------------------------------------------- persistencia

## Snapshot del estado (equivalente local al snapshot a Redis cada 30 s).
func save() -> void:
	if not persist:
		return
	_last_save = U.now_ms()
	var tmp: String = save_path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("No se pudo guardar el estado: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(state, "", false))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_path))


func _load() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not (parsed is Dictionary) or int((parsed as Dictionary).get("save_version", 0)) != SAVE_VERSION:
		return false
	state = parsed
	if not state.has("galaxy"):
		return false
	for k: String in ["players", "reports", "alliances"]:
		if not state.has(k):
			state[k] = {}
	cur = {}
	current_system = ""
	_hashes.clear()
	social.ensure_alliances()
	var first: String = galaxy.newest_open(U.now_ms())
	for p: Dictionary in state["players"].values():
		if not p.get("is_bot", false):
			first = str(p.get("system", first))
			break
	use_system(first)
	refresh_alliances()
	# Recovery por timestamps: las flotas y viajes vencidos se resuelven en el
	# primer tick en orden de llegada, sin perder nada.
	_log("Estado restaurado desde %s" % save_path)
	return true


func reset_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		if persist and not state.is_empty():
			save()
