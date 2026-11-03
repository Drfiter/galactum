extends "res://ui/panels/window.gd"
## Tienda: Materia Oscura (moneda opaca), objetos, recursos y la tabla de
## precios que relaciona todo con dólares. Las compras con dinero son simuladas.

var tab: String = "offers"


func _init() -> void:
	desired_size = Vector2(1140, 650)


func window_title() -> String:
	return U.t("Tienda Galáctica")


func window_icon() -> String:
	return "ui_shop"


func extra_header(h: HBoxContainer) -> void:
	var chip := UI.panel("Chip")
	var hh := UI.hbox(6)
	chip.add_child(hh)
	hh.add_child(UI.icon("res_dark_matter", 26))
	var l := UI.label(U.fmt_int(GameClient.res("dark_matter")), 18, Color("e2b8ff"), "bold")
	l.name = "MO"
	hh.add_child(l)
	h.add_child(chip)


func on_player_updated() -> void:
	var l: Label = header.find_child("MO", true, false)
	if l != null:
		l.text = U.fmt_int(GameClient.res("dark_matter"))


func build() -> void:
	tab = str(args.get("tab", tab))
	var tabs := UI.hbox(8)
	body.add_child(tabs)
	for t: Array in [["offers", U.t("Materia Oscura"), "res_dark_matter"], ["items", U.t("Objetos"), "ui_inventory"], ["resources", U.t("Recursos"), "ui_cargo"], ["prices", U.t("Tabla de precios"), "ui_reports"]]:
		var b := UI.button(t[1], "PrimaryButton" if t[0] == tab else "TabButton", t[2], Vector2(0, 48))
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			args["tab"] = key
			tab = key
			rebuild())
		tabs.add_child(b)
	match tab:
		"items":
			_items()
		"resources":
			_resources()
		"prices":
			_prices()
		_:
			_offers()


func _usd(v: float) -> String:
	return U.t("US$ %.2f") % v


func _offers() -> void:
	var note := UI.panel("Chip")
	note.add_child(UI.wrap(UI.label(U.t("La Materia Oscura es la moneda premium: todo en Galactum tiene un precio en MO y 1 USD = %d MO. Compras SIMULADAS para la demo: no se realiza ningún cobro.") % int(Catalog.shop.get("usd_to_mo", 100)), 14, UI.TEXT_DIM)))
	body.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(scroll_body(grid))
	var bought: Array = GameClient.me.get("shop", {}).get("packs_bought", [])
	for pk: Dictionary in Catalog.shop.get("packs", []):
		var once: bool = bool(pk.get("once", false))
		var card := UI.panel("CardGold" if once else "Card")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UI.vbox(6, BoxContainer.ALIGNMENT_CENTER)
		card.add_child(v)
		var name := UI.wrap(UI.label(U.t(str(pk["name"])), 15, UI.GOLD if once else UI.TEXT, "bold"))
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name)
		var ic := UI.icon("res_dark_matter", 54)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var amt := UI.title(U.fmt_int(int(pk["mo"])) + U.t(" MO"), 22, Color("e2b8ff"))
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(amt)
		if int(pk.get("bonus_pct", 0)) > 0:
			var bl := UI.label("+%d%% %s" % [int(pk["bonus_pct"]), U.t("de bonificación")], 13, UI.GREEN, "bold")
			bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(bl)
		if not (pk.get("items", {}) as Dictionary).is_empty():
			var rr := UI.reward_row(pk["items"], 13)
			rr.alignment = FlowContainer.ALIGNMENT_CENTER
			v.add_child(rr)
			var value_mo: float = float(pk["mo"]) + Catalog.bundle_value_mo(pk["items"])
			var vl := UI.label(U.t("Valor: %s") % _usd(value_mo / float(Catalog.shop.get("usd_to_mo", 100))), 13, UI.GREEN, "bold")
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(vl)
		var done: bool = once and bought.has(pk["id"])
		var b := UI.button(U.t("Comprado") if done else _usd(float(pk["usd"])), "GreenButton", "", Vector2(0, 50))
		b.disabled = done
		var pid: String = str(pk["id"])
		var pname: String = U.t(str(pk["name"]))
		var price: float = float(pk["usd"])
		b.pressed.connect(func() -> void:
			game.confirm(U.t("Compra SIMULADA de «%s» por %s. En la versión final se cobraría a través de Google Play; en la demo no se cobra nada.") % [pname, _usd(price)], func() -> void:
				send("buy_pack", {"pack": pid}, func(p: Dictionary) -> void:
					game.show_reward(p.get("reward", {}), pname)
					rebuild()), U.t("Comprar (simulado)"), "GreenButton"))
		v.add_child(b)
		grid.add_child(card)


