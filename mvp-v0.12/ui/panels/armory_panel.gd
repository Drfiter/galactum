extends "res://ui/panels/window.gd"
## Armería: equipo del Comandante (6 ranuras), forja y mejora de los 90 equipos
## y los 150 materiales con su refinado. Se abre desde la sala Armería o desde
## la ventana del Comandante.

var tab: String = "gear"
var slot_filter: String = "weapon"
var _sig: String = ""


func _init() -> void:
	desired_size = Vector2(1180, 650)


func window_title() -> String:
	return U.t("Armería")


func window_icon() -> String:
	return "ui_attack"


func gv() -> Dictionary:
	return GameClient.me.get("gear", {})


func _signature() -> String:
	return JSON.stringify([gv(), GameClient.res("credits"), GameClient.room_level("armory")])


func on_player_updated() -> void:
	var s: String = _signature()
	if s != _sig:
		rebuild()


func build() -> void:
	_sig = _signature()
	tab = str(args.get("tab", tab))
	var tabs := UI.hbox(8)
	body.add_child(tabs)
	for t: Array in [["gear", U.t("Equipo del Comandante"), "ui_star"], ["forge", U.t("Forja"), "ui_build"], ["materials", U.t("Materiales (%d)") % (gv().get("materials", {}) as Dictionary).size(), "ui_cargo"]]:
		var b := UI.button(t[1], "PrimaryButton" if t[0] == tab else "TabButton", t[2], Vector2(0, 48))
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			args["tab"] = key
			tab = key
			rebuild())
		tabs.add_child(b)
	tabs.add_child(UI.spacer())
	tabs.add_child(UI.label(U.t("Armería Nv %d · forja hasta escalón %d") % [GameClient.room_level("armory"), int(gv().get("tier_max", 0))], 15, UI.GOLD, "bold"))
	match tab:
		"forge":
			_forge()
		"materials":
			_materials()
		_:
			_gear()


func _slot_name(slot: String) -> String:
	for s: Dictionary in Catalog.armory.get("slots", []):
		if str(s["id"]) == slot:
			return U.t(str(s["name"]))
	return slot


func _set_name(set_id: String) -> String:
	for s: Dictionary in Catalog.armory.get("sets", []):
		if str(s["id"]) == set_id:
			return U.t(str(s["name"]))
	return set_id


func _stats_text(eq: Dictionary, lvl: int) -> String:
	var step: float = float(Catalog.armory.get("level_step", 0.25))
	var parts: Array = []
	for k: String in eq.get("stats", {}):
		parts.append("+%.1f%% %s" % [float(eq["stats"][k]) * (1.0 + step * (maxi(1, lvl) - 1)) * 100.0, _effect(k)])
	return " · ".join(parts)


func _effect(k: String) -> String:
	var labels: Dictionary = {
		"attack": U.t("ataque de fuerzas"), "defense": U.t("defensa de fuerzas"), "hp": U.t("vida de fuerzas"),
		"pve_damage": U.t("daño contra Xenoformas"), "march_speed": U.t("velocidad de flota"), "capture_resist": U.t("resistencia a la captura"),
		"production": U.t("producción"), "gather_speed": U.t("velocidad de minería"), "load": U.t("capacidad de carga"),
		"research_speed": U.t("velocidad de investigación"), "crew_power": U.t("pasivas de tripulantes"),
	}
	return str(labels.get(k, k))


