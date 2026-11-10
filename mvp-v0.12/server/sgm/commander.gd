extends RefCounted
## Comandante (feedback del 26/10: "no existen el nivel de Comandante, los
## Protocolos de Mando ni el riesgo de captura").
##
## - Nivel por EXP (cazar, atacar, defender, minar); cada nivel da puntos.
## - Protocolos de Mando: talentos en 3 ramas (Combate, Economía, Liderazgo).
##   Sus efectos entran al sistema único de modificadores como `cmd_mods`.
## - Captura: si la nave pierde un ataque con muchas bajas, el Comandante puede
##   quedar prisionero del atacante. Mientras tanto sus Protocolos no aplican.
##   Se libera pagando el rescate (Créditos, que cobra el captor) o al cumplir
##   la condena. Los bots pagan solos tras un tiempo.
## Todos los valores vienen de data/catalog_commander.json.

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")

var srv: Node


func _init(server: Node) -> void:
	srv = server


func cfg() -> Dictionary:
	return Catalog.commander


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func ensure(p: Dictionary) -> Dictionary:
	if not p.has("commander"):
		p["commander"] = {"level": 1, "exp": 0, "talents": {}, "captured": {}, "prisoners": {}}
	return p["commander"]


# ---------------------------------------------------------------- nivel

func exp_to_next(lvl: int) -> int:
	var lv: Dictionary = cfg().get("levels", {})
	if lvl >= int(lv.get("max", 60)):
		return 0
	return int(round(float(lv.get("exp_base", 150)) * pow(float(lv.get("exp_growth", 1.1)), lvl - 1)))


func grant_exp(p: Dictionary, amount: int) -> int:
	var c: Dictionary = ensure(p)
	amount = int(round(amount * (1.0 + Eco.extra(p, "cmd_exp"))))
	if amount <= 0:
		return 0
	var lvl: int = int(c["level"])
	var xp: int = int(c["exp"]) + amount
	var start: int = lvl
	while exp_to_next(lvl) > 0 and xp >= exp_to_next(lvl):
		xp -= exp_to_next(lvl)
		lvl += 1
	if exp_to_next(lvl) == 0:
		xp = 0
	c["level"] = lvl
	c["exp"] = xp
	if lvl > start and not p.get("is_bot", false):
		srv.notify(p["id"], U.t("¡Tu Comandante sube a nivel %d! Tienes puntos de Protocolo para asignar.") % lvl, "success")
	srv.mark_player_dirty(p["id"])
	return lvl - start


# ---------------------------------------------------------------- Protocolos de Mando

func talent(tid: String) -> Dictionary:
	for b: Dictionary in cfg().get("branches", []):
		for t: Dictionary in b.get("talents", []):
			if str(t["id"]) == tid:
				var out: Dictionary = t.duplicate()
				out["branch"] = b["id"]
				return out
	return {}


func points_total(p: Dictionary) -> int:
	return (int(ensure(p)["level"]) - 1) * int(cfg().get("points_per_level", 1)) + int(cfg().get("points_per_level", 1))


func points_spent(p: Dictionary, branch: String = "") -> int:
	var n: int = 0
	var tal: Dictionary = ensure(p)["talents"]
	for tid: String in tal:
		if branch.is_empty() or str(talent(tid).get("branch", "")) == branch:
			n += int(tal[tid])
	return n


func points_free(p: Dictionary) -> int:
	return points_total(p) - points_spent(p)


func learn(p: Dictionary, tid: String) -> Dictionary:
	var t: Dictionary = talent(tid)
	if t.is_empty():
		return _err("UNKNOWN_TALENT", U.t("Protocolo desconocido"))
	var tal: Dictionary = ensure(p)["talents"]
	var rank: int = int(tal.get(tid, 0))
	if rank >= int(t["max"]):
		return _err("MAX_RANK", U.t("Ese Protocolo ya está al máximo"))
	if points_free(p) <= 0:
		return _err("NO_POINTS", U.t("No tienes puntos de Protocolo: sube de nivel a tu Comandante"))
	var need: int = int(t["tier"]) * int(cfg().get("points_per_tier", 5))
	if points_spent(p, str(t["branch"])) < need:
		return _err("TIER_LOCKED", U.t("Invierte %d puntos en esta rama para desbloquearlo") % need)
	tal[tid] = rank + 1
	refresh_mods(p)
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "rank": rank + 1}


