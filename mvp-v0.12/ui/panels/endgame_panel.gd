extends "res://ui/panels/window.gd"
## Guerra del Sistema: Plataformas Orbitales (quién las controla y su bono),
## Colmenas Xeno (vida y botín) y títulos que otorga la alianza de la
## Ciudadela. Desde aquí se ubica cada objetivo en el mapa.

const CommanderPanel = preload("res://ui/panels/commander_panel.gd")

var tab: String = "platforms"
var _sig: String = ""
var _picking: String = ""


func _init() -> void:
	desired_size = Vector2(1200, 640)


func window_title() -> String:
	return U.t("Guerra del Sistema")


func window_icon() -> String:
	return "ui_flag"


func eg() -> Dictionary:
	return GameClient.me.get("endgame", {})


func _signature() -> String:
	return JSON.stringify([eg(), tab, _picking])


func on_player_updated() -> void:
	var s: String = _signature()
	if s != _sig:
		rebuild()


func build() -> void:
	_sig = _signature()
	tab = str(args.get("tab", tab))
	var tabs := UI.hbox(8)
	body.add_child(tabs)
	for t: Array in [["platforms", U.t("Plataformas Orbitales"), "ui_flag"], ["hives", U.t("Colmenas Xeno"), "ui_hunt"], ["titles", U.t("Títulos"), "ui_star"]]:
		var b := UI.button(t[1], "PrimaryButton" if t[0] == tab else "TabButton", t[2], Vector2(0, 48))
		b.name = "Tab_" + str(t[0])
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			args["tab"] = key
			tab = key
			_picking = ""
			rebuild())
		tabs.add_child(b)
	if eg().is_empty():
		body.add_child(UI.label(U.t("Cargando…"), 16, UI.TEXT_DIM))
		return
	match tab:
		"hives":
			_hives()
		"titles":
			_titles()
		_:
			_platforms()


func _mods_text(mods: Dictionary) -> String:
	var parts: Array = []
	for k: String in mods:
		var v: float = float(mods[k]) * 100.0
		parts.append("%s%d%% %s" % ["+" if v >= 0.0 else "−", int(round(absf(v))), CommanderPanel.effect_label(k)])
	return ", ".join(parts)


func _goto(pos: Array) -> void:
	close_window()
	game.show_map()
	game.focus_tile(Vector2(float(pos[0]), float(pos[1])))


