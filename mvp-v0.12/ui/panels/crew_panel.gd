extends "res://ui/panels/window.gd"
## Tripulación: elegir tripulantes activos, colección de los 45 personajes y
## reclutamiento en la Cantina (con revelado por rareza).

var tab: String = "active"
var _results: Array = []


func _init() -> void:
	desired_size = Vector2(1180, 650)


func window_title() -> String:
	return U.t("Tripulación")


func window_icon() -> String:
	return "ui_crew"


var _sig: String = ""


func _signature() -> String:
	var c: Dictionary = cv()
	return JSON.stringify([c.get("owned", []), c.get("active", []), c.get("free", false), c.get("slots", 0), GameClient.res("dark_matter"), GameClient.res("recruit_ticket"), GameClient.res("insignia")])


func on_player_updated() -> void:
	var s: String = _signature()
	if _results.is_empty() and s != _sig:
		rebuild()


func build() -> void:
	_sig = _signature()
	tab = str(args.get("tab", tab))
	var tabs := UI.hbox(8)
	body.add_child(tabs)
	for t: Array in [["active", U.t("Tripulación activa"), "ui_crew"], ["collection", U.t("Colección"), "ui_users"], ["recruit", U.t("Reclutar"), "ui_star"]]:
		var b := UI.button(t[1], "PrimaryButton" if t[0] == tab else "TabButton", t[2], Vector2(0, 48))
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			args["tab"] = key
			tab = key
			_results = []
			rebuild())
		tabs.add_child(b)
	if not _results.is_empty():
		_reveal()
		return
	match tab:
		"collection":
			_collection()
		"recruit":
			_recruit()
		_:
			_active()


func cv() -> Dictionary:
	return GameClient.me.get("crew", {})


func _def(cid: String) -> Dictionary:
	for c: Dictionary in Catalog.crew.get("crew", []):
		if str(c["id"]) == cid:
			return c
	return {}


func _rarity(rid: String) -> Dictionary:
	for r: Dictionary in Catalog.crew.get("rarities", []):
		if str(r["id"]) == rid:
			return r
	return {}


func _owned(cid: String) -> Dictionary:
	for o: Dictionary in cv().get("owned", []):
		if str(o["id"]) == cid:
			return o
	return {}


func _stat_label(stat: String) -> String:
	return U.t(str(Catalog.crew.get("stat_labels", {}).get(stat, stat)))


