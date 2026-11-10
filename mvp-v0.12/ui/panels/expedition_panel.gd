extends "res://ui/panels/window.gd"
## Expediciones: campaña PvE por capítulos. Se elige capítulo y etapa, se arma
## un equipo de hasta 5 tripulantes y se combate (el combate se reproduce en la
## ventana de batalla). Modo Élite, barrido con Licencia 6 y cofres por estrellas.

var _sig: String = ""
var chapter: int = 0
var stage_idx: int = 0
var elite: bool = false
var team: Array = []
var _team_init: bool = false
var _busy: bool = false


func _init() -> void:
	desired_size = Vector2(1260, 670)


func window_title() -> String:
	return U.t("Expediciones")


func window_icon() -> String:
	return "ui_target"


func ev() -> Dictionary:
	return GameClient.me.get("expedition", {})


func chapters() -> Array:
	return Catalog.expeditions.get("chapters", [])


func _signature() -> String:
	var e: Dictionary = ev().duplicate()
	e.erase("fuel_next")
	return JSON.stringify([e, GameClient.me.get("crew", {}).get("owned", []), GameClient.res("dark_matter"), chapter, stage_idx, elite, team])


func on_player_updated() -> void:
	var s: String = _signature()
	if s != _sig and not _busy:
		rebuild()


func extra_header(h: HBoxContainer) -> void:
	var fuel_box := UI.hbox(6)
	fuel_box.name = "FuelBox"
	h.add_child(fuel_box)


func _owned() -> Dictionary:
	var out: Dictionary = {}
	for o: Dictionary in GameClient.me.get("crew", {}).get("owned", []):
		out[str(o["id"])] = o
	return out


func _crew_power(cid: String) -> int:
	return int(ev().get("units", {}).get(cid, {}).get("power", 0))


func _auto_team() -> Array:
	var owned: Dictionary = _owned()
	var ids: Array = owned.keys().filter(func(cid: String) -> bool: return str(owned[cid].get("fleet", "")).is_empty())
	ids.sort_custom(func(a: String, b: String) -> bool: return _crew_power(a) > _crew_power(b))
	return ids.slice(0, int(Catalog.expeditions.get("team_max", 5)))


func _first_open() -> void:
	# Abre en el primer capítulo/etapa sin ganar.
	var stars: Dictionary = ev().get("stars", {})
	for ci: int in range(chapters().size()):
		if not str(ev().get("chapters", [])[ci].get("locked", "")).is_empty():
			break
		chapter = ci
		var sts: Array = chapters()[ci]["stages"]
		stage_idx = sts.size() - 1
		for si: int in range(sts.size()):
			if int(stars.get(sts[si]["id"], 0)) <= 0:
				stage_idx = si
				return


func build() -> void:
	if ev().is_empty():
		body.add_child(UI.label(U.t("Cargando…"), 16, UI.TEXT_DIM))
		return
	if not _team_init:
		_team_init = true
		_first_open()
		var saved: Array = ev().get("team", [])
		var owned: Dictionary = _owned()
		team = saved.filter(func(cid: String) -> bool: return owned.has(cid) and str(owned[cid].get("fleet", "")).is_empty())
		if team.is_empty():
			team = _auto_team()
	_sig = _signature()
	_fuel_header()
	var row := UI.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	row.add_child(_chapter_list())
	row.add_child(_chapter_view())
	row.add_child(_stage_detail())


