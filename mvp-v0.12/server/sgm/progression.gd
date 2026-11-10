extends RefCounted
## Progresión de la Astronave (Equipo 2): mejoras de salas, investigación,
## entrenamiento, curación, reanimación del Criosantuario, aceleradores e items.
## Todos los temporizadores son {start, end, total}; se completan de forma lazy.

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")

const QUEUES: Array = ["build", "research", "train", "heal", "revive", "rescue"]

var srv: Node


func _init(server: Node) -> void:
	srv = server


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func _ok(extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"ok": true}
	d.merge(extra)
	return d


func _queue_busy(p: Dictionary, q: String) -> bool:
	return p["queues"].get(q) is Dictionary and not (p["queues"][q] as Dictionary).is_empty()


func _start_queue(p: Dictionary, q: String, seconds: float, payload: Dictionary) -> void:
	var now: int = U.now_ms()
	var dur: int = maxi(1000, int(seconds * 1000.0))
	payload["start"] = now
	payload["end"] = now + dur
	payload["total"] = dur
	payload["helps"] = 0
	payload["help_requested"] = false
	p["queues"][q] = payload


# ---------------------------------------------------------------- salas

func upgrade_room(p: Dictionary, room_id: String) -> Dictionary:
	var room_def: Dictionary = Catalog.room(room_id)
	if room_def.is_empty():
		return _err("ROOM_UNKNOWN", U.t("Sala desconocida"))
	if _queue_busy(p, "build"):
		return _err("QUEUE_BUSY", U.t("Ya hay una construcción en curso"))
	var lvl: int = Eco.room_level(p, room_id)
	var target: int = lvl + 1
	if target > Catalog.room_max_level():
		return _err("MAX_LEVEL", U.t("La sala ya está al nivel máximo de la demo"))
	var cost: Dictionary = Catalog.room_cost(room_id, target)
	var label: String = U.t("%s Nv %d") % [room_def["name"], target]
	if lvl == 0:
		# Fase 2: construir una sala nueva (requisito de Puente y precio de desbloqueo).
		var unlock: Dictionary = room_def.get("unlock", {})
		if unlock.is_empty():
			return _err("ROOM_UNKNOWN", U.t("Sala desconocida"))
		if Eco.room_level(p, "bridge") < int(unlock.get("bridge", 1)):
			return _err("BRIDGE_REQUIRED", U.t("Requiere Puente de Mando Nv %d") % int(unlock.get("bridge", 1)))
		cost = unlock.get("cost", cost)
		label = U.t("Construyendo %s") % room_def["name"]
	elif room_id != "bridge" and target > Eco.room_level(p, "bridge"):
		return _err("BRIDGE_REQUIRED", U.t("Mejora primero el Puente de Mando a nivel %d") % target)
	if not Eco.apply(p, Eco.negate(cost), "room_upgrade:%s:%d" % [room_id, target]):
		return _err("INSUFFICIENT_RESOURCES", U.t("Recursos insuficientes"))
	if cost.has("dark_matter"):
		srv.on_activity(p, "mo_spent", float(cost["dark_matter"]))
	_start_queue(p, "build", Catalog.room_time(room_id, target), {"room": room_id, "target": target, "label": label})
	return _ok()


## Taller de Piezas: canje de elementos (X a 1 según el nivel del taller).
func exchange(p: Dictionary, from_id: String, to_id: String, amount: int) -> Dictionary:
	var lvl: int = Eco.room_level(p, "workshop")
	if lvl <= 0:
		return _err("ROOM_REQUIRED", U.t("Construye el Taller de Piezas para canjear elementos"))
	if from_id == to_id or not Catalog.element_ids.has(from_id) or not Catalog.element_ids.has(to_id):
		return _err("INVALID", U.t("Canje inválido"))
	amount = clampi(amount, 1, 100000)
	var rate: int = maxi(2, int(Eco.effect(p, "workshop", "exchange_rate")))
	if not Eco.apply(p, {from_id: -amount * rate, to_id: amount}, "exchange"):
		return _err("INSUFFICIENT_RESOURCES", U.t("Recursos insuficientes"))
	return _ok({"rate": rate, "gained": {to_id: amount}})


# ---------------------------------------------------------------- investigación

