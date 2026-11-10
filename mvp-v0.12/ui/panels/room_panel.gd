extends "res://ui/panels/window.gd"
## Ventana de sala: mejora con temporizador + la función propia de cada sala
## (entrenar en Hangar, investigar, curar, reanimar, recolectar...).

var room_id: String = ""
var _sel_troop: String = "infantry_1"
var _qty: int = 20
var _sig: String = ""
var _timers: Array = []   # [label, bar, queue]
var _qty_label: Label
var _cost_box: Control
var _time_label: Label
var _train_btn: Button


func _init() -> void:
	desired_size = Vector2(1080, 640)
	live_refresh = 0.25


func window_title() -> String:
	room_id = str(args.get("room", "bridge"))
	return U.t("%s  ·  Nv %d") % [Catalog.room(room_id).get("name", room_id), GameClient.room_level(room_id)]


func window_icon() -> String:
	return "ui_build"


func _signature() -> String:
	var me: Dictionary = GameClient.me
	return "%d|%s|%s|%s|%s|%s|%s|%s" % [GameClient.room_level(room_id), str(GameClient.queue("build").get("end", "")), str(GameClient.queue(_room_queue()).get("end", "")), str(me.get("tech", {})), str(me.get("wounded", {})), str(me.get("cryo", {})), str(me.get("troops", {}).size()), str(me.get("items", {}))]


func on_player_updated() -> void:
	var s: String = _signature()
	if s != _sig:
		title_label.text = window_title()
		rebuild()


func _room_queue() -> String:
	return {"hangar": "train", "lab": "research", "medbay": "heal", "cryo": "revive"}.get(room_id, "build")


func build() -> void:
	room_id = str(args.get("room", "bridge"))
	_sig = _signature()
	_timers.clear()
	var r: Dictionary = Catalog.room(room_id)
	var row := UI.hbox(18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)

	# Columna izquierda: arte, descripción y efectos.
	var left := UI.vbox(10)
	left.custom_minimum_size.x = 300
	row.add_child(left)
	var art := UI.image(UI.room_tex(room_id), Vector2(220, 220))
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(art)
	left.add_child(UI.wrap(UI.label(str(r.get("desc", "")), 15, UI.TEXT_DIM), 300))
	var lvl: int = GameClient.room_level(room_id)
	var eff_box := UI.vbox(4)
	left.add_child(eff_box)
	for line: String in _effect_lines(lvl):
		eff_box.add_child(UI.wrap(UI.label(line, 14, UI.TEXT), 300))

	# Columna derecha.
	var right := UI.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := scroll_body(right)
	row.add_child(sc)
	right.add_child(_upgrade_section(lvl))
	var special: Control = _special_section()
	if special != null:
		right.add_child(special)


func _effect_lines(lvl: int) -> Array:
	var out: Array = []
	var r: Dictionary = Catalog.room(room_id)
	var next: int = mini(lvl + 1, Catalog.room_max_level())
	for eff: String in r.get("effects", {}):
		var e: Dictionary = r["effects"][eff]
		var cur: float = Catalog.room_effect(room_id, eff, lvl)
		var nxt: float = Catalog.room_effect(room_id, eff, next)
		var pct: bool = bool(e.get("pct", false))
		var fmt := func(x: float) -> String: return ("+%d%%" % int(round(x * 100))) if pct else U.fmt_int(int(x))
		if lvl == 0:
			out.append("• %s: %s" % [e.get("label", eff), fmt.call(nxt)])
		else:
			out.append("• %s: %s  »  %s" % [e.get("label", eff), fmt.call(cur), fmt.call(nxt)])
	if r.has("produces"):
		var a: Dictionary = Catalog.room_production(room_id, lvl)
		var b: Dictionary = Catalog.room_production(room_id, next)
		for k: String in a:
			out.append(U.t("• %s: %s/min  »  %s/min") % [Catalog.res_name(k), U.fmt_num(float(a[k])), U.fmt_num(float(b[k]))])
	if room_id == "bridge":
		out.append(U.t("• Límite de nivel para las demás salas: Nv %d") % lvl)
	return out


