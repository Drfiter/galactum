extends RefCounted
## Tienda, moneda opaca y bono diario (SGM).
##
## Todo tiene un precio en Materia Oscura (MO) y la MO tiene un precio en USD
## (catalog_shop.json). Las compras con dinero real son SIMULADAS en el MVP:
## se registran (usd_spent) para medir la economía y la rentabilidad de eventos,
## pero no se cobra nada.

const U = preload("res://shared/util.gd")
const Eco = preload("res://server/sgm/economy.gd")
const DAY_MS: int = 86400000

var srv: Node


func _init(server: Node) -> void:
	srv = server


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func cfg() -> Dictionary:
	return Catalog.shop


func usd_to_mo() -> float:
	return float(cfg().get("usd_to_mo", 100))


func item_price(item_id: String) -> int:
	return maxi(1, int(round(Catalog.value_mo(item_id))))


func bundle(bundle_id: String) -> Dictionary:
	for b: Dictionary in cfg().get("bundles", []):
		if str(b["id"]) == bundle_id:
			return b
	return {}


func bundle_price(b: Dictionary) -> int:
	return maxi(1, int(round(Catalog.value_mo(str(b["res"]), float(b["amount"])))))


func pack(pack_id: String) -> Dictionary:
	for pk: Dictionary in cfg().get("packs", []):
		if str(pk["id"]) == pack_id:
			return pk
	return {}


func _stat_add(p: Dictionary, key: String, v: float) -> void:
	var st: Dictionary = p.get("stats", {})
	st[key] = float(st.get(key, 0.0)) + v
	p["stats"] = st


## Compra con Materia Oscura (objetos de la tienda).
func buy_item(p: Dictionary, item_id: String, qty: int) -> Dictionary:
	if not (cfg().get("item_offers", []) as Array).has(item_id):
		return _err("NOT_FOR_SALE", U.t("Ese objeto no está a la venta"))
	qty = clampi(qty, 1, 99)
	var cost: int = item_price(item_id) * qty
	if not Eco.apply(p, {"dark_matter": -cost, item_id: qty}, "shop:%s" % item_id):
		return _err("INSUFFICIENT_RESOURCES", U.t("Materia Oscura insuficiente (%d)") % cost)
	_stat_add(p, "mo_spent", cost)
	srv.on_activity(p, "mo_spent", float(cost))
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "reward": {item_id: qty}, "cost": cost}


func buy_bundle(p: Dictionary, bundle_id: String) -> Dictionary:
	var b: Dictionary = bundle(bundle_id)
	if b.is_empty():
		return _err("NOT_FOR_SALE", U.t("Paquete desconocido"))
	var cost: int = bundle_price(b)
	if not Eco.apply(p, {"dark_matter": -cost, str(b["res"]): int(b["amount"])}, "shop:%s" % bundle_id):
		return _err("INSUFFICIENT_RESOURCES", U.t("Materia Oscura insuficiente (%d)") % cost)
	_stat_add(p, "mo_spent", cost)
	srv.on_activity(p, "mo_spent", float(cost))
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "reward": {str(b["res"]): int(b["amount"])}, "cost": cost}


## Compra de MO con dinero (SIMULADA: no hay pasarela de pago en el MVP).
func buy_pack(p: Dictionary, pack_id: String) -> Dictionary:
	var pk: Dictionary = pack(pack_id)
	if pk.is_empty():
		return _err("NOT_FOR_SALE", U.t("Oferta desconocida"))
	var bought: Array = p.get("packs_bought", [])
	if bool(pk.get("once", false)) and bought.has(pack_id):
		return _err("ALREADY_BOUGHT", U.t("Esta oferta solo se puede comprar una vez"))
	var reward: Dictionary = {"dark_matter": int(pk["mo"])}
	for k: String in pk.get("items", {}):
		reward[k] = int(pk["items"][k])
	srv.progression.grant(p, reward, "purchase:%s" % pack_id)
	bought.append(pack_id)
	p["packs_bought"] = bought
	_stat_add(p, "usd_spent", float(pk["usd"]))
	srv.on_activity(p, "usd_spent", float(pk["usd"]))
	srv.mark_player_dirty(p["id"])
	return {"ok": true, "reward": reward, "usd": float(pk["usd"])}