func _gear() -> void:
	var g: Dictionary = gv()
	var owned: Dictionary = g.get("owned", {})
	var equipped: Dictionary = g.get("equipped", {})
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	row.add_child(grid)
	for s: Dictionary in Catalog.armory.get("slots", []):
		var slot: String = str(s["id"])
		var card := UI.panel("Card")
		card.custom_minimum_size = Vector2(250, 150)
		var v := UI.vbox(4)
		card.add_child(v)
		v.add_child(UI.label(_slot_name(slot), 13, UI.TEXT_MUTED, "bold"))
		var eq_id: String = str(equipped.get(slot, ""))
		if eq_id.is_empty():
			v.add_child(UI.label(U.t("Vacío"), 17, UI.TEXT_MUTED, "bold"))
			var fb := UI.button(U.t("Forjar o equipar"), "GhostButton", "ui_build", Vector2(0, 40))
			fb.pressed.connect(func() -> void:
				slot_filter = slot
				args["tab"] = "forge"
				tab = "forge"
				rebuild())
			v.add_child(fb)
		else:
			var eq: Dictionary = Catalog.equipment_by_id.get(eq_id, {})
			var lvl: int = int(owned.get(eq_id, 1))
			var col := Color(str((Catalog.armory["grades"] as Array)[int(eq["tier"]) - 1]["color"]))
			v.add_child(UI.label("%s  Nv %d" % [U.t(str(eq["name"])), lvl], 17, col, "bold"))
			v.add_child(UI.wrap(UI.label(_stats_text(eq, lvl), 13, UI.GREEN)))
			v.add_child(UI.label(U.t("Conjunto %s · escalón %d") % [_set_name(str(eq["set"])), int(eq["tier"])], 12, UI.TEXT_DIM))
			var ub := UI.button(U.t("Quitar"), "GhostButton", "", Vector2(0, 36))
			ub.pressed.connect(func() -> void: send("armory_unequip", {"slot": slot}))
			v.add_child(ub)
		grid.add_child(card)
	var right := UI.panel("CardHi")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var rv := UI.vbox(8)
	right.add_child(rv)
	rv.add_child(UI.label(U.t("Bonos del equipo"), 17, UI.CYAN, "bold"))
	var mods: Dictionary = g.get("mods", {})
	if mods.is_empty():
		rv.add_child(UI.wrap(UI.label(U.t("Sin equipo todavía. Caza xenoformas y mina asteroides para conseguir materiales, y forja tu primer equipo."), 14, UI.TEXT_MUTED)))
	for k: String in mods:
		rv.add_child(UI.label("+%.1f%% %s" % [float(mods[k]) * 100.0, _effect(k)], 15, UI.GREEN, "semibold"))
	rv.add_child(UI.separator())
	var sb: Array = Catalog.armory.get("set_bonus", [])
	rv.add_child(UI.wrap(UI.label(U.t("Bono de conjunto: con 3 piezas del mismo conjunto +%.0f%% de ataque por escalón; con las 6, además +%.0f%% de vida por escalón.") % [float(sb[0]["per_tier"]) * 100.0, float(sb[1]["per_tier"]) * 100.0], 13, UI.TEXT_DIM)))


func _forge() -> void:
	var g: Dictionary = gv()
	var owned: Dictionary = g.get("owned", {})
	var equipped: Dictionary = g.get("equipped", {})
	var tmax: int = int(g.get("tier_max", 0))
	var filt := UI.hbox(6)
	body.add_child(filt)
	for s: Dictionary in Catalog.armory.get("slots", []):
		var sid: String = str(s["id"])
		var b := UI.button(U.t(str(s["name"])), "PrimaryButton" if sid == slot_filter else "TabButton", "", Vector2(0, 40))
		b.pressed.connect(func() -> void:
			slot_filter = sid
			rebuild())
		filt.add_child(b)
	var list := UI.vbox(8)
	body.add_child(scroll_body(list))
	for eq: Dictionary in Catalog.armory.get("equipment", []):
		if str(eq["slot"]) != slot_filter:
			continue
		var eq_id: String = str(eq["id"])
		var lvl: int = int(owned.get(eq_id, 0))
		var tier: int = int(eq["tier"])
		var col := Color(str((Catalog.armory["grades"] as Array)[tier - 1]["color"]))
		var card := UI.panel("Card")
		var h := UI.hbox(12)
		card.add_child(h)
		var v := UI.vbox(3)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UI.label("%s  ·  %s" % [U.t(str(eq["name"])), U.t("Nv %d") % lvl if lvl > 0 else U.t("no forjado")], 16, col if tier <= tmax else UI.TEXT_MUTED, "bold"))
		v.add_child(UI.label(_stats_text(eq, maxi(1, lvl)) + "   " + U.t("(escalón %d, %s)") % [tier, _set_name(str(eq["set"]))], 13, UI.GREEN if tier <= tmax else UI.TEXT_MUTED))
		var cost: Dictionary = {}
		if lvl == 0:
			cost = (eq["recipe"] as Dictionary).duplicate()
			cost["credits"] = int(eq["credits"])
		elif lvl < int(Catalog.armory.get("max_level", 5)):
			cost = {}
			for k: String in eq["recipe"]:
				cost[k] = int(eq["recipe"][k]) * lvl
			cost["credits"] = int(Catalog.armory.get("upgrade_credits", 900)) * tier * lvl
		if not cost.is_empty():
			v.add_child(_cost_row(cost))
		h.add_child(v)
		var actions := UI.vbox(6)
		if tier > tmax:
			actions.add_child(UI.label(U.t("Armería Nv %d") % _armory_level_for(tier), 14, UI.GOLD, "bold"))
		elif lvl == 0:
			var fb := UI.button(U.t("Forjar"), "PrimaryButton", "ui_build", Vector2(150, 44))
			fb.disabled = not _affordable(cost)
			fb.name = "Forge_" + eq_id
			fb.pressed.connect(func() -> void: send("armory_forge", {"equipment": eq_id}, func(_p: Dictionary) -> void:
				UI.Sfx.play("upgrade")
				game.toast(U.t("Forjaste %s") % U.t(str(eq["name"])), "success")))
			actions.add_child(fb)
		else:
			if not cost.is_empty():
				var ub := UI.button(U.t("Mejorar"), "GoldButton", "ui_build", Vector2(150, 40))
				ub.disabled = not _affordable(cost)
				ub.pressed.connect(func() -> void: send("armory_upgrade", {"equipment": eq_id}, func(_p: Dictionary) -> void: UI.Sfx.play("upgrade")))
				actions.add_child(ub)
			var on: bool = str(equipped.get(str(eq["slot"]), "")) == eq_id
			var eb := UI.button(U.t("Equipado") if on else U.t("Equipar"), "GhostButton" if on else "GreenButton", "", Vector2(150, 40))
			eb.disabled = on
			eb.pressed.connect(func() -> void: send("armory_equip", {"equipment": eq_id}))
			actions.add_child(eb)
		h.add_child(actions)
		list.add_child(card)