func _upgrade_section(lvl: int) -> Control:
	var card := UI.panel("CardHi")
	var v := UI.vbox(8)
	card.add_child(v)
	var build_job: Dictionary = GameClient.queue("build")
	if not build_job.is_empty() and str(build_job.get("room", "")) == room_id:
		v.add_child(UI.label(U.t("Mejorando a Nv %d") % int(build_job["target"]), 18, UI.CYAN, "bold"))
		v.add_child(_queue_controls("build"))
		return card
	if lvl >= Catalog.room_max_level():
		v.add_child(UI.label(U.t("Nivel máximo de la demo alcanzado"), 17, UI.GREEN, "bold"))
		return card
	if lvl == 0:
		return _unlock_section(card, v, build_job)
	var target: int = lvl + 1
	v.add_child(UI.label(U.t("Mejorar a Nv %d") % target, 18, UI.TEXT, "bold"))
	var cost: Dictionary = Catalog.room_cost(room_id, target)
	v.add_child(UI.cost_row(cost))
	var h := UI.hbox(14)
	h.add_child(UI.icon("ui_timer", 20, UI.TEXT_DIM))
	h.add_child(UI.label(U.fmt_duration_short(Catalog.room_time(room_id, target)), 16, UI.TEXT_DIM, "semibold"))
	v.add_child(h)
	var blocked: String = ""
	if room_id != "bridge" and target > GameClient.room_level("bridge"):
		blocked = U.t("Requiere Puente de Mando Nv %d") % target
	elif not build_job.is_empty():
		blocked = U.t("Cola de construcción ocupada: %s") % str(build_job.get("label", ""))
	if not blocked.is_empty():
		v.add_child(UI.label(blocked, 15, UI.GOLD, "semibold"))
	var b := UI.button(U.t("Mejorar"), "PrimaryButton", "ui_build", Vector2(220, 54))
	b.disabled = not blocked.is_empty() or not GameClient.can_afford(cost)
	b.pressed.connect(func() -> void:
		send("upgrade_room", {"room": room_id}, func(_p: Dictionary) -> void: UI.Sfx.play("upgrade"); game.toast(U.t("Mejora iniciada"), "success")))
	v.add_child(b)
	return card


## Fase 2 de la nave: la sala aún no existe y se compra/construye.
func _unlock_section(card: PanelContainer, v: VBoxContainer, build_job: Dictionary) -> Control:
	var r: Dictionary = Catalog.room(room_id)
	var unlock: Dictionary = r.get("unlock", {})
	card.theme_type_variation = "CardGold"
	var hh := UI.hbox(8)
	hh.add_child(UI.icon("ui_build", 26, UI.GOLD))
	hh.add_child(UI.title(U.t("Construir sala · %s") % str(r.get("phase", "Fase 2")), 20, UI.GOLD))
	v.add_child(hh)
	v.add_child(UI.wrap(UI.label(U.t("Tu Astronave crece en dos etapas: primero mejoras las salas básicas y luego compras las de Fase 2, que desbloquean nuevas mecánicas."), 14, UI.TEXT_DIM)))
	var cost: Dictionary = unlock.get("cost", {})
	v.add_child(UI.cost_row(cost))
	var value_usd: float = Catalog.bundle_value_mo(cost) / float(Catalog.shop.get("usd_to_mo", 100))
	var h := UI.hbox(14)
	h.add_child(UI.icon("ui_timer", 20, UI.TEXT_DIM))
	h.add_child(UI.label(U.fmt_duration_short(Catalog.room_time(room_id, 1)), 16, UI.TEXT_DIM, "semibold"))
	h.add_child(UI.label(U.t("Precio equivalente: US$ %.2f") % value_usd, 15, UI.GREEN, "semibold"))
	v.add_child(h)
	var need: int = int(unlock.get("bridge", 1))
	var blocked: String = ""
	if GameClient.room_level("bridge") < need:
		blocked = U.t("Requiere Puente de Mando Nv %d") % need
	elif not build_job.is_empty():
		blocked = U.t("Cola de construcción ocupada: %s") % str(build_job.get("label", ""))
	if not blocked.is_empty():
		v.add_child(UI.label(blocked, 15, UI.GOLD, "semibold"))
	var b := UI.button(U.t("Construir"), "GoldButton", "ui_build", Vector2(240, 56))
	b.disabled = not blocked.is_empty() or not GameClient.can_afford(cost)
	b.pressed.connect(func() -> void:
		send("upgrade_room", {"room": room_id}, func(_p: Dictionary) -> void: UI.Sfx.play("upgrade"); game.toast(U.t("Construcción iniciada"), "success")))
	v.add_child(b)
	return card