## Puerto de Comercio: vende elementos a cambio de Créditos.
func trade_sell(p: Dictionary, res_id: String, amount: int) -> Dictionary:
	if Eco.room_level(p, "trade_port") <= 0:
		return _err("ROOM_REQUIRED", U.t("Construye el Puerto de Comercio"))
	if not Catalog.element_ids.has(res_id) or amount <= 0:
		return _err("INVALID", U.t("Solo se venden elementos"))
	var credits: int = int(floor(amount * Eco.effect(p, "trade_port", "credit_rate")))
	if credits <= 0:
		return _err("INVALID", U.t("Cantidad demasiado pequeña"))
	if not Eco.apply(p, {res_id: -amount, "credits": credits}, "trade_sell"):
		return _err("INSUFFICIENT_RESOURCES", U.t("No tienes esa cantidad"))
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "credits": credits}


func start_research(p: Dictionary, tech_id: String) -> Dictionary:
	var t: Dictionary = Catalog.tech(tech_id)
	if t.is_empty():
		return _err("TECH_UNKNOWN", U.t("Tecnología desconocida"))
	if _queue_busy(p, "research"):
		return _err("QUEUE_BUSY", U.t("El Laboratorio ya está investigando"))
	var lvl: int = Eco.tech_level(p, tech_id)
	var target: int = lvl + 1
	if target > int(t.get("max", 5)):
		return _err("MAX_LEVEL", U.t("Tecnología completada"))
	var lab: int = Eco.room_level(p, "lab")
	if target > lab:
		return _err("LAB_REQUIRED", U.t("Requiere Laboratorio nivel %d") % target)
	if lab < int(t.get("requires_lab", 0)):
		return _err("LAB_REQUIRED", U.t("Requiere Laboratorio nivel %d") % int(t["requires_lab"]))
	# Árbol de investigación: prerrequisitos de la rama.
	var reqs: Dictionary = t.get("requires", {})
	for rid: String in reqs:
		if Eco.tech_level(p, rid) < int(reqs[rid]):
			return _err("TECH_REQUIRED", U.t("Requiere %s Nv %d") % [Catalog.tech(rid).get("name", rid), int(reqs[rid])])
	var cost: Dictionary = Catalog.tech_cost(tech_id, target)
	if not Eco.apply(p, Eco.negate(cost), "research:%s:%d" % [tech_id, target]):
		return _err("INSUFFICIENT_RESOURCES", U.t("Recursos insuficientes"))
	var speed: float = 1.0 + Eco.effect(p, "lab", "research_speed") + Eco.extra(p, "research_speed")
	_start_queue(p, "research", Catalog.tech_time(tech_id, target) / speed, {"tech": tech_id, "target": target, "label": U.t("%s Nv %d") % [t["name"], target]})
	return _ok()


# ---------------------------------------------------------------- entrenamiento

func train(p: Dictionary, key: String, qty: int) -> Dictionary:
	var tier: Dictionary = Catalog.troop_tier(key)
	if tier.is_empty():
		return _err("TROOP_UNKNOWN", U.t("Fuerza desconocida"))
	if qty <= 0:
		return _err("INVALID_QTY", U.t("Cantidad inválida"))
	if _queue_busy(p, "train"):
		return _err("QUEUE_BUSY", U.t("El Hangar ya está entrenando"))
	var req: String = str(tier.get("requires_tech", ""))
	if not req.is_empty() and Eco.tech_level(p, req) <= 0:
		return _err("TECH_REQUIRED", U.t("Requiere investigar %s") % Catalog.tech(req).get("name", req))
	var batch: int = Eco.train_batch(p)
	if qty > batch:
		return _err("BATCH_LIMIT", U.t("El Hangar entrena máximo %d por lote") % batch)
	var recipe: Dictionary = tier.get("recipe", {})
	if not Eco.apply(p, Eco.negate(recipe, qty), "train:%s:%d" % [key, qty]):
		return _err("INSUFFICIENT_RESOURCES", U.t("Recursos insuficientes"))
	var speed: float = 1.0 + Eco.effect(p, "hangar", "train_speed") + Eco.extra(p, "train_speed")
	var secs: float = float(tier.get("train_sec", 1.0)) * qty / speed
	_start_queue(p, "train", secs, {"troop": key, "qty": qty, "label": "%d × %s" % [qty, Catalog.troop_name(key)]})
	return _ok()


# ---------------------------------------------------------------- curación / reanimación

