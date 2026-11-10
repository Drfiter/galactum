extends "res://ui/panels/window.gd"
## Inventario: aceleradores, energía, Campo de Distorsión, Salto Warp y cápsulas.


func _init() -> void:
	desired_size = Vector2(980, 600)


func window_title() -> String:
	return U.t("Objetos")


func window_icon() -> String:
	return "ui_inventory"


func on_player_updated() -> void:
	rebuild()


func build() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(scroll_body(grid))
	var any: bool = false
	for it: Dictionary in Catalog.items.get("items", []):
		var qty: int = GameClient.res(str(it["id"]))
		if qty <= 0:
			continue
		any = true
		grid.add_child(_item_card(it, qty))
	if not any:
		body.add_child(UI.label(U.t("No tienes objetos. Se obtienen en misiones, cazas y cápsulas."), 16, UI.TEXT_DIM))


func _item_card(it: Dictionary, qty: int) -> Control:
	var card := UI.panel("Card")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UI.hbox(12)
	card.add_child(h)
	var icon_name: String = UI.res_icon_name(str(it["id"]))
	var icon_box := UI.panel("Chip", UI.icon(icon_name, 44, UI.GOLD if icon_name.begins_with("ui_") else Color.WHITE))
	h.add_child(icon_box)
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label("%s  ×%d" % [it["name"], qty], 16, UI.TEXT, "bold"))
	v.add_child(UI.wrap(UI.label(str(it.get("desc", "")), 13, UI.TEXT_DIM)))
	h.add_child(v)
	var kind: String = str(it.get("kind", ""))
	var b := UI.button(U.t("Usar"), "PrimaryButton", "", Vector2(100, 48))
	var id: String = str(it["id"])
	match kind:
		"speedup":
			b.text = U.t("Acelerar…")
			b.pressed.connect(func() -> void: _choose_queue(id))
		"warp":
			b.pressed.connect(func() -> void:
				close_window()
				game.start_relocation("warp"))
		"shield":
			b.pressed.connect(func() -> void:
				close_window()
				game.use_shield())
		"escape":
			b.pressed.connect(func() -> void:
				close_window()
				game.escape_jump())
		"recruit":
			b.text = U.t("Reclutar…")
			b.pressed.connect(func() -> void:
				close_window()
				game.open_panel("crew", {"tab": "recruit"}))
		"badge":
			b.text = U.t("Tripulación…")
			b.pressed.connect(func() -> void:
				close_window()
				game.open_panel("crew", {"tab": "collection"}))
		"interstellar":
			b.text = U.t("Galaxia…")
			b.pressed.connect(func() -> void:
				close_window()
				game.open_panel("galaxy"))
		_:
			b.pressed.connect(func() -> void: send("use_item", {"item": id}, func(_p: Dictionary) -> void: game.toast(U.t("%s usado") % it["name"], "success")))
	h.add_child(b)
	return card


func _choose_queue(item_id: String) -> void:
	var active: Array = []
	for q: Array in [["build", U.t("Construcción")], ["research", U.t("Investigación")], ["train", U.t("Entrenamiento")], ["heal", U.t("Curación")], ["revive", U.t("Reanimación")]]:
		if not GameClient.queue(q[0]).is_empty():
			active.append(q)
	if active.is_empty():
		game.toast(U.t("No hay temporizadores activos para acelerar"), "warning")
		return
	UI.clear(body)
	body.add_child(UI.label(U.t("¿Qué temporizador quieres acelerar con %s?") % Catalog.item(item_id)["name"], 18, UI.TEXT, "bold"))
	for q: Array in active:
		var job: Dictionary = GameClient.queue(q[0])
		var b := UI.button("%s · %s · %s" % [q[1], job.get("label", ""), U.fmt_time(GameClient.queue_remaining(q[0]))], "Button", "ui_speedup", Vector2(0, 56))
		var qq: String = q[0]
		b.pressed.connect(func() -> void: send("use_item", {"item": item_id, "queue": qq}, func(_p: Dictionary) -> void:
			game.toast(U.t("Temporizador acelerado"), "success")
			rebuild()))
		body.add_child(b)
	var back := UI.button(U.t("Volver"), "GhostButton", "ui_back", Vector2(160, 48))
	back.pressed.connect(rebuild)
	body.add_child(back)
