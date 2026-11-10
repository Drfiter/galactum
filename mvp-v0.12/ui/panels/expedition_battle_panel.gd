extends "res://ui/panels/window.gd"
## Reproducción de un combate de Expedición: el servidor ya resolvió la batalla
## y envía el registro; aquí se reproduce golpe a golpe (con opción de saltar)
## y al final se muestran el resultado, las estrellas y los premios.

const STEP: float = 0.16

var result: Dictionary = {}
var cards: Array = [[], []]   # [lado][índice] -> {bar, hp_label, fx, cur, max, root}
var _step: int = 0
var _timer: Timer
var _done: bool = false
var _result_box: VBoxContainer
var _round_label: Label


func _init() -> void:
	desired_size = Vector2(1160, 640)


var dismissable: bool = false


func window_title() -> String:
	return U.t("Combate de Expedición")


func window_icon() -> String:
	return "ui_attack"


func build() -> void:
	result = args.get("result", {})
	var top := UI.hbox(10)
	body.add_child(top)
	top.add_child(UI.label(U.t("Etapa %s") % str(result.get("stage", "")) + ("  ·  " + U.t("ÉLITE") if bool(result.get("elite", false)) else ""), 20, UI.GOLD, "title"))
	top.add_child(UI.spacer())
	_round_label = UI.label(U.t("Ronda %d") % 1, 16, UI.CYAN, "bold")
	top.add_child(_round_label)
	var skip := UI.button(U.t("Saltar"), "GhostButton", "ui_speed", Vector2(140, 44))
	skip.name = "Skip"
	skip.pressed.connect(_finish)
	top.add_child(skip)
	var field := UI.hbox(20)
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(field)
	field.add_child(_side(0, result.get("team", []), U.t("Tu equipo"), UI.CYAN))
	var vs := UI.label("VS", 34, UI.GOLD, "title")
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	field.add_child(vs)
	field.add_child(_side(1, result.get("enemies", []), U.t("Xenoformas"), UI.RED))
	_result_box = UI.vbox(8)
	body.add_child(_result_box)
	_timer = Timer.new()
	_timer.wait_time = STEP
	_timer.timeout.connect(_advance)
	add_child(_timer)
	_timer.start()