## Barra de progreso de una cola con acelerar / gratis / ayuda / acelerador.
func _queue_controls(q: String) -> Control:
	var v := UI.vbox(8)
	var job: Dictionary = GameClient.queue(q)
	var lbl := UI.label("", 16, UI.TEXT, "semibold")
	var bar := UI.progress(0, 100, UI.CYAN, 14)
	v.add_child(UI.label(str(job.get("label", "")), 15, UI.TEXT_DIM))
	v.add_child(bar)
	v.add_child(lbl)
	_timers.append([lbl, bar, q])
	var h := UI.hbox(8)
	v.add_child(h)
	var rem_ms: int = int(job.get("end", 0)) - GameClient.server_now()
	var free_s: int = int(Catalog.rooms_data.get("free_speedup_sec", 15))
	if rem_ms <= free_s * 1000:
		var fb := UI.button(U.t("Gratis"), "GreenButton", "ui_speedup", Vector2(140, 48))
		fb.pressed.connect(func() -> void: send("speedup", {"queue": q, "method": "free"}))
		h.add_child(fb)
	else:
		var cost: int = maxi(1, ceili(rem_ms / 6000.0))
		var sb := UI.button(U.t("Acelerar  %d MO") % cost, "GoldButton", "ui_speedup", Vector2(190, 48))
		sb.disabled = GameClient.res("dark_matter") < cost
		sb.pressed.connect(func() -> void:
			game.confirm(U.t("¿Terminar ahora por %d Materia Oscura?") % cost, func() -> void: send("speedup", {"queue": q, "method": "dark_matter"})))
		h.add_child(sb)
	var item_id: String = _best_speedup_item(rem_ms)
	if not item_id.is_empty():
		var ib := UI.button(U.t("Usar %s (×%d)") % [Catalog.item(item_id)["name"], GameClient.res(item_id)], "GhostButton", "ui_speedup", Vector2(0, 48))
		ib.pressed.connect(func() -> void: send("use_item", {"item": item_id, "queue": q}))
		h.add_child(ib)
	if not bool(job.get("help_requested", false)) and q in ["build", "research", "heal"]:
		var hb := UI.button(U.t("Ayuda"), "GreenButton", "ui_help", Vector2(120, 48))
		hb.pressed.connect(func() -> void: send("help", {"queue": q}, func(_p: Dictionary) -> void: game.toast(U.t("Ayuda solicitada a la Alianza"), "help")))
		h.add_child(hb)
	elif bool(job.get("help_requested", false)):
		h.add_child(UI.label(U.t("Ayudas: %d/10") % int(job.get("helps", 0)), 14, UI.GREEN, "semibold"))
	return v


func _best_speedup_item(rem_ms: int) -> String:
	var best: String = ""
	for id: String in ["speedup_1m", "speedup_5m", "speedup_1h"]:
		if GameClient.res(id) <= 0:
			continue
		if best.is_empty():
			best = id
		var secs: int = int(Catalog.item(id).get("seconds", 60))
		if secs * 1000 <= rem_ms * 1.3:
			best = id
	return best


func tick() -> void:
	var now: int = GameClient.server_now()
	for t: Array in _timers:
		var job: Dictionary = GameClient.queue(t[2])
		if job.is_empty():
			continue
		var rem: float = float(int(job["end"]) - now) / 1000.0
		(t[0] as Label).text = U.t("Restante: ") + U.fmt_time(rem)
		(t[1] as ProgressBar).value = clampf(1.0 - rem * 1000.0 / maxf(1.0, float(job.get("total", 1))), 0.0, 1.0) * 100.0


# ---------------------------------------------------------------- secciones propias