func _fuel_header() -> void:
	var box: HBoxContainer = header.find_child("FuelBox", false, false) as HBoxContainer
	if box == null:
		return
	UI.clear(box)
	var e: Dictionary = ev()
	box.add_child(UI.icon("res_energy", 26, UI.GOLD))
	var txt: String = U.t("Combustible %d/%d") % [int(e.get("fuel", 0)), int(e.get("fuel_max", 120))]
	if int(e.get("fuel_next", 0)) > 0:
		txt += "  (+1 " + U.t("en %s") % U.fmt_time(maxf(0.0, float(int(e["fuel_next"]) - GameClient.server_now()) / 1000.0)) + ")"
	box.add_child(UI.label(txt, 16, UI.GOLD, "bold"))
	var fc: Dictionary = Catalog.expeditions.get("fuel", {})
	var rb := UI.button(U.t("+%d (%d MO)") % [int(fc.get("refill_amount", 60)), int(fc.get("refill_mo", 50))], "GhostButton", "res_dark_matter", Vector2(0, 40))
	rb.name = "Refill"
	rb.tooltip_text = U.t("Recargas restantes hoy: %d") % int(e.get("refills_left", 0))
	rb.disabled = int(e.get("refills_left", 0)) <= 0 or GameClient.res("dark_matter") < int(fc.get("refill_mo", 50))
	rb.pressed.connect(func() -> void: send("exp_refill", {}, func(_p: Dictionary) -> void:
		game.toast(U.t("Combustible recargado"), "success")))
	box.add_child(rb)
	box.add_child(UI.spacer(false, Vector2(16, 0)))


func _chapter_list() -> Control:
	var col := UI.vbox(6)
	col.custom_minimum_size.x = 250
	var mode := UI.hbox(4)
	for m: Array in [[false, U.t("Normal")], [true, U.t("Élite")]]:
		var b := UI.button(m[1], ("GoldButton" if m[0] else "PrimaryButton") if elite == m[0] else "TabButton", "", Vector2(0, 42))
		b.name = "Mode_" + ("elite" if m[0] else "normal")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val: bool = m[0]
		b.pressed.connect(func() -> void:
			elite = val
			rebuild())
		mode.add_child(b)
	col.add_child(mode)
	var info: Array = ev().get("chapters", [])
	for ci: int in range(chapters().size()):
		var ch: Dictionary = chapters()[ci]
		var lock: String = str(info[ci].get("elite_locked" if elite else "locked", "")) if ci < info.size() else ""
		var b := Button.new()
		b.name = "Chapter_%d" % ci
		b.theme_type_variation = "PrimaryButton" if ci == chapter else "TabButton"
		b.custom_minimum_size = Vector2(0, 66)
		b.focus_mode = Control.FOCUS_NONE
		var v := UI.vbox(0, BoxContainer.ALIGNMENT_CENTER)
		UI.full_rect(v)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := UI.label(U.t("Cap. %d · %s") % [ci + 1, str(ch["name"])], 14, UI.TEXT if lock.is_empty() else UI.TEXT_MUTED, "bold")
		t.clip_text = true
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(t)
		var sub := UI.label((("★ %d/%d" % [_stars_in(ci), (ch["stages"] as Array).size() * 3]) if lock.is_empty() else lock), 13, UI.GOLD if lock.is_empty() else UI.TEXT_MUTED)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sub)
		b.add_child(v)
		var idx: int = ci
		b.pressed.connect(func() -> void:
			chapter = idx
			stage_idx = 0
			rebuild())
		col.add_child(b)
	return col


func _stars_in(ci: int) -> int:
	var book: Dictionary = ev().get("elite" if elite else "stars", {})
	var n: int = 0
	for st: Dictionary in chapters()[ci]["stages"]:
		n += int(book.get(st["id"], 0))
	return n


