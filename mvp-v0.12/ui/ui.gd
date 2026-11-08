extends RefCounted
## Kit de UI de Galactum: paleta, tema, fuentes y constructores de controles.
## Toda la interfaz se construye por código con estas piezas (consistencia visual).

const U = preload("res://shared/util.gd")

const BG := Color("060a1a")
const PANEL := Color("13204a")
const PANEL_2 := Color("1a2a5e")
const BORDER := Color("e2ad48")
const CYAN := Color("3fd0ff")
const CYAN_DIM := Color("1d7fa8")
const GOLD := Color("ffc24a")
const RED := Color("ff4d6d")
const GREEN := Color("3ddc97")
const PURPLE := Color("b388ff")
const TEXT := Color("e6f0ff")
const TEXT_DIM := Color("8fa3c8")
const TEXT_MUTED := Color("5b6d94")
const REL_COLORS: Dictionary = {"own": Color("3fd0ff"), "ally": Color("3ddc97"), "enemy": Color("ff4d6d"), "neutral": Color("ffb347")}

static var _tex_cache: Dictionary = {}
static var _fonts: Dictionary = {}


# ---------------------------------------------------------------- recursos gráficos

static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t


static func icon_tex(name: String) -> Texture2D:
	return tex("res://assets/icons/%s.svg" % name)


static func res_icon_name(id: String) -> String:
	if Catalog.items_by_id.has(id):
		var ic: String = str(Catalog.item(id).get("icon", "gift"))
		if ResourceLoader.exists("res://assets/icons/ui_%s.svg" % ic):
			return "ui_" + ic
		if ResourceLoader.exists("res://assets/icons/res_%s.svg" % ic):
			return "res_" + ic
		return "ui_gift"
	if ResourceLoader.exists("res://assets/icons/res_%s.svg" % id):
		return "res_" + id
	return "ui_star"


static func troop_icon_name(key: String) -> String:
	return "troop_" + str(Catalog.split_troop_key(key)[0])


static func portrait_tex(avatar: String) -> Texture2D:
	var info: Dictionary = Catalog.portraits.get(avatar, Catalog.portraits.get("p01", {}))
	return tex("res://assets/art/retratos/" + str(info.get("file", "p01_comandante_kael_g3.png")))


static func xeno_tex(species: String, level: int) -> Texture2D:
	var sp: Dictionary = Catalog.species_by_id.get(species, {})
	return tex("res://assets/art/xenoformas/%s_%s_n%d.png" % [species, sp.get("slug", ""), clampi(level, 1, 5)])


static func room_tex(room_id: String) -> Texture2D:
	var r: Dictionary = Catalog.room(room_id)
	if r.is_empty():
		for l: Dictionary in Catalog.rooms_data.get("locked", []):
			if l["id"] == room_id:
				r = l
	return tex("res://assets/art/salas/%s.png" % r.get("art", "s01_puente_de_mando"))


static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font
	match kind:
		"title":
			var fv := FontVariation.new()
			var orb: FontFile = load("res://assets/fonts/Orbitron.ttf")
			orb.fallbacks = [load("res://assets/fonts/Exo2.ttf")]
			fv.base_font = orb
			fv.variation_opentype = {"wght": 800}
			f = fv
		"game":
			var lil: FontFile = load("res://assets/fonts/LilitaOne.ttf")
			lil.fallbacks = [load("res://assets/fonts/Exo2.ttf")]
			f = lil
		"bold":
			var fb := FontVariation.new()
			fb.base_font = load("res://assets/fonts/Exo2.ttf")
			fb.variation_opentype = {"wght": 700}
			f = fb
		"semibold":
			var fs := FontVariation.new()
			fs.base_font = load("res://assets/fonts/Exo2.ttf")
			fs.variation_opentype = {"wght": 600}
			f = fs
		_:
			var fr := FontVariation.new()
			fr.base_font = load("res://assets/fonts/Exo2.ttf")
			fr.variation_opentype = {"wght": 500}
			f = fr
	_fonts[kind] = f
	return f


# ---------------------------------------------------------------- tema