func _special_section() -> Control:
	match room_id:
		"hangar":
			return _hangar()
		"lab":
			return _lab()
		"medbay":
			return _medbay()
		"cryo":
			return _cryo()
		"factory", "platform", "bank":
			return _production()
		"vault":
			return _vault()
		"sensors":
			return _sensors()
		"cantina", "crew":
			return _crew_hub()
		"workshop":
			return _workshop()
		"armory":
			return _armory()
	return null


func _armory() -> Control:
	if GameClient.room_level("armory") <= 0:
		return null
	var s: Array = _section(U.t("Equipamiento"), "ui_attack")
	var v: VBoxContainer = s[1]
	var g: Dictionary = GameClient.me.get("gear", {})
	v.add_child(UI.label(U.t("Equipos forjados: %d de %d · materiales: %d tipos") % [(g.get("owned", {}) as Dictionary).size(), Catalog.equipment_by_id.size(), (g.get("materials", {}) as Dictionary).size()], 16, UI.TEXT, "semibold"))
	var b := UI.button(U.t("Abrir Armería"), "PrimaryButton", "ui_attack", Vector2(260, 54))
	b.pressed.connect(func() -> void:
		close_window()
		game.open_panel("armory"))
	v.add_child(b)
	return s[0]


func _crew_hub() -> Control:
	if GameClient.room_level(room_id) <= 0:
		return null
	var s: Array = _section(U.t("Tripulación"), "ui_crew")
	var v: VBoxContainer = s[1]
	var cv: Dictionary = GameClient.me.get("crew", {})
	v.add_child(UI.label(U.t("Tripulantes: %d  ·  Activos %d/%d") % [(cv.get("owned", []) as Array).size(), (cv.get("active", []) as Array).size(), int(cv.get("slots", 2))], 16, UI.TEXT, "semibold"))
	if room_id == "cantina":
		var od: Dictionary = cv.get("odds", {})
		var f := UI.flow(14, 4)
		for rr: Dictionary in Catalog.crew.get("rarities", []):
			f.add_child(UI.label("%s %.1f%%" % [U.t(str(rr["name"])), float(od.get(rr["id"], 0.0))], 15, Color(str(rr["color"])), "bold"))
		v.add_child(f)
	var b := UI.button(U.t("Abrir Tripulación"), "PrimaryButton", "ui_crew", Vector2(260, 54))
	b.pressed.connect(func() -> void:
		close_window()
		game.open_panel("crew", {"tab": "recruit" if room_id == "cantina" else "active"}))
	v.add_child(b)
	return s[0]


var _ex_from: String = "ore"
var _ex_to: String = "kliptium"
var _ex_amt: int = 100


func _workshop() -> Control:
	if GameClient.room_level("workshop") <= 0:
		return null
	var s: Array = _section(U.t("Canje de elementos"), "ui_cargo")
	var v: VBoxContainer = s[1]
	var rate: int = maxi(2, int(Catalog.room_effect("workshop", "exchange_rate", GameClient.room_level("workshop"))))
	v.add_child(UI.label(U.t("Tasa actual: %d a 1") % rate, 16, UI.GOLD, "bold"))
	for side: Array in [["from", U.t("Entregas")], ["to", U.t("Recibes")]]:
		var row := UI.flow(6, 6)
		var lab := UI.label(side[1], 14, UI.TEXT_DIM, "semibold")
		lab.custom_minimum_size.x = 90
		row.add_child(lab)
		for el: String in Catalog.element_ids:
			var sel: bool = (_ex_from if side[0] == "from" else _ex_to) == el
			var b := UI.button("", "PrimaryButton" if sel else "TabButton", UI.res_icon_name(el), Vector2(52, 44))
			b.tooltip_text = Catalog.res_name(el)
			var key: String = side[0]
			b.pressed.connect(func() -> void:
				if key == "from":
					_ex_from = el
				else:
					_ex_to = el
				rebuild())
			row.add_child(b)
		v.add_child(row)
	var ah := UI.hbox(8)
	for amt: int in [100, 500, 1000, 5000]:
		var ab := UI.button("+%s" % U.fmt_num(amt), "PrimaryButton" if _ex_amt == amt else "TabButton", "", Vector2(90, 42))
		var a2: int = amt
		ab.pressed.connect(func() -> void:
			_ex_amt = a2
			rebuild())
		ah.add_child(ab)
	v.add_child(ah)
	var res := UI.hbox(10)
	res.add_child(UI.amount_chip(_ex_from, _ex_amt * rate, 18, UI.RED if GameClient.res(_ex_from) < _ex_amt * rate else UI.TEXT))
	res.add_child(UI.label("»", 22, UI.TEXT_DIM, "bold"))
	res.add_child(UI.amount_chip(_ex_to, _ex_amt, 18, UI.GREEN))
	v.add_child(res)
	var go := UI.button(U.t("Canjear"), "GoldButton", "ui_check", Vector2(200, 52))
	go.disabled = _ex_from == _ex_to or GameClient.res(_ex_from) < _ex_amt * rate
	go.pressed.connect(func() -> void: send("exchange", {"from": _ex_from, "to": _ex_to, "amount": _ex_amt}, func(_p: Dictionary) -> void:
		game.toast(U.t("Canje realizado: +%s %s") % [U.fmt_int(_ex_amt), Catalog.res_name(_ex_to)], "success")))
	v.add_child(go)
	return s[0]


