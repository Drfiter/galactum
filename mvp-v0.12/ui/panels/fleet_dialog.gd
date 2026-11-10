extends "res://ui/panels/window.gd"
## Composición de flota antes de despegar (el snapshot de combate se congela al enviar).

const Resolver = preload("res://server/combat/combat_resolver.gd")
const MISSION_TITLES: Dictionary = {"gather": "Enviar flota minera", "hunt": "Enviar flota de caza", "attack": "Enviar flota de ataque",
	"reinforce": "Enviar refuerzos", "rally": "Abrir Asedio", "rally_join": "Sumarse al Asedio"}

var mission: String = "gather"
var entity: Dictionary = {}
var _sel: Dictionary = {}
var _sliders: Dictionary = {}
var _labels: Dictionary = {}
var _summary: VBoxContainer
var _send_btn: Button
var _updating: bool = false
var _crew_sel: Array = []
var _crew_label: Label
var _rally_wait: int = 60
var _formation: String = "balanced"


func _init() -> void:
	desired_size = Vector2(960, 640)


func window_title() -> String:
	mission = str(args.get("mission", "gather"))
	return U.t(MISSION_TITLES.get(mission, U.t("Enviar flota")))


func window_icon() -> String:
	return {"gather": "ui_mine", "hunt": "ui_hunt", "attack": "ui_attack", "reinforce": "ui_shield", "rally": "ui_rally", "rally_join": "ui_rally"}.get(str(args.get("mission", "")), "ui_ship")


func build() -> void:
	mission = str(args.get("mission", "gather"))
	entity = args.get("entity", {})
	var row := UI.hbox(18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)

	var left := UI.vbox(10)
	left.custom_minimum_size.x = 300
	row.add_child(left)
	left.add_child(_target_card())
	_summary = UI.vbox(6)
	var sum_card := UI.panel("Card", _summary)
	left.add_child(sum_card)
	left.add_child(UI.spacer())
	if mission == "rally":
		left.add_child(_wait_picker())
	elif mission in ["gather", "hunt", "attack"]:
		left.add_child(_formation_picker())
	_send_btn = UI.button(U.t("¡Despegar!") if not mission.begins_with("rally") else (U.t("Abrir Asedio") if mission == "rally" else U.t("Sumarme")), "DangerButton" if mission in ["attack", "rally", "rally_join"] else "PrimaryButton", window_icon(), Vector2(0, 60))
	_send_btn.pressed.connect(_send)
	left.add_child(_send_btn)

	var right := UI.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var presets := UI.hbox(8)
	right.add_child(presets)
	for p: Array in [[U.t("Recomendado"), "recommended"], [U.t("Máximo"), "max"], [U.t("Equilibrado"), "balanced"], [U.t("Limpiar"), "clear"]]:
		var b := UI.button(p[0], "GhostButton", "", Vector2(0, 44))
		var key: String = p[1]
		b.pressed.connect(func() -> void: _apply_preset(key))
		presets.add_child(b)
	if not mission.begins_with("rally") and mission != "reinforce":
		right.add_child(_crew_card())
	var list := UI.vbox(8)
	right.add_child(scroll_body(list))
	var home: Dictionary = GameClient.troops_home()
	var keys: Array = home.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return Catalog.troop_order.find(Catalog.split_troop_key(a)[0]) * 10 + int(Catalog.split_troop_key(a)[1]) < Catalog.troop_order.find(Catalog.split_troop_key(b)[0]) * 10 + int(Catalog.split_troop_key(b)[1]))
	if keys.is_empty():
		list.add_child(UI.label(U.t("No tienes tropas en la nave. Entrena en el Hangar o espera a que regresen tus flotas."), 16, UI.GOLD))
	for k: String in keys:
		if int(home[k]) <= 0:
			continue
		list.add_child(_troop_row(k, int(home[k])))
	_apply_preset("recommended")