func _side(s: int, units: Array, title: String, col: Color) -> Control:
	var card := UI.panel("Card")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(6)
	card.add_child(v)
	v.add_child(UI.label(title, 17, col, "bold"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for u: Dictionary in units:
		var c := UI.panel("Chip")
		c.custom_minimum_size = Vector2(150, 0)
		var cv := UI.vbox(2)
		c.add_child(cv)
		var tex: Texture2D = UI.portrait_tex(str(u["id"])) if s == 0 else UI.xeno_tex(str(u.get("species", "")), int(u.get("level", 1)))
		var img := UI.image(tex, Vector2(64, 64))
		img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(img)
		var name_s: String = str(Catalog.portraits.get(str(u["id"]), {}).get("name", "")) if s == 0 else str(Catalog.species_by_id.get(str(u.get("species", "")), {}).get("name", ""))
		var nl := UI.label(name_s, 12, UI.TEXT, "semibold")
		nl.clip_text = true
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(nl)
		var role_s: String = U.t(str(Catalog.crew.get("roles", {}).get(str(u["role"]), u["role"])))
		if bool(u.get("boss", false)):
			role_s = U.t("JEFE") + " · " + role_s
		var rl := UI.label(role_s, 11, UI.TEXT_MUTED)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(rl)
		var mx: int = int(u["hp"])
		var bar := UI.progress(float(mx), float(mx), UI.GREEN if s == 0 else UI.RED, 10)
		cv.add_child(bar)
		var hl := UI.label("%s / %s" % [U.fmt_num(mx), U.fmt_num(mx)], 11, UI.TEXT_DIM)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(hl)
		var fx := UI.label(" ", 15, UI.GOLD, "bold")
		fx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(fx)
		grid.add_child(c)
		(cards[s] as Array).append({"bar": bar, "hp": hl, "fx": fx, "cur": mx, "max": mx, "root": c, "img": img})
	return card


func _apply(e: Dictionary, animate: bool) -> void:
	var s: int = int(e["s"])
	var heal: bool = e.has("h")
	var target_side: int = s if heal else 1 - s
	var t: Dictionary = cards[target_side][int(e["t"])]
	if heal:
		t["cur"] = mini(int(t["max"]), int(t["cur"]) + int(e["h"]))
	else:
		t["cur"] = maxi(0, int(t["cur"]) - int(e["d"]))
	(t["bar"] as ProgressBar).value = float(t["cur"])
	(t["hp"] as Label).text = "%s / %s" % [U.fmt_num(int(t["cur"])), U.fmt_num(int(t["max"]))]
	if int(t["cur"]) <= 0:
		(t["img"] as Control).modulate = Color(0.35, 0.35, 0.4, 0.8)
	if animate:
		var fx: Label = t["fx"]
		if heal:
			fx.text = "+%s" % U.fmt_num(int(e["h"]))
			fx.add_theme_color_override("font_color", UI.GREEN)
		else:
			fx.text = ("¡%s!" if bool(e.get("c", false)) else "-%s") % U.fmt_num(int(e["d"]))
			fx.add_theme_color_override("font_color", UI.GOLD if bool(e.get("c", false)) else UI.RED)
		var root: Control = t["root"]
		root.modulate = Color(1.6, 1.3, 1.3) if not heal else Color(1.2, 1.6, 1.2)
		create_tween().tween_property(root, "modulate", Color.WHITE, STEP * 1.5)
		var att: Dictionary = cards[s][int(e["a"])]
		var ar: Control = att["root"]
		ar.scale = Vector2(1.06, 1.06)
		ar.pivot_offset = ar.size / 2.0
		create_tween().tween_property(ar, "scale", Vector2.ONE, STEP)
		_round_label.text = U.t("Ronda %d") % int(e.get("r", 1))


func _advance() -> void:
	var log: Array = result.get("log", [])
	if _step >= log.size():
		_finish()
		return
	_apply(log[_step], true)
	_step += 1


func _finish() -> void:
	if _done:
		return
	_done = true
	_timer.stop()
	var log: Array = result.get("log", [])
	while _step < log.size():
		_apply(log[_step], false)
		_step += 1
	_round_label.text = U.t("Ronda %d") % int(result.get("rounds", 1))
	var win: bool = bool(result.get("win", false))
	UI.Sfx.play("reward" if win else "error")
	var banner := UI.panel("CardGold" if win else "CardRed")
	_result_box.add_child(banner)
	var h := UI.hbox(16)
	banner.add_child(h)
	var stars: int = int(result.get("stars", 0))
	h.add_child(UI.label((U.t("¡VICTORIA!") + "  " + "★".repeat(stars) + "☆".repeat(3 - stars)) if win else U.t("DERROTA"), 26, UI.GOLD if win else UI.RED, "title"))
	var mid := UI.vbox(2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if win and not (result.get("reward", {}) as Dictionary).is_empty():
		mid.add_child(UI.label(U.t("Primera victoria") if bool(result.get("first", false)) else U.t("Premio por repetir"), 13, UI.TEXT_DIM))
		mid.add_child(UI.reward_row(result.get("reward", {}), 16))
	elif not win:
		mid.add_child(UI.wrap(UI.label(U.t("Recuperas la mitad del Combustible. Sube de nivel y de grado a tus tripulantes o prueba otro equipo."), 14, UI.TEXT)))
	var cx: Array = result.get("crew_exp", [])
	if not cx.is_empty():
		var up: int = cx.filter(func(x: Dictionary) -> bool: return bool(x.get("leveled", false))).size()
		mid.add_child(UI.label(U.t("Tripulantes: +%d EXP cada uno") % int(cx[0].get("exp", 0)) + (("  ·  " + U.t("%d suben de nivel") % up) if up > 0 else ""), 13, UI.CYAN))
	h.add_child(mid)
	var ok := UI.button(U.t("Continuar"), "GoldButton" if win else "PrimaryButton", "ui_check", Vector2(200, 52))
	ok.name = "Continue"
	ok.pressed.connect(close_window)
	h.add_child(ok)