func _section(title: String, icon_name: String) -> Array:
	var card := UI.panel("Card")
	var v := UI.vbox(10)
	card.add_child(v)
	var h := UI.hbox(8)
	h.add_child(UI.icon(icon_name, 24, UI.CYAN) if icon_name.begins_with("ui_") else UI.icon(icon_name, 26))
	h.add_child(UI.label(title, 18, UI.CYAN, "bold"))
	v.add_child(h)
	return [card, v]


func _hangar() -> Control:
	var s: Array = _section(U.t("Entrenamiento de fuerzas"), "troop_infantry")
	var v: VBoxContainer = s[1]
	var job: Dictionary = GameClient.queue("train")
	if not job.is_empty():
		v.add_child(_queue_controls("train"))
		v.add_child(UI.separator())
	v.add_child(UI.wrap(UI.label(U.t("Triángulo: Infantería > Drones > Pilotos > Infantería (+30%). Escudos absorben el primer daño. Cañoneros destruyen Escudos y el Escudo Perimetral."), 14, UI.TEXT_DIM)))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var tier2: bool = GameClient.tech_level("tier2_protocol") > 0
	for type_id: String in Catalog.troop_order:
		for tier: int in [1, 2]:
			var key: String = Catalog.troop_key(type_id, tier)
			var locked: bool = tier == 2 and not tier2
			var b := Button.new()
			b.theme_type_variation = "PrimaryButton" if key == _sel_troop else "TabButton"
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(118, 96)
			b.disabled = locked
			var bv := UI.vbox(2, BoxContainer.ALIGNMENT_CENTER)
			UI.full_rect(bv)
			var ic := UI.icon(UI.troop_icon_name(key), 40)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			bv.add_child(ic)
			var nl := UI.label(Catalog.troop_name(key), 13, UI.TEXT, "bold")
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bv.add_child(nl)
			var ol := UI.label((U.t("Tienes %s") % U.fmt_int(int(GameClient.troops_home().get(key, 0)))) if not locked else U.t("Requiere investigación"), 11, UI.TEXT_DIM)
			ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bv.add_child(ol)
			b.add_child(bv)
			b.pressed.connect(func() -> void:
				_sel_troop = key
				rebuild())
			grid.add_child(b)
	var tier_data: Dictionary = Catalog.troop_tier(_sel_troop)
	var st: Dictionary = tier_data.get("stats", {})
	var tinfo: Dictionary = Catalog.troop_type(Catalog.split_troop_key(_sel_troop)[0])
	var info := UI.hbox(16)
	info.add_child(UI.icon(UI.troop_icon_name(_sel_troop), 56))
	var iv := UI.vbox(2)
	iv.add_child(UI.label(Catalog.troop_name(_sel_troop), 18, UI.TEXT, "bold"))
	iv.add_child(UI.wrap(UI.label(str(tinfo.get("desc", "")), 13, UI.TEXT_DIM), 420))
	iv.add_child(UI.label(U.t("ATQ %d · DEF %d · VIDA %d · CARGA %d · VEL %.1f · Poder %d") % [int(st.get("attack", 0)), int(st.get("defense", 0)), int(st.get("hp", 0)), int(st.get("load", 0)), float(st.get("speed", 1)), int(tier_data.get("power", 0))], 13, UI.TEXT, "semibold"))
	info.add_child(iv)
	v.add_child(info)
	var batch: int = int(GameClient.me.get("caps", {}).get("train_batch", 60))
	_qty = clampi(_qty, 1, batch)
	var qrow := UI.hbox(10)
	var minus := UI.icon_button("ui_minus", 44, "Button")
	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = batch
	slider.step = 1
	slider.value = _qty
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(200, 34)
	var plus := UI.icon_button("ui_plus", 44, "Button")
	_qty_label = UI.label("", 18, UI.TEXT, "bold")
	_qty_label.custom_minimum_size.x = 64
	var maxb := UI.button(U.t("Máx"), "GhostButton", "", Vector2(70, 44))
	qrow.add_child(minus)
	qrow.add_child(slider)
	qrow.add_child(plus)
	qrow.add_child(_qty_label)
	qrow.add_child(maxb)
	v.add_child(qrow)
	_cost_box = UI.vbox(4)
	v.add_child(_cost_box)
	_time_label = UI.label("", 15, UI.TEXT_DIM, "semibold")
	v.add_child(_time_label)
	_train_btn = UI.button(U.t("Entrenar"), "PrimaryButton", "troop_infantry", Vector2(220, 54))
	v.add_child(_train_btn)
	slider.value_changed.connect(func(val: float) -> void:
		_qty = int(val)
		_update_train())
	minus.pressed.connect(func() -> void: slider.value = maxf(1, slider.value - 10))
	plus.pressed.connect(func() -> void: slider.value = minf(batch, slider.value + 10))
	maxb.pressed.connect(func() -> void: slider.value = _max_affordable(batch))
	_train_btn.pressed.connect(func() -> void:
		send("train", {"troop": _sel_troop, "qty": _qty}, func(_p: Dictionary) -> void: UI.Sfx.play("upgrade"); game.toast(U.t("Entrenando %d × %s") % [_qty, Catalog.troop_name(_sel_troop)], "success")))
	_update_train()
	return s[0]


