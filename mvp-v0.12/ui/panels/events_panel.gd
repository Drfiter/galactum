extends "res://ui/panels/window.gd"
## Eventos: torneo rotativo con pozo de premios, evento de recursos activo y la
## vista de rentabilidad ("la casa siempre gana": valor quemado vs premio).

var tab: String = "tournament"
var ev: Dictionary = {}
var _sim: Dictionary = {"players": 2000.0, "payers": 4.0, "spend": 12.0}
var _sim_out: Label


func _init() -> void:
	desired_size = Vector2(1180, 650)


func window_title() -> String:
	return U.t("Eventos y Torneos")


func window_icon() -> String:
	return "ui_event"


func build() -> void:
	live_refresh = 2.0
	tab = str(args.get("tab", tab))
	var tabs := UI.hbox(8)
	body.add_child(tabs)
	for t: Array in [["tournament", U.t("Torneo"), "ui_trophy"], ["resource", U.t("Evento de recursos"), "ui_event"], ["profit", U.t("Rentabilidad"), "ui_reports"]]:
		var b := UI.button(t[1], "PrimaryButton" if t[0] == tab else "TabButton", t[2], Vector2(0, 48))
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			args["tab"] = key
			tab = key
			rebuild())
		tabs.add_child(b)
	if ev.is_empty():
		body.add_child(UI.label(U.t("Cargando eventos…"), 16, UI.TEXT_DIM))
		_fetch()
		return
	match tab:
		"resource":
			_resource()
		"profit":
			_profit()
		_:
			_tournament()


func _fetch(force: bool = true) -> void:
	GameClient.intent("events", {}, func(ok: bool, payload: Dictionary) -> void:
		if not ok or not is_inside_tree():
			return
		var nev: Dictionary = payload.get("events", {})
		var sig_old: String = JSON.stringify(ev.get("tournament", {}).get("leaderboard", [])) + str(ev.get("tournament", {}).get("my_points", 0)) + str((ev.get("history", []) as Array).size())
		var sig_new: String = JSON.stringify(nev.get("tournament", {}).get("leaderboard", [])) + str(nev.get("tournament", {}).get("my_points", 0)) + str((nev.get("history", []) as Array).size())
		ev = nev
		if force or sig_old != sig_new:
			rebuild())


func tick() -> void:
	if tab == "tournament":
		_fetch(false)
	var l: Label = body.find_child("Timer", true, false)
	if l != null and l.has_meta("end"):
		l.text = U.fmt_time(maxf(0.0, float(int(l.get_meta("end")) - GameClient.server_now()) / 1000.0))


func _timer_label(end_ts: int, size: int = 20) -> Label:
	var l := UI.label(U.fmt_time(maxf(0.0, float(end_ts - GameClient.server_now()) / 1000.0)), size, UI.GOLD, "bold")
	l.name = "Timer"
	l.set_meta("end", end_ts)
	return l