func reset(p: Dictionary) -> Dictionary:
	var c: Dictionary = ensure(p)
	if (c["talents"] as Dictionary).is_empty():
		return _err("NOTHING", U.t("No hay Protocolos que reiniciar"))
	var cost: int = int(cfg().get("respec_cost_mo", 200))
	if not Eco.apply(p, {"dark_matter": -cost}, "commander_respec"):
		return _err("INSUFFICIENT_RESOURCES", U.t("Materia Oscura insuficiente (%d)") % cost)
	c["talents"] = {}
	refresh_mods(p)
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


## Efectos de los Protocolos (vacío mientras el Comandante está capturado).
func refresh_mods(p: Dictionary) -> void:
	var c: Dictionary = ensure(p)
	var mods: Dictionary = {}
	if (c.get("captured", {}) as Dictionary).is_empty():
		for tid: String in c["talents"]:
			var t: Dictionary = talent(tid)
			if not t.is_empty():
				mods[t["effect"]] = float(mods.get(t["effect"], 0.0)) + float(t["per_rank"]) * int(c["talents"][tid])
	p["cmd_mods"] = mods
	if p.has("crew"):
		srv.crew.refresh_mods(p)


# ---------------------------------------------------------------- captura

func is_captured(p: Dictionary) -> bool:
	return not (ensure(p).get("captured", {}) as Dictionary).is_empty()


func ransom_cost(p: Dictionary) -> int:
	var cap: Dictionary = cfg().get("capture", {})
	var base: float = float(cap.get("ransom_credits_per_level", 300)) * int(ensure(p)["level"])
	return int(round(base * maxf(0.2, 1.0 - Eco.extra(p, "ransom_discount"))))


## Tras un ataque ganado contra una nave: decide si el Comandante defensor
## queda capturado. Devuelve true si hubo captura (para el informe).
func try_capture(att: Dictionary, def: Dictionary, initial: Dictionary, losses: Dictionary, seed: int) -> bool:
	var cap: Dictionary = cfg().get("capture", {})
	if is_captured(def) or att["id"] == def["id"]:
		return false
	var total: int = maxi(1, U.sum_values(initial))
	if float(U.sum_values(losses)) / float(total) < float(cap.get("min_loss_ratio", 0.5)):
		return false
	var chance: float = float(cap.get("base_chance", 0.25)) * (1.0 + Eco.extra(att, "capture_chance")) * maxf(0.0, 1.0 - Eco.extra(def, "capture_resist"))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x5eed
	if rng.randf() >= chance:
		return false
	var now: int = U.now_ms()
	var until: int = now + int(cap.get("duration_sec", 900)) * 1000
	var ransom: int = ransom_cost(def)
	ensure(def)["captured"] = {"by": att["id"], "since": now, "until": until, "ransom": ransom}
	var pay_at: int = 0
	if def.get("is_bot", false):
		var rr: Array = cap.get("bot_ransom_after_sec", [90, 300])
		pay_at = now + rng.randi_range(int(rr[0]), int(rr[1])) * 1000
	ensure(att)["prisoners"][def["id"]] = {"since": now, "until": until, "ransom": ransom, "bot_pays_at": pay_at}
	refresh_mods(def)
	srv.notify(def["id"], U.t("¡%s capturó a tu Comandante! Sus Protocolos no aplican hasta pagar el rescate (%s Créditos) o cumplir la condena.") % [srv.display_name(att["id"]), U.fmt_int(ransom)], "danger")
	srv.notify(att["id"], U.t("Capturaste al Comandante de %s. Cobrarás %s Créditos si paga el rescate.") % [srv.display_name(def["id"]), U.fmt_int(ransom)], "success")
	srv.mark_player_dirty(def["id"])
	srv.mark_player_dirty(att["id"])
	return true


