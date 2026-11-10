extends "res://ui/panels/window.gd"
## Informes: combate (con desglose por rondas, versión y seed para replays),
## caza de xenoformas y espionaje.

const TYPE_ICONS: Dictionary = {"attack": "ui_attack", "defense": "ui_defense", "tile_hit": "ui_mine", "tile_defense": "ui_mine", "hunt": "ui_hunt", "scout": "ui_scout"}

var _list: VBoxContainer
var _detail: VBoxContainer
var _selected: String = ""


func _init() -> void:
	desired_size = Vector2(1140, 650)


func window_title() -> String:
	return U.t("Informes")


func window_icon() -> String:
	return "ui_reports"


func extra_header(h: HBoxContainer) -> void:
	var all := UI.button(U.t("Marcar todo leído"), "GhostButton", "ui_check", Vector2(0, 44))
	all.pressed.connect(func() -> void:
		GameClient.intent("read_report", {"report_id": ""})
		for r: Dictionary in GameClient.reports:
			r["read"] = true
		rebuild())
	h.add_child(all)


func build() -> void:
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	_list = UI.vbox(6)
	var ls := scroll_body(_list)
	ls.custom_minimum_size.x = 380
	ls.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(ls)
	_detail = UI.vbox(10)
	var ds := scroll_body(_detail)
	row.add_child(ds)
	var reports: Array = GameClient.reports
	if reports.is_empty():
		_list.add_child(UI.wrap(UI.label(U.t("Aún no hay informes. Mina, caza, espía o ataca para generarlos."), 15, UI.TEXT_DIM), 360))
	for r: Dictionary in reports:
		_list.add_child(_item(r))
	if _selected.is_empty() and not reports.is_empty():
		_selected = str(reports[0]["id"])
	_show_detail()


func _item(r: Dictionary) -> Control:
	var outcome: String = str(r.get("outcome", "info"))
	var col: Color = UI.GREEN if outcome == "victory" else (UI.RED if outcome == "defeat" else (UI.GOLD if outcome == "partial" else UI.CYAN))
	var b := Button.new()
	b.theme_type_variation = "PrimaryButton" if str(r["id"]) == _selected else "TabButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(360, 66)
	var h := UI.hbox(10)
	UI.full_rect(h)
	h.add_theme_constant_override("separation", 10)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(UI.icon(TYPE_ICONS.get(str(r.get("type", "")), "ui_reports"), 30, col))
	h.add_child(m)
	var v := UI.vbox(0, BoxContainer.ALIGNMENT_CENTER)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := UI.label(str(r.get("title", "")), 14, UI.TEXT, "bold")
	t.clip_text = true
	t.custom_minimum_size.x = 260
	v.add_child(t)
	v.add_child(UI.label(_ago(int(r.get("ts", 0))), 12, UI.TEXT_DIM))
	h.add_child(v)
	if not bool(r.get("read", false)):
		var dot := UI.badge("•", UI.RED)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
	b.add_child(h)
	b.pressed.connect(func() -> void:
		_selected = str(r["id"])
		rebuild())
	return b


func _ago(ts: int) -> String:
	var s: float = maxf(0.0, float(GameClient.server_now() - ts) / 1000.0)
	if s < 5:
		return "ahora"
	if s < 60:
		return U.t("hace %ds") % int(s)
	if s < 3600:
		return U.t("hace %d min") % int(s / 60)
	return U.t("hace %d h") % int(s / 3600)


func _show_detail() -> void:
	var r: Dictionary = {}
	for x: Dictionary in GameClient.reports:
		if str(x["id"]) == _selected:
			r = x
	if r.is_empty():
		return
	if not bool(r.get("read", false)):
		r["read"] = true
		GameClient.intent("read_report", {"report_id": r["id"]})
	match str(r.get("type", "")):
		"hunt":
			_hunt_detail(r)
		"scout":
			_scout_detail(r)
		"event":
			_event_detail(r)
		_:
			_battle_detail(r)
	if str(r.get("type", "")) in ["hunt", "attack", "defense", "tile_hit", "tile_defense"] and not (r.get("rounds", []) as Array).is_empty():
		var watch := UI.button(U.t("Ver batalla en 3D"), "GoldButton", "ui_attack", Vector2(280, 54))
		watch.pressed.connect(func() -> void: game.open_panel("battle", {"report": r}))
		_detail.add_child(watch)
		_detail.move_child(watch, 1)