func _stars_text(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(3 - n)


func _stage_locked(ci: int, si: int) -> String:
	var info: Array = ev().get("chapters", [])
	var lock: String = str(info[ci].get("elite_locked" if elite else "locked", "")) if ci < info.size() else ""
	if not lock.is_empty():
		return lock
	if si > 0:
		var prev: String = str(chapters()[ci]["stages"][si - 1]["id"])
		if int(ev().get("elite" if elite else "stars", {}).get(prev, 0)) <= 0:
			return U.t("Gana la etapa anterior")
	return ""


func _chapter_view() -> Control:
	var ch: Dictionary = chapters()[chapter]
	var card := UI.panel("CardHi" if not elite else "CardGold")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(8)
	card.add_child(v)
	v.add_child(UI.label(U.t("Capítulo %d: %s") % [chapter + 1, str(ch["name"])] + ("  ·  " + U.t("ÉLITE") if elite else ""), 20, UI.GOLD, "title"))
	v.add_child(UI.wrap(UI.label(str(ch.get("desc", "")), 14, UI.TEXT_DIM)))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var book: Dictionary = ev().get("elite" if elite else "stars", {})
	var sts: Array = ch["stages"]
	for si: int in range(sts.size()):
		var st: Dictionary = sts[si]
		var lock: String = _stage_locked(chapter, si)
		var b := Button.new()
		b.name = "Stage_" + str(st["id"])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.theme_type_variation = "PrimaryButton" if si == stage_idx else "TabButton"
		var col: Color = UI.RED if bool(st.get("boss", false)) else (UI.GOLD if elite else UI.CYAN)
		if si != stage_idx:
			b.add_theme_stylebox_override("normal", UI.sb(Color(col, 0.10), Color(col, 0.55 if lock.is_empty() else 0.2), 12, 2, 6))
		var bv := UI.vbox(2, BoxContainer.ALIGNMENT_CENTER)
		UI.full_rect(bv)
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l1 := UI.label(str(st["id"]) + ("  " + U.t("JEFE") if bool(st.get("boss", false)) else ""), 17, col if lock.is_empty() else UI.TEXT_MUTED, "title")
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(l1)
		var l2 := UI.label(str(st["name"]), 13, UI.TEXT if lock.is_empty() else UI.TEXT_MUTED)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(l2)
		var l3 := UI.label(_stars_text(int(book.get(st["id"], 0))) if lock.is_empty() else U.t("Bloqueada"), 16 if lock.is_empty() else 12, UI.GOLD if lock.is_empty() else UI.TEXT_MUTED)
		l3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(l3)
		for c: Control in [l1, l2, l3]:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bv)
		var idx: int = si
		b.pressed.connect(func() -> void:
			stage_idx = idx
			rebuild())
		grid.add_child(b)
	v.add_child(UI.spacer())
	if not elite:
		v.add_child(UI.label(U.t("Cofres del capítulo (★ %d/%d)") % [_stars_in(chapter), sts.size() * 3], 15, UI.CYAN, "bold"))
		var chest_row := UI.hbox(8)
		var claimed: Array = ev().get("chests", [])
		var chests: Array = ch.get("chests", [])
		for i: int in range(chests.size()):
			var c := UI.panel("Chip")
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cv := UI.vbox(4)
			c.add_child(cv)
			var need: int = int(chests[i]["stars"])
			cv.add_child(UI.label("★ %d" % need, 15, UI.GOLD, "bold"))
			cv.add_child(UI.reward_row(chests[i]["reward"], 13))
			var key: String = "%d:%d" % [chapter, i]
			if claimed.has(key):
				cv.add_child(UI.label(U.t("Abierto"), 13, UI.GREEN, "semibold"))
			else:
				var cb := UI.button(U.t("Abrir"), "GoldButton", "ui_chest", Vector2(0, 38))
				cb.name = "Chest_%d" % i
				cb.disabled = _stars_in(chapter) < need
				var ci: int = chapter
				var ii: int = i
				var rw: Dictionary = chests[i]["reward"]
				cb.pressed.connect(func() -> void: send("exp_chest", {"chapter": ci, "index": ii}, func(_p: Dictionary) -> void:
					game.show_reward(rw, U.t("Cofre de Expedición"))))
				cv.add_child(cb)
			chest_row.add_child(c)
		v.add_child(chest_row)
	else:
		v.add_child(UI.wrap(UI.label(U.t("Élite: enemigos más fuertes, premios dobles y %d intentos diarios por etapa.") % int(Catalog.expeditions.get("elite", {}).get("daily_attempts", 3)), 13, UI.TEXT_MUTED)))
	return card


func _enemy_power(st: Dictionary) -> int:
	var m: float = float(Catalog.expeditions.get("elite", {}).get("power_mult", 1.6)) if elite else 1.0
	var t: float = 0.0
	for e: Dictionary in st.get("enemies", []):
		t += sqrt(float(e["hp"]) * m * float(e["atk"]) * m)
	return int(round(t))


