extends "res://ui/panels/window.gd"
## Cuartel de Alianza: Asedios y refuerzos, gestión (rangos, solicitudes,
## modo de ingreso, salir), Tesorería, Tienda de Alianza y búsqueda/creación de
## alianzas. Si el jugador no tiene alianza solo muestra Buscar y Crear.

var tab: String = "rallies"
var _sig: String = ""
var _results: Array = []
var _query: String = ""
var _searched: bool = false
var _create_tag: LineEdit
var _create_name: LineEdit


func _init() -> void:
	desired_size = Vector2(1180, 650)


func window_title() -> String:
	var hq: Dictionary = hq()
	return U.t("Cuartel de Alianza") + ("  ·  [%s] %s" % [hq.get("tag", ""), hq.get("name", "")] if not str(hq.get("tag", "")).is_empty() else "")


func window_icon() -> String:
	return "ui_alliance"


func hq() -> Dictionary:
	return GameClient.me.get("alliance_hq", {})


func perms() -> Array:
	return hq().get("permissions", [])


func _signature() -> String:
	var h: Dictionary = hq().duplicate()
	h.erase("treasury_log")
	return JSON.stringify([h, GameClient.res("credits"), GameClient.res("bonds"), int(GameClient.server_now() / 5000)])


func on_player_updated() -> void:
	var s: String = _signature()
	if s != _sig:
		rebuild()


func build() -> void:
	_sig = _signature()
	live_refresh = 1.0
	var has: bool = not str(hq().get("tag", "")).is_empty()
	if not has and tab != "create":
		tab = "search"
	tab = str(args.get("tab", tab)) if has or str(args.get("tab", "")) in ["search", "create"] else tab
	var tabs := UI.hbox(6)
	body.add_child(tabs)
	var list: Array = [["search", U.t("Buscar"), "ui_users"], ["create", U.t("Crear"), "ui_plus"]]
	if has:
		list = [["rallies", U.t("Asedios y refuerzos"), "ui_rally"], ["manage", U.t("Gestión") + (" (%d)" % (hq().get("requests", []) as Array).size() if not (hq().get("requests", []) as Array).is_empty() else ""), "ui_crew"],
			["treasury", U.t("Tesorería"), "res_credits"], ["shop", U.t("Tienda"), "res_bonds"]] + list
	for t: Array in list:
		var b := UI.button(t[1], "PrimaryButton" if t[0] == tab else "TabButton", t[2], Vector2(0, 44))
		b.add_theme_font_size_override("font_size", 15)
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			args["tab"] = key
			tab = key
			rebuild())
		tabs.add_child(b)
	tabs.add_child(UI.spacer())
	tabs.add_child(UI.icon("res_bonds", 24))
	tabs.add_child(UI.label(U.fmt_int(GameClient.res("bonds")), 16, Color("7fd1ff"), "bold"))
	match tab:
		"manage":
			_manage()
		"treasury":
			_treasury()
		"shop":
			_shop()
		"search":
			_search()
		"create":
			_create()
		_:
			_rallies()


func tick() -> void:
	if tab == "rallies":
		var s: String = _signature()
		if s != _sig:
			rebuild()


# ---------------------------------------------------------------- Asedios y refuerzos