func _max_affordable(batch: int) -> int:
	var recipe: Dictionary = Catalog.troop_tier(_sel_troop).get("recipe", {})
	var m: int = batch
	for k: String in recipe:
		m = mini(m, int(GameClient.res(k) / maxi(1, int(recipe[k]))))
	return maxi(1, m)


func _update_train() -> void:
	if _qty_label == null:
		return
	_qty_label.text = "×%d" % _qty
	UI.clear(_cost_box)
	var recipe: Dictionary = Catalog.troop_tier(_sel_troop).get("recipe", {})
	_cost_box.add_child(UI.cost_row(recipe, _qty))
	var speed: float = 1.0 + Catalog.room_effect("hangar", "train_speed", GameClient.room_level("hangar"))
	_time_label.text = U.t("Tiempo: %s") % U.fmt_duration_short(float(Catalog.troop_tier(_sel_troop).get("train_sec", 1)) * _qty / speed)
	_train_btn.disabled = not GameClient.queue("train").is_empty() or not GameClient.can_afford(recipe, _qty)
	_train_btn.icon = UI.icon_tex(UI.troop_icon_name(_sel_troop))


func _lab() -> Control:
	var s: Array = _section(U.t("Investigación"), "ui_lab")
	var v: VBoxContainer = s[1]
	if not GameClient.queue("research").is_empty():
		v.add_child(_queue_controls("research"))
		v.add_child(UI.separator())
	var lab_lvl: int = GameClient.room_level("lab")
	for t: Dictionary in Catalog.research.get("techs", []):
		var tid: String = t["id"]
		var cur: int = GameClient.tech_level(tid)
		var mx: int = int(t.get("max", 5))
		var card := UI.panel("Card")
		var h := UI.hbox(12)
		card.add_child(h)
		h.add_child(UI.icon("ui_" + str(t.get("icon", "star")) if ResourceLoader.exists("res://assets/icons/ui_%s.svg" % t.get("icon", "")) else "ui_star", 40, UI.PURPLE))
		var tv := UI.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UI.label("%s  ·  %d/%d" % [t["name"], cur, mx], 16, UI.TEXT, "bold"))
		var eff_now: String = ("+%d%%" % int(round(float(t["per_level"]) * cur * 100))) if bool(t.get("pct", true)) else (U.t("Sí") if cur > 0 else U.t("No"))
		tv.add_child(UI.label(U.t("%s · %s · Rama: %s") % [t.get("label", ""), eff_now, t.get("branch", "")], 13, UI.TEXT_DIM))
		if cur < mx:
			var target: int = cur + 1
			var cost: Dictionary = Catalog.tech_cost(tid, target)
			tv.add_child(UI.cost_row(cost, 1.0, 14))
			var req: int = maxi(target, int(t.get("requires_lab", 0)))
			var b := UI.button(U.t("Investigar"), "PrimaryButton", "ui_lab", Vector2(150, 46))
			var reason: String = ""
			if lab_lvl < req:
				reason = U.t("Laboratorio Nv %d") % req
			elif not GameClient.queue("research").is_empty():
				reason = U.t("Ocupado")
			b.disabled = not reason.is_empty() or not GameClient.can_afford(cost)
			var right := UI.vbox(2)
			right.add_child(b)
			right.add_child(UI.label(reason if not reason.is_empty() else U.fmt_duration_short(Catalog.tech_time(tid, target) / (1.0 + Catalog.room_effect("lab", "research_speed", lab_lvl))), 12, UI.GOLD if not reason.is_empty() else UI.TEXT_DIM))
			b.pressed.connect(func() -> void: send("research", {"tech": tid}, func(_p: Dictionary) -> void: UI.Sfx.play("upgrade"); game.toast(U.t("Investigación iniciada: %s") % t["name"], "success")))
			h.add_child(tv)
			h.add_child(right)
		else:
			h.add_child(tv)
			h.add_child(UI.icon("ui_check", 30, UI.GREEN))
		v.add_child(card)
	return s[0]


