extends "res://ui/panels/window.gd"
## LiveOps: Pase de Expedición (50 niveles, pista gratuita y premium),
## Licencia de Comandante (15 niveles VIP), Eventos de Singularidad y Festival
## de la Flota de la alianza. Los pagos con dinero real son simulados: el
## premium se compra con Materia Oscura.

const CommanderPanel = preload("res://ui/panels/commander_panel.gd")

var tab: String = "pass"
var _sig: String = ""
var _scroll: ScrollContainer
var _scroll_pos: int = -1


func _init() -> void:
	desired_size = Vector2(1180, 650)


func window_title() -> String:
	return U.t("Pase y Eventos")


func window_icon() -> String:
	return "ui_trophy"


func lo() -> Dictionary:
	return GameClient.me.get("liveops", {})


func _signature() -> String:
	return JSON.stringify([lo(), GameClient.res("dark_matter"), tab])


func on_player_updated() -> void:
	var s: String = _signature()
	if s != _sig:
		if _scroll != null and is_instance_valid(_scroll):
			_scroll_pos = _scroll.scroll_vertical
		rebuild()


## Recompensas listas para reclamar (para el aviso del HUD).
static func claimable(v: Dictionary) -> int:
	var n: int = 0
	var ps: Dictionary = v.get("pass", {})
	for lvl: int in range(1, int(ps.get("level", 0)) + 1):
		if not (ps.get("free_claimed", []) as Array).has(lvl):
			n += 1
		if bool(ps.get("premium", false)) and not (ps.get("prem_claimed", []) as Array).has(lvl):
			n += 1
	if bool(v.get("license", {}).get("daily_ready", false)):
		n += 1
	var sg: Dictionary = v.get("singularity", {})
	var ms: Array = sg.get("milestones", [])
	for i: int in range(ms.size()):
		if int(sg.get("points", 0)) >= int(ms[i]["points"]) and not (sg.get("claimed", []) as Array).has(i):
			n += 1
	var fe: Dictionary = v.get("festival", {})
	var fm: Array = fe.get("milestones", [])
	for i: int in range(fm.size()):
		if int(fe.get("points", 0)) >= int(fm[i]["points"]) and not (fe.get("claimed", []) as Array).has(i):
			n += 1
	return n


func build() -> void:
	_sig = _signature()
	tab = str(args.get("tab", tab))
	var tabs := UI.hbox(8)
	body.add_child(tabs)
	var v: Dictionary = lo()
	var sing_on: bool = bool(v.get("singularity", {}).get("active", false))
	for t: Array in [["pass", U.t("Pase de Expedición"), "ui_trophy"], ["license", U.t("Licencia de Comandante"), "ui_star"],
			["singularity", U.t("Singularidad") + ("  ●" if sing_on else ""), "ui_event"], ["festival", U.t("Festival de la Flota"), "ui_alliance"]]:
		var b := UI.button(t[1], "PrimaryButton" if t[0] == tab else "TabButton", t[2], Vector2(0, 48))
		b.name = "Tab_" + str(t[0])
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			args["tab"] = key
			tab = key
			_scroll_pos = -1
			rebuild())
		tabs.add_child(b)
	if v.is_empty():
		body.add_child(UI.label(U.t("Cargando…"), 16, UI.TEXT_DIM))
		return
	match tab:
		"license":
			_license(v["license"])
		"singularity":
			_singularity(v["singularity"])
		"festival":
			_festival(v["festival"])
		_:
			_pass(v["pass"])


func _left(ms: int) -> String:
	return U.fmt_time(maxf(0.0, float(ms - GameClient.server_now()) / 1000.0))


func _claimed_mark() -> Control:
	var h := UI.hbox(4)
	h.add_child(UI.icon("ui_check", 22, UI.GREEN))
	h.add_child(UI.label(U.t("Reclamado"), 13, UI.GREEN, "semibold"))
	return h


func _keep_scroll(sc: ScrollContainer, fallback: int) -> void:
	_scroll = sc
	var pos: int = _scroll_pos if _scroll_pos >= 0 else fallback
	(func() -> void:
		if is_instance_valid(sc):
			sc.scroll_vertical = pos).call_deferred()


# ---------------------------------------------------------------- Pase

