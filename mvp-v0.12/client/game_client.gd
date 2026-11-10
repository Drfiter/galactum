extends Node
## Fachada del cliente: mantiene la réplica NO autoritativa (jugador + entidades
## del área de interés) y envía intenciones. La UI solo habla con este nodo.

const U = preload("res://shared/util.gd")
const LocalLink = preload("res://client/links/local_link.gd")
const WsLink = preload("res://client/links/ws_link.gd")
const GameServerScript = preload("res://server/game_server.gd")
const PROTOCOL: String = "galactum-mvp-1"

signal connection_changed(state: String, detail: String)
signal welcomed
signal player_updated
signal world_changed(added: Array, updated: Array, removed: Array)
signal report_received(report: Dictionary)
signal reports_changed
signal toast(text: String, kind: String)
signal chat_received(message: Dictionary)
signal fx(kind: String, pos: Vector2, own: bool)
signal request_done(request_id: String, ok: bool, payload: Dictionary)
signal system_changed(info: Dictionary)

var link: RefCounted
var local_server: Node
var mode: String = ""
var connected: bool = false
var commander_name: String = U.t("Comandante")
var avatar: String = "p01"
## Cuenta del servidor dedicado: {username, password, register} o {} para
## reanudar la sesión guardada (token de renovación) o el modo demo.
var account: Dictionary = {}
var access_token: String = ""
var _host_key: String = ""
const SESSION_PATH: String = "user://session.cfg"

var player_id: String = ""
var map_size: int = 600
var terrain: Array = []
var alliances: Dictionary = {}
var me: Dictionary = {}
var entities: Dictionary = {}
var reports: Array = []
var chat: Array = []
var system: Dictionary = {}       # Sistema Solar actual {id, index, name, hue}

var _clock_offset: int = 0      # server_time - ticks local
var _callbacks: Dictionary = {}
var _req_seq: int = 0
var _last_view: Vector3 = Vector3(-1, -1, -1)
var _view_timer: float = 0.0
var _pending_view: Vector3 = Vector3(-1, -1, -1)


func _process(delta: float) -> void:
	if link != null:
		link.poll()
	_view_timer -= delta
	if _pending_view.x >= 0 and _view_timer <= 0.0:
		_flush_view()


# ---------------------------------------------------------------- conexión

func start_local(name: String, avatar_id: String, fresh: bool = false) -> void:
	disconnect_all()
	commander_name = name
	avatar = avatar_id
	mode = "local"
	local_server = GameServerScript.new()
	local_server.name = "LocalGameServer"
	add_child(local_server)
	if fresh:
		local_server.reset_save()
	local_server.start({"persist": true, "fresh": fresh})
	var l := LocalLink.new()
	_wire(l)
	link = l
	l.open(local_server)


func start_remote(host: String, port: int, name: String, avatar_id: String, account_info: Dictionary = {}) -> void:
	disconnect_all()
	commander_name = name
	avatar = avatar_id
	account = account_info
	_host_key = "%s_%d" % [host.replace(".", "_"), port]
	mode = "remote"
	var l := WsLink.new()
	_wire(l)
	link = l
	connection_changed.emit("connecting", "ws://%s:%d" % [host, port])
	var err: Error = l.open_url("ws://%s:%d" % [host, port])
	if err != OK:
		connection_changed.emit("error", U.t("No se pudo iniciar la conexión (%s)") % error_string(err))


func _wire(l: RefCounted) -> void:
	l.message_received.connect(_on_message)
	l.opened.connect(_on_open)
	l.closed.connect(_on_closed)


func disconnect_all() -> void:
	if link != null:
		link.close()
	link = null
	if local_server != null and is_instance_valid(local_server):
		local_server.save()
		local_server.queue_free()
	local_server = null
	connected = false
	entities.clear()
	me = {}
	reports.clear()
	chat.clear()
	_last_view = Vector3(-1, -1, -1)


func _on_open() -> void:
	if mode == "remote":
		if not account.is_empty():
			var action: String = "register" if bool(account.get("register", false)) else "login"
			link.send({"type": action, "username": str(account.get("username", "")), "password": str(account.get("password", "")), "avatar": avatar})
			account.erase("password")   # la contraseña no queda en memoria
			return
		var saved: String = saved_refresh_token()
		if not saved.is_empty():
			link.send({"type": "refresh", "refresh_token": saved})
			return
	_send_hello()


func _send_hello() -> void:
	link.send({"type": "hello", "protocol": PROTOCOL, "name": commander_name, "avatar": avatar, "token": access_token if not access_token.is_empty() else "demo-%s" % commander_name})


func saved_refresh_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return ""
	return str(cfg.get_value("refresh", _host_key, ""))


func _store_refresh_token(token: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SESSION_PATH)
	if token.is_empty():
		if cfg.has_section_key("refresh", _host_key):
			cfg.erase_section_key("refresh", _host_key)
	else:
		cfg.set_value("refresh", _host_key, token)
	cfg.save(SESSION_PATH)