func _target_card() -> Control:
	var card := UI.panel("CardHi")
	var v := UI.vbox(6)
	card.add_child(v)
	if mission == "rally_join":
		v.add_child(UI.label(U.t("Asedio de %s") % str(entity.get("leader", "")), 17, UI.TEXT, "bold"))
		v.add_child(UI.wrap(UI.label(U.t("Objetivo: %s · %d/%d tropas") % [str(entity.get("target", "")), int(entity.get("troops", 0)), int(entity.get("capacity", 0))], 13, UI.TEXT_DIM)))
		return card
	var kind: String = str(entity.get("kind", ""))
	var h := UI.hbox(10)
	v.add_child(h)
	var title: String = ""
	var sub: String = ""
	match kind:
		"asteroid":
			h.add_child(UI.icon(UI.res_icon_name(str(entity.get("element", ""))), 56))
			title = U.t("Asteroide N%d") % int(entity.get("level", 1))
			sub = U.t("%s · %s restante") % [Catalog.res_name(str(entity.get("element", ""))), U.fmt_num(int(entity.get("remaining", 0)))]
			if mission == "attack":
				title = U.t("Flota minera de ") + str(entity.get("occupant_name", ""))
		"xenoform":
			h.add_child(UI.image(UI.xeno_tex(str(entity.get("species", "")), int(entity.get("level", 1))), Vector2(64, 64)))
			var sp: Dictionary = Catalog.species_by_id.get(str(entity.get("species", "")), {})
			title = U.t("%s N%d") % [sp.get("name", ""), int(entity.get("level", 1))]
			sub = U.t("Vida %s · Débil a daño %s") % [U.fmt_num(int(entity.get("hp", 0))), U.t("físico") if sp.get("weakness", "") == "fisica" else U.t("energético")]
		"base":
			h.add_child(UI.image(UI.portrait_tex(str(entity.get("avatar", "p01"))), Vector2(64, 64)))
			title = ("[%s] " % entity.get("tag", "") if not str(entity.get("tag", "")).is_empty() else "") + str(entity.get("name", ""))
			sub = U.t("Poder %s · Astronave Nv %d") % [U.fmt_int(int(entity.get("power", 0))), int(entity.get("level", 1))]
	var tv := UI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.wrap(UI.label(title, 17, UI.TEXT, "bold")))
	tv.add_child(UI.wrap(UI.label(sub, 13, UI.TEXT_DIM)))
	h.add_child(tv)
	var dist: float = GameClient.base_pos().distance_to(GameClient.entity_position(entity))
	v.add_child(UI.label(U.t("Distancia: %d casillas") % int(dist), 14, UI.TEXT_DIM))
	return card


func _troop_row(key: String, have: int) -> Control:
	var card := UI.panel("Card")
	var h := UI.hbox(10)
	card.add_child(h)
	h.add_child(UI.icon(UI.troop_icon_name(key), 46))
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := UI.hbox(8)
	top.add_child(UI.label(Catalog.troop_name(key), 16, UI.TEXT, "bold"))
	top.add_child(UI.spacer())
	var lbl := UI.label("", 15, UI.CYAN, "bold")
	top.add_child(lbl)
	v.add_child(top)
	var srow := UI.hbox(8)
	var minus := UI.icon_button("ui_minus", 38, "Button")
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = have
	s.step = 1
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(160, 32)
	var plus := UI.icon_button("ui_plus", 38, "Button")
	srow.add_child(minus)
	srow.add_child(s)
	srow.add_child(plus)
	v.add_child(srow)
	h.add_child(v)
	_sliders[key] = s
	_labels[key] = lbl
	s.value_changed.connect(func(val: float) -> void: _on_slider(key, int(val)))
	minus.pressed.connect(func() -> void: s.value = maxf(0, s.value - 5))
	plus.pressed.connect(func() -> void: s.value = minf(s.max_value, s.value + 5))
	return card