func pay_ransom(p: Dictionary) -> Dictionary:
	var c: Dictionary = ensure(p)
	var cap: Dictionary = c.get("captured", {})
	if cap.is_empty():
		return _err("NOT_CAPTURED", U.t("Tu Comandante no está capturado"))
	var cost: int = int(cap["ransom"])
	if not Eco.apply(p, {"credits": -cost}, "ransom_paid", "ransom:%s:%d" % [p["id"], int(cap["since"])]):
		return _err("INSUFFICIENT_RESOURCES", U.t("Créditos insuficientes (%s)") % U.fmt_int(cost))
	_release(p, true)
	return {"ok": true, "paid": cost}


## Libera al Comandante. Si se pagó el rescate, el captor lo cobra.
func _release(p: Dictionary, paid: bool) -> void:
	var c: Dictionary = ensure(p)
	var cap: Dictionary = c.get("captured", {})
	if cap.is_empty():
		return
	var captor: Dictionary = srv.player(str(cap.get("by", "")))
	c["captured"] = {}
	refresh_mods(p)
	if not captor.is_empty():
		ensure(captor)["prisoners"].erase(p["id"])
		if paid:
			var gain: int = int(round(int(cap["ransom"]) * (1.0 + Eco.extra(captor, "ransom_bonus"))))
			Eco.apply(captor, {"credits": gain}, "ransom_received", "ransom_in:%s:%d" % [p["id"], int(cap["since"])])
			srv.notify(captor["id"], U.t("%s pagó el rescate de su Comandante: +%s Créditos") % [srv.display_name(p["id"]), U.fmt_int(gain)], "success")
		srv.mark_player_dirty(captor["id"])
	srv.notify(p["id"], U.t("Tu Comandante volvió a la nave. Sus Protocolos de Mando están activos otra vez.") if paid else U.t("Tu Comandante cumplió la condena y volvió a la nave."), "success")
	srv.mark_player_dirty(p["id"])


func tick(now: int) -> void:
	for p: Dictionary in srv.state["players"].values():
		var c: Dictionary = p.get("commander", {})
		var cap: Dictionary = c.get("captured", {})
		if cap.is_empty():
			continue
		if now >= int(cap.get("until", 0)):
			_release(p, false)
			continue
		if p.get("is_bot", false):
			var captor: Dictionary = srv.player(str(cap.get("by", "")))
			var pr: Dictionary = captor.get("commander", {}).get("prisoners", {}).get(p["id"], {})
			if not pr.is_empty() and int(pr.get("bot_pays_at", 0)) > 0 and now >= int(pr["bot_pays_at"]):
				p["resources"]["credits"] = maxi(int(p["resources"].get("credits", 0)), int(cap["ransom"]))
				pay_ransom(p)


# ---------------------------------------------------------------- vista

func view(p: Dictionary) -> Dictionary:
	var c: Dictionary = ensure(p)
	var cap: Dictionary = c.get("captured", {})
	var captured: Dictionary = {}
	if not cap.is_empty():
		captured = {"by": srv.display_name(str(cap["by"])), "until": int(cap["until"]), "ransom": int(cap["ransom"])}
	var prisoners: Array = []
	for pid: String in c.get("prisoners", {}):
		var pr: Dictionary = c["prisoners"][pid]
		prisoners.append({"name": srv.display_name(pid), "avatar": srv.player(pid).get("avatar", "p01"), "until": int(pr["until"]), "ransom": int(pr["ransom"]), "level": int(srv.player(pid).get("commander", {}).get("level", 1))})
	return {
		"level": int(c["level"]), "exp": int(c["exp"]), "exp_next": exp_to_next(int(c["level"])),
		"points": points_free(p), "points_total": points_total(p), "talents": c["talents"],
		"spent": {"combat": points_spent(p, "combat"), "economy": points_spent(p, "economy"), "leadership": points_spent(p, "leadership")},
		"mods": p.get("cmd_mods", {}), "captured": captured, "prisoners": prisoners,
		"respec_cost": int(cfg().get("respec_cost_mo", 200)),
	}