func _platforms() -> void:
	var my_tag: String = str(GameClient.me.get("tag", ""))
	var mods: Dictionary = eg().get("platform_mods", {})
	body.add_child(UI.wrap(UI.label(U.t("Cuatro Plataformas rodean el Portal de Salto. Conquístalas con un Asedio contra su guarnición: tu alianza recibe su bono mientras la controle. La Ciudadela permite otorgar títulos."), 14, UI.TEXT_DIM)))
	if not mods.is_empty():
		body.add_child(UI.label(U.t("Bonos activos para ti: %s") % _mods_text(mods), 15, UI.GREEN, "semibold"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	for pl: Dictionary in eg().get("platforms", []):
		var holder: String = str(pl.get("holder", ""))
		var mine: bool = not holder.is_empty() and holder == my_tag
		var card := UI.panel("CardGold" if bool(pl.get("titles", false)) else ("CardHi" if mine else "Card"))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UI.vbox(5)
		card.add_child(v)
		var h := UI.hbox(8)
		h.add_child(UI.icon("ui_flag", 32, UI.GOLD if bool(pl.get("titles", false)) else UI.CYAN))
		var nl := UI.label(str(pl["name"]), 18, UI.TEXT, "bold")
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nl)
		var hl := UI.label((U.t("Tu alianza") if mine else "[%s]" % holder) if not holder.is_empty() else U.t("Libre"), 16, UI.GREEN if mine else (UI.RED if not holder.is_empty() else UI.TEXT_DIM), "bold")
		h.add_child(hl)
		v.add_child(h)
		v.add_child(UI.wrap(UI.label(str(pl.get("desc", "")), 13, UI.TEXT_DIM)))
		v.add_child(UI.label(U.t("Bono: %s") % _mods_text(pl.get("buff", {})), 14, UI.GOLD, "semibold"))
		var g: int = 0
		for k: String in pl.get("garrison", {}):
			g += int(pl["garrison"][k])
		var foot := UI.hbox(8)
		var fl := UI.label(U.t("Guarnición: %s fuerzas") % U.fmt_int(g), 13, UI.TEXT_DIM)
		var sl: float = float(int(pl.get("shield_until", 0)) - GameClient.server_now()) / 1000.0
		if sl > 0.0:
			fl.text += "  ·  " + U.t("Escudo %s") % U.fmt_time(sl)
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(fl)
		var b := UI.button(U.t("Ver en el mapa"), "GhostButton", "ui_map", Vector2(0, 40))
		var pos: Array = pl["pos"]
		b.pressed.connect(func() -> void: _goto(pos))
		foot.add_child(b)
		v.add_child(foot)
		grid.add_child(card)


func _hives() -> void:
	body.add_child(UI.wrap(UI.label(U.t("Las Colmenas Xeno son jefes cooperativos: solo se atacan con un Asedio de alianza y su vida no se recupera mientras sigan recibiendo ataques. Al caer reaparecen a los 20 minutos."), 14, UI.TEXT_DIM)))
	var list := UI.vbox(8)
	body.add_child(scroll_body(list))
	var hs: Array = eg().get("hives", [])
	hs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tier"]) < int(b["tier"]))
	if hs.is_empty():
		list.add_child(UI.label(U.t("No hay Colmenas activas: reaparecerán pronto."), 15, UI.TEXT_MUTED))
	for x: Dictionary in hs:
		var card := UI.panel("Card")
		var h := UI.hbox(12)
		card.add_child(h)
		h.add_child(UI.image(UI.xeno_tex("x24", 5), Vector2(72, 72)))
		var v := UI.vbox(4)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UI.label(U.t("%s · T%d") % [str(x["name"]), int(x["tier"])], 17, Color("ff8fa3"), "bold"))
		var hr := UI.hbox(8)
		var bar := UI.progress(float(x["hp"]), float(x["max_hp"]), UI.RED, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hr.add_child(bar)
		hr.add_child(UI.label("%s / %s" % [U.fmt_num(int(x["hp"])), U.fmt_num(int(x["max_hp"]))], 13, UI.TEXT_DIM))
		v.add_child(hr)
		var kr := UI.hbox(8)
		kr.add_child(UI.label(U.t("Botín:"), 13, UI.GOLD, "bold"))
		var rr := UI.reward_row(x.get("kill", {}), 13)
		rr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kr.add_child(rr)
		v.add_child(kr)
		if int(x.get("my_damage", 0)) > 0:
			v.add_child(UI.label(U.t("Tu daño: %s") % U.fmt_num(int(x["my_damage"])), 13, UI.CYAN))
		h.add_child(v)
		var b := UI.button(U.t("Ver en el mapa"), "PrimaryButton", "ui_map", Vector2(200, 48))
		var pos: Array = x["pos"]
		b.pressed.connect(func() -> void: _goto(pos))
		h.add_child(b)
		list.add_child(card)


func _titles() -> void:
	var holder: String = str(eg().get("citadel_holder", ""))
	var can: bool = bool(eg().get("can_grant", false))
	var top := UI.hbox(10)
	body.add_child(top)
	var tl := UI.wrap(UI.label((U.t("La Ciudadela Orbital está en manos de [%s]: su líder y oficiales otorgan los títulos del sistema.") % holder) if not holder.is_empty() else U.t("Nadie controla la Ciudadela: conquístala para otorgar títulos."), 14, UI.TEXT_DIM))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tl)
	if can:
		top.add_child(UI.label(U.t("Puedes otorgar títulos"), 15, UI.GOLD, "bold"))
	var row := UI.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var list := UI.vbox(6)
	var sc: ScrollContainer = scroll_body(list)
	row.add_child(sc)
	var now: int = GameClient.server_now()
	for t: Dictionary in eg().get("titles", []):
		var pos: bool = bool(t.get("positive", true))
		var card := UI.panel("Chip")
		if str(t["id"]) == _picking:
			card.add_theme_stylebox_override("panel", UI.sb(Color(UI.GOLD, 0.16), UI.GOLD, 10, 2, 6))
		var h := UI.hbox(10)
		card.add_child(h)
		h.add_child(UI.icon("ui_star" if pos else "ui_warning", 28, UI.GOLD if pos else UI.RED))
		var v := UI.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UI.label(str(t["name"]), 16, UI.GOLD if pos else UI.RED, "bold"))
		v.add_child(UI.label(_mods_text(t.get("mods", {})), 13, UI.GREEN if pos else UI.RED))
		var who: String = str(t.get("holder_name", ""))
		var sub: String = (U.t("Lo lleva %s · %s restantes") % [who, U.fmt_time(maxf(0.0, float(int(t["until"]) - now) / 1000.0))]) if not who.is_empty() else U.t("Sin asignar")
		v.add_child(UI.label(sub, 12, UI.TEXT if not who.is_empty() else UI.TEXT_MUTED))
		h.add_child(v)
		if can:
			var tid: String = str(t["id"])
			var cd: float = float(int(t.get("cooldown", 0)) - now) / 1000.0
			var gb := UI.button(U.t("Otorgar") if cd <= 0.0 else U.fmt_time(cd), "GoldButton" if pos else "DangerButton", "", Vector2(130, 42))
			gb.name = "Grant_" + tid
			gb.disabled = cd > 0.0
			gb.pressed.connect(func() -> void:
				_picking = tid
				rebuild())
			h.add_child(gb)
			if not who.is_empty():
				var rb := UI.button(U.t("Retirar"), "GhostButton", "", Vector2(110, 42))
				rb.pressed.connect(func() -> void: send("title_revoke", {"title": tid}, func(_p: Dictionary) -> void:
					game.toast(U.t("Título retirado"), "info")))
				h.add_child(rb)
		list.add_child(card)
	if can and not _picking.is_empty():
		var side := UI.panel("CardHi")
		side.custom_minimum_size.x = 420
		row.add_child(side)
		var sv := UI.vbox(6)
		side.add_child(sv)
		var tname: String = ""
		for t2: Dictionary in eg().get("titles", []):
			if str(t2["id"]) == _picking:
				tname = str(t2["name"])
		sv.add_child(UI.label(U.t("Otorgar %s a…") % tname, 16, UI.GOLD, "bold"))
		var cl := UI.vbox(4)
		sv.add_child(scroll_body(cl))
		for cnd: Dictionary in eg().get("candidates", []):
			var h2 := UI.hbox(8)
			h2.add_child(UI.image(UI.portrait_tex(str(cnd.get("avatar", "p01"))), Vector2(36, 36)))
			var nl := UI.label((("[%s] " % cnd["tag"]) if not str(cnd["tag"]).is_empty() else "") + str(cnd["name"]), 14, UI.TEXT)
			nl.clip_text = true
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h2.add_child(nl)
			h2.add_child(UI.label(U.fmt_num(int(cnd["power"])), 12, UI.TEXT_DIM))
			var pick := UI.button(U.t("Elegir"), "PrimaryButton", "", Vector2(90, 36))
			var pid: String = str(cnd["id"])
			var title_id: String = _picking
			pick.pressed.connect(func() -> void: send("title_grant", {"title": title_id, "player": pid}, func(_p: Dictionary) -> void:
				UI.Sfx.play("reward")
				game.toast(U.t("Título otorgado"), "success")
				_picking = ""
				rebuild()))
			h2.add_child(pick)
			cl.add_child(h2)
