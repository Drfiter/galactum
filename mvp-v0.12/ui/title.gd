extends Control

const U = preload("res://shared/util.gd")
## Pantalla de título: identidad del comandante y modo de juego
## (servidor embebido para jugar sin red / SSS dedicado por WebSocket).

const UI = preload("res://ui/ui.gd")
const BG_SHADER = preload("res://assets/shaders/space_bg.gdshader")
const AVATARS: Array = ["p01", "p05", "p03", "p06", "p09", "p13", "p21", "p27", "p44", "p40"]
const SETTINGS_PATH: String = "user://settings.cfg"

var _bg_mat: ShaderMaterial
var _name: LineEdit
var _host: LineEdit
var _port: SpinBox
var _avatar: String = "p01"
var _avatar_btns: Dictionary = {}
var _remote_box: VBoxContainer
var _status: Label
var _t: float = 0.0
var _logo: Control


func _ready() -> void:
	UI.apply_global_theme()
	UI.full_rect(self)
	var bg := ColorRect.new()
	UI.full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = BG_SHADER
	_bg_mat.set_shader_parameter("grid_alpha", 0.0)
	bg.material = _bg_mat
	add_child(bg)
	var deco := Control.new()
	UI.full_rect(deco)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func() -> void: _draw_deco(deco))
	add_child(deco)
	set_meta("deco", deco)

	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_avatar = str(cfg.get_value("player", "avatar", "p01"))

	var root := UI.hbox(40, BoxContainer.ALIGNMENT_CENTER)
	UI.full_rect(root)
	root.add_theme_constant_override("separation", 48)
	add_child(root)

	# Selector de idioma (inglés por defecto)
	var lang := UI.hbox(6)
	lang.anchor_left = 1.0
	lang.anchor_right = 1.0
	lang.offset_left = -330
	lang.offset_right = -16
	lang.offset_top = 14
	lang.alignment = BoxContainer.ALIGNMENT_END
	add_child(lang)
	lang.add_child(UI.icon("ui_language", 30, UI.CYAN))
	for loc: Array in preload("res://shared/i18n.gd").LOCALES:
		var lb := UI.button(str(loc[1]), "PrimaryButton" if preload("res://shared/i18n.gd").current() == loc[0] else "GhostButton", "", Vector2(130, 44))
		var code: String = loc[0]
		lb.pressed.connect(func() -> void:
			preload("res://shared/i18n.gd").set_locale(code)
			Catalog.reload()
			get_tree().reload_current_scene())
		lang.add_child(lb)

	var left := UI.vbox(10, BoxContainer.ALIGNMENT_CENTER)
	left.custom_minimum_size.x = 520
	root.add_child(left)
	_logo = UI.vbox(0)
	left.add_child(_logo)
	var logo_row := UI.hbox(14)
	logo_row.add_child(UI.image(UI.icon_tex("logo_mark"), Vector2(96, 96)))
	var t := UI.title("GALACTUM", 76, Color("e9f7ff"))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 0)
	t.add_theme_constant_override("shadow_outline_size", 18)
	t.add_theme_color_override("font_shadow_color", Color(0.25, 0.8, 1.0, 0.45))
	logo_row.add_child(t)
	_logo.add_child(logo_row)
	var sub := UI.outline(UI.label(U.t("ESTRATEGIA ESPACIAL MASIVA"), 26, Color("ffd36a"), "game"), 8)
	_logo.add_child(sub)
	left.add_child(UI.wrap(UI.label(U.t("Mejora tu Astronave, mina asteroides, caza xenoformas y saquea a comandantes rivales en una galaxia de Sistemas Solares persistentes de 600×600 casillas."), 18, UI.TEXT_DIM), 500))
	var feats := UI.flow(10, 8)
	for f: Array in [["ui_ship", U.t("Astronave-base")], ["ui_mine", U.t("Minería N1-N5")], ["ui_hunt", U.t("24 Xenoformas")], ["ui_attack", U.t("Combate determinista")], ["ui_alliance", U.t("Alianzas")], ["ui_galaxy", U.t("Galaxia multisistema")]]:
		var chip := UI.panel("Chip")
		var h := UI.hbox(6)
		chip.add_child(h)
		h.add_child(UI.icon(f[0], 20, UI.CYAN))
		h.add_child(UI.label(f[1], 15, UI.TEXT, "semibold"))
		feats.add_child(chip)
	left.add_child(feats)

	var card := UI.panel("")
	card.custom_minimum_size = Vector2(500, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(card)
	var v := UI.vbox(12)
	card.add_child(v)
	v.add_child(UI.outline(UI.label(U.t("IDENTIDAD DEL COMANDANTE"), 20, Color("ffd36a"), "game"), 6))
	_name = LineEdit.new()
	_name.placeholder_text = U.t("Nombre del comandante")
	_name.max_length = 18
	_name.text = str(cfg.get_value("player", "name", U.t("Mateo")))
	_name.custom_minimum_size.y = 54
	v.add_child(_name)
	v.add_child(UI.label(U.t("Retrato"), 14, UI.TEXT_DIM))
	var av_row := UI.flow(8, 8)
	for a: String in AVATARS:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(76, 76)
		b.flat = true
		var img := UI.image(UI.portrait_tex(a), Vector2(72, 72))
		UI.full_rect(img)
		b.add_child(img)
		b.pressed.connect(func() -> void: _select_avatar(a))
		av_row.add_child(b)
		_avatar_btns[a] = b
	v.add_child(av_row)
	_select_avatar(_avatar)
	var play := UI.button(U.t("JUGAR"), "GreenButton", "ui_ship", Vector2(0, 68))
	play.add_theme_font_size_override("font_size", 32)
	play.pressed.connect(func() -> void: _play(false))
	v.add_child(play)
	var row := UI.hbox(8)
	var fresh := UI.button(U.t("Nueva partida"), "GhostButton", "ui_plus", Vector2(0, 50))
	fresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fresh.pressed.connect(_confirm_fresh)
	row.add_child(fresh)
	var online := UI.button(U.t("Servidor dedicado"), "GhostButton", "ui_sensors", Vector2(0, 50))
	online.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	online.pressed.connect(func() -> void: _remote_box.visible = not _remote_box.visible)
	row.add_child(online)
	v.add_child(row)
	_remote_box = UI.vbox(8)
	_remote_box.visible = false
	var rh := UI.hbox(8)
	_host = LineEdit.new()
	_host.text = str(cfg.get_value("net", "host", "127.0.0.1"))
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.custom_minimum_size.y = 48
	rh.add_child(_host)
	_port = SpinBox.new()
	_port.min_value = 1
	_port.max_value = 65535
	_port.value = int(cfg.get_value("net", "port", 9100))
	_port.custom_minimum_size = Vector2(130, 48)
	rh.add_child(_port)
	_remote_box.add_child(rh)
	var connect := UI.button(U.t("Conectar al SSS"), "Button", "ui_sensors", Vector2(0, 50))
	connect.pressed.connect(func() -> void: _play(true))
	_remote_box.add_child(connect)
	_remote_box.add_child(UI.wrap(UI.label(U.t("Inicia el servidor con Ejecutar_Servidor_Dedicado.bat (o godot --headless -- --server) y conecta varios clientes al mismo sistema."), 13, UI.TEXT_MUTED)))
	v.add_child(_remote_box)
	_status = UI.label("", 14, UI.GOLD)
	v.add_child(_status)
	var foot := UI.label(U.t("v0.12 MVP  ·  Proyecto de Título (APT) · Duoc UC 2026"), 13, UI.TEXT_MUTED)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(20, -34)
	add_child(foot)


func _select_avatar(a: String) -> void:
	_avatar = a
	for k: String in _avatar_btns:
		var b: Button = _avatar_btns[k]
		b.modulate = Color(1, 1, 1, 1) if k == a else Color(0.55, 0.6, 0.75, 0.75)
		b.scale = Vector2(1.06, 1.06) if k == a else Vector2.ONE


func _process(delta: float) -> void:
	_t += delta
	_bg_mat.set_shader_parameter("cam_pos", Vector2(9600 + _t * 40.0, 9600 + sin(_t * 0.1) * 300.0))
	_bg_mat.set_shader_parameter("zoom", 0.6)
	_bg_mat.set_shader_parameter("screen_size", get_viewport_rect().size)
	(get_meta("deco") as Control).queue_redraw()


func _draw_deco(c: Control) -> void:
	var s: Vector2 = c.size
	var center := Vector2(s.x * 0.28, s.y * 1.25)
	for i: int in range(4):
		var r: float = s.y * (0.75 + i * 0.16)
		var a0: float = -PI * 0.92 + sin(_t * 0.2 + i) * 0.05
		c.draw_arc(center, r, a0, a0 + PI * 0.55, 96, Color(0.3, 0.6, 1.0, 0.12 - i * 0.02), 2.0, true)
	var planet := Vector2(s.x * 0.86, s.y * 0.18)
	for i: int in range(14):
		var k: float = 1.0 - i / 14.0
		c.draw_circle(planet + Vector2(-0.25, -0.25) * 90.0 * (1.0 - k), 90.0 * k, Color("2b2f6b").lerp(Color("9b7bd9"), (1.0 - k) * 0.8))
	c.draw_arc(planet, 150.0, -0.4, PI - 0.4, 64, Color(0.7, 0.6, 1.0, 0.35), 4.0, true)
	var ship_pos := Vector2(s.x * 0.08 + fmod(_t * 30.0, s.x * 1.2), s.y * 0.82 - fmod(_t * 30.0, s.x * 1.2) * 0.25)
	c.draw_circle(ship_pos, 3.0, Color(0.6, 0.9, 1.0, 0.9))
	c.draw_line(ship_pos, ship_pos - Vector2(60, -15), Color(0.4, 0.8, 1.0, 0.25), 2.0)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", _name.text.strip_edges())
	cfg.set_value("player", "avatar", _avatar)
	cfg.set_value("net", "host", _host.text.strip_edges())
	cfg.set_value("net", "port", int(_port.value))
	cfg.save(SETTINGS_PATH)


func _player_name() -> String:
	var n: String = _name.text.strip_edges()
	return n if not n.is_empty() else U.t("Comandante")


func _play(remote: bool, fresh: bool = false) -> void:
	_save_settings()
	if remote:
		GameClient.start_remote(_host.text.strip_edges(), int(_port.value), _player_name(), _avatar)
	else:
		_status.text = U.t("Generando el Sistema Solar…") if fresh else U.t("Cargando partida…")
		await get_tree().process_frame
		GameClient.start_local(_player_name(), _avatar, fresh)
	get_tree().change_scene_to_file("res://ui/game.tscn")


func _confirm_fresh() -> void:
	if not FileAccess.file_exists("user://galactum_save.json"):
		_play(false, true)
		return
	_status.text = U.t("Pulsa de nuevo «Nueva partida» para borrar el progreso local.")
	if has_meta("fresh_armed"):
		_play(false, true)
	set_meta("fresh_armed", true)