func _capacity() -> int:
	var hq: Dictionary = GameClient.me.get("alliance_hq", {})
	match mission:
		"rally":
			return int(hq.get("rally_capacity", 450))
		"rally_join":
			return maxi(0, int(entity.get("capacity", 0)) - int(entity.get("troops", 0)))
	return int(GameClient.me.get("caps", {}).get("march_capacity", 150))


## Formación de combate: bonos y penalizaciones para esta flota.
func _formation_picker() -> Control:
	if mission == "hunt":
		_formation = "hunter"
	var card := UI.panel("Card")
	var v := UI.vbox(4)
	card.add_child(v)
	v.add_child(UI.label(U.t("Formación"), 14, UI.CYAN, "bold"))
	var flow := UI.flow(4, 4)
	v.add_child(flow)
	var desc := UI.wrap(UI.label("", 12, UI.TEXT_DIM), 270)
	for f: Dictionary in Catalog.troops.get("formations", []):
		var fid: String = str(f["id"])
		var req: String = str(f.get("requires_tech", ""))
		var locked: bool = not req.is_empty() and GameClient.tech_level(req) <= 0
		var b := UI.button(U.t(str(f["name"])), "PrimaryButton" if fid == _formation else "TabButton", "", Vector2(0, 36))
		b.add_theme_font_size_override("font_size", 13)
		b.disabled = locked
		b.name = "Formation_" + fid
		b.tooltip_text = U.t(str(f.get("desc", ""))) + ("\n" + U.t("Requiere investigar %s") % str(Catalog.tech(req).get("name", req)) if locked else "")
		var fdesc: String = U.t(str(f.get("desc", "")))
		b.pressed.connect(func() -> void:
			_formation = fid
			desc.text = fdesc
			for ch: Node in flow.get_children():
				(ch as Button).theme_type_variation = "TabButton"
			b.theme_type_variation = "PrimaryButton")
		if fid == _formation:
			desc.text = fdesc
		flow.add_child(b)
	v.add_child(desc)
	return card


## Tiempo de espera del Asedio para que los aliados se sumen.
func _wait_picker() -> Control:
	var card := UI.panel("Card")
	var v := UI.vbox(6)
	card.add_child(v)
	v.add_child(UI.label(U.t("Espera para que se sumen los aliados"), 14, UI.CYAN, "bold"))
	var h := UI.hbox(6)
	v.add_child(h)
	for w: Variant in GameClient.me.get("alliance_hq", {}).get("waits", [30, 60, 120]):
		var secs: int = int(w)
		var b := UI.button("%d s" % secs, "PrimaryButton" if secs == _rally_wait else "TabButton", "", Vector2(80, 42))
		b.pressed.connect(func() -> void:
			_rally_wait = secs
			for ch: Node in h.get_children():
				(ch as Button).theme_type_variation = "TabButton"
			b.theme_type_variation = "PrimaryButton")
		h.add_child(b)
	v.add_child(UI.wrap(UI.label(U.t("La flota conjunta usa tus bonos (herencia de boosts). Bajas y botín se reparten según lo que aporte cada uno."), 12, UI.TEXT_MUTED), 270))
	return card


func _total(exclude: String = "") -> int:
	var t: int = 0
	for k: String in _sel:
		if k != exclude:
			t += int(_sel[k])
	return t


func _on_slider(key: String, val: int) -> void:
	if _updating:
		return
	var allowed: int = maxi(0, _capacity() - _total(key))
	var v: int = mini(val, allowed)
	_sel[key] = v
	if v != val:
		_updating = true
		(_sliders[key] as HSlider).value = v
		_updating = false
	_refresh()