func _medbay() -> Control:
	var s: Array = _section(U.t("Heridos en la Bahía Médica"), "ui_medic")
	var v: VBoxContainer = s[1]
	if not GameClient.queue("heal").is_empty():
		v.add_child(_queue_controls("heal"))
	var w: Dictionary = GameClient.me.get("wounded", {})
	if w.is_empty():
		v.add_child(UI.label(U.t("No hay heridos. Los defensores heridos se recuperan aquí al 100%."), 15, UI.TEXT_DIM))
		return s[0]
	var f := UI.flow(16, 8)
	for k: String in w:
		f.add_child(UI.troop_chip(k, int(w[k])))
	v.add_child(f)
	var cost: Dictionary = GameClient.me.get("heal_cost", {})
	v.add_child(UI.label(U.t("Costo de curación:"), 14, UI.TEXT_DIM))
	v.add_child(UI.cost_row(cost))
	var b := UI.button(U.t("Curar a todos"), "GreenButton", "ui_medic", Vector2(220, 54))
	b.disabled = not GameClient.queue("heal").is_empty() or not GameClient.can_afford(cost)
	b.pressed.connect(func() -> void: send("heal", {}, func(_p: Dictionary) -> void: game.toast(U.t("Curación iniciada"), "success")))
	v.add_child(b)
	return s[0]


func _cryo() -> Control:
	var s: Array = _section(U.t("Fuerzas en criostasis"), "ui_cryo")
	var v: VBoxContainer = s[1]
	v.add_child(UI.wrap(UI.label(U.t("Innovación de Galactum: el 80% de las bajas mortales queda en criostasis recuperable (el 20% se pierde)."), 14, UI.TEXT_DIM)))
	if not GameClient.queue("revive").is_empty():
		v.add_child(_queue_controls("revive"))
	var c: Dictionary = GameClient.me.get("cryo", {})
	if c.is_empty():
		v.add_child(UI.label(U.t("No hay fuerzas en criostasis."), 15, UI.TEXT_DIM))
		return s[0]
	var f := UI.flow(16, 8)
	for k: String in c:
		f.add_child(UI.troop_chip(k, int(c[k])))
	v.add_child(f)
	var cost: Dictionary = GameClient.me.get("revive_cost", {})
	v.add_child(UI.cost_row(cost))
	var b := UI.button(U.t("Reanimar"), "PrimaryButton", "ui_cryo", Vector2(220, 54))
	b.disabled = not GameClient.queue("revive").is_empty() or not GameClient.can_afford(cost)
	b.pressed.connect(func() -> void: send("revive", {}, func(_p: Dictionary) -> void: game.toast(U.t("Reanimación iniciada"), "success")))
	v.add_child(b)
	return s[0]


