extends "res://ui/panels/window.gd"
## Comandante: perfil (nivel, EXP, bonos, captura), Protocolos de Mando
## (talentos en 3 ramas) y prisioneros. Se abre tocando el retrato de la
## barra superior.

var tab: String = "profile"
var _sig: String = ""


func _init() -> void:
	desired_size = Vector2(1180, 640)


func window_title() -> String:
	return U.t("Comandante")


func window_icon() -> String:
	return "ui_star"


func cv() -> Dictionary:
	return GameClient.me.get("commander", {})


func _signature() -> String:
	return JSON.stringify([cv(), GameClient.res("credits"), GameClient.res("dark_matter")])


func on_player_updated() -> void:
	var s: String = _signature()
	if s != _sig:
		rebuild()


func build() -> void:
	_sig = _signature()
	tab = str(args.get("tab", tab))
	var tabs := UI.hbox(8)
	body.add_child(tabs)
	var c: Dictionary = cv()
	var pts: int = int(c.get("points", 0))
	for t: Array in [["profile", U.t("Perfil"), "ui_star"], ["talents", U.t("Protocolos de Mando") + ("  (%d)" % pts if pts > 0 else ""), "ui_lab"], ["prisoners", U.t("Prisioneros (%d)") % (c.get("prisoners", []) as Array).size(), "ui_shield"]]:
		var b := UI.button(t[1], "PrimaryButton" if t[0] == tab else "TabButton", t[2], Vector2(0, 48))
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			args["tab"] = key
			tab = key
			rebuild())
		tabs.add_child(b)
	match tab:
		"talents":
			_talents()
		"prisoners":
			_prisoners()
		_:
			_profile()


