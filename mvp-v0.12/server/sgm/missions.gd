extends RefCounted
## Misiones de historia (onboarding) y el evento rotativo "Órdenes del Día"
## (Equipo 5: el evento es data-driven; su scorer mapea eventos de juego a puntos).

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")

var srv: Node


func _init(server: Node) -> void:
	srv = server


func story() -> Array:
	return Catalog.missions.get("story", [])


func daily_def() -> Dictionary:
	return Catalog.missions.get("daily_event", {})


func ensure(p: Dictionary) -> void:
	if not p.has("missions"):
		p["missions"] = {"index": 0, "progress": 0}
	_refresh_daily(p)
	refresh_story(p)


func current(p: Dictionary) -> Dictionary:
	var idx: int = int(p["missions"].get("index", 0))
	var list: Array = story()
	return list[idx] if idx < list.size() else {}


func refresh_story(p: Dictionary) -> void:
	var m: Dictionary = current(p)
	if m.is_empty():
		return
	var ev: String = str(m["event"])
	if ev.begins_with("room_level:"):
		var lvl: int = Eco.room_level(p, ev.trim_prefix("room_level:"))
		p["missions"]["progress"] = maxi(int(p["missions"]["progress"]), lvl)


func on_event(p: Dictionary, event: String, amount: int, extra: Dictionary = {}) -> void:
	if p.get("is_bot", false):
		return
	ensure(p)
	var m: Dictionary = current(p)
	if not m.is_empty() and str(m["event"]) == event:
		if bool(extra.get("set", false)):
			p["missions"]["progress"] = maxi(int(p["missions"]["progress"]), amount)
		else:
			p["missions"]["progress"] = int(p["missions"]["progress"]) + amount
		if int(p["missions"]["progress"]) >= int(m["target"]):
			srv.notify(p["id"], U.t("¡Misión completada! %s — reclama tu recompensa") % m["title"], "mission")
	var pts_table: Dictionary = daily_def().get("points", {})
	if pts_table.has(event):
		var d: Dictionary = p["daily"]
		var before: int = int(d.get("points", 0))
		d["points"] = before + int(ceil(float(pts_table[event]) * amount))
		for i: int in range(daily_def().get("tiers", []).size()):
			var tier: Dictionary = daily_def()["tiers"][i]
			if before < int(tier["points"]) and int(d["points"]) >= int(tier["points"]):
				srv.notify(p["id"], U.t("Órdenes del Día: ¡nivel %d alcanzado!") % (i + 1), "mission")
	srv.mark_player_dirty(p["id"])


func claim_story(p: Dictionary) -> Dictionary:
	ensure(p)
	var m: Dictionary = current(p)
	if m.is_empty():
		return {"ok": false, "code": "NO_MISSION", "message": U.t("No hay misiones pendientes")}
	if int(p["missions"]["progress"]) < int(m["target"]):
		return {"ok": false, "code": "NOT_DONE", "message": U.t("La misión aún no está completa")}
	srv.progression.grant(p, m.get("reward", {}), "mission:%s" % m["id"], "mission:%s" % m["id"])
	p["missions"]["index"] = int(p["missions"]["index"]) + 1
	p["missions"]["progress"] = 0
	refresh_story(p)
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "reward": m.get("reward", {})}


func _refresh_daily(p: Dictionary) -> void:
	var cycle_ms: int = int(daily_def().get("cycle_sec", 10800)) * 1000
	var cycle: int = U.now_ms() / cycle_ms
	var d: Dictionary = p.get("daily", {})
	if int(d.get("cycle", -1)) != cycle:
		d = {"cycle": cycle, "points": 0, "claimed": []}
	p["daily"] = d


func daily_ends_at(p: Dictionary) -> int:
	var cycle_ms: int = int(daily_def().get("cycle_sec", 10800)) * 1000
	return (int(p["daily"]["cycle"]) + 1) * cycle_ms


func claim_daily(p: Dictionary, tier_index: int) -> Dictionary:
	ensure(p)
	var tiers: Array = daily_def().get("tiers", [])
	if tier_index < 0 or tier_index >= tiers.size():
		return {"ok": false, "code": "INVALID", "message": U.t("Nivel inválido")}
	var d: Dictionary = p["daily"]
	if (d["claimed"] as Array).has(tier_index):
		return {"ok": false, "code": "CLAIMED", "message": U.t("Ya reclamado")}
	if int(d["points"]) < int(tiers[tier_index]["points"]):
		return {"ok": false, "code": "NOT_DONE", "message": U.t("Faltan puntos")}
	(d["claimed"] as Array).append(tier_index)
	srv.progression.grant(p, tiers[tier_index]["reward"], "daily:%d" % tier_index, "daily:%d:%d" % [int(d["cycle"]), tier_index])
	return {"ok": true, "reward": tiers[tier_index]["reward"]}