static func sb(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 12, bw: int = 0, margin: float = 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin + 2
	s.content_margin_right = margin + 2
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	s.anti_aliasing = true
	return s


static var _theme_applied: bool = false


## Aplica el tema de Galactum a TODA la interfaz (incluidos los CanvasLayer),
## fusionándolo con el tema por defecto del motor.
static func apply_global_theme() -> void:
	if _theme_applied:
		return
	_theme_applied = true
	var th: Theme = build_theme()
	ThemeDB.get_default_theme().merge_with(th)
	ThemeDB.get_default_theme().default_font = th.default_font
	ThemeDB.get_default_theme().default_font_size = th.default_font_size


static func build_theme() -> Theme:
	var th := Theme.new()
	th.default_font = font("regular")
	th.default_font_size = 18
	th.set_color("font_color", "Label", TEXT)
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))

	var panel_sb := sb(Color(PANEL, 0.97), BORDER, 18, 3, 14)
	panel_sb.shadow_color = Color(0, 0, 0, 0.45)
	panel_sb.shadow_size = 14
	th.set_stylebox("panel", "PanelContainer", panel_sb)
	th.set_stylebox("panel", "Panel", panel_sb)
	_variation(th, "Card", "PanelContainer", sb(PANEL_2, Color("34508f"), 12, 2, 10))
	_variation(th, "CardHi", "PanelContainer", sb(Color("142347"), CYAN_DIM, 12, 2, 10))
	_variation(th, "CardGold", "PanelContainer", sb(Color("2a2210"), Color("8a6a1f"), 12, 2, 10))
	_variation(th, "CardRed", "PanelContainer", sb(Color("2a0f1a"), Color("a3213d"), 12, 2, 10))
	_variation(th, "Chip", "PanelContainer", sb(Color(0.03, 0.06, 0.14, 1.0), Color("1f3463"), 10, 1, 5))
	var bar := sb(Color(0.03, 0.05, 0.12, 0.97), Color("1f3463"), 0, 0, 6)
	bar.border_width_bottom = 2
	_variation(th, "TopBar", "PanelContainer", bar)
	_variation(th, "Clear", "PanelContainer", StyleBoxEmpty.new())
	_variation(th, "Dim", "PanelContainer", sb(Color(0.01, 0.02, 0.05, 0.72), Color.TRANSPARENT, 0, 0, 0))

	# Botones
	_button_style(th, "Button", Color("3b5bb5"), Color("6f8fe8"), Color("ffffff"))
	_button_style(th, "PrimaryButton", Color("2b98f0"), Color("8fd2ff"), Color("ffffff"))
	_button_style(th, "GoldButton", Color("f2a81d"), Color("ffe08a"), Color("ffffff"))
	_button_style(th, "DangerButton", Color("e23b52"), Color("ff9aa8"), Color("ffffff"))
	_button_style(th, "GreenButton", Color("43b83a"), Color("a8f09c"), Color("ffffff"))
	_button_style(th, "GhostButton", Color("26346a"), Color("4a64b0"), Color("dfe8ff"))
	_button_style(th, "TabButton", Color("1c2a58"), Color("34508f"), Color("c5d3f5"))
	for v: String in ["PrimaryButton", "GoldButton", "DangerButton", "GreenButton", "GhostButton", "TabButton"]:
		th.set_type_variation(v, "Button")
	th.set_font("font", "Button", font("game"))
	th.set_font_size("font_size", "Button", 20)
	th.set_constant("h_separation", "Button", 8)
	th.set_constant("icon_max_width", "Button", 30)

	# Entradas
	th.set_stylebox("normal", "LineEdit", sb(Color("0a1226"), Color("2b4a8a"), 10, 2, 10))
	th.set_stylebox("focus", "LineEdit", sb(Color("0a1226"), CYAN, 10, 2, 10))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	th.set_color("caret_color", "LineEdit", CYAN)
	th.set_font_size("font_size", "LineEdit", 20)

	# Barras
	th.set_stylebox("background", "ProgressBar", sb(Color("0a1022"), Color("1f3463"), 6, 1, 0))
	th.set_stylebox("fill", "ProgressBar", sb(CYAN, Color.TRANSPARENT, 6, 0, 0))
	th.set_color("font_color", "ProgressBar", Color.WHITE)
	th.set_font_size("font_size", "ProgressBar", 13)

	# Slider táctil
	var slider_bg := sb(Color("0a1022"), Color("1f3463"), 6, 1, 0)
	slider_bg.content_margin_top = 5
	slider_bg.content_margin_bottom = 5
	th.set_stylebox("slider", "HSlider", slider_bg)
	th.set_stylebox("grabber_area", "HSlider", sb(CYAN_DIM, Color.TRANSPARENT, 6, 0, 0))
	th.set_stylebox("grabber_area_highlight", "HSlider", sb(CYAN, Color.TRANSPARENT, 6, 0, 0))
	th.set_icon("grabber", "HSlider", _circle_tex(26, Color.WHITE, CYAN))
	th.set_icon("grabber_highlight", "HSlider", _circle_tex(28, Color.WHITE, CYAN))

	# Scroll fino
	var sbar := sb(Color(1, 1, 1, 0.04), Color.TRANSPARENT, 4, 0, 0)
	var sgrab := sb(Color(CYAN, 0.35), Color.TRANSPARENT, 4, 0, 0)
	for t: String in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("scroll", t, sbar)
		th.set_stylebox("grabber", t, sgrab)
		th.set_stylebox("grabber_highlight", t, sb(Color(CYAN, 0.6), Color.TRANSPARENT, 4, 0, 0))
		th.set_stylebox("grabber_pressed", t, sb(CYAN, Color.TRANSPARENT, 4, 0, 0))

	th.set_stylebox("panel", "TooltipPanel", sb(PANEL, BORDER, 8, 1, 8))
	th.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	th.set_color("default_color", "RichTextLabel", TEXT)
	return th