func _profile() -> void:
	var c: Dictionary = cv()
	var me: Dictionary = GameClient.me
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	var left := UI.panel("CardHi")
	left.custom_minimum_size.x = 380
	row.add_child(left)
	var lv := UI.vbox(10)
	left.add_child(lv)
	var h := UI.hbox(14)
	var img := UI.image(UI.portrait_tex(str(me.get("avatar", "p01"))), Vector2(120, 120))
	if not (c.get("captured", {}) as Dictionary).is_empty():
		img.modulate = Color(0.55, 0.55, 0.6)
	h.add_child(img)
	var tv := UI.vbox(4)
	tv.add_child(UI.label(str(me.get("name", "")), 22, UI.TEXT, "bold"))
	tv.add_child(UI.label(U.t("Comandante Nv %d") % int(c.get("level", 1)), 20, UI.GOLD, "bold"))
	tv.add_child(UI.label(U.t("Puntos de Protocolo: %d libres de %d") % [int(c.get("points", 0)), int(c.get("points_total", 1))], 14, UI.CYAN))
	h.add_child(tv)
	lv.add_child(h)
	var nxt: int = int(c.get("exp_next", 0))
	lv.add_child(UI.label(U.t("EXP %s / %s") % [U.fmt_int(int(c.get("exp", 0))), U.fmt_int(nxt)] if nxt > 0 else U.t("Nivel máximo"), 14, UI.TEXT_DIM))
	lv.add_child(UI.progress(float(c.get("exp", 0)), float(maxi(1, nxt)), UI.GOLD, 12))
	lv.add_child(UI.wrap(UI.label(U.t("Gana EXP cazando xenoformas, atacando, defendiendo tu nave y minando. Cada nivel da un punto de Protocolo de Mando."), 13, UI.TEXT_MUTED)))
	var gb := UI.button(U.t("Equipo del Comandante (%d/6)") % (GameClient.me.get("gear", {}).get("equipped", {}) as Dictionary).size(), "GhostButton", "ui_attack", Vector2(0, 44))
	gb.pressed.connect(func() -> void:
		close_window()
		game.open_panel("armory"))
	lv.add_child(gb)
	var cap: Dictionary = c.get("captured", {})
	if not cap.is_empty():
		var cc := UI.panel("CardRed")
		var cvb := UI.vbox(6)
		cc.add_child(cvb)
		cvb.add_child(UI.label(U.t("¡COMANDANTE CAPTURADO!"), 18, UI.RED, "title"))
		var left_s: float = float(int(cap.get("until", 0)) - GameClient.server_now()) / 1000.0
		cvb.add_child(UI.wrap(UI.label(U.t("Prisionero de %s. Sus Protocolos de Mando no aplican. Vuelve solo en %s o al pagar el rescate.") % [str(cap.get("by", "")), U.fmt_time(left_s)], 14, UI.TEXT)))
		var pay := UI.button(U.t("Pagar rescate (%s Créditos)") % U.fmt_int(int(cap.get("ransom", 0))), "GoldButton", "res_credits", Vector2(0, 50))
		pay.disabled = GameClient.res("credits") < int(cap.get("ransom", 0))
		pay.pressed.connect(func() -> void: send("pay_ransom", {}, func(_p: Dictionary) -> void:
			UI.Sfx.play("reward")
			game.toast(U.t("Rescate pagado: tu Comandante vuelve a la nave"), "success")))
		cvb.add_child(pay)
		lv.add_child(cc)
	var right := UI.panel("Card")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var rv := UI.vbox(8)
	right.add_child(rv)
	rv.add_child(UI.label(U.t("Bonos activos de los Protocolos"), 17, UI.CYAN, "bold"))
	var mods: Dictionary = c.get("mods", {})
	if mods.is_empty():
		rv.add_child(UI.wrap(UI.label(U.t("Ninguno todavía. Asigna puntos en Protocolos de Mando.") if cap.is_empty() else U.t("Desactivados mientras el Comandante está capturado."), 14, UI.TEXT_MUTED)))
	for k: String in mods:
		rv.add_child(UI.label("+%.0f%% %s" % [float(mods[k]) * 100.0, _effect_label(k)], 15, UI.GREEN, "semibold"))
	rv.add_child(UI.separator())
	rv.add_child(UI.label(U.t("Riesgo de captura"), 15, UI.GOLD, "bold"))
	var capcfg: Dictionary = Catalog.commander.get("capture", {})
	rv.add_child(UI.wrap(UI.label(U.t("Si tu nave pierde un ataque y caen al menos el %d%% de tus tropas, hay un %d%% de probabilidad de que el enemigo capture a tu Comandante (menos con Protocolo de Evasión). Tú también puedes capturar Comandantes enemigos y cobrar su rescate.") % [int(float(capcfg.get("min_loss_ratio", 0.5)) * 100), int(float(capcfg.get("base_chance", 0.25)) * 100)], 13, UI.TEXT_DIM)))


func _effect_label(effect: String) -> String:
	var labels: Dictionary = {
		"attack": U.t("ataque de fuerzas"), "defense": U.t("defensa de fuerzas"), "hp": U.t("vida de fuerzas"),
		"pve_damage": U.t("daño contra Xenoformas"), "march_speed": U.t("velocidad de flota"), "capture_resist": U.t("resistencia a la captura"),
		"production": U.t("producción"), "gather_speed": U.t("velocidad de minería"), "load": U.t("capacidad de carga"),
		"research_speed": U.t("velocidad de investigación"), "train_speed": U.t("velocidad de entrenamiento"), "ransom_discount": U.t("descuento de rescate"),
		"crew_power": U.t("pasivas de tripulantes"), "march_capacity": U.t("capacidad de flota"), "capture_chance": U.t("probabilidad de captura"),
		"crew_exp": U.t("EXP de tripulantes"), "ransom_bonus": U.t("rescate cobrado"), "cmd_exp": U.t("EXP del Comandante"),
	}
	return str(labels.get(effect, effect))