func _rallies() -> void:
	var h: Dictionary = hq()
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add_child(UI.label(U.t("Asedios de la Alianza"), 17, UI.CYAN, "bold"))
	var rl: Array = h.get("rallies", [])
	if rl.is_empty():
		left.add_child(UI.wrap(UI.label(U.t("No hay Asedios abiertos. Para abrir uno (rango R3 o superior) toca una nave enemiga en el mapa y elige «Abrir Asedio». Tus aliados tendrán un tiempo para sumar tropas y la flota conjunta atacará con tus bonos."), 14, UI.TEXT_MUTED)))
	for r: Dictionary in rl:
		var card := UI.panel("CardRed" if r["state"] == "gathering" else "Card")
		var v := UI.vbox(4)
		card.add_child(v)
		var top := UI.hbox(8)
		top.add_child(UI.icon("ui_rally", 26, UI.RED))
		top.add_child(UI.label(U.t("%s → %s") % [str(r["leader"]), str(r["target"])], 16, UI.TEXT, "bold"))
		top.add_child(UI.spacer())
		var left_s: float = float(int(r["launch_ts"]) - GameClient.server_now()) / 1000.0
		top.add_child(UI.label(U.t("Despega en %s") % U.fmt_time(left_s) if r["state"] == "gathering" else U.t("En marcha"), 15, UI.GOLD, "bold"))
		v.add_child(top)
		v.add_child(UI.progress(float(r["troops"]), float(maxi(1, int(r["capacity"]))), UI.RED, 10))
		var names: Array = (r.get("participants", []) as Array).map(func(x: Dictionary) -> String: return "%s (%d)" % [x["name"], int(x["troops"])])
		v.add_child(UI.wrap(UI.label(U.t("%d/%d tropas · %s") % [int(r["troops"]), int(r["capacity"]), ", ".join(names)], 13, UI.TEXT_DIM)))
		if r["state"] == "gathering":
			var ah := UI.hbox(8)
			if not bool(r.get("joined", false)):
				var jb := UI.button(U.t("Sumar tropas"), "DangerButton", "ui_rally", Vector2(200, 44))
				var rr: Dictionary = r
				jb.pressed.connect(func() -> void:
					close_window()
					game.open_panel("fleet", {"mission": "rally_join", "entity": rr}))
				ah.add_child(jb)
			if bool(r.get("mine", false)):
				var cb := UI.button(U.t("Cancelar"), "GhostButton", "", Vector2(140, 44))
				var rid: String = str(r["id"])
				cb.pressed.connect(func() -> void: send("rally_cancel", {"rally_id": rid}))
				ah.add_child(cb)
			v.add_child(ah)
		left.add_child(card)
	var right := UI.panel("CardHi")
	right.custom_minimum_size.x = 420
	row.add_child(right)
	var rv := UI.vbox(8)
	right.add_child(rv)
	rv.add_child(UI.label(U.t("Refuerzos"), 17, UI.CYAN, "bold"))
	var here: Array = h.get("reinforcements_here", [])
	var cap: int = int(h.get("reinforce_capacity", 600))
	var tot: int = 0
	for f: Dictionary in here:
		tot += int(f["troops"])
	rv.add_child(UI.label(U.t("En tu nave: %d / %d tropas aliadas") % [tot, cap], 15, UI.TEXT, "semibold"))
	for f: Dictionary in here:
		rv.add_child(UI.label("•  %s: %d" % [str(f["from"]), int(f["troops"])], 14, UI.GREEN))
	rv.add_child(UI.separator())
	rv.add_child(UI.label(U.t("Tus refuerzos enviados"), 15, UI.TEXT, "semibold"))
	var mine: Array = h.get("my_reinforcements", [])
	if mine.is_empty():
		rv.add_child(UI.wrap(UI.label(U.t("Para reforzar a un aliado toca su nave en el mapa y elige «Enviar refuerzos». Tus tropas defenderán su nave y ganarás Bonos."), 13, UI.TEXT_MUTED)))
	for f: Dictionary in mine:
		var hh := UI.hbox(8)
		hh.add_child(UI.label(U.t("%s: %d (%s)") % [str(f["to"]), int(f["troops"]), U.t("estacionados") if f["state"] == "stationed" else U.t("en camino")], 14, UI.TEXT))
		hh.add_child(UI.spacer())
		var fid: String = str(f["id"])
		var bb := UI.button(U.t("Retirar"), "GhostButton", "", Vector2(110, 38))
		bb.pressed.connect(func() -> void: send("recall", {"fleet_id": fid}))
		hh.add_child(bb)
		rv.add_child(hh)


# ---------------------------------------------------------------- Gestión