static func _variation(th: Theme, name: String, base: String, style: StyleBox) -> void:
	th.set_type_variation(name, base)
	th.set_stylebox("panel", name, style)


static func _button_style(th: Theme, type: String, bg: Color, border: Color, fg: Color) -> void:
	# Botón "chunky" con bisel: borde inferior grueso y oscuro, superior claro.
	var bottom: Color = bg.darkened(0.45)
	var n := sb(bg, bottom, 14, 2, 10)
	n.border_width_bottom = 6
	n.border_color = bottom
	n.shadow_color = Color(0, 0, 0, 0.4)
	n.shadow_size = 5
	n.shadow_offset = Vector2(0, 3)
	n.content_margin_bottom = 12
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = bg.lightened(0.12)
	var p := sb(bg.darkened(0.12), bottom, 14, 2, 10)
	p.border_width_bottom = 2
	p.content_margin_top = 14
	p.content_margin_bottom = 8
	var d := sb(Color(0.25, 0.28, 0.38, 0.85), Color(0.15, 0.17, 0.24, 0.9), 14, 2, 10)
	d.border_width_bottom = 5
	d.content_margin_bottom = 11
	th.set_stylebox("normal", type, n)
	th.set_stylebox("hover", type, h)
	th.set_stylebox("pressed", type, p)
	th.set_stylebox("hover_pressed", type, p)
	th.set_stylebox("disabled", type, d)
	th.set_stylebox("focus", type, StyleBoxEmpty.new())
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		th.set_color(k, type, fg)
	th.set_color("font_disabled_color", type, Color(0.7, 0.73, 0.82, 0.85))
	th.set_color("font_outline_color", type, Color(0.04, 0.05, 0.12, 0.85) if fg.get_luminance() > 0.5 else Color(1, 1, 1, 0.0))
	th.set_constant("outline_size", type, 6 if fg.get_luminance() > 0.5 else 0)
	for k2: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		th.set_color(k2, type, fg)
	th.set_color("icon_disabled_color", type, Color(0.6, 0.64, 0.72, 0.6))


static func _circle_tex(size: int, fill: Color, ring: Color) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size / 2.0, size / 2.0)
	for y: int in range(size):
		for x: int in range(size):
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
			var r: float = size / 2.0 - 1.0
			if d <= r - 3.0:
				img.set_pixel(x, y, fill)
			elif d <= r:
				img.set_pixel(x, y, ring)
			elif d <= r + 1.0:
				img.set_pixel(x, y, Color(ring, r + 1.0 - d))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- constructores

static func label(text: String, size: int = 18, color: Color = TEXT, kind: String = "regular") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if kind != "regular":
		l.add_theme_font_override("font", font(kind))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, size: int = 24, color: Color = TEXT) -> Label:
	var l := label(text, size + 2, color, "game")
	return outline(l, 7)