func _apply_preset(kind: String) -> void:
	var home: Dictionary = GameClient.troops_home()
	var cap: int = _capacity()
	var target: Dictionary = {}
	match kind:
		"clear":
			pass
		"max":
			var left: int = cap
			for k: String in _order_by_power(home.keys()):
				var q: int = mini(int(home[k]), left)
				target[k] = q
				left -= q
		"balanced":
			var per: int = int(cap / maxf(1.0, float(home.size())))
			var left2: int = cap
			for k: String in home:
				var q2: int = mini(mini(int(home[k]), per), left2)
				target[k] = q2
				left2 -= q2
		_:
			target = _recommended(home, cap)
	_updating = true
	_sel.clear()
	for k: String in _sliders:
		var q3: int = int(target.get(k, 0))
		_sel[k] = q3
		(_sliders[k] as HSlider).value = q3
	_updating = false
	_refresh()


func _order_by_power(keys: Array) -> Array:
	var out: Array = keys.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool: return Catalog.troop_stat(a, "attack") > Catalog.troop_stat(b, "attack"))
	return out


func _recommended(home: Dictionary, cap: int) -> Dictionary:
	var out: Dictionary = {}
	var left: int = cap
	match mission:
		"gather":
			var need_load: int = int(entity.get("remaining", 500))
			var bonus: float = float(GameClient.me.get("mods", {}).get("load", 0.0))
			var keys: Array = home.keys()
			keys.sort_custom(func(a: String, b: String) -> bool: return Catalog.troop_stat(a, "load") > Catalog.troop_stat(b, "load"))
			for k: String in keys:
				if need_load <= 0 or left <= 0:
					break
				var per_unit: float = Catalog.troop_stat(k, "load") * (1.0 + bonus)
				var q: int = mini(mini(int(home[k]), left), ceili(need_load / maxf(1.0, per_unit)))
				out[k] = q
				left -= q
				need_load -= int(q * per_unit)
		"hunt":
			var sp: Dictionary = Catalog.species_by_id.get(str(entity.get("species", "")), {})
			var weak: String = str(sp.get("weakness", "fisica"))
			var keys2: Array = home.keys()
			keys2.sort_custom(func(a: String, b: String) -> bool:
				return _hunt_score(a, weak) > _hunt_score(b, weak))
			var need: float = float(entity.get("hp", 1000)) / 2.5
			for k: String in keys2:
				if left <= 0 or need <= 0:
					break
				var dmg: float = _hunt_score(k, weak)
				var q2: int = mini(mini(int(home[k]), left), ceili(need / maxf(1.0, dmg)) + 5)
				out[k] = q2
				left -= q2
				need -= q2 * dmg
		_:
			for k: String in _order_by_power(home.keys()):
				var q3: int = mini(int(home[k]), left)
				out[k] = q3
				left -= q3
	return out


func _hunt_score(key: String, weak: String) -> float:
	var cls: String = str(Catalog.troop_type(Catalog.split_troop_key(key)[0]).get("damage_class", ""))
	return Catalog.troop_stat(key, "attack") * (1.5 if cls == weak else 1.0)