func _pass(ps: Dictionary) -> void:
	var cfg: Dictionary = Catalog.liveops.get("pass", {})
	var lvl: int = int(ps.get("level", 0))
	var maxl: int = int(cfg.get("levels", 50))
	var ppl: int = int(ps.get("points_per_level", 300))
	var premium: bool = bool(ps.get("premium", false))
	var top := UI.panel("CardHi")
	body.add_child(top)
	var th := UI.hbox(16)
	top.add_child(th)
	var tv := UI.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.label(U.t("Nivel %d / %d") % [lvl, maxl], 22, UI.GOLD, "bold"))
	var pts: int = int(ps.get("points", 0))
	if lvl < maxl:
		tv.add_child(UI.label(U.t("Puntos %s · %s para el siguiente nivel") % [U.fmt_int(pts), U.fmt_int(ppl - pts % ppl)], 14, UI.TEXT_DIM))
		tv.add_child(UI.progress(float(pts % ppl), float(ppl), UI.GOLD, 12))
	tv.add_child(UI.label(U.t("La temporada termina en %s. Ganas puntos cazando, minando, mejorando salas, investigando, entrenando y en PvP.") % _left(int(ps.get("season_end", 0))), 13, UI.TEXT_MUTED))
	th.add_child(tv)
	var rv := UI.vbox(6)
	if premium:
		rv.add_child(UI.label(U.t("PREMIUM ACTIVO"), 18, UI.GOLD, "title"))
	else:
		var cost: int = int(ps.get("premium_mo", 1000))
		var buy := UI.button(U.t("Activar premium (%s MO)") % U.fmt_int(cost), "GoldButton", "res_dark_matter", Vector2(300, 52))
		buy.name = "BuyPremium"
		buy.disabled = GameClient.res("dark_matter") < cost
		buy.pressed.connect(func() -> void: send("pass_buy", {}, func(_p: Dictionary) -> void:
			UI.Sfx.play("reward")
			game.toast(U.t("¡Pase premium activado! Reclama las recompensas de los niveles alcanzados."), "success")))
		rv.add_child(buy)
		rv.add_child(UI.label(U.t("Precio real: US$ %.2f (pago simulado con MO)") % float(cfg.get("premium_usd", 9.99)), 12, UI.TEXT_MUTED))
	var pending: Array = []
	for i: int in range(1, lvl + 1):
		if not (ps.get("free_claimed", []) as Array).has(i):
			pending.append([i, "free"])
		if premium and not (ps.get("prem_claimed", []) as Array).has(i):
			pending.append([i, "premium"])
	var all := UI.button(U.t("Reclamar todo (%d)") % pending.size(), "PrimaryButton", "ui_gift", Vector2(300, 46))
	all.name = "ClaimAll"
	all.disabled = pending.is_empty()
	all.pressed.connect(func() -> void: _claim_all(pending))
	rv.add_child(all)
	th.add_child(rv)
	# Tabla de niveles: una fila por nivel con la pista gratuita y la premium.
	var list := UI.vbox(4)
	var sc: ScrollContainer = scroll_body(list)
	body.add_child(sc)
	var hdr := UI.hbox(10)
	hdr.add_child(UI.spacer(false, Vector2(70, 0)))
	var hf := UI.label(U.t("Gratis"), 15, UI.CYAN, "bold")
	hf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(hf)
	var hp := UI.label(U.t("Premium"), 15, UI.GOLD, "bold")
	hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(hp)
	list.add_child(hdr)
	var free_l: Array = cfg.get("free", [])
	var prem_l: Array = cfg.get("premium", [])
	var first_open: int = maxl
	for i: int in range(1, maxl + 1):
		var row := UI.hbox(10)
		var reached: bool = i <= lvl
		var badge := UI.label(str(i), 20, UI.GOLD if reached else UI.TEXT_MUTED, "title")
		badge.custom_minimum_size.x = 70
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(badge)
		row.add_child(_pass_cell(i, "free", free_l[i - 1].get("reward", {}) if i <= free_l.size() else {}, reached, (ps.get("free_claimed", []) as Array).has(i), true))
		row.add_child(_pass_cell(i, "premium", prem_l[i - 1].get("reward", {}) if i <= prem_l.size() else {}, reached, (ps.get("prem_claimed", []) as Array).has(i), premium))
		list.add_child(row)
		if first_open == maxl and (not reached or not (ps.get("free_claimed", []) as Array).has(i)):
			first_open = i
	_keep_scroll(sc, maxi(0, (first_open - 2) * 62))