func _tournament() -> void:
	var t: Dictionary = ev.get("tournament", {})
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var hero := UI.panel("CardGold")
	left.add_child(hero)
	var hv := UI.vbox(4)
	hero.add_child(hv)
	var hh := UI.hbox(10)
	hh.add_child(UI.icon("ui_" + str(t.get("icon", "trophy")), 44, UI.GOLD))
	var tv := UI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.title(str(t.get("name", "")), 24, UI.GOLD))
	tv.add_child(UI.label(str(t.get("desc", "")), 14, UI.TEXT_DIM))
	hh.add_child(tv)
	var tt := UI.vbox(0)
	tt.add_child(UI.label(U.t("Termina en"), 12, UI.TEXT_MUTED))
	tt.add_child(_timer_label(int(t.get("end", 0))))
	hh.add_child(tt)
	hv.add_child(hh)
	var stats := UI.hbox(26)
	stats.add_child(_stat(U.t("Pozo de premios"), "US$ %s" % U.fmt_int(int(t.get("pool_usd", 0))), "ui_gift", UI.GREEN))
	stats.add_child(_stat(U.t("Participantes"), str(int(t.get("participants", 0))), "ui_users", UI.TEXT))
	var my_rank: int = int(t.get("my_rank", 0))
	stats.add_child(_stat(U.t("Tu puesto"), ("#%d" % my_rank) if my_rank > 0 else "—", "ui_trophy", UI.CYAN))
	stats.add_child(_stat(U.t("Tus puntos"), U.fmt_int(int(t.get("my_points", 0))), "ui_star", UI.CYAN))
	hv.add_child(stats)
	left.add_child(UI.label(U.t("CLASIFICACIÓN"), 15, UI.GOLD, "bold"))
	var list := UI.vbox(4)
	left.add_child(scroll_body(list))
	for r: Dictionary in t.get("leaderboard", []):
		var me: bool = str(r["id"]) == GameClient.player_id
		var card := UI.panel("CardHi" if me else "Card")
		var h := UI.hbox(10)
		card.add_child(h)
		var rk := UI.label("#%d" % int(r["rank"]), 17, UI.GOLD if int(r["rank"]) <= 3 else UI.TEXT_DIM, "bold")
		rk.custom_minimum_size.x = 46
		h.add_child(rk)
		h.add_child(UI.image(UI.portrait_tex(str(r.get("avatar", "p01"))), Vector2(34, 34)))
		var n := UI.label(str(r["name"]), 15, UI.CYAN if me else UI.TEXT, "semibold")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(UI.label(U.t("%s pts") % U.fmt_int(int(r["points"])), 15, UI.TEXT, "bold"))
		list.add_child(card)
	if (t.get("leaderboard", []) as Array).is_empty():
		list.add_child(UI.label(U.t("Aún nadie suma puntos. ¡Sé el primero!"), 15, UI.TEXT_MUTED))
	# Premios por puesto
	var right := UI.panel("Card")
	right.custom_minimum_size.x = 420
	row.add_child(right)
	var rv := UI.vbox(6)
	right.add_child(rv)
	rv.add_child(UI.label(U.t("PREMIOS (en objetos)"), 15, UI.GOLD, "bold"))
	var pl := UI.vbox(4)
	for pz: Dictionary in t.get("prizes", []):
		var ph := UI.hbox(8)
		var rk2 := UI.label("#%d" % int(pz["rank"]), 15, UI.GOLD if int(pz["rank"]) <= 3 else UI.TEXT_DIM, "bold")
		rk2.custom_minimum_size.x = 36
		ph.add_child(rk2)
		var u := UI.label("US$ %.0f" % float(pz["usd"]), 14, UI.GREEN, "bold")
		u.custom_minimum_size.x = 76
		ph.add_child(u)
		var rr := UI.reward_row(pz["reward"], 12)
		rr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ph.add_child(rr)
		pl.add_child(ph)
	rv.add_child(scroll_body(pl))
	var up: Array = ev.get("upcoming", ["", ""])
	rv.add_child(UI.label(U.t("Siguiente torneo: %s") % str(up[1]), 13, UI.TEXT_MUTED))
	var dbg := UI.button(U.t("Demo: terminar torneo y repartir premios"), "GhostButton", "ui_timer", Vector2(0, 42))
	dbg.pressed.connect(func() -> void: send("debug_finish_event", {"which": "tournament"}, func(_p: Dictionary) -> void:
		game.toast(U.t("Torneo finalizado: revisa Rentabilidad"), "success")
		_fetch()))
	rv.add_child(dbg)