func _heal_cost(stacks: Dictionary, factor: float) -> Dictionary:
	var cost: Dictionary = {}
	for k: String in stacks:
		var recipe: Dictionary = Catalog.troop_tier(k).get("recipe", {})
		for r: String in recipe:
			cost[r] = int(cost.get(r, 0)) + int(ceil(float(recipe[r]) * int(stacks[k]) * factor))
	return cost


func heal_cost(p: Dictionary) -> Dictionary:
	return _heal_cost(p.get("wounded", {}), 0.25)


func revive_cost(p: Dictionary) -> Dictionary:
	return _heal_cost(p.get("cryo", {}), 0.4)


func heal(p: Dictionary) -> Dictionary:
	if _queue_busy(p, "heal"):
		return _err("QUEUE_BUSY", U.t("La Bahía Médica ya está curando"))
	var stacks: Dictionary = p.get("wounded", {}).duplicate()
	var total: int = Eco.troops_total(stacks)
	if total <= 0:
		return _err("NOTHING", U.t("No hay heridos"))
	if not Eco.apply(p, Eco.negate(_heal_cost(stacks, 0.25)), "heal"):
		return _err("INSUFFICIENT_RESOURCES", U.t("Recursos insuficientes"))
	p["wounded"] = {}
	_start_queue(p, "heal", 2.0 + total * 0.15, {"stacks": stacks, "label": U.t("Curando %d heridos") % total})
	return _ok()


func revive(p: Dictionary) -> Dictionary:
	if _queue_busy(p, "revive"):
		return _err("QUEUE_BUSY", U.t("El Criosantuario ya está reanimando"))
	var stacks: Dictionary = p.get("cryo", {}).duplicate()
	var total: int = Eco.troops_total(stacks)
	if total <= 0:
		return _err("NOTHING", U.t("No hay fuerzas en criostasis"))
	if not Eco.apply(p, Eco.negate(_heal_cost(stacks, 0.4)), "revive"):
		return _err("INSUFFICIENT_RESOURCES", U.t("Recursos insuficientes"))
	p["cryo"] = {}
	_start_queue(p, "revive", 4.0 + total * 0.3, {"stacks": stacks, "label": U.t("Reanimando %d fuerzas") % total})
	return _ok()


# ---------------------------------------------------------------- completar / acelerar

## Completa los temporizadores vencidos. Devuelve eventos para misiones.
func complete_due(p: Dictionary, now: int) -> Array:
	var events: Array = []
	for q: String in QUEUES:
		var job: Variant = p["queues"].get(q)
		if not (job is Dictionary) or (job as Dictionary).is_empty():
			continue
		if int(job["end"]) > now:
			continue
		p["queues"][q] = {}
		match q:
			"build":
				var room_id: String = job["room"]
				if not p["rooms"].has(room_id):
					p["rooms"][room_id] = {"level": 0, "pending": {}, "last_ts": now}
					events.append(["room_built", 1, {"room": room_id}])
				p["rooms"][room_id]["level"] = int(job["target"])
				if room_id == "crew":
					srv.crew.refresh_mods(p)
				events.append(["room_upgraded", 1, {"room": room_id, "level": int(job["target"])}])
				events.append(["room_level:%s" % room_id, int(job["target"]), {"set": true}])
				srv.notify(p["id"], U.t("Mejora completada: %s") % job["label"], "success")
			"research":
				p["tech"][job["tech"]] = int(job["target"])
				events.append(["research_done", 1, {}])
				srv.notify(p["id"], U.t("Investigación completada: %s") % job["label"], "success")
			"train":
				Eco.add_troops(p["troops"], {job["troop"]: int(job["qty"])})
				events.append(["troops_trained", int(job["qty"]), {}])
				srv.notify(p["id"], U.t("Entrenamiento completado: %s") % job["label"], "success")
			"heal":
				Eco.add_troops(p["troops"], job["stacks"])
				srv.notify(p["id"], U.t("Heridos recuperados"), "success")
			"revive":
				Eco.add_troops(p["troops"], job["stacks"])
				srv.notify(p["id"], U.t("Fuerzas reanimadas desde el Criosantuario"), "success")
			"rescue":
				var back: Dictionary = srv.endgame.rescue_complete(p)
				srv.notify(p["id"], U.t("Operación de Rescate completada: %d fuerzas vuelven del Criosantuario") % Eco.troops_total(back), "success")
		srv.mark_player_dirty(p["id"], true)
	return events


