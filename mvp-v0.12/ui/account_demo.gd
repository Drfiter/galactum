extends Control
## «Jugar con cuenta»: demostración del registro, el inicio de sesión y la
## validación del token JWT, sin red. Usa el servidor embebido en modo
## «exige cuenta» (las cuentas se guardan en user://galactum_cuentas.json).
##
## Pasos que muestra: 1) cuenta creada / contraseña verificada (PBKDF2 + sal),
## 2) token JWT firmado por el servidor (sus 3 partes y su contenido),
## 3) al entrar, el servidor valida la firma; un token alterado se rechaza.

const UI = preload("res://ui/ui.gd")
const U = preload("res://shared/util.gd")

var avatar: String = "p01"
var default_user: String = ""
var _box: VBoxContainer
var _user: LineEdit
var _pass: LineEdit
var _msg: Label
var _info: Dictionary = {}
var _tamper_label: Label
var _testing_tamper: bool = false
var _busy: bool = false


func _ready() -> void:
	UI.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.05, 0.78)
	UI.full_rect(dim)
	add_child(dim)
	var center := CenterContainer.new()
	UI.full_rect(center)
	add_child(center)
	var card := UI.panel("")
	card.custom_minimum_size = Vector2(760, 0)
	center.add_child(card)
	_box = UI.vbox(12)
	card.add_child(_box)
	GameClient.auth_result.connect(_on_auth_result)
	GameClient.connection_changed.connect(_on_connection_changed)
	_build_login()


func _exit_tree() -> void:
	if GameClient.auth_result.is_connected(_on_auth_result):
		GameClient.auth_result.disconnect(_on_auth_result)
	if GameClient.connection_changed.is_connected(_on_connection_changed):
		GameClient.connection_changed.disconnect(_on_connection_changed)


func _header(title: String, icon: String) -> void:
	UI.clear(_box)
	var h := UI.hbox(12)
	h.add_child(UI.icon(icon, 40, UI.GOLD))
	var t := UI.outline(UI.label(title, 26, Color("ffd36a"), "game"), 6)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var close := UI.icon_button("ui_close", 46, "GhostButton")
	close.name = "Close"
	close.pressed.connect(_close)
	h.add_child(close)
	_box.add_child(h)
	_box.add_child(UI.separator())


# ---------------------------------------------------------------- 1. formulario

func _build_login() -> void:
	_header(U.t("JUGAR CON CUENTA"), "ui_shield")
	_box.add_child(UI.wrap(UI.label(U.t("Así entra un jugador al servidor: crea su cuenta o inicia sesión, el servidor le entrega un token JWT firmado y solo con ese token lo deja jugar."), 16, UI.TEXT_DIM)))
	_user = LineEdit.new()
	_user.name = "User"
	_user.placeholder_text = U.t("Usuario (3 a 18 letras o números)")
	_user.max_length = 18
	_user.text = default_user
	_user.custom_minimum_size.y = 54
	_box.add_child(_user)
	_pass = LineEdit.new()
	_pass.name = "Pass"
	_pass.placeholder_text = U.t("Contraseña (8 caracteres o más)")
	_pass.secret = true
	_pass.custom_minimum_size.y = 54
	_pass.text_submitted.connect(func(_t: String) -> void: _submit(false))
	_box.add_child(_pass)
	var row := UI.hbox(10)
	var reg := UI.button(U.t("Crear cuenta"), "GoldButton", "ui_plus", Vector2(0, 60))
	reg.name = "Register"
	reg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reg.pressed.connect(func() -> void: _submit(true))
	row.add_child(reg)
	var login := UI.button(U.t("Entrar"), "GreenButton", "ui_check", Vector2(0, 60))
	login.name = "Login"
	login.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	login.pressed.connect(func() -> void: _submit(false))
	row.add_child(login)
	_box.add_child(row)
	_msg = UI.wrap(UI.label("", 16, UI.RED, "semibold"))
	_box.add_child(_msg)
	_box.add_child(UI.wrap(UI.label(U.t("Las cuentas quedan guardadas en este equipo: la próxima vez usa «Entrar». No necesita internet."), 13, UI.TEXT_MUTED)))


func _submit(register: bool) -> void:
	if _busy:
		return
	var u: String = _user.text.strip_edges()
	var pw: String = _pass.text
	if u.length() < 3 or pw.is_empty():
		_msg.text = U.t("Escribe usuario y contraseña.")
		return
	_busy = true
	_msg.add_theme_color_override("font_color", UI.CYAN)
	_msg.text = U.t("Conectando con el servidor…")
	_pass.text = ""
	await get_tree().process_frame
	await get_tree().process_frame
	GameClient.start_local_accounts({"username": u, "password": pw, "register": register}, avatar)


func _on_auth_result(ok: bool, info: Dictionary) -> void:
	_busy = false
	if not ok:
		if _msg != null and is_instance_valid(_msg):
			_msg.add_theme_color_override("font_color", UI.RED)
			_msg.text = str(info.get("message", U.t("No se pudo iniciar sesión")))
		return
	_info = info
	_build_granted()


