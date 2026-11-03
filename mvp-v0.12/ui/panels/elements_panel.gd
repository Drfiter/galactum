extends "res://ui/panels/window.gd"
## Los 10 elementos de construcción + monedas: origen, producción y protección.


func _init() -> void:
	desired_size = Vector2(1000, 620)


func window_title() -> String:
	return U.t("Recursos de la nave")


func window_icon() -> String:
	return "ui_cargo"


func build() -> void:
	var rates: Dictionary = GameClient.me.get("rates", {})
	var protect: int = int(GameClient.me.get("caps", {}).get("vault", 0))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(UI.wrap(UI.label(U.t("Los elementos de minería solo se obtienen en asteroides del mapa (expuestos al PvP). Los de interior los producen la Fábrica y la Segunda Plataforma. La Bóveda Cuántica protege %s de cada elemento.") % U.fmt_num(protect), 14, UI.TEXT_DIM)))
	body.add_child(scroll_body(grid))
	for e: Dictionary in Catalog.elements + Catalog.currencies:
		var id: String = e["id"]
		var card := UI.panel("Card")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := UI.hbox(12)
		card.add_child(h)
		h.add_child(UI.icon(UI.res_icon_name(id), 40))
		var v := UI.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UI.label(str(e["name"]), 16, Catalog.res_color(id).lightened(0.2), "bold"))
		var src: String = {"mining": U.t("Minería de asteroides"), "interior": U.t("Producción interior")}.get(str(e.get("source", "")), "")
		match id:
			"credits":
				src = U.t("Banco Galáctico, cazas y saqueos")
			"dark_matter":
				src = U.t("Moneda premium: misiones, cazas, cápsulas")
			"energy":
				src = U.t("Se regenera sola · para cazar xenoformas")
			"plasma":
				src = U.t("Segunda Plataforma · para mover la nave")
		if rates.has(id):
			src += U.t("  ·  +%s/min") % U.fmt_num(float(rates[id]))
		v.add_child(UI.label(src, 13, UI.TEXT_DIM))
		h.add_child(v)
		var amount: int = GameClient.res(id)
		h.add_child(UI.label(U.fmt_int(amount), 20, UI.TEXT, "bold"))
		if str(e.get("source", "")) != "":
			h.add_child(UI.icon("ui_lock" if amount <= protect else "ui_warning", 20, UI.GREEN if amount <= protect else UI.GOLD))
		grid.add_child(card)