static func wrap(l: Label, min_width: float = 0.0) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if min_width > 0.0:
		l.custom_minimum_size.x = min_width
	return l


static func outline(l: Label, size: int = 4) -> Label:
	l.add_theme_constant_override("outline_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.06, 0.9))
	return l


static func icon(name: String, size: float = 24.0, tint: Color = Color.WHITE) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon_tex(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func image(texture: Texture2D, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func button(text: String, variation: String = "", icon_name: String = "", min_size: Vector2 = Vector2(0, 52)) -> Button:
	var b := Button.new()
	b.text = text
	if not variation.is_empty():
		b.theme_type_variation = variation
	if not icon_name.is_empty():
		b.icon = icon_tex(icon_name)
		b.expand_icon = false
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


static func icon_button(icon_name: String, size: float = 52.0, variation: String = "GhostButton") -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	b.icon = icon_tex(icon_name)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_constant_override("icon_max_width", int(size * 0.55))
	return b


static func hbox(sep: int = 8, align: int = BoxContainer.ALIGNMENT_BEGIN) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.alignment = align
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func vbox(sep: int = 8, align: int = BoxContainer.ALIGNMENT_BEGIN) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.alignment = align
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func flow(hsep: int = 10, vsep: int = 6) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", hsep)
	f.add_theme_constant_override("v_separation", vsep)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


static func panel(variation: String = "", child: Control = null) -> PanelContainer:
	var p := PanelContainer.new()
	if not variation.is_empty():
		p.theme_type_variation = variation
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	if child != null:
		p.add_child(child)
	return p


static func spacer(expand: bool = true, min_size: Vector2 = Vector2.ZERO) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func expand(c: Control, h: bool = true, v: bool = false) -> Control:
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func progress(value: float, max_value: float, color: Color = CYAN, height: float = 12.0, show_pct: bool = false) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = max_value
	p.value = value
	p.show_percentage = show_pct
	p.custom_minimum_size = Vector2(0, height)
	p.add_theme_stylebox_override("fill", sb(color, Color.TRANSPARENT, 6, 0, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func amount_chip(res_id: String, amount: int, size: int = 18, color: Color = TEXT) -> HBoxContainer:
	var h := hbox(4)
	h.add_child(icon(res_icon_name(res_id), size + 6))
	h.add_child(label(U.fmt_num(amount), size, color, "semibold"))
	return h


## Fila de costo; resalta en rojo lo que falta.
static func cost_row(cost: Dictionary, factor: float = 1.0, size: int = 17) -> HFlowContainer:
	var f := flow(14, 6)
	for k: String in cost:
		var need: int = int(ceil(float(cost[k]) * factor))
		var have: int = GameClient.res(k)
		var col: Color = TEXT if have >= need else RED
		f.add_child(amount_chip(k, need, size, col))
	return f


static func reward_row(reward: Dictionary, size: int = 17) -> HFlowContainer:
	var f := flow(14, 6)
	for k: String in reward:
		var h := hbox(4)
		h.add_child(icon(res_icon_name(k), size + 8))
		var txt: String = ("×%d" % int(reward[k])) if Catalog.items_by_id.has(k) else "+" + U.fmt_num(int(reward[k]))
		h.add_child(label(txt, size, GREEN if not Catalog.items_by_id.has(k) else GOLD, "semibold"))
		f.add_child(h)
	return f


static func troop_chip(key: String, qty: int, size: int = 30, color: Color = TEXT) -> HBoxContainer:
	var h := hbox(4)
	h.add_child(icon(troop_icon_name(key), size))
	var v := vbox(0)
	v.add_child(label(U.fmt_int(qty), 16, color, "bold"))
	v.add_child(label(Catalog.troop_name(key), 12, TEXT_DIM))
	h.add_child(v)
	return h


static func separator(color: Color = Color("1f3463")) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(0, 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
	return c


static func badge(text: String, color: Color = RED) -> PanelContainer:
	var p := PanelContainer.new()
	var s := sb(color, Color("0b1020"), 10, 2, 1)
	s.content_margin_left = 6
	s.content_margin_right = 6
	p.add_theme_stylebox_override("panel", s)
	var l := label(text, 13, Color.WHITE, "bold")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func clear(c: Node) -> void:
	for ch: Node in c.get_children():
		ch.queue_free()