## Cierra la sesión de la cuenta en este servidor (revoca el token de renovación).
func logout() -> void:
	var saved: String = saved_refresh_token()
	if link != null and not saved.is_empty():
		link.send({"type": "logout", "refresh_token": saved})
	_store_refresh_token("")
	access_token = ""


func _on_auth(msg: Dictionary) -> void:
	if bool(msg.get("ok", false)) and str(msg.get("action", "")) != "logout":
		access_token = str(msg.get("access_token", ""))
		_store_refresh_token(str(msg.get("refresh_token", "")))
		commander_name = str(msg.get("username", commander_name))
		_send_hello()
	elif not bool(msg.get("ok", false)):
		if str(msg.get("action", "")) == "refresh":
			_store_refresh_token("")
		connection_changed.emit("error", str(msg.get("message", U.t("No se pudo iniciar sesión"))))


func _on_closed(reason: String) -> void:
	connected = false
	connection_changed.emit("closed", reason)


# ---------------------------------------------------------------- tiempo

func server_now() -> int:
	return Time.get_ticks_msec() + _clock_offset


func _sync_clock(server_time: Variant) -> void:
	if server_time == null:
		return
	var st: int = int(server_time)
	if st > 0:
		var offset: int = st - Time.get_ticks_msec()
		# Suaviza: el reloj visual nunca retrocede bruscamente.
		_clock_offset = offset if _clock_offset == 0 else int(lerpf(_clock_offset, offset, 0.3))


# ---------------------------------------------------------------- envío

func intent(action: String, params: Dictionary = {}, cb: Callable = Callable()) -> String:
	if link == null:
		return ""
	_req_seq += 1
	var rid: String = "r%d_%d" % [Time.get_ticks_msec(), _req_seq]
	var msg: Dictionary = params.duplicate(true)
	msg["type"] = "intent"
	msg["action"] = action
	msg["request_id"] = rid
	if cb.is_valid():
		_callbacks[rid] = cb
	link.send(msg)
	return rid


## Suscripción por región (AOI): el cliente informa el centro de su cámara.
func set_view(center: Vector2, radius: float) -> void:
	var v := Vector3(roundf(center.x), roundf(center.y), roundf(radius))
	if v == _last_view:
		return
	_pending_view = v
	if _view_timer <= 0.0:
		_flush_view()


func _flush_view() -> void:
	if link == null or not connected or _pending_view.x < 0:
		return
	_last_view = _pending_view
	link.send({"type": "view", "x": _pending_view.x, "y": _pending_view.y, "r": _pending_view.z})
	_pending_view = Vector3(-1, -1, -1)
	_view_timer = 0.25


# ---------------------------------------------------------------- recepción

func _on_message(msg: Dictionary) -> void:
	var t: String = str(msg.get("type", ""))
	match t:
		"welcome":
			connected = true
			player_id = str(msg["player_id"])
			map_size = int(msg.get("map_size", 600))
			terrain = msg.get("terrain", [])
			entities.clear()
			var prev_sys: String = str(system.get("id", ""))
			system = msg.get("system", {})
			alliances.clear()
			for a: Dictionary in msg.get("alliances", []):
				alliances[a["tag"]] = a
			_sync_clock(msg.get("server_time"))
			connection_changed.emit("connected", mode)
			welcomed.emit()
			if not prev_sys.is_empty() and prev_sys != str(system.get("id", "")):
				system_changed.emit(system)
		"player":
			_sync_clock(msg.get("server_time"))
			me = msg.get("data", {})
			player_updated.emit()
		"map_delta":
			_sync_clock(msg.get("server_time"))
			for e: Dictionary in msg.get("added", []):
				entities[str(e["id"])] = e
			for e2: Dictionary in msg.get("updated", []):
				entities[str(e2["id"])] = e2
			for id: Variant in msg.get("removed", []):
				entities.erase(str(id))
			world_changed.emit(msg.get("added", []), msg.get("updated", []), msg.get("removed", []))
		"report":
			var r: Dictionary = msg.get("report", {})
			reports.push_front(r)
			while reports.size() > 60:
				reports.pop_back()
			report_received.emit(r)
			reports_changed.emit()
		"reports":
			reports = msg.get("list", [])
			reports_changed.emit()
		"toast":
			toast.emit(str(msg.get("text", "")), str(msg.get("kind", "info")))
		"chat":
			chat.append(msg.get("message", {}))
			while chat.size() > 80:
				chat.pop_front()
			chat_received.emit(msg.get("message", {}))
		"chat_history":
			chat = msg.get("list", [])
		"fx":
			fx.emit(str(msg.get("kind", "")), U.v2(msg.get("pos", [0, 0])), bool(msg.get("own", false)))
		"ack":
			_resolve(str(msg.get("request_id", "")), true, msg)
		"auth":
			_on_auth(msg)
		"error":
			var rid: String = str(msg.get("request_id", ""))
			if rid.is_empty():
				toast.emit(str(msg.get("message", "Error")), "error")
				if str(msg.get("code", "")) in ["PROTOCOL_MISMATCH", "AUTH_REQUIRED"]:
					connection_changed.emit("error", str(msg.get("message", "")))
			_resolve(rid, false, msg)
		"pong":
			_sync_clock(msg.get("server_time"))