func _manage() -> void:
	var h: Dictionary = hq()
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.vbox(8)
	left.custom_minimum_size.x = 400
	row.add_child(left)
	var my: String = str(h.get("rank", ""))
	var card := UI.panel("CardHi")
	var cv := UI.vbox(6)
	card.add_child(cv)
	cv.add_child(UI.label(U.t("Tu rango: %s (%s)") % [my, U.t(_rank_name(my))], 17, UI.GOLD, "bold"))
	cv.add_child(UI.wrap(UI.label(U.t("Permisos: %s") % ", ".join((perms() as Array).map(func(x: String) -> String: return U.t(_perm_name(x)))), 13, UI.TEXT_DIM)))
	cv.add_child(UI.label(U.t("Líder: %s · %d/%d miembros") % [str(h.get("leader", "")), _member_count(), int(h.get("max_members", 30))], 14, UI.TEXT))
	var mh := UI.hbox(6)
	mh.add_child(UI.label(U.t("Ingreso:"), 14, UI.TEXT_DIM))
	for m: Array in [["open", U.t("Abierta")], ["request", U.t("Solicitud")], ["invite", U.t("Invitación")]]:
		var mb := UI.button(m[1], "PrimaryButton" if str(h.get("mode", "")) == m[0] else "TabButton", "", Vector2(0, 38))
		mb.disabled = not perms().has("set_mode")
		var mode: String = m[0]
		mb.pressed.connect(func() -> void: send("alliance_mode", {"mode": mode}))
		mh.add_child(mb)
	cv.add_child(mh)
	var lb := UI.button(U.t("Salir de la Alianza"), "DangerButton", "ui_back", Vector2(0, 44))
	lb.pressed.connect(func() -> void: send("alliance_leave", {}, func(_p: Dictionary) -> void:
		game.toast(U.t("Saliste de la Alianza"), "info")
		args["tab"] = "search"
		tab = "search"
		rebuild()))
	cv.add_child(lb)
	left.add_child(card)
	var reqs: Array = h.get("requests", [])
	left.add_child(UI.label(U.t("Solicitudes de ingreso (%d)") % reqs.size(), 16, UI.CYAN, "bold"))
	for rq: Dictionary in reqs:
		var rh := UI.hbox(6)
		rh.add_child(UI.label("%s · %s" % [str(rq["name"]), U.t("Poder %s") % U.fmt_num(int(rq["power"]))], 14, UI.TEXT))
		rh.add_child(UI.spacer())
		var pid: String = str(rq["id"])
		var ab := UI.button(U.t("Aceptar"), "GreenButton", "", Vector2(100, 36))
		ab.disabled = not perms().has("accept")
		ab.pressed.connect(func() -> void: send("alliance_accept", {"player": pid}))
		rh.add_child(ab)
		var xb := UI.button(U.t("Rechazar"), "GhostButton", "", Vector2(100, 36))
		xb.disabled = not perms().has("accept")
		xb.pressed.connect(func() -> void: send("alliance_reject", {"player": pid}))
		rh.add_child(xb)
		left.add_child(rh)
	var right := UI.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(UI.label(U.t("Miembros y rangos"), 16, UI.CYAN, "bold"))
	var list := UI.vbox(6)
	right.add_child(scroll_body(list))
	var members: Array = GameClient.me.get("alliance", {}).get("members", [])
	var mine_n: int = int(my.substr(1)) if my.length() == 2 else 0
	for m: Dictionary in members:
		var row2 := UI.panel("Chip")
		var mh2 := UI.hbox(6)
		row2.add_child(mh2)
		var rank: String = str(m.get("rank", "R2"))
		mh2.add_child(UI.label(rank, 15, UI.GOLD, "bold"))
		var nl := UI.label(str(m["name"]), 14, UI.TEXT, "semibold")
		nl.custom_minimum_size.x = 160
		nl.clip_text = true
		mh2.add_child(nl)
		mh2.add_child(UI.label(U.fmt_num(int(m.get("power", 0))), 13, UI.TEXT_DIM))
		mh2.add_child(UI.spacer())
		var pid2: String = str(m["id"])
		var rn: int = int(rank.substr(1))
		if pid2 != GameClient.player_id and perms().has("promote") and rn < mine_n:
			if rn + 1 < mine_n:
				var up := UI.button("▲", "GhostButton", "", Vector2(44, 34))
				up.tooltip_text = U.t("Ascender a R%d") % (rn + 1)
				up.pressed.connect(func() -> void: send("alliance_rank", {"player": pid2, "rank": "R%d" % (rn + 1)}))
				mh2.add_child(up)
			if rn > 1:
				var dn := UI.button("▼", "GhostButton", "", Vector2(44, 34))
				dn.tooltip_text = U.t("Bajar a R%d") % (rn - 1)
				dn.pressed.connect(func() -> void: send("alliance_rank", {"player": pid2, "rank": "R%d" % (rn - 1)}))
				mh2.add_child(dn)
		if pid2 != GameClient.player_id and perms().has("kick") and rn < mine_n:
			var kb := UI.button(U.t("Expulsar"), "GhostButton", "", Vector2(100, 34))
			kb.pressed.connect(func() -> void: send("alliance_kick", {"player": pid2}))
			mh2.add_child(kb)
		if pid2 != GameClient.player_id and perms().has("transfer"):
			var tb := UI.button(U.t("Hacer líder"), "GhostButton", "", Vector2(120, 34))
			tb.pressed.connect(func() -> void: send("alliance_transfer", {"player": pid2}))
			mh2.add_child(tb)
		list.add_child(row2)