func _stage_detail() -> Control:
	var st: Dictionary = chapters()[chapter]["stages"][stage_idx]
	var card := UI.panel("Card")
	card.custom_minimum_size.x = 440
	var v := UI.vbox(7)
	card.add_child(v)
	var h := UI.hbox(8)
	var tl := UI.label(U.t("Etapa %s · %s") % [str(st["id"]), str(st["name"])], 18, UI.TEXT, "bold")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tl)
	var ep: int = _enemy_power(st)
	h.add_child(UI.label(U.t("Poder %s") % U.fmt_num(ep), 15, UI.RED, "bold"))
	v.add_child(h)
	var foes := UI.hbox(6)
	for e: Dictionary in st.get("enemies", []):
		var fv := UI.vbox(0)
		var img := UI.image(UI.xeno_tex(str(e["species"]), int(e["level"])), Vector2(64, 64) if bool(e.get("boss", false)) else Vector2(50, 50))
		fv.add_child(img)
		fv.add_child(UI.label(_role_name(str(e["role"])), 11, UI.TEXT_MUTED))
		fv.tooltip_text = "%s · %s" % [str(Catalog.species_by_id.get(str(e["species"]), {}).get("name", "")), _role_name(str(e["role"]))]
		foes.add_child(fv)
	v.add_child(foes)
	v.add_child(UI.separator())
	# Equipo.
	var th := UI.hbox(8)
	var tp: int = 0
	for cid: String in team:
		tp += _crew_power(cid)
	var tlab := UI.label(U.t("Equipo (%d/%d)") % [team.size(), int(Catalog.expeditions.get("team_max", 5))], 15, UI.CYAN, "bold")
	tlab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(tlab)
	th.add_child(UI.label(U.t("Poder %s") % U.fmt_num(tp), 15, UI.GREEN if tp >= ep else UI.GOLD, "bold"))
	var auto := UI.button(U.t("Mejor equipo"), "GhostButton", "ui_crew", Vector2(0, 36))
	auto.name = "AutoTeam"
	auto.pressed.connect(func() -> void:
		team = _auto_team()
		rebuild())
	th.add_child(auto)
	v.add_child(th)
	var picker := UI.flow(6, 6)
	var owned: Dictionary = _owned()
	var ids: Array = owned.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return _crew_power(a) > _crew_power(b))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = 150
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(picker)
	for cid: String in ids:
		picker.add_child(_crew_chip(cid, owned[cid]))
	v.add_child(sc)
	# Premios.
	var book: Dictionary = ev().get("elite" if elite else "stars", {})
	var first: bool = int(book.get(st["id"], 0)) <= 0
	var mult: int = int(Catalog.expeditions.get("elite", {}).get("reward_mult", 2)) if elite else 1
	var rw: Dictionary = {}
	for k: String in st.get("first" if first else "repeat", {}):
		rw[k] = int(st["first" if first else "repeat"][k]) * mult
	v.add_child(UI.label(U.t("Primera victoria") if first else U.t("Premio por repetir"), 13, UI.TEXT_DIM, "semibold"))
	v.add_child(UI.reward_row(rw, 14))
	# Acciones.
	var lock: String = _stage_locked(chapter, stage_idx)
	var fc: Dictionary = Catalog.expeditions.get("fuel", {})
	var cost: int = int(fc.get("cost_elite" if elite else "cost_normal", 6))
	var tries: int = int(Catalog.expeditions.get("elite", {}).get("daily_attempts", 3)) - int(ev().get("elite_tries", {}).get(st["id"], 0))
	var ah := UI.hbox(6)
	var fight := UI.button(U.t("Combatir (−%d Combustible)") % cost, "GoldButton" if elite else "PrimaryButton", "ui_attack", Vector2(0, 52))
	fight.name = "Fight"
	fight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var reason: String = lock
	if reason.is_empty() and team.is_empty():
		reason = U.t("Elige tu equipo")
	elif reason.is_empty() and int(ev().get("fuel", 0)) < cost:
		reason = U.t("Sin Combustible")
	elif reason.is_empty() and elite and tries <= 0:
		reason = U.t("Sin intentos hoy")
	fight.disabled = not reason.is_empty()
	var sid: String = str(st["id"])
	fight.pressed.connect(func() -> void: _fight(sid))
	ah.add_child(fight)
	var stars_here: int = int(book.get(st["id"], 0))
	for times: int in [1, 5]:
		var sb := UI.button(U.t("Barrido ×%d") % times, "GhostButton", "ui_speed", Vector2(0, 52))
		sb.name = "Sweep_%d" % times
		sb.disabled = stars_here < 3 or not bool(ev().get("auto_battle", false)) or int(ev().get("fuel", 0)) < cost * times or (elite and tries < times)
		sb.tooltip_text = U.t("Auto-batalla: requiere Licencia de Comandante 6 y 3 estrellas en la etapa")
		var tt: int = times
		sb.pressed.connect(func() -> void: send("exp_sweep", {"stage": sid, "elite": elite, "times": tt}, func(p: Dictionary) -> void:
			game.show_reward(p.get("reward", {}), U.t("Barrido ×%d completado") % tt)))
		ah.add_child(sb)
	v.add_child(ah)
	var foot: String = reason
	if foot.is_empty():
		foot = U.t("Intentos Élite hoy: %d") % tries if elite else ""
	if not bool(ev().get("auto_battle", false)):
		foot += ("  ·  " if not foot.is_empty() else "") + U.t("Barrido con Licencia de Comandante 6")
	if not foot.is_empty():
		v.add_child(UI.wrap(UI.label(foot, 12, UI.GOLD if not reason.is_empty() else UI.TEXT_MUTED)))
	return card


