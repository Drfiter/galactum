extends "res://ui/panels/window.gd"
## Árbol de investigación: 5 ramas (Combate, Fuerzas, Economía, Logística y
## Ciencia) con 30 tecnologías. Cada una muestra su nivel, prerrequisitos y
## costo; las bloqueadas indican qué falta.

var _sig: String = ""


func _init() -> void:
	desired_size = Vector2(1240, 660)


func window_title() -> String:
	return U.t("Árbol de investigación")


func window_icon() -> String:
	return "ui_lab"


func _signature() -> String:
	return JSON.stringify([GameClient.me.get("tech", {}), GameClient.queue("research"), GameClient.room_level("lab"), int(GameClient.res("credits") / 1000)])


func on_player_updated() -> void:
	var s: String = _signature()
	if s != _sig:
		rebuild()


func build() -> void:
	_sig = _signature()
	var top := UI.hbox(10)
	body.add_child(top)
	var lab: int = GameClient.room_level("lab")
	top.add_child(UI.label(U.t("Laboratorio Nv %d") % lab, 16, UI.GOLD, "bold"))
	var q: Dictionary = GameClient.queue("research")
	if not q.is_empty():
		top.add_child(UI.label(U.t("Investigando: %s") % str(q.get("label", "")), 15, UI.CYAN, "semibold"))
	top.add_child(UI.spacer())
	top.add_child(UI.label(U.t("Completa los prerrequisitos de cada rama para desbloquear las tecnologías de abajo."), 13, UI.TEXT_DIM))
	var cols := UI.hbox(8)
	var sc: ScrollContainer = scroll_body(cols)
	body.add_child(sc)
	var by_branch: Dictionary = {}
	for t: Dictionary in Catalog.research.get("techs", []):
		var br: String = str(t.get("branch", ""))
		if not by_branch.has(br):
			by_branch[br] = []
		(by_branch[br] as Array).append(t)
	var colors: Array = [Color("ff6680"), Color("ffb347"), Color("5ce08a"), Color("4fa8ff"), Color("c77dff")]
	var i: int = 0
	for br: String in Catalog.research.get("branches", by_branch.keys()):
		var col := UI.panel("Card")
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
		var v := UI.vbox(6)
		col.add_child(v)
		v.add_child(UI.label(U.t(br), 17, colors[i % colors.size()], "bold"))
		var list: Array = by_branch.get(br, [])
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("tier", 0)) < int(b.get("tier", 0)))
		for t: Dictionary in list:
			v.add_child(_tech_card(t, lab, colors[i % colors.size()]))
		i += 1


func _tech_card(t: Dictionary, lab: int, col: Color) -> Control:
	var tid: String = str(t["id"])
	var cur: int = GameClient.tech_level(tid)
	var mx: int = int(t.get("max", 5))
	var card := UI.panel("Chip")
	var v := UI.vbox(2)
	card.add_child(v)
	var name_l := UI.label("%s  %d/%d" % [str(t["name"]), cur, mx], 13, UI.TEXT, "bold")
	name_l.clip_text = true
	v.add_child(name_l)
	var eff: String = str(t.get("label", ""))
	if bool(t.get("pct", true)):
		eff = "+%d%% %s" % [int(round(float(t["per_level"]) * maxi(1, cur) * 100)), eff]
	var el := UI.label(eff, 12, UI.GREEN if cur > 0 else UI.TEXT_DIM)
	el.clip_text = true
	v.add_child(el)
	var missing: Array = []
	var reqs: Dictionary = t.get("requires", {})
	for rid: String in reqs:
		if GameClient.tech_level(rid) < int(reqs[rid]):
			missing.append("%s %d" % [str(Catalog.tech(rid).get("name", rid)), int(reqs[rid])])
	var need_lab: int = maxi(cur + 1, int(t.get("requires_lab", 0)))
	if cur >= mx:
		v.add_child(UI.label(U.t("Completada"), 12, UI.GREEN, "bold"))
		card.add_theme_stylebox_override("panel", UI.sb(Color(col, 0.16), Color(col, 0.7), 10, 1, 5))
	elif not missing.is_empty():
		var ml := UI.wrap(UI.label(U.t("Requiere: %s") % ", ".join(missing), 11, UI.TEXT_MUTED))
		v.add_child(ml)
	else:
		var cost: Dictionary = Catalog.tech_cost(tid, cur + 1)
		var h := UI.hbox(4)
		var b := UI.button(U.t("Investigar"), "PrimaryButton", "", Vector2(0, 34))
		b.add_theme_font_size_override("font_size", 13)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.name = "Research_" + tid
		var reason: String = ""
		if lab < need_lab:
			reason = U.t("Lab Nv %d") % need_lab
		elif not GameClient.queue("research").is_empty():
			reason = U.t("Ocupado")
		b.disabled = not reason.is_empty() or not GameClient.can_afford(cost)
		b.tooltip_text = U.t("Costo: %s") % ", ".join(cost.keys().map(func(k: String) -> String: return "%s %s" % [U.fmt_num(int(cost[k])), Catalog.res_name(k)]))
		b.pressed.connect(func() -> void: send("research", {"tech": tid}, func(_p: Dictionary) -> void:
			UI.Sfx.play("upgrade")
			game.toast(U.t("Investigación iniciada: %s") % str(t["name"]), "success")))
		h.add_child(b)
		if not reason.is_empty():
			h.add_child(UI.label(reason, 11, UI.GOLD, "bold"))
		v.add_child(h)
	return card