func _talents() -> void:
	var c: Dictionary = cv()
	var learned: Dictionary = c.get("talents", {})
	var spent: Dictionary = c.get("spent", {})
	var per_tier: int = int(Catalog.commander.get("points_per_tier", 5))
	var top := UI.hbox(12)
	body.add_child(top)
	top.add_child(UI.label(U.t("Puntos libres: %d") % int(c.get("points", 0)), 17, UI.GOLD, "bold"))
	top.add_child(UI.spacer())
	var reset := UI.button(U.t("Reiniciar (%d MO)") % int(c.get("respec_cost", 200)), "GhostButton", "ui_back", Vector2(0, 44))
	reset.disabled = learned.is_empty()
	reset.pressed.connect(func() -> void: send("talent_reset", {}, func(_p: Dictionary) -> void: game.toast(U.t("Protocolos reiniciados: puntos devueltos"), "info")))
	top.add_child(reset)
	var cols := UI.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	for b: Dictionary in Catalog.commander.get("branches", []):
		var col := UI.panel("Card")
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
		var v := UI.vbox(6)
		col.add_child(v)
		var bc := Color(str(b.get("color", "#ffffff")))
		var hh := UI.hbox(8)
		hh.add_child(UI.icon(str(b.get("icon", "ui_star")), 26, bc))
		hh.add_child(UI.label(U.t(str(b["name"])), 18, bc, "bold"))
		hh.add_child(UI.spacer())
		hh.add_child(UI.label(U.t("%d pts") % int(spent.get(b["id"], 0)), 14, UI.TEXT_DIM))
		v.add_child(hh)
		for t: Dictionary in b.get("talents", []):
			v.add_child(_talent_row(t, int(learned.get(t["id"], 0)), int(spent.get(b["id"], 0)) >= int(t["tier"]) * per_tier, int(c.get("points", 0)) > 0, bc))


func _talent_row(t: Dictionary, rank: int, unlocked: bool, has_points: bool, col: Color) -> Control:
	var card := UI.panel("Chip")
	var h := UI.hbox(8)
	card.add_child(h)
	var v := UI.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l := UI.label("%s  %d/%d" % [U.t(str(t["name"])), rank, int(t["max"])], 14, UI.TEXT if unlocked else UI.TEXT_MUTED, "bold")
	name_l.clip_text = true
	v.add_child(name_l)
	var d := UI.label(U.t(str(t.get("desc", ""))) if unlocked else U.t("Requiere %d pts en la rama") % (int(t["tier"]) * int(Catalog.commander.get("points_per_tier", 5))), 12, UI.TEXT_DIM if unlocked else UI.TEXT_MUTED)
	d.clip_text = true
	v.add_child(d)
	h.add_child(v)
	var b := UI.icon_button("ui_plus", 40, "PrimaryButton" if unlocked and has_points and rank < int(t["max"]) else "GhostButton")
	b.disabled = not unlocked or not has_points or rank >= int(t["max"])
	b.name = "Talent_" + str(t["id"])
	var tid: String = str(t["id"])
	b.pressed.connect(func() -> void: send("talent_learn", {"talent": tid}, func(_p: Dictionary) -> void: UI.Sfx.play("upgrade")))
	h.add_child(b)
	if rank > 0:
		var sb := UI.sb(Color(col, 0.16), Color(col, 0.7), 10, 1, 5)
		card.add_theme_stylebox_override("panel", sb)
	return card


func _prisoners() -> void:
	var list: Array = cv().get("prisoners", [])
	body.add_child(UI.wrap(UI.label(U.t("Comandantes que capturaste al vencer sus naves. Cobras su rescate cuando lo pagan; si no, vuelven solos al cumplir la condena."), 15, UI.TEXT_DIM)))
	if list.is_empty():
		body.add_child(UI.label(U.t("No tienes prisioneros."), 16, UI.TEXT_MUTED))
		return
	var v := UI.vbox(8)
	body.add_child(scroll_body(v))
	for pr: Dictionary in list:
		var card := UI.panel("Card")
		var h := UI.hbox(12)
		card.add_child(h)
		h.add_child(UI.image(UI.portrait_tex(str(pr.get("avatar", "p01"))), Vector2(56, 56)))
		var tv := UI.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UI.label(U.t("%s · Comandante Nv %d") % [str(pr.get("name", "")), int(pr.get("level", 1))], 16, UI.TEXT, "bold"))
		tv.add_child(UI.label(U.t("Rescate: %s Créditos · libre en %s") % [U.fmt_int(int(pr.get("ransom", 0))), U.fmt_time(float(int(pr.get("until", 0)) - GameClient.server_now()) / 1000.0)], 14, UI.GOLD))
		h.add_child(tv)
		v.add_child(card)
