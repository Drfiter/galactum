extends RefCounted
## Eventos y torneos (feedback de revisión: "eventos con bonus de recursos",
## "ir probando eventos para ver qué tan rentables son").
##
##  - Evento de recursos rotativo (1 h): bonos de minería, caza o producción.
##  - Torneo rotativo (3 h): ranking por puntos con un pozo de premios en USD
##    que se paga en objetos (convertidos con la tabla de precios).
##  - Métricas de rentabilidad por torneo: valor "quemado" por los participantes
##    (tropas perdidas, MO gastada, compras) frente al pozo de premios, y una
##    recomendación para ajustar el premio del próximo evento.

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.events


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func data() -> Dictionary:
	if not srv.state.has("events"):
		srv.state["events"] = {"resource": {}, "tournament": {}, "history": [], "r_index": -1, "t_index": -1}
	return srv.state["events"]


func _def(list_key: String, idx: int) -> Dictionary:
	var list: Array = cfg().get(list_key, [])
	return list[idx % list.size()] if not list.is_empty() else {}


func tick(now: int) -> void:
	var d: Dictionary = data()
	var r: Dictionary = d["resource"]
	if r.is_empty() or now >= int(r.get("end", 0)):
		_start_resource(now)
	var t: Dictionary = d["tournament"]
	if t.is_empty() or now >= int(t.get("end", 0)):
		if not t.is_empty():
			finish_tournament()
		_start_tournament(now)
	_apply_global_mods()


func _start_resource(now: int) -> void:
	var d: Dictionary = data()
	d["r_index"] = int(d["r_index"]) + 1
	var def: Dictionary = _def("resource_events", int(d["r_index"]))
	d["resource"] = {"id": def.get("id", ""), "start": now, "end": now + int(cfg().get("resource_event_minutes", 60)) * 60000}
	_apply_global_mods()


func _start_tournament(now: int) -> void:
	var d: Dictionary = data()
	d["t_index"] = int(d["t_index"]) + 1
	var def: Dictionary = _def("tournaments", int(d["t_index"]))
	var pool: float = float(def.get("prize_pool_usd", 500))
	# Ajuste del premio según la rentabilidad del último torneo del mismo tipo.
	for h: Dictionary in d["history"]:
		if str(h.get("def", "")) == str(def.get("id", "")) and h.has("next_pool_usd"):
			pool = float(h["next_pool_usd"])
			break
	d["tournament"] = {
		"id": "tor_%s" % U.new_id(), "def": def.get("id", ""), "start": now,
		"end": now + int(cfg().get("tournament_minutes", 180)) * 60000,
		"pool_usd": pool, "scores": {}, "burn_mo": 0.0, "spend_usd": 0.0, "mo_spent": 0.0, "troops_lost_mo": 0.0,
	}


func resource_def() -> Dictionary:
	var r: Dictionary = data()["resource"]
	for e: Dictionary in cfg().get("resource_events", []):
		if str(e["id"]) == str(r.get("id", "")):
			return e
	return {}


func tournament_def(def_id: String = "") -> Dictionary:
	if def_id.is_empty():
		def_id = str(data()["tournament"].get("def", ""))
	for e: Dictionary in cfg().get("tournaments", []):
		if str(e["id"]) == def_id:
			return e
	return {}


## Los efectos del evento activo se publican en Eco (los usa el cálculo de
## minería, caza y producción).
func _apply_global_mods() -> void:
	var eff: Dictionary = resource_def().get("effects", {})
	Eco.event_mods = eff.duplicate(true)


# ---------------------------------------------------------------- actividad

func on_activity(p: Dictionary, kind: String, amount: float, extra: Dictionary = {}) -> void:
	var t: Dictionary = data()["tournament"]
	if t.is_empty():
		return
	match kind:
		"troops_lost":
			t["burn_mo"] = float(t["burn_mo"]) + amount
			t["troops_lost_mo"] = float(t["troops_lost_mo"]) + amount
		"mo_spent":
			t["burn_mo"] = float(t["burn_mo"]) + amount
			t["mo_spent"] = float(t["mo_spent"]) + amount
		"usd_spent":
			t["spend_usd"] = float(t["spend_usd"]) + amount
	var scoring: Dictionary = tournament_def().get("scoring", {})
	if not scoring.has(kind):
		return
	var pts: float = float(scoring[kind]) * amount
	if pts <= 0.0:
		return
	var sc: Dictionary = t["scores"]
	sc[p["id"]] = float(sc.get(p["id"], 0.0)) + pts
	if not p.get("is_bot", false):
		srv.mark_player_dirty(p["id"])


func leaderboard(limit: int = 10) -> Array:
	var t: Dictionary = data()["tournament"]
	var rows: Array = []
	for pid: String in t.get("scores", {}):
		rows.append([pid, float(t["scores"][pid])])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var out: Array = []
	for i: int in range(mini(limit, rows.size())):
		var q: Dictionary = srv.player(str(rows[i][0]))
		out.append({"rank": i + 1, "id": rows[i][0], "name": srv.display_name(str(rows[i][0])), "avatar": q.get("avatar", "p01"), "points": int(rows[i][1]), "bot": q.get("is_bot", false)})
	return out


func rank_of(pid: String) -> int:
	var t: Dictionary = data()["tournament"]
	var mine: float = float(t.get("scores", {}).get(pid, 0.0))
	if mine <= 0.0:
		return 0
	var r: int = 1
	for k: String in t["scores"]:
		if float(t["scores"][k]) > mine:
			r += 1
	return r