func _resource() -> void:
	var r: Dictionary = ev.get("resource", {})
	var card := UI.panel("CardHi")
	body.add_child(card)
	var h := UI.hbox(16)
	card.add_child(h)
	h.add_child(UI.icon("ui_" + str(r.get("icon", "event")), 80, UI.PURPLE))
	var v := UI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.title(str(r.get("name", "")), 28, UI.PURPLE))
	v.add_child(UI.wrap(UI.label(str(r.get("desc", "")), 17, UI.TEXT)))
	var eff: Dictionary = r.get("effects", {})
	var chips := UI.flow(10, 6)
	for k: String in eff:
		var txt: String = ""
		match k:
			"gather_speed":
				txt = U.t("+%d%% velocidad de minería") % int(round(float(eff[k]) * 100))
			"production":
				txt = U.t("+%d%% producción de la nave") % int(round(float(eff[k]) * 100))
			"hunt_reward":
				txt = U.t("+%d%% recompensas de caza") % int(round(float(eff[k]) * 100))
			"hunt_energy":
				txt = U.t("%d%% energía por caza") % int(round(float(eff[k]) * 100))
			"element_gather":
				for el: String in eff[k]:
					txt += ("  " if not txt.is_empty() else "") + U.t("x%.0f %s") % [1.0 + float(eff[k][el]), Catalog.res_name(el)]
		var c := UI.panel("Chip")
		c.add_child(UI.label(txt, 15, UI.GREEN, "bold"))
		chips.add_child(c)
	v.add_child(chips)
	h.add_child(v)
	var tv := UI.vbox(0)
	tv.add_child(UI.label(U.t("Termina en"), 12, UI.TEXT_MUTED))
	tv.add_child(_timer_label(int(r.get("end", 0)), 24))
	h.add_child(tv)
	body.add_child(UI.wrap(UI.label(U.t("Los eventos de recursos rotan cada hora. Siguiente: %s. Aprovecha el evento activo para minar o cazar más rápido; los torneos premian a quienes más participan.") % str(ev.get("upcoming", [""])[0]), 15, UI.TEXT_DIM)))
	var dbg := UI.button(U.t("Demo: pasar al siguiente evento"), "GhostButton", "ui_timer", Vector2(320, 44))
	dbg.pressed.connect(func() -> void: send("debug_finish_event", {"which": "resource"}, func(_p: Dictionary) -> void: _fetch()))
	body.add_child(dbg)