func _refresh() -> void:
	for k: String in _labels:
		(_labels[k] as Label).text = "%d / %d" % [int(_sel.get(k, 0)), int((_sliders[k] as HSlider).max_value)]
	UI.clear(_summary)
	var stacks: Dictionary = {}
	for k: String in _sel:
		if int(_sel[k]) > 0:
			stacks[k] = int(_sel[k])
	var total: int = _total()
	var mods: Dictionary = GameClient.me.get("mods", {})
	var load: int = Resolver.load_of(stacks, float(mods.get("load", 0.0)))
	var speed: float = Resolver.speed_of(stacks) * float(Catalog.cfg("march_speed_tiles_per_sec", 1.6)) * (1.0 + float(mods.get("march_speed", 0.0)))
	var dist: float = GameClient.base_pos().distance_to(GameClient.entity_position(entity))
	var eta: float = maxf(2.5, dist / maxf(0.1, speed))
	_summary.add_child(_line("ui_users", U.t("Tropas"), "%d / %d" % [total, _capacity()], UI.TEXT if total <= _capacity() else UI.RED))
	_summary.add_child(_line("res_power", U.t("Poder de flota"), U.fmt_int(Resolver.power_of(stacks)), UI.GOLD))
	_summary.add_child(_line("ui_cargo", U.t("Carga"), U.fmt_int(load), UI.TEXT))
	_summary.add_child(_line("ui_timer", U.t("Llegada"), U.fmt_time(eta), UI.TEXT))
	var can: bool = total > 0
	match mission:
		"gather":
			var amount: int = mini(load, int(entity.get("remaining", 0)))
			var rate: float = float(Catalog.asteroid_level(int(entity.get("level", 1))).get("rate", 10)) * (1.0 + float(mods.get("gather_speed", 0.0)))
			_summary.add_child(_line(UI.res_icon_name(str(entity.get("element", ""))), U.t("Extraerá"), U.t("%s en %s") % [U.fmt_num(amount), U.fmt_duration_short(amount / maxf(1.0, rate))], UI.GREEN))
		"hunt":
			var cost: int = int(Catalog.xeno_level(int(entity.get("level", 1))).get("energy", 10))
			var ok_e: bool = GameClient.current_energy() >= cost
			_summary.add_child(_line("res_energy", U.t("Energía"), U.t("%d (tienes %d)") % [cost, GameClient.current_energy()], UI.TEXT if ok_e else UI.RED))
			can = can and ok_e
			var sp: Dictionary = Catalog.species_by_id.get(str(entity.get("species", "")), {})
			var dmg: float = 0.0
			for k: String in stacks:
				dmg += _hunt_score(k, str(sp.get("weakness", ""))) * int(stacks[k]) * (1.0 + float(mods.get("attack", 0.0)) + float(mods.get("pve_damage", 0.0)))
			dmg *= int(Catalog.xeno.get("rounds", 3))
			var hp: float = float(entity.get("hp", 1))
			_summary.add_child(_line("ui_hunt", U.t("Daño estimado"), "%s (%d%%)" % [U.fmt_num(dmg), int(minf(100.0, dmg / hp * 100.0))], UI.GREEN if dmg >= hp else UI.GOLD))
		"attack":
			if str(entity.get("kind", "")) == "base":
				var their: int = int(entity.get("power", 0))
				_summary.add_child(_line("ui_attack", U.t("Poder del objetivo"), U.fmt_int(their), UI.RED))
				_summary.add_child(UI.wrap(UI.label(U.t("Consejo: espía primero para ver sus tropas. Los Cañoneros rompen el Escudo Perimetral."), 12, UI.TEXT_MUTED), 270))
	_send_btn.disabled = not can or total > _capacity()