func _production() -> Control:
	var s: Array = _section(U.t("Producción"), "ui_cargo")
	var v: VBoxContainer = s[1]
	var pend: Dictionary = GameClient.pending_amount(room_id)
	var lvl: int = GameClient.room_level(room_id)
	var rates: Dictionary = Catalog.room_production(room_id, lvl)
	var cap_min: float = float(Catalog.room(room_id).get("storage_minutes", 20))
	for k: String in rates:
		var h := UI.hbox(10)
		h.add_child(UI.icon(UI.res_icon_name(k), 30))
		var cv := UI.vbox(2)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(UI.label(U.t("%s  ·  +%s/min") % [Catalog.res_name(k), U.fmt_num(float(rates[k]))], 15, UI.TEXT, "semibold"))
		cv.add_child(UI.progress(float(pend.get(k, 0.0)), float(rates[k]) * cap_min, Catalog.res_color(k), 8))
		h.add_child(cv)
		h.add_child(UI.label("%s / %s" % [U.fmt_num(float(pend.get(k, 0))), U.fmt_num(float(rates[k]) * cap_min)], 14, UI.TEXT_DIM))
		v.add_child(h)
	var b := UI.button(U.t("Recolectar"), "GreenButton", "ui_cargo", Vector2(200, 52))
	b.pressed.connect(func() -> void:
		send("collect", {"room": room_id}, func(p: Dictionary) -> void:
			var parts: Array = []
			for k2: String in p.get("gained", {}):
				parts.append("+%s %s" % [U.fmt_num(int(p["gained"][k2])), Catalog.res_name(k2)])
			game.toast(U.t("Recolectado: ") + ", ".join(parts), "success")
			rebuild()))
	v.add_child(b)
	v.add_child(UI.label(U.t("La producción se acumula hasta %d minutos. Lo producido en la nave no se puede saquear mientras no lo recolectes.") % int(cap_min), 13, UI.TEXT_MUTED))
	return s[0]


func _vault() -> Control:
	var s: Array = _section(U.t("Protección contra saqueo"), "ui_shield")
	var v: VBoxContainer = s[1]
	var protect: int = int(GameClient.me.get("caps", {}).get("vault", 0))
	var f := UI.flow(18, 8)
	for e: String in Catalog.element_ids:
		var have: int = GameClient.res(e)
		var h := UI.hbox(4)
		h.add_child(UI.icon(UI.res_icon_name(e), 24))
		h.add_child(UI.label("%s %s" % [U.fmt_num(mini(have, protect)), "protegido" if have <= protect else U.t("(+%s expuesto)") % U.fmt_num(have - protect)], 14, UI.GREEN if have <= protect else UI.GOLD))
		f.add_child(h)
	v.add_child(f)
	return s[0]


func _sensors() -> Control:
	var s: Array = _section(U.t("Alertas de sensores"), "ui_sensors")
	var v: VBoxContainer = s[1]
	var inc: Array = GameClient.me.get("incoming", [])
	if inc.is_empty():
		v.add_child(UI.label(U.t("Sin amenazas detectadas."), 15, UI.GREEN))
	for i: Dictionary in inc:
		v.add_child(UI.label(U.t("%s · %s · %d tropas · llega en %s") % [U.t("ATAQUE") if i["mission"] == "attack" else U.t("SONDA"), str(i["from"]), int(i.get("troops", 0)), U.fmt_time(float(int(i["arrive_ts"]) - GameClient.server_now()) / 1000.0)], 15, UI.RED if i["mission"] == "attack" else UI.GOLD))
	v.add_child(UI.wrap(UI.label(U.t("La precisión del espionaje depende de tu Sala de Sensores frente a la del objetivo: nivel 1 solo Poder, nivel 3 tropas aproximadas, nivel 5 composición exacta."), 13, UI.TEXT_MUTED)))
	return s[0]