func _profit() -> void:
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add_child(UI.wrap(UI.label(U.t("Cada torneo mide el valor que los participantes «queman» (tropas perdidas, Materia Oscura gastada y compras) frente al pozo de premios. Si la razón supera %.1f× el premio sube un 25%%; si baja de %.1f× baja un 20%%. Así se encuentra el evento más rentable para la casa.") % [float(ev.get("profit_targets", {}).get("raise_above", 4.0)), float(ev.get("profit_targets", {}).get("lower_below", 2.0))], 14, UI.TEXT_DIM)))
	var live: Dictionary = ev.get("tournament", {})
	var lc := UI.panel("CardHi")
	var lh := UI.hbox(20)
	lc.add_child(lh)
	lh.add_child(UI.label(U.t("En curso: %s") % str(live.get("name", "")), 15, UI.TEXT, "bold"))
	lh.add_child(UI.label(U.t("Quemado: US$ %.2f") % float(live.get("burned_usd", 0.0)), 15, UI.GOLD, "bold"))
	lh.add_child(UI.label(U.t("Pozo: US$ %s") % U.fmt_int(int(live.get("pool_usd", 0))), 15, UI.GREEN, "bold"))
	left.add_child(lc)
	var head := UI.hbox(6)
	for col: Array in [[U.t("Torneo"), 210], [U.t("Part."), 60], [U.t("Pozo"), 80], [U.t("Quemado"), 100], [U.t("Razón"), 70], [U.t("Ajuste"), 150]]:
		var l := UI.label(col[0], 13, UI.GOLD, "bold")
		l.custom_minimum_size.x = col[1]
		head.add_child(l)
	left.add_child(head)
	var list := UI.vbox(4)
	left.add_child(scroll_body(list))
	var hist: Array = ev.get("history", [])
	if hist.is_empty():
		list.add_child(UI.label(U.t("Aún no termina ningún torneo. Usa «Demo: terminar torneo» en la pestaña Torneo."), 14, UI.TEXT_MUTED))
	for h: Dictionary in hist:
		var card := UI.panel("Card")
		var hh := UI.hbox(6)
		card.add_child(hh)
		var ratio: float = float(h.get("ratio", 0.0))
		var advice: String = {"raise": U.t("Subir a US$ %d"), "lower": U.t("Bajar a US$ %d"), "keep": U.t("Mantener US$ %d")}.get(str(h.get("advice", "keep")), "%d") % int(h.get("next_pool_usd", 0))
		var col: Color = UI.GREEN if str(h.get("advice", "")) == "raise" else (UI.RED if str(h.get("advice", "")) == "lower" else UI.GOLD)
		for c: Array in [[U.t(str(h.get("name", ""))), 210, UI.TEXT], [str(int(h.get("participants", 0))), 60, UI.TEXT_DIM], ["$%d" % int(h.get("pool_usd", 0)), 80, UI.GREEN], ["$%.2f" % float(h.get("burned_usd", 0.0)), 100, UI.GOLD], ["%.2f×" % ratio, 70, col], [advice, 150, col]]:
			var l := UI.label(c[0], 14, c[2], "semibold")
			l.custom_minimum_size.x = c[1]
			hh.add_child(l)
		list.add_child(card)
	# Simulador de rentabilidad
	var sim := UI.panel("CardGold")
	sim.custom_minimum_size.x = 400
	row.add_child(sim)
	var sv := UI.vbox(6)
	sim.add_child(sv)
	sv.add_child(UI.title(U.t("Simulador de evento"), 20, UI.GOLD))
	sv.add_child(UI.wrap(UI.label(U.t("Proyección con jugadores reales: cuánto entra por compras frente al pozo de premios."), 13, UI.TEXT_DIM)))
	var pool: float = float(live.get("pool_usd", 500))
	for s: Array in [["players", U.t("Participantes"), 100.0, 20000.0, 100.0], ["payers", U.t("% que compra algo"), 0.5, 15.0, 0.5], ["spend", U.t("Gasto medio por pagador (US$)"), 1.0, 100.0, 1.0]]:
		var key: String = s[0]
		var lab := UI.label("", 14, UI.TEXT, "semibold")
		sv.add_child(lab)
		var sl := HSlider.new()
		sl.min_value = s[2]
		sl.max_value = s[3]
		sl.step = s[4]
		sl.value = float(_sim[key])
		sl.custom_minimum_size = Vector2(360, 28)
		var title: String = s[1]
		var upd := func(v: float) -> void:
			_sim[key] = v
			lab.text = "%s: %s" % [title, ("%.1f" % v) if key == "payers" else U.fmt_int(int(v))]
			_update_sim(pool)
		sl.value_changed.connect(upd)
		sv.add_child(sl)
		lab.text = "%s: %s" % [title, ("%.1f" % float(_sim[key])) if key == "payers" else U.fmt_int(int(_sim[key]))]
	_sim_out = UI.wrap(UI.label("", 15, UI.TEXT, "bold"), 360)
	sv.add_child(_sim_out)
	_update_sim(pool)


func _update_sim(pool: float) -> void:
	if _sim_out == null:
		return
	var revenue: float = float(_sim["players"]) * float(_sim["payers"]) / 100.0 * float(_sim["spend"])
	var margin: float = revenue - pool
	var ratio: float = revenue / maxf(1.0, pool)
	var verdict: String = U.t("Muy rentable: sube el premio para atraer más jugadores.") if ratio > 4.0 else (U.t("Poco rentable: baja el premio o cambia el tipo de evento.") if ratio < 2.0 else U.t("Equilibrado: mantén el premio."))
	_sim_out.text = U.t("Ingresos: US$ %s  ·  Pozo: US$ %s\nMargen: US$ %s  (%.1f×)\n%s") % [U.fmt_int(int(revenue)), U.fmt_int(int(pool)), U.fmt_int(int(margin)), ratio, verdict]
	_sim_out.add_theme_color_override("font_color", UI.GREEN if ratio > 4.0 else (UI.RED if ratio < 2.0 else UI.GOLD))


func _stat(label_text: String, value: String, icon_name: String, col: Color) -> HBoxContainer:
	var h := UI.hbox(6)
	h.add_child(UI.icon(icon_name, 24, UI.TEXT_DIM))
	var v := UI.vbox(0)
	v.add_child(UI.label(label_text, 12, UI.TEXT_MUTED))
	v.add_child(UI.label(value, 17, col, "bold"))
	h.add_child(v)
	return h