func _member_count() -> int:
	return (GameClient.me.get("alliance", {}).get("members", []) as Array).size()


func _rank_name(rank: String) -> String:
	for r: Dictionary in Catalog.alliance.get("ranks", []):
		if str(r["id"]) == rank:
			return str(r["name"])
	return rank


func _perm_name(perm: String) -> String:
	return str({"invite": "invitar", "accept": "aceptar", "kick": "expulsar", "promote": "ascender", "set_mode": "modo de ingreso",
		"treasury": "Tesorería", "rally": "abrir Asedios", "rally_join": "sumarse a Asedios", "mark_target": "marcar objetivo", "transfer": "transferir liderazgo"}.get(perm, perm))


# ---------------------------------------------------------------- Tesorería

func _treasury() -> void:
	var h: Dictionary = hq()
	var tr: Dictionary = h.get("treasury", {})
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	left.add_child(UI.label(U.t("Fondos de la Alianza"), 17, UI.CYAN, "bold"))
	var lim: int = int(h.get("withdraw_limit", 0))
	left.add_child(UI.wrap(UI.label(U.t("Dona recursos y gana 1 Bono por cada 10. Retirar: %s.") % (U.t("sin límite") if lim < 0 else (U.t("hasta %s por día (hoy %s)") % [U.fmt_int(lim), U.fmt_int(int(h.get("withdrawn_today", 0)))] if lim > 0 else U.t("tu rango no puede retirar"))), 13, UI.TEXT_DIM)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(scroll_body(grid))
	for res: String in Catalog.alliance.get("treasury_resources", []):
		var c := UI.panel("Chip")
		var hh := UI.hbox(6)
		c.add_child(hh)
		hh.add_child(UI.icon(UI.res_icon_name(res), 26))
		var nl := UI.label("%s %s" % [Catalog.res_name(res), U.fmt_num(int(tr.get(res, 0)))], 13, UI.TEXT, "semibold")
		nl.custom_minimum_size.x = 170
		nl.clip_text = true
		hh.add_child(nl)
		var amount: int = 1000
		var db := UI.button(U.t("Donar 1K"), "GreenButton", "", Vector2(100, 34))
		db.disabled = GameClient.res(res) < amount
		var r_id: String = res
		db.pressed.connect(func() -> void: send("treasury_donate", {"res": r_id, "amount": amount}, func(_p: Dictionary) -> void: UI.Sfx.play("collect")))
		hh.add_child(db)
		if perms().has("treasury"):
			var wb := UI.button(U.t("Retirar 1K"), "GhostButton", "", Vector2(100, 34))
			wb.disabled = int(tr.get(res, 0)) < amount
			wb.pressed.connect(func() -> void: send("treasury_withdraw", {"res": r_id, "amount": amount}))
			hh.add_child(wb)
		grid.add_child(c)
	var right := UI.panel("Card")
	right.custom_minimum_size.x = 400
	row.add_child(right)
	var rv := UI.vbox(4)
	right.add_child(rv)
	rv.add_child(UI.label(U.t("Registro de auditoría"), 16, UI.CYAN, "bold"))
	var log: Array = h.get("treasury_log", [])
	if log.is_empty():
		rv.add_child(UI.label(U.t("Sin movimientos todavía."), 14, UI.TEXT_MUTED))
	for i: int in range(log.size() - 1, -1, -1):
		var e: Dictionary = log[i]
		var t: String = Time.get_time_string_from_unix_time(int(int(e["ts"]) / 1000)).substr(0, 5)
		rv.add_child(UI.label("%s  %s (%s) %s %s %s" % [t, str(e["who"]), str(e["rank"]), U.t("donó") if e["kind"] == "donate" else U.t("retiró"), U.fmt_num(int(e["amount"])), Catalog.res_name(str(e["res"]))], 12, UI.GREEN if e["kind"] == "donate" else UI.GOLD))


# ---------------------------------------------------------------- Tienda

func _shop() -> void:
	var h: Dictionary = hq()
	var bought: Dictionary = h.get("shop_bought", {})
	body.add_child(UI.wrap(UI.label(U.t("Gana Bonos de Alianza ayudando (Ayuda Mutua), donando a la Tesorería, participando en Asedios y enviando refuerzos."), 14, UI.TEXT_DIM)))
	var ab := UI.button(U.t("Ayudar a todos (%d)") % int(h.get("help_open", 0)), "GreenButton", "ui_help", Vector2(260, 46))
	ab.disabled = int(h.get("help_open", 0)) <= 0
	ab.pressed.connect(func() -> void: send("help_all", {}, func(p: Dictionary) -> void:
		UI.Sfx.play("collect")
		game.toast(U.t("Ayudaste %d veces: +%s Bonos") % [int(p.get("helped", 0)), U.fmt_int(int(p.get("bonds", 0)))], "success")))
	body.add_child(ab)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(scroll_body(grid))
	for e: Dictionary in Catalog.alliance.get("shop", []):
		var item: Dictionary = Catalog.item(str(e["id"]))
		var card := UI.panel("Card")
		card.custom_minimum_size = Vector2(340, 0)
		var hh := UI.hbox(10)
		card.add_child(hh)
		hh.add_child(UI.icon(UI.res_icon_name(str(e["id"])), 46))
		var v := UI.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UI.label(str(item.get("name", e["id"])), 15, UI.TEXT, "bold"))
		var left_n: int = int(e.get("daily", 1)) - int(bought.get(e["id"], 0))
		v.add_child(UI.label(U.t("%s Bonos · quedan %d hoy") % [U.fmt_int(int(e["cost"])), left_n], 13, Color("7fd1ff")))
		hh.add_child(v)
		var bb := UI.button(U.t("Comprar"), "PrimaryButton", "", Vector2(110, 42))
		bb.disabled = left_n <= 0 or GameClient.res("bonds") < int(e["cost"])
		var iid: String = str(e["id"])
		bb.pressed.connect(func() -> void: send("ally_shop_buy", {"item": iid}, func(_p: Dictionary) -> void:
			UI.Sfx.play("reward")
			game.toast(U.t("Compraste %s") % str(item.get("name", iid)), "success")))
		hh.add_child(bb)
		grid.add_child(card)


# ---------------------------------------------------------------- Buscar y crear

func _search() -> void:
	var invites: Array = hq().get("invites", [])
	for inv: Dictionary in invites:
		var ih := UI.hbox(8)
		ih.add_child(UI.label(U.t("Invitación de [%s] %s") % [str(inv["tag"]), str(inv["name"])], 15, UI.GOLD, "bold"))
		var tg: String = str(inv["tag"])
		var jb := UI.button(U.t("Aceptar"), "GreenButton", "", Vector2(110, 38))
		jb.pressed.connect(func() -> void: send("alliance_join", {"tag": tg}, func(_p: Dictionary) -> void: rebuild()))
		ih.add_child(jb)
		body.add_child(ih)
	var sh := UI.hbox(8)
	body.add_child(sh)
	var q := LineEdit.new()
	q.placeholder_text = U.t("Etiqueta o nombre…")
	q.text = _query
	q.custom_minimum_size = Vector2(320, 44)
	sh.add_child(q)
	var sb := UI.button(U.t("Buscar"), "PrimaryButton", "ui_users", Vector2(140, 44))
	sb.pressed.connect(func() -> void:
		_query = q.text
		_do_search())
	sh.add_child(sb)
	var list := UI.vbox(6)
	body.add_child(scroll_body(list))
	if not _searched:
		_searched = true
		_do_search()
	for a: Dictionary in _results:
		var card := UI.panel("Chip")
		var h := UI.hbox(10)
		card.add_child(h)
		h.add_child(UI.label("[%s]" % str(a["tag"]), 17, Color(str(a.get("color", "#ffffff"))), "bold"))
		var v := UI.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UI.label(str(a["name"]), 15, UI.TEXT, "bold"))
		v.add_child(UI.label(U.t("Nv %d · %d/%d miembros · Poder %s · %s") % [int(a["level"]), int(a["members"]), int(a["max"]), U.fmt_num(int(a["power"])), _mode_name(str(a["mode"]))], 12, UI.TEXT_DIM))
		h.add_child(v)
		if bool(a.get("mine", false)):
			h.add_child(UI.label(U.t("Tu alianza"), 14, UI.GREEN, "bold"))
		elif bool(a.get("requested", false)):
			h.add_child(UI.label(U.t("Solicitud enviada"), 14, UI.GOLD, "bold"))
		else:
			var tg2: String = str(a["tag"])
			var jb2 := UI.button(U.t("Unirse") if str(a["mode"]) == "open" or bool(a.get("invited", false)) else U.t("Solicitar"), "GreenButton", "", Vector2(130, 40))
			jb2.disabled = str(a["mode"]) == "invite" and not bool(a.get("invited", false))
			jb2.pressed.connect(func() -> void: send("alliance_join", {"tag": tg2}, func(p: Dictionary) -> void:
				game.toast(U.t("Te uniste a [%s]") % tg2 if bool(p.get("joined", false)) else U.t("Solicitud enviada a [%s]") % tg2, "success")
				_results = []
				_searched = false
				rebuild()))
			h.add_child(jb2)
		list.add_child(card)