func _armory_level_for(tier: int) -> int:
	var table: Array = Catalog.armory.get("tier_by_armory_level", [])
	for i: int in range(table.size()):
		if int(table[i]) >= tier:
			return i
	return table.size() - 1


func _affordable(cost: Dictionary) -> bool:
	for k: String in cost:
		if GameClient.res(k) < int(cost[k]):
			return false
	return true


func _cost_row(cost: Dictionary) -> Control:
	var f := UI.flow(12, 4)
	for k: String in cost:
		var have: int = GameClient.res(k)
		var ok: bool = have >= int(cost[k])
		var h := UI.hbox(4)
		h.add_child(UI.icon(UI.res_icon_name(k), 22, _mat_color(k)))
		h.add_child(UI.label("%s %s/%s" % [Catalog.res_name(k) if k.begins_with("mat_") else "", U.fmt_num(have), U.fmt_num(int(cost[k]))], 12, UI.TEXT if ok else UI.RED))
		f.add_child(h)
	return f


func _mat_color(id: String) -> Color:
	var m: Dictionary = Catalog.materials_by_id.get(id, {})
	if m.is_empty():
		return Color.WHITE
	return Color(str((Catalog.armory["grades"] as Array)[int(m["grade"]) - 1]["color"]))


func _materials() -> void:
	var mats: Dictionary = gv().get("materials", {})
	var n_in: int = int(Catalog.armory.get("refine_in", 4))
	body.add_child(UI.wrap(UI.label(U.t("Las cazas sueltan el material de cada especie (calidad = nivel de la xenoforma) y la minería, los materiales de forja. Refina %d de una calidad en 1 de la siguiente.") % n_in, 14, UI.TEXT_DIM)))
	if mats.is_empty():
		body.add_child(UI.label(U.t("Aún no tienes materiales."), 16, UI.TEXT_MUTED))
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(scroll_body(grid))
	var ids: Array = mats.keys()
	ids.sort()
	for mid: String in ids:
		var m: Dictionary = Catalog.materials_by_id.get(mid, {})
		if m.is_empty():
			continue
		var card := UI.panel("Chip")
		card.custom_minimum_size.x = 360
		var h := UI.hbox(8)
		card.add_child(h)
		h.add_child(UI.icon("ui_material", 30, _mat_color(mid)))
		var v := UI.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nl := UI.label(U.t(str(m["name"])), 14, _mat_color(mid), "bold")
		nl.clip_text = true
		v.add_child(nl)
		v.add_child(UI.label("×%d · %s" % [int(mats[mid]), U.t("caza") if str(m.get("source", "")) == "hunt" else U.t("minería")], 12, UI.TEXT_DIM))
		h.add_child(v)
		if int(m["grade"]) < 5:
			var rb := UI.button(U.t("Refinar"), "GhostButton", "", Vector2(100, 38))
			rb.disabled = int(mats[mid]) < n_in
			rb.pressed.connect(func() -> void: send("armory_refine", {"material": mid, "times": 1}))
			h.add_child(rb)
		grid.add_child(card)