func _card(cid: String, size: Vector2, show_action: bool, reveal: Dictionary = {}) -> Control:
	var d: Dictionary = _def(cid)
	var o: Dictionary = _owned(cid)
	var rr: Dictionary = _rarity(str(d.get("rarity", "common")))
	if not reveal.is_empty():
		# Recién reclutado: el estado del jugador aún no llega, se arma desde el resultado.
		var stars: int = int(reveal.get("stars", 1))
		o = {"stars": stars, "bonus": float(Catalog.crew.get("base_bonus", 0.03)) * float(rr.get("mult", 1.0)) * (1.0 + float(Catalog.crew.get("star_bonus", 0.2)) * (stars - 1))}
	var col := Color(str(rr.get("color", "#9aa6c8")))
	var card := PanelContainer.new()
	var sbx := UI.sb(Color(0.06, 0.09, 0.2, 0.95) if not o.is_empty() else Color(0.04, 0.05, 0.1, 0.9), col if not o.is_empty() else Color("2a3458"), 12, 3, 8)
	if not o.is_empty() and str(d.get("rarity", "")) in ["epic", "legendary"]:
		sbx.shadow_color = Color(col, 0.45)
		sbx.shadow_size = 10
	card.add_theme_stylebox_override("panel", sbx)
	card.custom_minimum_size = size
	var v := UI.vbox(3, BoxContainer.ALIGNMENT_CENTER)
	card.add_child(v)
	var img := UI.image(UI.portrait_tex(cid), Vector2(size.x - 34, size.x - 34))
	img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if o.is_empty():
		img.modulate = Color(0.15, 0.17, 0.25)
	v.add_child(img)
	var pname: String = str(Catalog.portraits.get(cid, {}).get("name", cid))
	var n := UI.label(pname if not o.is_empty() else "???", 14, UI.TEXT if not o.is_empty() else UI.TEXT_MUTED, "bold")
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	v.add_child(n)
	var rl := UI.label(str(rr.get("name", "")), 12, col, "bold")
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rl)
	if not o.is_empty():
		var stars: String = ""
		for i: int in range(int(Catalog.crew.get("max_stars", 5))):
			stars += "★" if i < int(o.get("stars", 1)) else "☆"
		var sl := UI.label(stars, 13, UI.GOLD)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sl)
		var bl := UI.wrap(UI.label("+%.1f%% %s" % [float(o.get("bonus", 0.0)) * 100.0, _stat_label(str(d.get("stat", "")))], 12, UI.GREEN, "semibold"))
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(bl)
		if o.has("level"):
			# Nivel (EXP), rango y grado (Insignias).
			var ll := UI.label(U.t("Nv %d · %s · Grado %d") % [int(o["level"]), U.t(str(o.get("rank", ""))), int(o.get("grade", 1))], 12, UI.CYAN, "semibold")
			ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ll.clip_text = true
			v.add_child(ll)
			var xb := ProgressBar.new()
			xb.show_percentage = false
			xb.custom_minimum_size = Vector2(0, 6)
			xb.max_value = maxi(1, int(o.get("exp_next", 1)))
			xb.value = int(o.get("exp", 0)) if int(o.get("exp_next", 0)) > 0 else xb.max_value
			v.add_child(xb)
		if show_action:
			var active: bool = (cv().get("active", []) as Array).has(cid)
			var in_fleet: bool = not str(o.get("fleet", "")).is_empty()
			var b := UI.button(U.t("En flota") if in_fleet else (U.t("Retirar") if active else U.t("Activar")), "GhostButton" if active or in_fleet else "GreenButton", "", Vector2(0, 36))
			b.add_theme_font_size_override("font_size", 14)
			b.disabled = in_fleet
			b.tooltip_text = U.t("Un tripulante trabaja en una sala o viaja en una flota, no ambas")
			b.pressed.connect(func() -> void: send("crew_assign", {"crew_id": cid, "on": not active}))
			v.add_child(b)
			var cost: int = int(o.get("promote_cost", 0))
			if cost > 0:
				var pb := UI.button(U.t("Grado +1 (%d)") % cost, "GoldButton", "ui_insignia", Vector2(0, 34))
				pb.add_theme_font_size_override("font_size", 13)
				pb.disabled = GameClient.res("insignia") < cost
				pb.tooltip_text = U.t("Sube el grado con Insignias de Mando (tienes %d)") % GameClient.res("insignia")
				pb.pressed.connect(func() -> void: send("crew_promote", {"crew_id": cid}, func(_p: Dictionary) -> void:
					UI.Sfx.play("upgrade")
					game.toast(U.t("%s sube a grado %d") % [U.t(pname), int(o.get("grade", 1)) + 1], "success")))
				v.add_child(pb)
	return card


