extends "res://ui/panels/window.gd"
## Alianza (Equipo 4 + feedback de revisión): metas grupales, cofre, cuota por
## miembro, objetivo marcado, ranking, chat, Cápsulas de Suministro y Ayuda Mutua.

var tab: String = "goals"
var _chat_list: VBoxContainer
var _chat_scroll: ScrollContainer
var _input: LineEdit
var guild: Dictionary = {}
var ranking: Array = []


func _init() -> void:
	desired_size = Vector2(1180, 650)


func window_title() -> String:
	var a: Dictionary = GameClient.me.get("alliance", {})
	return U.t("[%s] %s  ·  Nv %d") % [a.get("tag", ""), U.t(str(a.get("name", "Sin alianza"))), int(guild.get("level", a.get("level", 1)))]


func window_icon() -> String:
	return "ui_alliance"


func build() -> void:
	live_refresh = 3.0
	tab = str(args.get("tab", tab))
	if not GameClient.chat_received.is_connected(_on_chat):
		GameClient.chat_received.connect(_on_chat)
	var tabs := UI.hbox(6)
	body.add_child(tabs)
	var caps: int = (GameClient.me.get("capsules", []) as Array).size()
	var gb: Dictionary = GameClient.me.get("guild_brief", {})
	for t: Array in [["goals", U.t("Metas y Cofre"), "ui_chest"], ["target", U.t("Objetivo"), "ui_rally"], ["ranking", U.t("Ranking"), "ui_trophy"], ["members", U.t("Miembros"), "ui_users"], ["chat", U.t("Chat"), "ui_chat"], ["capsules", U.t("Cápsulas (%d)") % caps, "ui_capsule"], ["help", U.t("Ayuda"), "ui_help"]]:
		var b := UI.button(t[1], "PrimaryButton" if t[0] == tab else "TabButton", t[2], Vector2(0, 46))
		b.add_theme_font_size_override("font_size", 16)
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			args["tab"] = key
			tab = key
			rebuild())
		if key == "goals" and int(gb.get("chests", 0)) > 0:
			var bd := UI.badge(str(int(gb["chests"])), UI.RED)
			bd.position = Vector2(4, -6)
			b.add_child(bd)
		tabs.add_child(b)
	if guild.is_empty() and tab in ["goals", "target", "ranking", "members"]:
		body.add_child(UI.label(U.t("Cargando datos de la Alianza…"), 16, UI.TEXT_DIM))
		_fetch()
		return
	match tab:
		"goals":
			_goals()
		"target":
			_target()
		"ranking":
			_ranking()
		"members":
			_members()
		"capsules":
			_capsules()
		"help":
			_help()
		_:
			_chat()


func _fetch() -> void:
	GameClient.intent("guild", {}, func(ok: bool, payload: Dictionary) -> void:
		if not ok or not is_inside_tree():
			return
		guild = payload.get("guild", {})
		ranking = payload.get("ranking", [])
		title_label.text = window_title()
		rebuild())


func tick() -> void:
	if tab in ["goals", "target"]:
		GameClient.intent("guild", {}, func(ok: bool, payload: Dictionary) -> void:
			if not ok or not is_inside_tree():
				return
			var changed: bool = JSON.stringify(payload.get("guild", {})) != JSON.stringify(guild)
			guild = payload.get("guild", {})
			ranking = payload.get("ranking", [])
			if changed:
				rebuild())