## Tripulantes que embarcan en esta flota (hasta 5). Solo aparecen los libres:
## los que trabajan en una sala o viajan en otra flota no pueden embarcar.
func _crew_card() -> Control:
	var cv: Dictionary = GameClient.me.get("crew", {})
	var max_n: int = int(cv.get("fleet_max", 5))
	var active: Array = cv.get("active", [])
	var card := UI.panel("Card")
	var v := UI.vbox(6)
	card.add_child(v)
	_crew_label = UI.label("", 15, UI.CYAN, "bold")
	v.add_child(_crew_label)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	v.add_child(flow)
	var free: Array = []
	var busy: int = 0
	for o: Dictionary in cv.get("owned", []):
		if active.has(o["id"]) or not str(o.get("fleet", "")).is_empty():
			busy += 1
		else:
			free.append(o)
	free.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("bonus", 0.0)) > float(b.get("bonus", 0.0)))
	for o: Dictionary in free:
		var cid: String = str(o["id"])
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.icon = UI.portrait_tex(cid)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(58, 58)
		b.theme_type_variation = "TabButton"
		b.name = "Crew_" + cid
		var stat: String = str(Catalog.crew.get("stat_labels", {}).get(str(_crew_def(cid).get("stat", "")), ""))
		b.tooltip_text = "%s · Nv %d · %s\n+%.1f%% %s" % [U.t(str(Catalog.portraits.get(cid, {}).get("name", cid))), int(o.get("level", 1)), U.t(str(o.get("rank", ""))), float(o.get("bonus", 0.0)) * float(cv.get("fleet_mult", 1.5)) * 100.0, U.t(stat)]
		b.toggled.connect(func(on: bool) -> void:
			if on and _crew_sel.size() >= max_n:
				b.set_pressed_no_signal(false)
				game.toast(U.t("Máximo %d tripulantes por flota") % max_n, "warning")
				return
			if on:
				_crew_sel.append(cid)
			else:
				_crew_sel.erase(cid)
			b.theme_type_variation = "PrimaryButton" if on else "TabButton"
			_update_crew_label(max_n))
		flow.add_child(b)
	if free.is_empty():
		v.add_child(UI.wrap(UI.label(U.t("No hay tripulantes libres. Los que trabajan en una sala o viajan en otra flota no pueden embarcar."), 13, UI.TEXT_MUTED)))
	elif busy > 0:
		v.add_child(UI.label(U.t("%d ocupados en salas u otras flotas") % busy, 12, UI.TEXT_MUTED))
	_update_crew_label(max_n)
	return card


func _crew_def(cid: String) -> Dictionary:
	for c: Dictionary in Catalog.crew.get("crew", []):
		if str(c["id"]) == cid:
			return c
	return {}


func _update_crew_label(max_n: int) -> void:
	if _crew_label != null:
		_crew_label.text = U.t("Tripulantes a bordo (%d/%d) · su pasiva cuenta ×1,5 en esta flota") % [_crew_sel.size(), max_n]


func _line(icon_name: String, label_text: String, value: String, color: Color) -> HBoxContainer:
	var h := UI.hbox(8)
	h.add_child(UI.icon(icon_name, 20, UI.TEXT_DIM if icon_name.begins_with("ui_") else Color.WHITE))
	h.add_child(UI.label(label_text, 14, UI.TEXT_DIM))
	h.add_child(UI.spacer())
	h.add_child(UI.label(value, 15, color, "bold"))
	return h


func _send() -> void:
	var stacks: Dictionary = {}
	for k: String in _sel:
		if int(_sel[k]) > 0:
			stacks[k] = int(_sel[k])
	_send_btn.disabled = true
	if mission.begins_with("rally"):
		var action: String = "rally_start" if mission == "rally" else "rally_join"
		var params: Dictionary = {"troops": stacks, "wait": _rally_wait}
		if mission == "rally":
			params["target_id"] = entity["id"]
		else:
			params["rally_id"] = entity["id"]
		GameClient.intent(action, params, func(ok: bool, payload: Dictionary) -> void:
			if ok:
				UI.Sfx.play("alert")
				game.toast(U.t("Asedio abierto: tus aliados tienen %d s para sumarse") % _rally_wait if mission == "rally" else U.t("Te sumaste al Asedio"), "success")
				game.hud.hide_popup()
				close_window()
			else:
				game.toast(str(payload.get("message", U.t("No se pudo enviar"))), "error")
				_send_btn.disabled = false)
		return
	GameClient.intent("march", {"mission": mission, "target_id": entity["id"], "troops": stacks, "crew": _crew_sel, "formation": _formation}, func(ok: bool, payload: Dictionary) -> void:
		if ok:
			UI.Sfx.play("launch")
			game.toast(U.t("Flota en ruta: %s") % {"gather": U.t("minería"), "hunt": "caza", "attack": "ataque"}.get(mission, ""), "success")
			game.hud.hide_popup()
			game.map_view.clear_selection()
			close_window()
		else:
			game.toast(str(payload.get("message", U.t("No se pudo enviar"))), "error")
			_send_btn.disabled = false)