func _resolve(rid: String, ok: bool, payload: Dictionary) -> void:
	if not ok and not _callbacks.has(rid):
		toast.emit(str(payload.get("message", U.t("Acción rechazada"))), "error")
	if _callbacks.has(rid):
		var cb: Callable = _callbacks[rid]
		_callbacks.erase(rid)
		if cb.is_valid():
			cb.call(ok, payload)
	request_done.emit(rid, ok, payload)


# ---------------------------------------------------------------- consultas

func res(id: String) -> int:
	if Catalog.items_by_id.has(id):
		return int(me.get("items", {}).get(id, 0))
	if id == "energy":
		return current_energy()
	return int(me.get("resources", {}).get(id, 0))


func current_energy() -> int:
	var base: int = int(me.get("resources", {}).get("energy", 0))
	var mx: int = int(me.get("energy_max", 100))
	if base >= mx:
		return base
	var regen_ms: int = int(Catalog.xeno.get("energy_regen_sec", 10)) * 1000
	var gained: int = int((server_now() - int(me.get("energy_ts", server_now()))) / regen_ms)
	return mini(mx, base + maxi(0, gained))


func can_afford(cost: Dictionary, factor: float = 1.0) -> bool:
	for k: String in cost:
		if res(k) < int(ceil(float(cost[k]) * factor)):
			return false
	return true


func room_level(room_id: String) -> int:
	return int(me.get("rooms", {}).get(room_id, {}).get("level", 0))


func tech_level(tech_id: String) -> int:
	return int(me.get("tech", {}).get(tech_id, 0))


func queue(q: String) -> Dictionary:
	var job: Variant = me.get("queues", {}).get(q, {})
	return job if job is Dictionary else {}


func queue_remaining(q: String) -> float:
	var job: Dictionary = queue(q)
	if job.is_empty():
		return 0.0
	return maxf(0.0, float(int(job["end"]) - server_now()) / 1000.0)


func pending_amount(room_id: String) -> Dictionary:
	# Producción visible: lo pendiente + lo acumulado desde el último envío.
	var room: Dictionary = me.get("rooms", {}).get(room_id, {})
	var pending: Dictionary = room.get("pending", {})
	var out: Dictionary = {}
	var rates: Dictionary = Catalog.room_production(room_id, int(room.get("level", 1)))
	var elapsed_min: float = maxf(0.0, float(server_now() - int(me.get("server_time", server_now()))) / 60000.0)
	var cap_min: float = float(Catalog.room(room_id).get("storage_minutes", 20))
	var traveling: bool = str(me.get("base_state", "")) != "ANCHORED"
	for k: String in rates:
		var v: float = float(pending.get(k, 0.0))
		if not traveling:
			v += float(rates[k]) * elapsed_min
		out[k] = minf(v, float(rates[k]) * cap_min)
	return out


func troops_home() -> Dictionary:
	return me.get("troops", {})


func base_entity() -> Dictionary:
	return entities.get(str(me.get("base_id", "")), {})


func base_pos() -> Vector2:
	return U.v2(me.get("base_pos", [300, 300]))


func relation_of(owner_id: String, tag: String) -> String:
	if owner_id == player_id:
		return "own"
	if not tag.is_empty() and tag == str(me.get("tag", "")):
		return "ally"
	return "enemy"


func entity_position(e: Dictionary) -> Vector2:
	var now: int = server_now()
	if str(e.get("kind", "")) == "fleet":
		if str(e.get("state", "")) == "working":
			return U.v2(e["target"])
		return U.lerp_path(U.v2(e["origin"]), U.v2(e["target"]), int(e["depart_ts"]), int(e["arrive_ts"]), now)
	if str(e.get("kind", "")) == "base" and str(e.get("state", "")) == "TRAVELING":
		var tr: Dictionary = e.get("travel", {})
		return U.lerp_path(U.v2(tr["origin"]), U.v2(tr["target"]), int(tr["depart_ts"]), int(tr["arrive_ts"]), now)
	return U.v2(e.get("pos", [0, 0]))


func unread_reports() -> int:
	return int(me.get("unread_reports", 0))


func story_claimable() -> bool:
	var s: Dictionary = me.get("story", {})
	return not s.is_empty() and int(s.get("progress", 0)) >= int(s.get("target", 1))


func daily_claimable() -> bool:
	var d: Dictionary = me.get("daily", {})
	var tiers: Array = d.get("tiers", [])
	for i: int in range(tiers.size()):
		if int(d.get("points", 0)) >= int(tiers[i]["points"]) and not (d.get("claimed", []) as Array).has(i) and not (d.get("claimed", []) as Array).has(float(i)):
			return true
	return false
