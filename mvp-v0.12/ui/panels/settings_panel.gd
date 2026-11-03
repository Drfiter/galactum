extends "res://ui/panels/window.gd"

const I18n = preload("res://shared/i18n.gd")
## Menú: estado de conexión, guía rápida, herramientas de demo y salida.


func _init() -> void:
	desired_size = Vector2(1000, 640)


func window_title() -> String:
	return U.t("Menú del Comandante")


func window_icon() -> String:
	return "ui_settings"


func build() -> void:
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.vbox(10)
	left.custom_minimum_size.x = 360
	row.add_child(left)
	var me: Dictionary = GameClient.me
	var prof := UI.panel("CardHi")
	var ph := UI.hbox(12)
	prof.add_child(ph)
	ph.add_child(UI.image(UI.portrait_tex(str(me.get("avatar", "p01"))), Vector2(96, 96)))
	var pv := UI.vbox(2)
	pv.add_child(UI.label(str(me.get("name", "")), 20, UI.TEXT, "bold"))
	pv.add_child(UI.label(U.t("Alianza [%s]") % str(me.get("tag", "")), 15, UI.GREEN))
	pv.add_child(UI.label(U.t("Poder %s") % U.fmt_int(int(me.get("power", 0))), 15, UI.GOLD, "semibold"))
	pv.add_child(UI.label(U.t("Bajas causadas: %s") % U.fmt_int(int(me.get("stats", {}).get("kills", 0))), 14, UI.TEXT_DIM))
	ph.add_child(pv)
	left.add_child(prof)
	var conn := UI.panel("Card")
	var cv := UI.vbox(4)
	conn.add_child(cv)
	cv.add_child(UI.label(U.t("Conexión"), 15, UI.CYAN, "bold"))
	cv.add_child(UI.label(U.t("Modo: %s") % (U.t("Servidor embebido (sin red)") if GameClient.mode == "local" else U.t("SSS dedicado por WebSocket")), 14, UI.TEXT))
	cv.add_child(UI.label(U.t("Protocolo: galactum-mvp-1 · Combate: galactum-mvp-1.2"), 13, UI.TEXT_DIM))
	left.add_child(conn)
	var lang := UI.panel("Card")
	var lv := UI.vbox(6)
	lang.add_child(lv)
	var lh := UI.hbox(8)
	lh.add_child(UI.icon("ui_language", 22, UI.CYAN))
	lh.add_child(UI.label(U.t("Idioma / Language"), 15, UI.CYAN, "bold"))
	lv.add_child(lh)
	var lb := UI.hbox(8)
	for loc: Array in I18n.LOCALES:
		var b := UI.button(str(loc[1]), "PrimaryButton" if I18n.current() == loc[0] else "TabButton", "", Vector2(150, 46))
		var code: String = loc[0]
		b.pressed.connect(func() -> void: game.change_language(code))
		lb.add_child(b)
	lv.add_child(lb)
	left.add_child(lang)
	left.add_child(UI.spacer())
	var raid := UI.button(U.t("Demo: provocar incursión enemiga"), "DangerButton", "ui_warning", Vector2(0, 52))
	raid.pressed.connect(func() -> void:
		send("debug_raid", {}, func(_p: Dictionary) -> void:
			close_window()
			game.toast(U.t("Sensores: flota hostil detectada rumbo a tu nave"), "danger")))
	left.add_child(raid)
	var title_btn := UI.button(U.t("Guardar y volver al título"), "Button", "ui_back", Vector2(0, 52))
	title_btn.pressed.connect(func() -> void: game.back_to_title())
	left.add_child(title_btn)

	var help := UI.vbox(8)
	var hs := scroll_body(help)
	row.add_child(hs)
	help.add_child(UI.label(U.t("CÓMO JUGAR"), 18, UI.CYAN, "title"))
	for line: String in [
		U.t("• Tu Astronave es tu base: mejora salas, produce y entrena dentro de ella (botón NAVE)."),
		U.t("• En el MAPA envía flotas desde tu nave: minar asteroides, cazar xenoformas, espiar y atacar."),
		U.t("• Los asteroides dan los 5 elementos de minería (más ricos hacia el centro). La flota vuelve con la carga."),
		U.t("• Cazar cuesta Energía. Mira la debilidad: física (Infantería, Escudos, Cañoneros) o energética (Drones, Pilotos)."),
		U.t("• Triángulo: Infantería > Drones > Pilotos > Infantería (+30%). Escudos absorben primero; Cañoneros rompen escudos."),
		U.t("• Si te atacan defienden tus tropas en la nave y el Escudo Perimetral. Los heridos van a la Bahía Médica; el 80% de los muertos al Criosantuario."),
		U.t("• La Bóveda Cuántica protege una parte de cada elemento contra saqueos."),
		U.t("• Tu Alianza te ayuda a acelerar y comparte Cápsulas de Suministro por cada caza."),
		U.t("• Sigue las misiones de la izquierda y las Órdenes del Día para conseguir recompensas."),
		U.t("• Arrastra para mover el mapa, pellizca (o rueda del mouse) para zoom, toca para seleccionar."),
	]:
		help.add_child(UI.wrap(UI.label(line, 15, UI.TEXT)))
	help.add_child(UI.separator())
	help.add_child(UI.wrap(UI.label(U.t("Galactum MVP · Proyecto de Título (APT) · Duoc UC 2026. Arte placeholder vectorial del catálogo del proyecto. Fuentes Exo 2, Orbitron y Lilita One (SIL OFL)."), 13, UI.TEXT_MUTED)))