func _role_name(role: String) -> String:
	return U.t(str(Catalog.crew.get("roles", {}).get(role, role)))


func _crew_chip(cid: String, o: Dictionary) -> Control:
	var busy: bool = not str(o.get("fleet", "")).is_empty()
	var on: bool = team.has(cid)
	var b := Button.new()
	b.name = "Pick_" + cid
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.button_pressed = on
	b.disabled = busy
	b.custom_minimum_size = Vector2(76, 96)
	b.theme_type_variation = "TabButton"
	if on:
		var sel := UI.sb(Color(UI.GOLD, 0.22), UI.GOLD, 12, 3, 4)
		for st: String in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sel)
	b.tooltip_text = "%s · %s · Nv %d · %s" % [str(Catalog.portraits.get(cid, {}).get("name", cid)), _role_name(str(ev().get("units", {}).get(cid, {}).get("role", ""))), int(o.get("level", 1)), U.t("en una flota") if busy else U.t("Poder %s") % U.fmt_num(_crew_power(cid))]
	var v := UI.vbox(0, BoxContainer.ALIGNMENT_CENTER)
	UI.full_rect(v)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img := UI.image(UI.portrait_tex(cid), Vector2(52, 52))
	img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if busy:
		img.modulate = Color(0.5, 0.5, 0.55)
	v.add_child(img)
	var l := UI.label(U.t("Nv %d") % int(o.get("level", 1)), 12, UI.TEXT, "bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	var pw := UI.label(U.fmt_num(_crew_power(cid)), 11, UI.GOLD)
	pw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pw)
	b.add_child(v)
	b.toggled.connect(func(pressed: bool) -> void:
		if pressed and not team.has(cid):
			if team.size() >= int(Catalog.expeditions.get("team_max", 5)):
				game.toast(U.t("Máximo %d tripulantes por equipo") % int(Catalog.expeditions.get("team_max", 5)), "error")
			else:
				team.append(cid)
		elif not pressed:
			team.erase(cid)
		rebuild())
	return b


func _fight(stage_id: String) -> void:
	_busy = true
	GameClient.intent("exp_battle", {"stage": stage_id, "elite": elite, "crew": team}, func(ok: bool, payload: Dictionary) -> void:
		_busy = false
		if not ok:
			game.toast(str(payload.get("message", U.t("Acción rechazada"))), "error")
			return
		game.open_panel("expedition_battle", {"result": payload}))