func _goals() -> void:
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	# Columna izquierda: nivel, metas del día, cuota personal
	var left := UI.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var lvl := UI.panel("CardHi")
	var lv := UI.vbox(4)
	lvl.add_child(lv)
	var lh := UI.hbox(8)
	lh.add_child(UI.title(U.t("Nivel de Alianza %d") % int(guild["level"]), 20, UI.GREEN))
	lh.add_child(UI.spacer())
	var perks: Dictionary = guild.get("perks", {})
	lh.add_child(UI.label(U.t("Bono a todos: +%d%% minería · +%d%% velocidad de flota") % [int(round(float(perks.get("gather_speed", 0.0)) * 100)), int(round(float(perks.get("march_speed", 0.0)) * 100))], 13, UI.TEXT_DIM, "semibold"))
	lv.add_child(lh)
	var span: float = maxf(1.0, float(int(guild["next_xp"]) - int(guild["cur_xp"])))
	lv.add_child(UI.progress(float(int(guild["xp"]) - int(guild["cur_xp"])), span, UI.GREEN, 10))
	lv.add_child(UI.label(U.t("XP %s / %s · cada caza, entrega y victoria de un miembro suma") % [U.fmt_int(int(guild["xp"])), U.fmt_int(int(guild["next_xp"]))], 12, UI.TEXT_MUTED))
	left.add_child(lvl)
	var gh := UI.hbox(8)
	gh.add_child(UI.label(U.t("METAS DEL DÍA"), 15, UI.GOLD, "bold"))
	gh.add_child(UI.spacer())
	gh.add_child(UI.label(U.t("Reinicio en %s") % U.fmt_time(maxf(0.0, float(int(guild["cycle_end"]) - GameClient.server_now()) / 1000.0)), 13, UI.TEXT_DIM))
	left.add_child(gh)
	for g: Dictionary in guild.get("goals", []):
		var done: bool = float(g["progress"]) >= float(g["target"])
		var card := UI.panel("CardGold" if done else "Card")
		var h := UI.hbox(10)
		card.add_child(h)
		h.add_child(UI.icon("ui_check" if done else "ui_" + str(g.get("icon", "star")), 34, UI.GREEN if done else UI.GOLD))
		var v := UI.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var target_txt: String = U.fmt_int(int(g["target"]))
		v.add_child(UI.label("%s  ·  %s" % [str(g["name"]), str(g["desc"]).replace("%d", target_txt).replace("%s", target_txt)], 15, UI.TEXT, "bold"))
		var pr := UI.hbox(8)
		var bar := UI.progress(minf(float(g["progress"]), float(g["target"])), float(g["target"]), UI.GREEN if done else UI.GOLD, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pr.add_child(bar)
		pr.add_child(UI.label("%s / %s" % [U.fmt_num(int(g["progress"])), U.fmt_num(int(g["target"]))], 13, UI.TEXT_DIM))
		v.add_child(pr)
		h.add_child(v)
		h.add_child(UI.label(U.t("+%d PA") % int(g["points"]), 15, UI.GREEN if done else UI.TEXT_DIM, "bold"))
		left.add_child(card)
	var q: Dictionary = guild.get("quota", {})
	var mine: int = int(guild.get("my_quota", 0))
	var qc := UI.panel("Chip")
	var qh := UI.hbox(10)
	qc.add_child(qh)
	qh.add_child(UI.icon("ui_hunt", 26, UI.GREEN if mine >= int(q.get("target", 5)) else UI.CYAN))
	qh.add_child(UI.label(U.t("Tu cuota diaria: %s") % str(q.get("label", "")), 14, UI.TEXT, "semibold"))
	qh.add_child(UI.spacer())
	qh.add_child(UI.label("%d / %d" % [mine, int(q.get("target", 5))], 16, UI.GREEN if mine >= int(q.get("target", 5)) else UI.GOLD, "bold"))
	left.add_child(qc)
	# Columna derecha: cofre de alianza
	var right := UI.panel("CardGold")
	right.custom_minimum_size.x = 400
	row.add_child(right)
	var rv := UI.vbox(8)
	right.add_child(rv)
	rv.add_child(UI.title(U.t("Cofre de Alianza"), 20, UI.GOLD))
	rv.add_child(UI.label(U.t("%s PA hoy  ·  tu aporte: %s PA") % [U.fmt_int(int(guild["points"])), U.fmt_int(int(guild.get("my_contrib", 0)))], 15, UI.TEXT, "semibold"))
	var tiers: Array = guild.get("chest_tiers", [])
	var maxp: float = float(tiers[tiers.size() - 1]["points"]) if not tiers.is_empty() else 1.0
	rv.add_child(UI.progress(minf(float(guild["points"]), maxp), maxp, UI.GOLD, 12))
	var claimed: Array = guild.get("chest_claimed", [])
	for i: int in range(tiers.size()):
		var t: Dictionary = tiers[i]
		var unlocked: bool = int(guild["points"]) >= int(t["points"])
		var is_claimed: bool = claimed.has(i) or claimed.has(float(i))
		var c := UI.panel("Card")
		var ch := UI.hbox(8)
		c.add_child(ch)
		ch.add_child(UI.icon("ui_chest", 40, [Color("cd7f32"), Color("c0c8d8"), UI.GOLD][mini(i, 2)] if unlocked else UI.TEXT_MUTED))
		var cv := UI.vbox(2)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.add_child(UI.label(U.t("%s · %s PA") % [U.t(str(t["name"])), U.fmt_int(int(t["points"]))], 14, UI.TEXT, "bold"))
		cv.add_child(UI.reward_row(t["reward"], 12))
		ch.add_child(cv)
		var b := UI.button(U.t("Reclamado") if is_claimed else U.t("Reclamar"), "GoldButton", "", Vector2(110, 44))
		b.disabled = not unlocked or is_claimed
		var idx: int = i
		b.pressed.connect(func() -> void: send("claim_chest", {"tier": idx}, func(p: Dictionary) -> void:
			game.show_reward(p.get("reward", {}), str(p.get("name", "")))
			_fetch()))
		ch.add_child(b)
		rv.add_child(c)
	var dbg := UI.button(U.t("Demo: nuevo día de Alianza"), "GhostButton", "ui_timer", Vector2(0, 40))
	dbg.pressed.connect(func() -> void: send("debug_guild_cycle", {}, func(_p: Dictionary) -> void: _fetch()))
	rv.add_child(dbg)


func _target() -> void:
	var t: Dictionary = guild.get("target", {})
	var v := UI.vbox(10)
	body.add_child(v)
	v.add_child(UI.wrap(UI.label(U.t("Los oficiales (R4/R5) marcan una nave enemiga y toda la Alianza la ataca durante 30 minutos. Cada golpe al objetivo vale +120 PA para el cofre. Para marcar: toca una nave enemiga en el mapa → «Marcar objetivo»."), 15, UI.TEXT_DIM)))
	if t.is_empty():
		var c := UI.panel("Card")
		c.add_child(UI.label(U.t("No hay un objetivo activo."), 17, UI.TEXT_MUTED, "semibold"))
		v.add_child(c)
		var go := UI.button(U.t("Buscar objetivo en el mapa"), "DangerButton", "ui_target", Vector2(300, 52))
		go.pressed.connect(func() -> void:
			close_window()
			game.goto_mission({"event": "pvp_win"}))
		v.add_child(go)
		return
	var card := UI.panel("CardRed")
	v.add_child(card)
	var h := UI.hbox(14)
	card.add_child(h)
	h.add_child(UI.icon("ui_rally", 64, UI.RED))
	var tv := UI.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(UI.title(U.t("OBJETIVO: %s") % str(t.get("name", "")), 22, Color("ffd0da")))
	tv.add_child(UI.label(U.t("Marcado por %s  ·  Poder %s  ·  X:%d Y:%d") % [str(t.get("set_by", "")), U.fmt_int(int(t.get("power", 0))), int(t["pos"][0]), int(t["pos"][1])], 14, UI.TEXT, "semibold"))
	tv.add_child(UI.label(U.t("Termina en %s  ·  %d golpes") % [U.fmt_time(maxf(0.0, float(int(t.get("until", 0)) - GameClient.server_now()) / 1000.0)), int(t.get("hits", 0))], 15, UI.GOLD, "bold"))
	var hitters: Array = t.get("hitters", [])
	tv.add_child(UI.wrap(UI.label(U.t("Participaron: %s") % (", ".join(hitters) if not hitters.is_empty() else "—"), 14, UI.TEXT_DIM)))
	h.add_child(tv)
	var bv := UI.vbox(8)
	var go2 := UI.button(U.t("Ir y atacar"), "DangerButton", "ui_attack", Vector2(200, 52))
	go2.pressed.connect(func() -> void:
		close_window()
		game.show_map()
		game.focus_tile(U.v2(t["pos"]))
		game.map_view.select(str(t["id"]))
		game.hud.show_entity(str(t["id"])))
	bv.add_child(go2)
	var clr := UI.button(U.t("Retirar marca"), "GhostButton", "ui_close", Vector2(200, 44))
	clr.pressed.connect(func() -> void: send("clear_target", {}, func(_p: Dictionary) -> void: _fetch()))
	bv.add_child(clr)
	h.add_child(bv)


func _ranking() -> void:
	var list := UI.vbox(6)
	body.add_child(scroll_body(list))
	var head := UI.hbox(8)
	for col: Array in [["#", 40], [U.t("Alianza"), 360], [U.t("Nivel"), 90], [U.t("Miembros"), 110], [U.t("Poder total"), 160], [U.t("PA hoy"), 140]]:
		var l := UI.label(col[0], 14, UI.GOLD, "bold")
		l.custom_minimum_size.x = col[1]
		head.add_child(l)
	list.add_child(head)
	var my_tag: String = str(GameClient.me.get("tag", ""))
	for i: int in range(ranking.size()):
		var r: Dictionary = ranking[i]
		var card := UI.panel("CardHi" if str(r["tag"]) == my_tag else "Card")
		var h := UI.hbox(8)
		card.add_child(h)
		var cells: Array = [["%d" % (i + 1), 40, UI.GOLD if i < 3 else UI.TEXT_DIM], ["[%s] %s" % [r["tag"], r["name"]], 360, Color(str(r.get("color", "#ffffff")))], [U.t("Nv %d") % int(r["level"]), 90, UI.TEXT], [str(int(r["members"])), 110, UI.TEXT], [U.fmt_num(int(r["power"])), 160, UI.TEXT], [U.fmt_int(int(r["points"])), 140, UI.GREEN]]
		for c: Array in cells:
			var l := UI.label(c[0], 16, c[2], "semibold")
			l.custom_minimum_size.x = c[1]
			h.add_child(l)
		list.add_child(card)


func _members() -> void:
	var list := UI.vbox(6)
	body.add_child(scroll_body(list))
	var q: Dictionary = guild.get("quota", {})
	list.add_child(UI.label(U.t("Cuota diaria del grupo: %s. Los que no cumplen quedan en rojo.") % str(q.get("label", "")), 14, UI.TEXT_DIM))
	var a: Dictionary = GameClient.me.get("alliance", {})
	var power_of: Dictionary = {}
	var avatar_of: Dictionary = {}
	var rank_of: Dictionary = {}
	for m: Dictionary in a.get("members", []):
		power_of[m["id"]] = int(m.get("power", 0))
		avatar_of[m["id"]] = str(m.get("avatar", "p01"))
		rank_of[m["id"]] = str(m.get("rank", "R2"))
	var i: int = 0
	for m: Dictionary in guild.get("members", []):
		i += 1
		var ok: bool = int(m["quota"]) >= int(q.get("target", 5))
		var card := UI.panel("CardHi" if str(m["id"]) == GameClient.player_id else "Card")
		var h := UI.hbox(12)
		card.add_child(h)
		h.add_child(UI.label("#%d" % i, 16, UI.TEXT_MUTED, "bold"))
		h.add_child(UI.image(UI.portrait_tex(avatar_of.get(m["id"], "p01")), Vector2(42, 42)))
		var n := UI.label(str(m["name"]), 16, UI.TEXT, "bold")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		h.add_child(UI.label(rank_of.get(m["id"], "R2"), 15, UI.GOLD, "bold"))
		var sl := UI.label(str(m.get("system", "")), 13, UI.TEXT_DIM)
		sl.custom_minimum_size.x = 150
		h.add_child(sl)
		var pl := UI.label(U.t("Poder ") + U.fmt_num(int(power_of.get(m["id"], 0))), 14, UI.TEXT, "semibold")
		pl.custom_minimum_size.x = 130
		h.add_child(pl)
		var cl := UI.label(U.t("%s PA") % U.fmt_int(int(m["contrib"])), 14, UI.GREEN, "semibold")
		cl.custom_minimum_size.x = 100
		h.add_child(cl)
		var ql := UI.label(("✓ " if ok else "✗ ") + "%d/%d" % [int(m["quota"]), int(q.get("target", 5))], 15, UI.GREEN if ok else UI.RED, "bold")
		ql.custom_minimum_size.x = 70
		h.add_child(ql)
		list.add_child(card)


func _capsules() -> void:
	var caps: Array = GameClient.me.get("capsules", [])
	var c := UI.panel("CardGold")
	var v := UI.vbox(10)
	c.add_child(v)
	v.add_child(UI.wrap(UI.label(U.t("Cada Xenoforma abatida por un miembro genera una Cápsula de Suministro para TODA la alianza. Ábrelas para recibir elementos, créditos, Materia Oscura y aceleradores."), 15, UI.TEXT_DIM)))
	v.add_child(UI.label(U.t("%d cápsulas disponibles") % caps.size(), 22, UI.GOLD, "bold"))
	var f := UI.flow(10, 6)
	for cap: Dictionary in caps.slice(0, 24):
		var chip := UI.panel("Chip")
		var h := UI.hbox(6)
		chip.add_child(h)
		h.add_child(UI.icon("ui_capsule", 22, UI.GOLD))
		h.add_child(UI.label(U.t("N%d · %s") % [int(cap.get("level", 1)), str(cap.get("from", ""))], 13, UI.TEXT))
		f.add_child(chip)
	v.add_child(f)
	var b := UI.button(U.t("Abrir todas"), "GoldButton", "ui_gift", Vector2(240, 56))
	b.disabled = caps.is_empty()
	b.pressed.connect(func() -> void:
		send("open_capsules", {}, func(p: Dictionary) -> void:
			game.show_reward(p.get("reward", {}), U.t("%d Cápsulas de Suministro") % int(p.get("opened", 0)))
			rebuild()))
	v.add_child(b)
	body.add_child(c)


func _help() -> void:
	var v := UI.vbox(10)
	body.add_child(v)
	v.add_child(UI.wrap(UI.label(U.t("Ayuda Mutua: cada ayuda de un compañero reduce un 1% (mínimo 1 minuto) tu temporizador. Máximo 10 ayudas por tarea."), 15, UI.TEXT_DIM)))
	var any: bool = false
	for q: Array in [["build", U.t("Construcción")], ["research", U.t("Investigación")], ["heal", U.t("Curación")]]:
		var job: Dictionary = GameClient.queue(q[0])
		if job.is_empty():
			continue
		any = true
		var card := UI.panel("Card")
		var h := UI.hbox(10)
		card.add_child(h)
		var tv := UI.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UI.label("%s: %s" % [q[1], job.get("label", "")], 16, UI.TEXT, "bold"))
		tv.add_child(UI.label(U.t("Restante %s · Ayudas %d/10") % [U.fmt_time(GameClient.queue_remaining(q[0])), int(job.get("helps", 0))], 14, UI.TEXT_DIM))
		h.add_child(tv)
		var b := UI.button(U.t("Pedir ayuda") if not bool(job.get("help_requested", false)) else U.t("Solicitada"), "GreenButton", "ui_help", Vector2(180, 48))
		b.disabled = bool(job.get("help_requested", false))
		var qq: String = q[0]
		b.pressed.connect(func() -> void: send("help", {"queue": qq}, func(_p: Dictionary) -> void:
			game.toast(U.t("Ayuda solicitada"), "help")
			rebuild()))
		h.add_child(b)
		v.add_child(card)
	if not any:
		v.add_child(UI.label(U.t("No tienes construcciones, investigaciones ni curaciones en curso."), 15, UI.TEXT_MUTED))