func _mode_name(mode: String) -> String:
	return {"open": U.t("ingreso abierto"), "request": U.t("por solicitud"), "invite": U.t("solo invitación")}.get(mode, mode)


func _do_search() -> void:
	GameClient.intent("alliance_search", {"query": _query}, func(ok: bool, payload: Dictionary) -> void:
		if ok and is_inside_tree():
			_results = payload.get("results", [])
			rebuild())


func _create() -> void:
	var cost: Dictionary = Catalog.alliance.get("create_cost", {})
	var card := UI.panel("CardHi")
	var v := UI.vbox(10)
	card.add_child(v)
	v.add_child(UI.label(U.t("Fundar una Alianza"), 18, UI.CYAN, "bold"))
	v.add_child(UI.label(U.t("Costo: %s Créditos y %s Materia Oscura. Quedas como líder (R5).") % [U.fmt_int(int(cost.get("credits", 0))), U.fmt_int(int(cost.get("dark_matter", 0)))], 14, UI.TEXT_DIM))
	_create_tag = LineEdit.new()
	_create_tag.placeholder_text = U.t("Etiqueta (3 letras, p. ej. ORN)")
	_create_tag.max_length = 3
	_create_tag.custom_minimum_size = Vector2(360, 44)
	v.add_child(_create_tag)
	_create_name = LineEdit.new()
	_create_name.placeholder_text = U.t("Nombre de la alianza")
	_create_name.max_length = 28
	_create_name.custom_minimum_size = Vector2(360, 44)
	v.add_child(_create_name)
	var b := UI.button(U.t("Fundar"), "GoldButton", "ui_alliance", Vector2(220, 50))
	b.pressed.connect(func() -> void: send("alliance_create", {"tag": _create_tag.text, "name": _create_name.text, "mode": "request"}, func(p: Dictionary) -> void:
		UI.Sfx.play("reward")
		game.toast(U.t("¡Fundaste la Alianza [%s]!") % str(p.get("tag", "")), "success")
		args["tab"] = "manage"
		tab = "manage"
		rebuild()))
	v.add_child(b)
	body.add_child(card)