## Premio de un puesto: su parte del pozo (USD) convertida a objetos.
func prize_for_rank(rank: int, pool_usd: float) -> Dictionary:
	var shares: Array = cfg().get("prize_shares", [])
	if rank < 1 or rank > shares.size():
		return {}
	var usd: float = pool_usd * float(shares[rank - 1])
	var mo: float = usd * float(Catalog.shop.get("usd_to_mo", 100))
	var out: Dictionary = {}
	for m: Dictionary in cfg().get("prize_mix", []):
		var part: float = mo * float(m["share"])
		var unit: float = Catalog.value_mo(str(m["id"]))
		if unit <= 0.0:
			continue
		var qty: int = int(floor(part / unit))
		if qty > 0:
			out[str(m["id"])] = qty
	return out


func finish_tournament() -> void:
	var d: Dictionary = data()
	var t: Dictionary = d["tournament"]
	if t.is_empty():
		return
	var def: Dictionary = tournament_def(str(t["def"]))
	var board: Array = leaderboard(int((cfg().get("prize_shares", []) as Array).size()))
	var paid_usd: float = 0.0
	var winners: Array = []
	for row: Dictionary in board:
		var prize: Dictionary = prize_for_rank(int(row["rank"]), float(t["pool_usd"]))
		var shares: Array = cfg().get("prize_shares", [])
		paid_usd += float(t["pool_usd"]) * float(shares[int(row["rank"]) - 1])
		winners.append({"rank": row["rank"], "name": row["name"], "points": row["points"]})
		var p: Dictionary = srv.player(str(row["id"]))
		if not p.is_empty() and not p.get("is_bot", false):
			srv.progression.grant(p, prize, "tournament:%s:%d" % [t["id"], int(row["rank"])])
			srv.notify(p["id"], U.t("¡%s terminado! Quedaste #%d y recibiste tu premio.") % [U.t(str(def.get("name", ""))), int(row["rank"])], "success")
			srv.reports.add(p["id"], {"type": "event", "title": U.t("Premio de torneo: #%d en %s") % [int(row["rank"]), U.t(str(def.get("name", "")))], "outcome": "victory", "rewards": prize, "pos": [0, 0]})
	var usd_rate: float = float(Catalog.shop.get("usd_to_mo", 100))
	var burned_usd: float = float(t["burn_mo"]) / usd_rate + float(t["spend_usd"])
	var ratio: float = burned_usd / maxf(1.0, float(t["pool_usd"]))
	var targets: Dictionary = cfg().get("profit_targets", {})
	var next_pool: float = float(t["pool_usd"])
	var advice: String = "keep"
	if ratio > float(targets.get("raise_above", 4.0)):
		next_pool = roundf(next_pool * 1.25)
		advice = "raise"
	elif ratio < float(targets.get("lower_below", 2.0)):
		next_pool = maxf(50.0, roundf(next_pool * 0.8))
		advice = "lower"
	var hist: Dictionary = {
		"id": t["id"], "def": t["def"], "name": def.get("name", ""), "start": t["start"], "end": U.now_ms(),
		"participants": (t["scores"] as Dictionary).size(), "pool_usd": t["pool_usd"], "paid_usd": paid_usd,
		"burned_usd": burned_usd, "troops_lost_usd": float(t["troops_lost_mo"]) / usd_rate, "mo_spent_usd": float(t["mo_spent"]) / usd_rate,
		"spend_usd": t["spend_usd"], "ratio": ratio, "advice": advice, "next_pool_usd": next_pool, "winners": winners.slice(0, 3),
	}
	var hl: Array = d["history"]
	hl.push_front(hist)
	while hl.size() > 12:
		hl.pop_back()
	d["tournament"] = {}


# ---------------------------------------------------------------- vistas

func view(p: Dictionary) -> Dictionary:
	var d: Dictionary = data()
	var t: Dictionary = d["tournament"]
	var tdef: Dictionary = tournament_def()
	var prizes: Array = []
	for i: int in range((cfg().get("prize_shares", []) as Array).size()):
		prizes.append({"rank": i + 1, "usd": float(t.get("pool_usd", 0.0)) * float(cfg()["prize_shares"][i]), "reward": prize_for_rank(i + 1, float(t.get("pool_usd", 0.0)))})
	var rdef: Dictionary = resource_def()
	var usd_rate: float = float(Catalog.shop.get("usd_to_mo", 100))
	return {
		"resource": {"name": rdef.get("name", ""), "desc": rdef.get("desc", ""), "icon": rdef.get("icon", "event"), "end": int(d["resource"].get("end", 0)), "effects": rdef.get("effects", {})},
		"tournament": {
			"name": tdef.get("name", ""), "desc": tdef.get("desc", ""), "icon": tdef.get("icon", "event"), "end": int(t.get("end", 0)), "start": int(t.get("start", 0)),
			"pool_usd": float(t.get("pool_usd", 0.0)), "leaderboard": leaderboard(10), "my_rank": rank_of(p["id"]),
			"my_points": int(t.get("scores", {}).get(p["id"], 0.0)), "participants": (t.get("scores", {}) as Dictionary).size(), "prizes": prizes,
			"burned_usd": float(t.get("burn_mo", 0.0)) / usd_rate + float(t.get("spend_usd", 0.0)),
		},
		"history": d["history"],
		"upcoming": [_def("resource_events", int(d["r_index"]) + 1).get("name", ""), _def("tournaments", int(d["t_index"]) + 1).get("name", "")],
		"profit_targets": cfg().get("profit_targets", {}),
	}


## Solo para demos: termina el torneo / evento actual ahora.
func debug_finish(which: String) -> Dictionary:
	var now: int = U.now_ms()
	if which == "resource":
		_start_resource(now)
	else:
		finish_tournament()
		_start_tournament(now)
	return {"ok": true}