func _chat() -> void:
	_chat_list = UI.vbox(6)
	_chat_scroll = scroll_body(_chat_list)
	body.add_child(_chat_scroll)
	for m: Dictionary in GameClient.chat:
		_chat_list.add_child(_chat_line(m))
	var h := UI.hbox(8)
	_input = LineEdit.new()
	_input.placeholder_text = U.t("Escribe a tu alianza…")
	_input.max_length = 200
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size.y = 50
	_input.text_submitted.connect(func(_t: String) -> void: _send_chat())
	h.add_child(_input)
	var b := UI.button(U.t("Enviar"), "PrimaryButton", "ui_chat", Vector2(140, 50))
	b.pressed.connect(_send_chat)
	h.add_child(b)
	body.add_child(h)
	_scroll_end.call_deferred()


func _chat_line(m: Dictionary) -> Control:
	var kind: String = str(m.get("kind", "chat"))
	var mine: bool = str(m.get("from", "")) == str(GameClient.me.get("name", ""))
	var col: Color = UI.GOLD if kind == "system" else (UI.GREEN if kind == "help" else (Color("ff6680") if kind == "rally" else (UI.CYAN if mine else UI.TEXT)))
	var h := UI.hbox(8)
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(int(int(m.get("ts", 0)) / 1000))
	h.add_child(UI.label("%02d:%02d" % [int(t.get("hour", 0)), int(t.get("minute", 0))], 12, UI.TEXT_MUTED))
	h.add_child(UI.label(str(m.get("from", "")) + ":", 15, col, "bold"))
	var txt := UI.wrap(UI.label(str(m.get("text", "")), 15, UI.TEXT if kind == "chat" else UI.TEXT_DIM))
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(txt)
	return h


func _on_chat(m: Dictionary) -> void:
	if tab == "chat" and _chat_list != null and is_instance_valid(_chat_list):
		_chat_list.add_child(_chat_line(m))
		_scroll_end.call_deferred()


func _scroll_end() -> void:
	if _chat_scroll != null and is_instance_valid(_chat_scroll):
		await get_tree().process_frame
		_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


func _send_chat() -> void:
	var txt: String = _input.text.strip_edges()
	if txt.is_empty():
		return
	_input.text = ""
	send("chat", {"text": txt})


func _exit_tree() -> void:
	if GameClient.chat_received.is_connected(_on_chat):
		GameClient.chat_received.disconnect(_on_chat)