func dark_matter_cost(remaining_ms: int) -> int:
	# 1 Materia Oscura por cada 6 s restantes (valores de demo).
	return maxi(1, ceili(remaining_ms / 6000.0))


func speedup(p: Dictionary, q: String, method: String) -> Dictionary:
	var job: Variant = p["queues"].get(q)
	if not (job is Dictionary) or (job as Dictionary).is_empty():
		return _err("NO_JOB", U.t("No hay nada que acelerar"))
	var now: int = U.now_ms()
	var remaining: int = int(job["end"]) - now
	if remaining <= 0:
		return _ok()
	if method == "free":
		if remaining > int(Catalog.rooms_data.get("free_speedup_sec", 15)) * 1000:
			return _err("NOT_FREE", U.t("Aún no es gratis"))
		job["end"] = now
	elif method == "dark_matter":
		var cost: int = dark_matter_cost(remaining)
		if not Eco.apply(p, {"dark_matter": -cost}, "speedup:%s" % q):
			return _err("INSUFFICIENT_RESOURCES", U.t("Materia Oscura insuficiente"))
		srv.on_activity(p, "mo_spent", float(cost))
		job["end"] = now
	elif method.begins_with("item:"):
		var item_id: String = method.trim_prefix("item:")
		var it: Dictionary = Catalog.item(item_id)
		if str(it.get("kind", "")) != "speedup":
			return _err("INVALID_ITEM", U.t("Ese objeto no es un acelerador"))
		if not Eco.apply(p, {item_id: -1}, "speedup_item:%s" % q):
			return _err("NO_ITEM", U.t("No tienes ese acelerador"))
		job["end"] = int(job["end"]) - int(it["seconds"]) * 1000
	else:
		return _err("INVALID_METHOD", U.t("Método inválido"))
	complete_due(p, U.now_ms())
	return _ok()


## Ayuda Mutua (Equipo 4): -1% del total (mínimo 60 s) por ayuda.
func apply_help(p: Dictionary, q: String) -> bool:
	var job: Variant = p["queues"].get(q)
	if not (job is Dictionary) or (job as Dictionary).is_empty():
		return false
	var reduce: int = maxi(60000, int(int(job["total"]) * 0.01))
	job["end"] = int(job["end"]) - reduce
	job["helps"] = int(job.get("helps", 0)) + 1
	return true


# ---------------------------------------------------------------- items

func use_item(p: Dictionary, item_id: String, params: Dictionary) -> Dictionary:
	var it: Dictionary = Catalog.item(item_id)
	if it.is_empty():
		return _err("INVALID_ITEM", U.t("Objeto desconocido"))
	if Eco.balance(p, item_id) <= 0:
		return _err("NO_ITEM", U.t("No tienes ese objeto"))
	match str(it.get("kind", "")):
		"speedup":
			return speedup(p, str(params.get("queue", "")), "item:" + item_id)
		"energy":
			Eco.apply(p, {item_id: -1, "energy": int(it.get("amount", 50))}, "use_item")
			return _ok()
		"shield":
			Eco.apply(p, {item_id: -1}, "use_item")
			p["shield_until"] = maxi(int(p.get("shield_until", 0)), U.now_ms()) + int(it.get("seconds", 900)) * 1000
			srv.bump_base_of(p["id"])
			return _ok()
		"crate":
			var delta: Dictionary = {item_id: -1}
			for e: String in Catalog.mining_element_ids:
				delta[e] = int(it.get("amount", 400))
			Eco.apply(p, delta, "use_item")
			return _ok()
		"warp":
			return srv.fleets.relocate(p, Vector2i(int(params.get("x", -1)), int(params.get("y", -1))), true)
		"escape":
			return srv.fleets.escape_jump(p)
		"interstellar":
			return srv.galaxy.jump(p, str(params.get("system", "")), "item")
	return _err("INVALID_ITEM", U.t("Objeto no utilizable"))


## Concede un paquete de recompensa (recursos o items).
func grant(p: Dictionary, reward: Dictionary, reason: String, idem: String = "") -> void:
	var delta: Dictionary = {}
	for k: String in reward:
		delta[k] = int(reward[k])
	Eco.apply(p, delta, reason, idem)
	# La energía no supera el máximo salvo por items.
	srv.mark_player_dirty(p["id"])