func _pass_cell(level: int, track: String, reward: Dictionary, reached: bool, claimed: bool, unlocked: bool) -> Control:
	var card := UI.panel("Chip")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 56
	if reached and unlocked and not claimed:
		var col: Color = UI.GOLD if track == "premium" else UI.CYAN
		card.add_theme_stylebox_override("panel", UI.sb(Color(col, 0.14), Color(col, 0.8), 10, 2, 6))
	var h := UI.hbox(8)
	card.add_child(h)
	var rr := UI.reward_row(reward, 15)
	rr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not reached or not unlocked:
		rr.modulate = Color(1, 1, 1, 0.55)
	h.add_child(rr)
	if claimed:
		h.add_child(_claimed_mark())
	elif not unlocked:
		h.add_child(UI.icon("ui_lock", 22, UI.TEXT_MUTED))
	elif reached:
		var b := UI.button(U.t("Reclamar"), "GoldButton" if track == "premium" else "PrimaryButton", "", Vector2(120, 40))
		b.name = "Claim_%s_%d" % [track, level]
		b.pressed.connect(func() -> void: send("pass_claim", {"level": level, "track": track}, func(_p: Dictionary) -> void:
			UI.Sfx.play("reward")
			game.toast(U.t("Recompensa del nivel %d reclamada") % level, "success")))
		h.add_child(b)
	return card


func _claim_all(pending: Array) -> void:
	var total: Dictionary = {}
	var left: Array = [pending.size()]
	for e: Array in pending:
		GameClient.intent("pass_claim", {"level": e[0], "track": e[1]}, func(ok: bool, payload: Dictionary) -> void:
			if ok:
				var r: Dictionary = payload.get("reward", {})
				for k: String in r:
					total[k] = int(total.get(k, 0)) + int(r[k])
			left[0] -= 1
			if left[0] == 0 and not total.is_empty() and is_inside_tree():
				game.show_reward(total, U.t("Pase de Expedición")))


# ---------------------------------------------------------------- Licencia

func _license(lic: Dictionary) -> void:
	var cfg: Dictionary = Catalog.liveops.get("license", {})
	var lvl: int = int(lic.get("level", 0))
	var maxl: int = int(cfg.get("levels", 15))
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.panel("CardHi")
	left.custom_minimum_size.x = 420
	row.add_child(left)
	var lv := UI.vbox(10)
	left.add_child(lv)
	var h := UI.hbox(12)
	h.add_child(UI.icon("ui_star", 64, UI.GOLD))
	var tv := UI.vbox(2)
	tv.add_child(UI.label(U.t("Licencia de Comandante"), 16, UI.TEXT_DIM))
	tv.add_child(UI.label(U.t("Nivel %d / %d") % [lvl, maxl], 26, UI.GOLD, "title"))
	h.add_child(tv)
	lv.add_child(h)
	var nxt: int = int(lic.get("next", -1))
	var pts: int = int(lic.get("points", 0))
	if nxt > 0:
		lv.add_child(UI.label(U.t("Puntos %s / %s") % [U.fmt_int(pts), U.fmt_int(nxt)], 14, UI.TEXT_DIM))
		lv.add_child(UI.progress(float(pts), float(nxt), UI.GOLD, 12))
	else:
		lv.add_child(UI.label(U.t("Nivel máximo"), 14, UI.GREEN, "bold"))
	lv.add_child(UI.wrap(UI.label(U.t("Sube de nivel gastando Materia Oscura (1 punto por MO) y reclamando el bono diario. Los beneficios son permanentes."), 13, UI.TEXT_MUTED)))
	var d := UI.button(U.t("Bono diario (+%d puntos)") % int(cfg.get("daily_points", 60)), "PrimaryButton", "ui_calendar", Vector2(0, 50))
	d.name = "LicenseDaily"
	d.disabled = not bool(lic.get("daily_ready", false))
	if d.disabled:
		d.text = U.t("Bono diario reclamado")
	d.pressed.connect(func() -> void: send("license_daily", {}, func(_p: Dictionary) -> void:
		UI.Sfx.play("reward")
		game.toast(U.t("Puntos de Licencia sumados"), "success")))
	lv.add_child(d)
	var ab: bool = bool(lic.get("auto_battle", false))
	lv.add_child(UI.wrap(UI.label((U.t("Auto-batalla en Expediciones: ACTIVA") if ab else U.t("Auto-batalla en Expediciones: se desbloquea en el nivel %d") % int(cfg.get("auto_battle_level", 6))), 14, UI.GREEN if ab else UI.TEXT_DIM, "semibold")))
	var right := UI.panel("Card")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var list := UI.vbox(4)
	var sc: ScrollContainer = scroll_body(list)
	right.add_child(sc)
	var perks: Array = cfg.get("perks", [])
	var table: Array = cfg.get("points", [])
	for i: int in range(1, perks.size()):
		var c := UI.panel("Chip")
		if i == lvl:
			c.add_theme_stylebox_override("panel", UI.sb(Color(UI.GOLD, 0.16), Color(UI.GOLD, 0.8), 10, 2, 6))
		var ch := UI.hbox(12)
		c.add_child(ch)
		var nl := UI.label(U.t("Nv %d") % i, 16, UI.GOLD if i <= lvl else UI.TEXT_MUTED, "bold")
		nl.custom_minimum_size.x = 64
		ch.add_child(nl)
		var parts: Array = []
		for k: String in perks[i]:
			parts.append("+%s%% %s" % [str(snappedf(float(perks[i][k]) * 100.0, 0.1)).trim_suffix(".0"), CommanderPanel.effect_label(k)])
		if i == int(cfg.get("auto_battle_level", 6)):
			parts.append(U.t("auto-batalla"))
		var pl := UI.wrap(UI.label(", ".join(parts), 13, UI.TEXT if i <= lvl else UI.TEXT_DIM))
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ch.add_child(pl)
		if i - 1 < table.size():
			ch.add_child(UI.label(U.t("%s pts") % U.fmt_int(int(table[i - 1])), 12, UI.TEXT_MUTED))
		list.add_child(c)
	_keep_scroll(sc, maxi(0, (lvl - 3) * 60))