func _items() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(scroll_body(grid))
	for item_id: String in Catalog.shop.get("item_offers", []):
		var it: Dictionary = Catalog.item(item_id)
		if it.is_empty():
			continue
		var price: int = maxi(1, int(round(Catalog.value_mo(item_id))))
		var card := UI.panel("Card")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := UI.hbox(12)
		card.add_child(h)
		h.add_child(UI.panel("Chip", UI.icon(UI.res_icon_name(item_id), 42, UI.GOLD)))
		var v := UI.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UI.label("%s  ·  %s ×%d" % [U.t(str(it["name"])), U.t("tienes"), GameClient.res(item_id)], 15, UI.TEXT, "bold"))
		v.add_child(UI.wrap(UI.label(U.t(str(it.get("desc", ""))), 12, UI.TEXT_DIM)))
		h.add_child(v)
		var bv := UI.vbox(4)
		for qty: int in [1, 10]:
			var b := UI.button(U.t("×%d  ·  %s MO") % [qty, U.fmt_int(price * qty)], "PrimaryButton" if qty == 1 else "Button", "", Vector2(150, 40))
			b.disabled = GameClient.res("dark_matter") < price * qty
			var q: int = qty
			b.pressed.connect(func() -> void: send("buy_item", {"item": item_id, "qty": q}, func(_p: Dictionary) -> void:
				game.toast(U.t("Compraste %s ×%d") % [U.t(str(it["name"])), q], "success")
				rebuild()))
			bv.add_child(b)
		h.add_child(bv)
		grid.add_child(card)


func _resources() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(scroll_body(grid))
	for b: Dictionary in Catalog.shop.get("bundles", []):
		var res_id: String = str(b["res"])
		var price: int = maxi(1, int(round(Catalog.value_mo(res_id, float(b["amount"])))))
		var card := UI.panel("Card")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := UI.hbox(10)
		card.add_child(h)
		h.add_child(UI.icon(UI.res_icon_name(res_id), 46))
		var v := UI.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UI.label("+%s" % U.fmt_int(int(b["amount"])), 18, UI.GREEN, "bold"))
		v.add_child(UI.label(Catalog.res_name(res_id), 14, UI.TEXT_DIM))
		h.add_child(v)
		var bt := UI.button(U.t("%s MO") % U.fmt_int(price), "PrimaryButton", "", Vector2(110, 46))
		bt.disabled = GameClient.res("dark_matter") < price
		var bid: String = str(b["id"])
		bt.pressed.connect(func() -> void: send("buy_bundle", {"bundle": bid}, func(_p: Dictionary) -> void:
			game.toast(U.t("+%s %s") % [U.fmt_int(int(b["amount"])), Catalog.res_name(res_id)], "success")
			rebuild()))
		h.add_child(bt)
		grid.add_child(card)


func _prices() -> void:
	var rate: float = float(Catalog.shop.get("usd_to_mo", 100))
	var intro := UI.panel("Chip")
	intro.add_child(UI.wrap(UI.label(U.t("Tabla de equivalencias (moneda opaca). Cada recurso y objeto tiene un valor en Materia Oscura; así se calcula el precio de la tienda, el valor del bono diario (≈ US$1) y el pozo de premios de los eventos. Terminar al instante cuesta %d MO por minuto.") % int(Catalog.shop.get("instant_finish_mo_per_min", 10)), 14, UI.TEXT_DIM)))
	body.add_child(intro)
	var list := UI.vbox(4)
	body.add_child(scroll_body(list))
	var head := UI.hbox(8)
	for col: Array in [[U.t("Recurso / objeto"), 380], [U.t("Unidad"), 160], [U.t("Valor en MO"), 180], [U.t("Valor en USD"), 180]]:
		var l := UI.label(col[0], 14, UI.GOLD, "bold")
		l.custom_minimum_size.x = col[1]
		head.add_child(l)
	list.add_child(head)
	var rows: Array = []
	for id: String in Catalog.element_ids:
		rows.append([id, 1000])
	for c: Dictionary in Catalog.currencies:
		if str(c["id"]) != "dark_matter":
			rows.append([str(c["id"]), 100])
	for item_id: String in Catalog.shop.get("item_offers", []):
		rows.append([item_id, 1])
	for r: Array in rows:
		var id: String = r[0]
		var qty: int = r[1]
		var mo: float = Catalog.value_mo(id, qty)
		var card := UI.panel("Card")
		var h := UI.hbox(8)
		card.add_child(h)
		var nh := UI.hbox(8)
		nh.custom_minimum_size.x = 380
		nh.add_child(UI.icon(UI.res_icon_name(id), 24))
		nh.add_child(UI.label(Catalog.res_name(id), 15, UI.TEXT, "semibold"))
		h.add_child(nh)
		for cell: Array in [["×" + U.fmt_int(qty), 160, UI.TEXT_DIM], [U.t("%s MO") % (("%.1f" % mo) if mo < 10.0 else U.fmt_int(int(round(mo)))), 180, Color("e2b8ff")], [_usd(mo / rate), 180, UI.GREEN]]:
			var l := UI.label(cell[0], 15, cell[2], "semibold")
			l.custom_minimum_size.x = cell[1]
			h.add_child(l)
		list.add_child(card)