func _banner(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sb(Color(col, 0.18), col, 12, 2, 10))
	var l := UI.title(text, 26, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _battle_detail(r: Dictionary) -> void:
	var outcome: String = str(r.get("outcome", ""))
	_detail.add_child(_banner(U.t("VICTORIA") if outcome == "victory" else U.t("DERROTA"), UI.GREEN if outcome == "victory" else UI.RED))
	_detail.add_child(UI.label(str(r.get("title", "")), 18, UI.TEXT, "bold"))
	var cols := UI.hbox(12)
	_detail.add_child(cols)
	cols.add_child(_side_column(r.get("attacker", {}), U.t("ATACANTE"), false))
	cols.add_child(_side_column(r.get("defender", {}), U.t("DEFENSOR"), true))
	var loot: Dictionary = r.get("loot", {})
	if not loot.is_empty():
		var lc := UI.panel("CardGold")
		var lv := UI.vbox(6)
		lc.add_child(lv)
		lv.add_child(UI.label(U.t("Botín saqueado (limitado por la Bóveda Cuántica y la carga)"), 15, UI.GOLD, "bold"))
		lv.add_child(UI.reward_row(loot, 15))
		_detail.add_child(lc)
	var rounds: Array = r.get("rounds", [])
	if not rounds.is_empty():
		var rc := UI.panel("Card")
		var rv := UI.vbox(6)
		rc.add_child(rv)
		rv.add_child(UI.label(U.t("Desarrollo por rondas"), 15, UI.CYAN, "bold"))
		var mx: float = 1.0
		for rd: Dictionary in rounds:
			mx = maxf(mx, maxf(float(rd.get("attacker_damage", 0)), float(rd.get("defender_damage", 0))))
		for rd2: Dictionary in rounds:
			var h := UI.hbox(8)
			h.add_child(UI.label("R%d" % int(rd2.get("round", 0)), 14, UI.TEXT_DIM, "bold"))
			var a := UI.progress(float(rd2.get("attacker_damage", 0)), mx, UI.CYAN, 10)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			a.fill_mode = ProgressBar.FILL_END_TO_BEGIN
			var d := UI.progress(float(rd2.get("defender_damage", 0)), mx, UI.RED, 10)
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(UI.label(U.fmt_num(float(rd2.get("attacker_damage", 0))), 12, UI.CYAN))
			h.add_child(a)
			h.add_child(d)
			h.add_child(UI.label(U.fmt_num(float(rd2.get("defender_damage", 0))), 12, UI.RED))
			var extra: String = ""
			if int(rd2.get("perimeter_left", 0)) > 0:
				extra = U.t(" · Escudo %s") % U.fmt_num(int(rd2["perimeter_left"]))
			h.add_child(UI.label(U.t("vivos %d/%d%s") % [int(rd2.get("attacker_alive", 0)), int(rd2.get("defender_alive", 0)), extra], 12, UI.TEXT_DIM))
			rv.add_child(h)
		_detail.add_child(rc)
	_crew_section(r)
	_detail.add_child(UI.label(U.t("combat_version %s · seed %s (replay determinista)") % [str(r.get("combat_version", "")), str(r.get("seed", ""))], 12, UI.TEXT_MUTED))


## Tripulantes que viajaron en la flota y la EXP que ganaron.
func _crew_section(r: Dictionary) -> void:
	var crew: Array = r.get("crew", [])
	if crew.is_empty():
		return
	var c := UI.panel("Card")
	var v := UI.vbox(6)
	c.add_child(v)
	v.add_child(UI.label(U.t("Tripulantes a bordo"), 15, UI.CYAN, "bold"))
	var f := UI.flow(14, 6)
	for e: Dictionary in crew:
		var h := UI.hbox(6)
		h.add_child(UI.image(UI.portrait_tex(str(e.get("id", "p01"))), Vector2(40, 40)))
		var tv := UI.vbox(0)
		tv.add_child(UI.label(U.t(str(Catalog.portraits.get(str(e.get("id", "")), {}).get("name", ""))), 13, UI.TEXT, "bold"))
		var txt: String = U.t("+%d EXP · Nv %d") % [int(e.get("exp", 0)), int(e.get("level", 1))]
		if bool(e.get("leveled", false)):
			txt += "  " + U.t("¡Sube de nivel!")
		tv.add_child(UI.label(txt, 12, UI.GOLD if bool(e.get("leveled", false)) else UI.GREEN))
		h.add_child(tv)
		f.add_child(h)
	v.add_child(f)
	_detail.add_child(c)


func _side_column(side: Dictionary, title: String, defender: bool) -> Control:
	var card := UI.panel("Card")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(6)
	card.add_child(v)
	var h := UI.hbox(8)
	h.add_child(UI.image(UI.portrait_tex(str(side.get("avatar", "p01"))), Vector2(52, 52)))
	var tv := UI.vbox(0)
	tv.add_child(UI.label(title, 12, UI.TEXT_MUTED, "bold"))
	var n := UI.label(str(side.get("name", "")), 15, UI.TEXT, "bold")
	n.clip_text = true
	n.custom_minimum_size.x = 180
	tv.add_child(n)
	tv.add_child(UI.label(U.t("Poder perdido: %s") % U.fmt_int(int(side.get("power_lost", 0))), 12, UI.RED))
	h.add_child(tv)
	v.add_child(h)
	var initial: Dictionary = side.get("initial", {})
	var losses: Dictionary = side.get("losses", {})
	var wounded: Dictionary = side.get("wounded", {})
	var cryo: Dictionary = side.get("cryo", {})
	var lost: Dictionary = side.get("lost", {})
	for k: String in initial:
		var row := UI.hbox(6)
		row.add_child(UI.icon(UI.troop_icon_name(k), 26))
		var nm := UI.label(Catalog.troop_name(k), 13, UI.TEXT)
		nm.custom_minimum_size.x = 104
		row.add_child(nm)
		row.add_child(UI.label(U.fmt_int(int(initial[k])), 13, UI.TEXT, "bold"))
		row.add_child(UI.label("−%s" % U.fmt_int(int(losses.get(k, 0))), 13, UI.RED, "bold"))
		var det: String = ""
		if int(wounded.get(k, 0)) > 0:
			det += " H%d" % int(wounded[k])
		if int(cryo.get(k, 0)) > 0:
			det += " C%d" % int(cryo[k])
		if int(lost.get(k, 0)) > 0:
			det += " P%d" % int(lost[k])
		row.add_child(UI.label(det, 12, UI.TEXT_DIM))
		v.add_child(row)
	if defender and int(side.get("perimeter_initial", 0)) > 0:
		v.add_child(UI.label(U.t("Escudo Perimetral: %s » %s") % [U.fmt_num(int(side["perimeter_initial"])), U.fmt_num(int(side.get("perimeter_left", 0)))], 13, UI.CYAN))
	v.add_child(UI.label(U.t("H = heridos (Bahía Médica) · C = criostasis · P = perdidos"), 11, UI.TEXT_MUTED))
	return card


func _event_detail(r: Dictionary) -> void:
	_detail.add_child(_banner(U.t("¡PREMIO!"), UI.GOLD))
	_detail.add_child(UI.label(str(r.get("title", "")), 18, UI.TEXT, "bold"))
	var c := UI.panel("CardGold")
	c.add_child(UI.reward_row(r.get("rewards", {}), 17))
	_detail.add_child(c)


func _hunt_detail(r: Dictionary) -> void:
	var x: Dictionary = r.get("xeno", {})
	_detail.add_child(_banner(U.t("XENOFORMA ABATIDA") if bool(x.get("killed", false)) else U.t("CAZA PARCIAL"), UI.GREEN if bool(x.get("killed", false)) else UI.GOLD))
	var h := UI.hbox(14)
	h.add_child(UI.image(UI.xeno_tex(str(x.get("species", "")), int(x.get("level", 1))), Vector2(150, 150)))
	var v := UI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label(U.t("%s · N%d") % [x.get("name", ""), int(x.get("level", 1))], 20, UI.TEXT, "bold"))
	v.add_child(UI.label(U.t("Daño infligido: %s") % U.fmt_int(int(x.get("damage", 0))), 16, UI.CYAN, "semibold"))
	var hp_bar := UI.progress(float(x.get("hp_left", 0)), float(x.get("max_hp", 1)), UI.RED, 12)
	v.add_child(hp_bar)
	v.add_child(UI.label(U.t("Vida restante: %s / %s") % [U.fmt_num(int(x.get("hp_left", 0))), U.fmt_num(int(x.get("max_hp", 1)))], 14, UI.TEXT_DIM))
	v.add_child(UI.label(U.t("Debilidad: daño %s (+50%%)") % (U.t("físico") if str(x.get("weakness", "")) == "fisica" else U.t("energético")), 14, UI.TEXT_DIM))
	if float(x.get("streak_bonus", 0.0)) > 0.0:
		v.add_child(UI.label(U.t("Bono por caza consecutiva: +%d%%") % int(float(x["streak_bonus"]) * 100), 14, UI.GOLD, "semibold"))
	h.add_child(v)
	_detail.add_child(h)
	var rw: Dictionary = r.get("rewards", {})
	if not rw.is_empty():
		var c := UI.panel("CardGold")
		var cv := UI.vbox(6)
		c.add_child(cv)
		cv.add_child(UI.label(U.t("Recompensas"), 15, UI.GOLD, "bold"))
		cv.add_child(UI.reward_row(rw, 15))
		_detail.add_child(c)
	_crew_section(r)
	var w: Dictionary = r.get("attacker", {}).get("wounded", {})
	var wc := UI.panel("Card")
	var wv := UI.vbox(6)
	wc.add_child(wv)
	wv.add_child(UI.label(U.t("Heridos en la caza (vuelven a la Bahía Médica): %d") % U.sum_values(w), 14, UI.TEXT_DIM))
	var f := UI.flow(14, 6)
	for k: String in w:
		f.add_child(UI.troop_chip(k, int(w[k]), 26))
	wv.add_child(f)
	_detail.add_child(wc)