# ---------------------------------------------------------------- Singularidad

func _milestones(ms: Array, points: int, claimed: Array, action: String, unit: String) -> Control:
	var v := UI.vbox(6)
	for i: int in range(ms.size()):
		var c := UI.panel("Chip")
		var h := UI.hbox(10)
		c.add_child(h)
		var need: int = int(ms[i]["points"])
		var done: bool = points >= need
		var nl := UI.label("%s %s" % [U.fmt_int(need), unit], 15, UI.GOLD if done else UI.TEXT_DIM, "bold")
		nl.custom_minimum_size.x = 140
		h.add_child(nl)
		var rr := UI.reward_row(ms[i]["reward"], 15)
		rr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(rr)
		if claimed.has(i):
			h.add_child(_claimed_mark())
		elif done:
			var b := UI.button(U.t("Reclamar"), "GoldButton", "", Vector2(120, 40))
			b.name = "Milestone_%d" % i
			var idx: int = i
			var reward: Dictionary = ms[i]["reward"]
			b.pressed.connect(func() -> void: send(action, {"index": idx}, func(_p: Dictionary) -> void:
				game.show_reward(reward, U.t("Hito alcanzado"))))
			h.add_child(b)
		else:
			h.add_child(UI.icon("ui_lock", 22, UI.TEXT_MUTED))
		v.add_child(c)
	return v