# ---------------------------------------------------------------- 2. acceso concedido

func _step(n: int, title: String, detail: String, col: Color) -> Control:
	var h := UI.hbox(12)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UI.sb(col, col.lightened(0.3), 20, 2, 0))
	badge.custom_minimum_size = Vector2(40, 40)
	var nl := UI.label(str(n), 20, UI.BG, "game")
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(nl)
	h.add_child(badge)
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label(title, 18, UI.TEXT, "bold"))
	if not detail.is_empty():
		v.add_child(UI.wrap(UI.label(detail, 14, UI.TEXT_DIM)))
	h.add_child(v)
	return h


func _build_granted() -> void:
	_header(U.t("ACCESO CONCEDIDO"), "ui_check")
	var user: String = str(_info.get("username", ""))
	var created: bool = str(_info.get("action", "")) == "register"
	_box.add_child(_step(1, U.t("Cuenta creada: %s") % user if created else U.t("Contraseña correcta: %s") % user,
		U.t("El servidor guarda la contraseña cifrada (PBKDF2 con sal), nunca el texto original."), UI.GREEN))
	var mins: int = int(_info.get("expires_in", 900)) / 60
	_box.add_child(_step(2, U.t("El servidor entregó un token JWT firmado"),
		U.t("Tiene 3 partes: encabezado · datos · firma. Vale %d minutos.") % mins, UI.CYAN))
	var jwt: Dictionary = GameClient.decode_jwt(str(_info.get("access_token", "")))
	var tok := UI.panel("Chip")
	var tv := UI.vbox(4)
	tok.add_child(tv)
	var short := func(s: String, n: int) -> String: return s.substr(0, n) + ("…" if s.length() > n else "")
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.add_theme_font_size_override("normal_font_size", 15)
	rich.custom_minimum_size.x = 680
	rich.text = "[color=#3fd0ff]%s[/color][color=#8fa3c8].[/color][color=#ffc24a]%s[/color][color=#8fa3c8].[/color][color=#b388ff]%s[/color]" % [
		short.call(str(jwt.get("header", "")), 20), short.call(str(jwt.get("payload", "")), 34), short.call(str(jwt.get("signature", "")), 20)]
	tv.add_child(rich)
	var data: Dictionary = jwt.get("data", {})
	tv.add_child(UI.label(U.t("Contenido: jugador %s · nombre %s · emisor %s") % [str(data.get("sub", "")), str(data.get("name", "")), str(data.get("iss", ""))], 14, UI.GOLD))
	_box.add_child(tok)
	_box.add_child(_step(3, U.t("Al entrar, el servidor valida la firma del token"),
		U.t("Si alguien cambia el token, la firma ya no coincide y el servidor lo rechaza."), UI.PURPLE))
	_tamper_label = UI.wrap(UI.label("", 15, UI.RED, "semibold"))
	_box.add_child(_tamper_label)
	var row := UI.hbox(10)
	var tamper := UI.button(U.t("Probar token alterado"), "GhostButton", "ui_warning", Vector2(0, 60))
	tamper.name = "Tamper"
	tamper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tamper.pressed.connect(_try_tampered)
	row.add_child(tamper)
	var enter := UI.button(U.t("ENTRAR AL JUEGO"), "GreenButton", "ui_ship", Vector2(0, 60))
	enter.name = "Enter"
	enter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enter.pressed.connect(_enter)
	row.add_child(enter)
	_box.add_child(row)


## Cambia el jugador dentro del token sin volver a firmarlo y lo envía.
func _try_tampered() -> void:
	var parts: PackedStringArray = str(_info.get("access_token", "")).split(".")
	if parts.size() != 3:
		return
	var fake: Dictionary = GameClient.decode_jwt(str(_info.get("access_token", ""))).get("data", {}).duplicate()
	fake["sub"] = "plr_otro_jugador"
	var body: String = Marshalls.raw_to_base64(JSON.stringify(fake).to_utf8_buffer()).replace("+", "-").replace("/", "_").replace("=", "")
	_testing_tamper = true
	_tamper_label.add_theme_color_override("font_color", UI.GOLD)
	_tamper_label.text = U.t("Enviando un token con otro jugador adentro, pero con la firma original…")
	GameClient.enter_with_token(parts[0] + "." + body + "." + parts[2])


func _on_connection_changed(state: String, detail: String) -> void:
	if state == "error" and _testing_tamper and _tamper_label != null and is_instance_valid(_tamper_label):
		_testing_tamper = false
		GameClient.hold_hello = true
		_tamper_label.add_theme_color_override("font_color", UI.RED)
		_tamper_label.text = U.t("RECHAZADO. El servidor respondió: «%s». La firma ya no coincide con los datos del token.") % detail


func _enter() -> void:
	set_process(false)
	GameClient.enter_with_token()
	get_tree().change_scene_to_file("res://ui/game.tscn")


func _close() -> void:
	if not _info.is_empty() or _busy:
		GameClient.disconnect_all()
	queue_free()