# ---------------------------------------------------------------- bono diario

func login_cfg() -> Dictionary:
	return cfg().get("login", {})


func _cycle_ms() -> int:
	return int(float(login_cfg().get("cycle_hours", 24)) * 3600000.0)


## Estado del bono: el día del ciclo y cuándo se puede reclamar el siguiente.
func login_state(p: Dictionary) -> Dictionary:
	var lg: Dictionary = p.get("login", {})
	var now: int = U.now_ms()
	var last: int = int(lg.get("last_ts", 0))
	var days: int = int(login_cfg().get("days", 7))
	var claimed: int = int(lg.get("claimed", 0))   # total de días reclamados
	var next_at: int = last + _cycle_ms() if last > 0 else 0
	var day: int = claimed % days                   # 0..6: el día que toca
	var budgets: Array = login_cfg().get("budget_usd", [1.0])
	var preview: Array = []
	for i: int in range(days):
		preview.append(float(budgets[mini(i, budgets.size() - 1)]))
	return {
		"day": day, "days": days, "claimed_total": claimed, "available": now >= next_at,
		"next_at": next_at, "budgets_usd": preview, "last_reward": lg.get("last_reward", {}),
	}


## "Función aleatoria con todos los regalos de un centavo que se corre hasta
## llegar al presupuesto": arma la caja del día con valor ≈ budget.
func roll_gift(seed: int, budget_mo: float) -> Dictionary:
	var pool: Array = login_cfg().get("pool", [])
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var out: Dictionary = {}
	var total: float = 0.0
	var guard: int = 0
	while total < budget_mo and guard < 500 and not pool.is_empty():
		guard += 1
		var g: Dictionary = pool[r.randi() % pool.size()]
		var v: float = Catalog.value_mo(str(g["id"]), float(g["qty"]))
		if v <= 0.0 or total + v > budget_mo * 1.08:
			continue
		out[str(g["id"])] = int(out.get(str(g["id"]), 0)) + int(g["qty"])
		total += v
	return out


func claim_login(p: Dictionary) -> Dictionary:
	var st: Dictionary = login_state(p)
	if not bool(st["available"]):
		return _err("NOT_YET", U.t("El próximo bono estará disponible en %s") % U.fmt_time(float(int(st["next_at"]) - U.now_ms()) / 1000.0))
	var day: int = int(st["day"])
	var budget_mo: float = float(st["budgets_usd"][day]) * usd_to_mo()
	var reward: Dictionary = roll_gift(U.hash_seed("%s:login:%d" % [p["id"], int(st["claimed_total"])]), budget_mo)
	if day == int(st["days"]) - 1:
		for k: String in login_cfg().get("day7_guaranteed", {}):
			reward[k] = int(reward.get(k, 0)) + int(login_cfg()["day7_guaranteed"][k])
	srv.progression.grant(p, reward, "login_bonus:%d" % int(st["claimed_total"]))
	var lg: Dictionary = p.get("login", {})
	lg["last_ts"] = U.now_ms()
	lg["claimed"] = int(st["claimed_total"]) + 1
	lg["last_reward"] = reward
	p["login"] = lg
	_stat_add(p, "gift_usd", Catalog.bundle_value_mo(reward) / usd_to_mo())
	srv.missions.on_event(p, "login_claimed", 1)
	return {"ok": true, "reward": reward, "day": day + 1, "value_usd": Catalog.bundle_value_mo(reward) / usd_to_mo()}


## Solo para demos: adelanta el ciclo para mostrar el siguiente día.
func debug_next_day(p: Dictionary) -> Dictionary:
	var lg: Dictionary = p.get("login", {})
	lg["last_ts"] = int(lg.get("last_ts", 0)) - _cycle_ms()
	p["login"] = lg
	srv.mark_player_dirty(p["id"])
	return {"ok": true}


func view(p: Dictionary) -> Dictionary:
	return {
		"login": login_state(p),
		"packs_bought": p.get("packs_bought", []),
		"usd_spent": float(p.get("stats", {}).get("usd_spent", 0.0)),
	}