func _active() -> void:
	var c: Dictionary = cv()
	var slots: int = int(c.get("slots", 2))
	var active: Array = c.get("active", [])
	body.add_child(UI.wrap(UI.label(U.t("Elige a los tripulantes que viajan contigo: sus pasivas se suman a tu flota y a tu economía. Gestión de Tripulación da más espacios; la Cantina recluta nuevos tripulantes."), 15, UI.TEXT_DIM)))
	var row := UI.hbox(14, BoxContainer.ALIGNMENT_CENTER)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	for i: int in range(slots):
		if i < active.size():
			row.add_child(_card(str(active[i]), Vector2(180, 300), true))
		else:
			var empty := UI.panel("Card")
			empty.custom_minimum_size = Vector2(180, 300)
			var ev := UI.vbox(8, BoxContainer.ALIGNMENT_CENTER)
			empty.add_child(ev)
			var ic := UI.icon("ui_plus", 54, UI.TEXT_MUTED)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			ev.add_child(ic)
			var el := UI.wrap(UI.label(U.t("Espacio libre: activa un tripulante en Colección"), 13, UI.TEXT_MUTED), 150)
			el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ev.add_child(el)
			row.add_child(empty)
	if GameClient.room_level("crew") <= 0:
		var lock := UI.panel("Chip")
		lock.custom_minimum_size = Vector2(180, 300)
		var lv := UI.vbox(8, BoxContainer.ALIGNMENT_CENTER)
		lock.add_child(lv)
		var li := UI.icon("ui_build", 46, UI.GOLD)
		li.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		lv.add_child(li)
		var ll := UI.wrap(UI.label(U.t("Construye Gestión de Tripulación (Fase 2) para más espacios"), 13, UI.GOLD), 150)
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.add_child(ll)
		row.add_child(lock)
	var mods: Dictionary = c.get("mods", {})
	var sum := UI.panel("Chip")
	var sh := UI.flow(16, 4)
	sum.add_child(sh)
	sh.add_child(UI.label(U.t("Pasivas activas:"), 15, UI.TEXT, "bold"))
	for k: String in mods:
		sh.add_child(UI.label("+%.1f%% %s" % [float(mods[k]) * 100.0, _stat_label(k)], 15, UI.GREEN, "semibold"))
	body.add_child(sum)