func _scout_detail(r: Dictionary) -> void:
	var s: Dictionary = r.get("scout", {})
	var tgt: Dictionary = r.get("target", {})
	var precision: int = int(s.get("precision", 1))
	_detail.add_child(_banner(U.t("INFORME DE ESPIONAJE"), UI.CYAN))
	var h := UI.hbox(14)
	h.add_child(UI.image(UI.portrait_tex(str(tgt.get("avatar", "p01"))), Vector2(110, 110)))
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label(str(tgt.get("name", "")), 20, UI.TEXT, "bold"))
	v.add_child(UI.label(U.t("Precisión del informe: %d / 5") % precision, 18, UI.GOLD, "bold"))
	v.add_child(UI.label(U.t("Poder: %s") % U.fmt_int(int(s.get("power", 0))), 16, UI.TEXT, "semibold"))
	if s.has("troops_total"):
		v.add_child(UI.label(U.t("Tropas en la nave: %s%s") % ["~" if precision < 5 else "", U.fmt_int(int(s["troops_total"]))], 16, UI.TEXT, "semibold"))
	if s.has("perimeter_hp"):
		v.add_child(UI.label(U.t("Escudo Perimetral: %s HP") % U.fmt_int(int(s["perimeter_hp"])), 15, UI.CYAN))
	h.add_child(v)
	_detail.add_child(h)
	if s.has("troops"):
		var c := UI.panel("Card")
		var f := UI.flow(16, 8)
		for k: String in s["troops"]:
			f.add_child(UI.troop_chip(k, int(s["troops"][k]), 30))
		c.add_child(f)
		_detail.add_child(c)
	if s.has("lootable"):
		var lc := UI.panel("CardGold")
		var lv := UI.vbox(6)
		lc.add_child(lv)
		lv.add_child(UI.label(U.t("Recursos saqueables (por encima de su Bóveda)"), 14, UI.GOLD, "bold"))
		lv.add_child(UI.reward_row(s["lootable"], 14))
		_detail.add_child(lc)
	if precision < 3:
		_detail.add_child(UI.wrap(UI.label(U.t("Mejora tu Sala de Sensores para obtener más detalle (tropas y composición)."), 14, UI.TEXT_MUTED)))
	var base_id: String = str(tgt.get("base_id", ""))
	if GameClient.entities.has(base_id):
		var atk := UI.button(U.t("Atacar a este objetivo"), "DangerButton", "ui_attack", Vector2(280, 54))
		atk.pressed.connect(func() -> void:
			var e: Dictionary = GameClient.entities.get(base_id, {})
			close_window()
			if not e.is_empty():
				game.open_fleet_dialog("attack", e))
		_detail.add_child(atk)