func _singularity(sg: Dictionary) -> void:
	if not bool(sg.get("active", false)):
		var c := UI.panel("CardHi")
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(c)
		var cv := UI.vbox(10, BoxContainer.ALIGNMENT_CENTER)
		c.add_child(cv)
		var t := UI.label(U.t("No hay un Evento de Singularidad activo"), 22, UI.TEXT, "bold")
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(t)
		var n := UI.label(U.t("Próximo: %s, en %s") % [str(sg.get("next_name", "")), _left(int(sg.get("next_start", 0)))], 17, UI.GOLD, "semibold")
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(n)
		var d := UI.wrap(UI.label(U.t("Los Eventos de Singularidad son ventanas cortas en las que una actividad vale mucho más. Alcanza hitos y compite en la clasificación."), 14, UI.TEXT_DIM))
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(d)
		return
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.panel("CardHi")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var lv := UI.vbox(8)
	left.add_child(lv)
	lv.add_child(UI.label(str(sg.get("name", "")), 22, UI.GOLD, "title"))
	lv.add_child(UI.wrap(UI.label(str(sg.get("desc", "")), 15, UI.TEXT)))
	lv.add_child(UI.label(U.t("Termina en %s") % _left(int(sg.get("end", 0))), 14, UI.CYAN, "semibold"))
	lv.add_child(UI.label(U.t("Tus puntos: %s") % U.fmt_int(int(sg.get("points", 0))), 18, UI.TEXT, "bold"))
	lv.add_child(UI.separator())
	lv.add_child(_milestones(sg.get("milestones", []), int(sg.get("points", 0)), sg.get("claimed", []), "sing_claim", U.t("pts")))
	var right := UI.panel("Card")
	right.custom_minimum_size.x = 380
	row.add_child(right)
	var rv := UI.vbox(4)
	right.add_child(rv)
	rv.add_child(UI.label(U.t("Clasificación"), 17, UI.CYAN, "bold"))
	var pos: int = 1
	for e: Dictionary in sg.get("ranking", []):
		var h := UI.hbox(8)
		var me: bool = bool(e.get("me", false))
		var col: Color = UI.GOLD if me else UI.TEXT
		var pl := UI.label("%d." % pos, 15, col, "bold")
		pl.custom_minimum_size.x = 34
		h.add_child(pl)
		var nl := UI.label(str(e.get("name", "")), 15, col, "semibold" if me else "regular")
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		h.add_child(nl)
		h.add_child(UI.label(U.fmt_int(int(e.get("points", 0))), 15, col, "bold"))
		rv.add_child(h)
		pos += 1


# ---------------------------------------------------------------- Festival

func _festival(fe: Dictionary) -> void:
	if fe.is_empty():
		var c := UI.panel("CardHi")
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(c)
		var cv := UI.vbox(12, BoxContainer.ALIGNMENT_CENTER)
		c.add_child(cv)
		var t := UI.wrap(UI.label(U.t("El Festival de la Flota es un evento cooperativo de tu Alianza. Únete a una para participar."), 18, UI.TEXT))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(t)
		var b := UI.button(U.t("Buscar alianza"), "PrimaryButton", "ui_alliance", Vector2(260, 52))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void:
			close_window()
			game.open_panel("alliance_hq", {"tab": "search"}))
		cv.add_child(b)
		return
	var top := UI.hbox(12)
	body.add_child(top)
	top.add_child(UI.label(U.t("Puntos de la alianza: %s") % U.fmt_int(int(fe.get("points", 0))), 20, UI.GOLD, "bold"))
	top.add_child(UI.spacer())
	top.add_child(UI.label(U.t("Tu aporte: %s · termina en %s") % [U.fmt_num(int(fe.get("my_contrib", 0.0))), _left(int(fe.get("end", 0)))], 14, UI.TEXT_DIM))
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.panel("Card")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var lv := UI.vbox(8)
	left.add_child(lv)
	lv.add_child(UI.label(U.t("Misiones colectivas"), 17, UI.CYAN, "bold"))
	for m: Dictionary in fe.get("missions", []):
		var c := UI.panel("Chip")
		var mv := UI.vbox(3)
		c.add_child(mv)
		var h := UI.hbox(8)
		var nl := UI.label(str(m["name"]), 15, UI.TEXT, "bold")
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nl)
		h.add_child(UI.label(U.t("%d pts") % int(m["points"]), 13, UI.GOLD, "semibold"))
		mv.add_child(h)
		var prog: float = minf(float(m["progress"]), float(m["target"]))
		mv.add_child(UI.label("%s: %s / %s" % [str(m["desc"]), U.fmt_int(int(prog)), U.fmt_int(int(m["target"]))], 13, UI.TEXT_DIM))
		mv.add_child(UI.progress(prog, float(m["target"]), UI.GREEN if prog >= float(m["target"]) else UI.CYAN, 10))
		lv.add_child(c)
	var right := UI.panel("CardHi")
	right.custom_minimum_size.x = 520
	row.add_child(right)
	var rv := UI.vbox(8)
	right.add_child(rv)
	rv.add_child(UI.label(U.t("Hitos (premio para cada miembro)"), 17, UI.GOLD, "bold"))
	rv.add_child(_milestones(fe.get("milestones", []), int(fe.get("points", 0)), fe.get("claimed", []), "fest_claim", U.t("pts")))