func _collection() -> void:
	var owned_n: int = (cv().get("owned", []) as Array).size()
	body.add_child(UI.label(U.t("%d de %d tripulantes reclutados · toca «Activar» para llevarlos contigo") % [owned_n, (Catalog.crew.get("crew", []) as Array).size()], 15, UI.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(scroll_body(grid))
	var order: Array = (Catalog.crew.get("crew", []) as Array).duplicate()
	var rank: Dictionary = {"legendary": 0, "epic": 1, "rare": 2, "common": 3}
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa: bool = not _owned(str(a["id"])).is_empty()
		var ob: bool = not _owned(str(b["id"])).is_empty()
		if oa != ob:
			return oa
		return int(rank[a["rarity"]]) < int(rank[b["rarity"]]))
	for d: Dictionary in order:
		grid.add_child(_card(str(d["id"]), Vector2(148, 330), true))


func _recruit() -> void:
	var c: Dictionary = cv()
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.panel("CardHi")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var lv := UI.vbox(10)
	left.add_child(lv)
	var cant: int = int(c.get("cantina", 0))
	lv.add_child(UI.title(U.t("Cantina Nv %d") % cant if cant > 0 else U.t("Reclutamiento"), 22, Color("ff8fe8")))
	lv.add_child(UI.wrap(UI.label(U.t("En la Cantina se reclutan los 45 tripulantes. Cada nivel de la Cantina mejora la suerte y da un reclutamiento gratis al día. Los repetidos suben estrellas (+20% de pasiva cada una)."), 14, UI.TEXT_DIM)))
	var od: Dictionary = c.get("odds", {})
	var f := UI.hbox(10)
	for rr: Dictionary in Catalog.crew.get("rarities", []):
		var chip := UI.panel("Chip")
		var cvb := UI.vbox(0, BoxContainer.ALIGNMENT_CENTER)
		chip.add_child(cvb)
		chip.custom_minimum_size = Vector2(130, 0)
		var a := UI.label(str(rr["name"]), 14, Color(str(rr["color"])), "bold")
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cvb.add_child(a)
		var b := UI.label("%.1f%%" % float(od.get(rr["id"], 0.0)), 20, UI.TEXT, "bold")
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cvb.add_child(b)
		f.add_child(chip)
	lv.add_child(f)
	if cant <= 0:
		lv.add_child(UI.label(U.t("Construye la Cantina (Fase 2) para mejorar las probabilidades y obtener reclutamientos gratis."), 14, UI.GOLD, "semibold"))
	var right := UI.vbox(10)
	right.custom_minimum_size.x = 380
	row.add_child(right)
	if cant > 0:
		var free: bool = bool(c.get("free", false))
		var fb := UI.button(U.t("Reclutamiento gratis") if free else U.t("Gratis en %s") % U.fmt_duration_short(maxf(0.0, float(int(c.get("free_ts", 0)) - GameClient.server_now()) / 1000.0)), "GreenButton", "ui_gift", Vector2(0, 60))
		fb.disabled = not free
		fb.pressed.connect(func() -> void: _do_recruit({"method": "free"}))
		right.add_child(fb)
	var tickets: int = GameClient.res("recruit_ticket")
	var tb := UI.button(U.t("Usar Contrato de Tripulante (×%d)") % tickets, "PrimaryButton", "ui_crew", Vector2(0, 60))
	tb.disabled = tickets <= 0
	tb.pressed.connect(func() -> void: _do_recruit({"method": "ticket"}))
	right.add_child(tb)
	var c1: int = int(Catalog.crew.get("recruit_cost_mo", 150))
	var b1 := UI.button(U.t("Reclutar ×1  ·  %d MO") % c1, "GoldButton", "res_dark_matter", Vector2(0, 60))
	b1.disabled = GameClient.res("dark_matter") < c1
	b1.pressed.connect(func() -> void: _do_recruit({"method": "mo", "count": 1}))
	right.add_child(b1)
	var c10: int = int(Catalog.crew.get("recruit10_cost_mo", 1350))
	var b10 := UI.button(U.t("Reclutar ×10  ·  %s MO") % U.fmt_int(c10), "GoldButton", "res_dark_matter", Vector2(0, 60))
	b10.disabled = GameClient.res("dark_matter") < c10
	b10.pressed.connect(func() -> void: _do_recruit({"method": "mo", "count": 10}))
	right.add_child(b10)
	right.add_child(UI.wrap(UI.label(U.t("×10 garantiza al menos un tripulante Raro o superior."), 13, UI.TEXT_MUTED)))


func _do_recruit(params: Dictionary) -> void:
	var before: Dictionary = {}
	for o: Dictionary in cv().get("owned", []):
		before[str(o["id"])] = int(o.get("stars", 1))
	send("recruit", params, func(p: Dictionary) -> void:
		_results = p.get("results", [])
		# "Nuevo" = no lo tenías antes de este reclutamiento (primera aparición).
		var seen: Dictionary = {}
		for r: Dictionary in _results:
			var cid: String = str(r["id"])
			r["new"] = not before.has(cid) and not seen.has(cid)
			seen[cid] = true
		if int(p.get("refund", 0)) > 0:
			game.toast(U.t("Repetidos al máximo de estrellas: +%s Créditos") % U.fmt_int(int(p["refund"])), "info")
		rebuild())


## Revelado de las cartas reclutadas (volteo por rareza).
func _reveal() -> void:
	var title := UI.title(U.t("¡Nuevos tripulantes!"), 26, UI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var grid := GridContainer.new()
	grid.columns = mini(5, _results.size())
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(grid)
	body.add_child(center)
	var big: bool = _results.size() == 1
	for i: int in range(_results.size()):
		var r: Dictionary = _results[i]
		var holder := Control.new()
		var sz := Vector2(200, 330) if big else Vector2(150, 236)
		holder.custom_minimum_size = sz
		grid.add_child(holder)
		var card: Control = _card(str(r["id"]), sz, false, r)
		card.size = sz
		card.pivot_offset = sz / 2.0
		holder.add_child(card)
		if bool(r.get("new", false)):
			var nb := UI.badge(U.t("¡NUEVO!"), UI.GREEN)
			nb.position = Vector2(sz.x - 70, -8)
			nb.z_index = 2
			holder.add_child(nb)
		card.scale = Vector2(0.0, 1.0)
		var tw := create_tween()
		tw.tween_interval(0.12 + i * 0.12)
		tw.tween_property(card, "scale", Vector2(1.08, 1.08), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2.ONE, 0.1)
	var ok := UI.button(U.t("¡Genial!"), "GoldButton", "ui_check", Vector2(240, 56))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func() -> void:
		_results = []
		rebuild())
	body.add_child(ok)
