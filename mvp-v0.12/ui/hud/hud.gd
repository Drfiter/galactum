extends Control
## HUD principal (estilo Lords Mobile): barra de recursos, comandante, misión
## activa, flotas en curso, alertas de ataque, menú inferior, minimapa y la
## ficha contextual de lo que se toca en el mapa.

const UI = preload("res://ui/ui.gd")
const U = preload("res://shared/util.gd")
const Minimap = preload("res://ui/hud/minimap.gd")

const MISSION_NAMES: Dictionary = {"gather": "Minería", "hunt": "Caza", "attack": "Ataque", "scout": "Espionaje"}
const MISSION_ICONS: Dictionary = {"gather": "ui_mine", "hunt": "ui_hunt", "attack": "ui_attack", "scout": "ui_scout"}
const STATE_NAMES: Dictionary = {"outbound": "En ruta", "working": "Minando", "returning": "Regresando"}
const TOP_RES: Array = ["roderitium", "kliptium", "copper", "water", "aluminium", "ore", "food", "aminoacids", "oxygen", "co2"]
const TOP_CUR: Array = ["credits", "dark_matter", "energy", "plasma"]

var game: Node
var top_bar: PanelContainer
var avatar_rect: TextureRect
var name_label: Label
var power_label: Label
var res_labels: Dictionary = {}
var mission_card: PanelContainer
var fleet_panel: PanelContainer
var fleet_rows: VBoxContainer
var fleet_header: Label
var toggle_btn: Button
var toggle_label: Label
var menu_bar: HBoxContainer
var menu_badges: Dictionary = {}
var feature_bar: VBoxContainer
var feature_badges: Dictionary = {}
var minimap: Control
var coords_chip: PanelContainer
var coords_label: Label
var system_chip: Button
var incoming_banner: PanelContainer
var incoming_label: Label
var popup: PanelContainer
var popup_body: VBoxContainer
var hint_banner: PanelContainer
var hint_label: Label
var popup_entity_id: String = ""
var popup_tile: Vector2i = Vector2i(-1, -1)
var in_base: bool = true
var _accum: float = 0.0
var _fleet_sig: String = ""
var _popup_refresh_pending: bool = false
var _pointer_down: bool = false
var _popup_hidden_ms: int = -100000
var _alerted_ids: Dictionary = {}
## Tiempo que la barra inferior espera tras cerrar la tarjeta, para que el
## mismo toque no caiga sobre "Informes" u otro botón que reaparece debajo.
const MENU_REAPPEAR_MS: int = 450
var _pointer_pos: Vector2 = Vector2.ZERO
var _mission_sig: String = ""
var _event_timers: Array = []


func setup(game_node: Node) -> void:
	game = game_node
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full_rect(self)
	_build_top()
	_build_mission_card()
	_build_fleet_panel()
	_build_bottom()
	_build_features()
	_build_minimap()
	_build_incoming()
	_build_popup()
	_build_hint()
	GameClient.player_updated.connect(refresh)
	refresh()


# ---------------------------------------------------------------- construcción

func _build_top() -> void:
	top_bar = UI.panel("TopBar")
	add_child(top_bar)
	var h := UI.hbox(10)
	top_bar.add_child(h)
	var av_btn := Button.new()
	av_btn.flat = true
	av_btn.custom_minimum_size = Vector2(54, 54)
	av_btn.focus_mode = Control.FOCUS_NONE
	avatar_rect = UI.image(null, Vector2(54, 54))
	UI.full_rect(avatar_rect)
	av_btn.add_child(avatar_rect)
	av_btn.pressed.connect(func() -> void: game.open_panel("commander"))
	av_btn.tooltip_text = U.t("Comandante: nivel, Protocolos de Mando y prisioneros")
	h.add_child(av_btn)
	var nv := UI.vbox(0)
	nv.custom_minimum_size.x = 170
	name_label = UI.label("", 16, UI.TEXT, "bold")
	name_label.clip_text = true
	power_label = UI.label("", 15, UI.GOLD, "bold")
	power_label.clip_text = true
	nv.add_child(name_label)
	nv.add_child(power_label)
	h.add_child(nv)
	var strip_btn := Button.new()
	strip_btn.flat = true
	strip_btn.focus_mode = Control.FOCUS_NONE
	strip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_btn.pressed.connect(func() -> void: game.open_panel("elements"))
	h.add_child(strip_btn)
	var strip := UI.hbox(2)
	UI.full_rect(strip)
	strip_btn.add_child(strip)
	for id: String in TOP_RES + TOP_CUR:
		var chip := UI.hbox(3)
		chip.custom_minimum_size.x = 64 if id in TOP_RES else 74
		chip.add_child(UI.icon(UI.res_icon_name(id), 22))
		var l := UI.label("0", 15, UI.TEXT, "semibold")
		if id == "dark_matter":
			l.add_theme_color_override("font_color", Color("e2b8ff"))
		elif id == "credits":
			l.add_theme_color_override("font_color", UI.GOLD)
		chip.add_child(l)
		res_labels[id] = l
		strip.add_child(chip)
		if id == "co2":
			strip.add_child(UI.spacer(false, Vector2(10, 0)))


func _build_mission_card() -> void:
	mission_card = UI.panel("Chip")
	mission_card.custom_minimum_size = Vector2(300, 0)
	add_child(mission_card)


func _build_fleet_panel() -> void:
	fleet_panel = UI.panel("Chip")
	fleet_panel.custom_minimum_size = Vector2(280, 0)
	add_child(fleet_panel)
	var v := UI.vbox(6)
	fleet_panel.add_child(v)
	var hh := UI.hbox(6)
	hh.add_child(UI.icon("ui_ship", 20, UI.CYAN))
	fleet_header = UI.label(U.t("FLOTAS"), 15, UI.CYAN, "bold")
	hh.add_child(fleet_header)
	v.add_child(hh)
	fleet_rows = UI.vbox(6)
	v.add_child(fleet_rows)


func _build_bottom() -> void:
	toggle_btn = Button.new()
	toggle_btn.focus_mode = Control.FOCUS_NONE
	toggle_btn.custom_minimum_size = Vector2(108, 108)
	var round_sb := UI.sb(Color("123a6b"), UI.CYAN, 54, 3, 0)
	round_sb.shadow_color = Color(0.2, 0.7, 1.0, 0.35)
	round_sb.shadow_size = 12
	toggle_btn.add_theme_stylebox_override("normal", round_sb)
	toggle_btn.add_theme_stylebox_override("hover", UI.sb(Color("174a85"), Color("8fe9ff"), 54, 3, 0))
	toggle_btn.add_theme_stylebox_override("pressed", UI.sb(Color("0d2a4f"), UI.CYAN, 54, 3, 0))
	toggle_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	toggle_btn.pressed.connect(func() -> void:
		if in_base:
			game.show_map()
		else:
			game.show_base())
	add_child(toggle_btn)
	var tv := UI.vbox(0, BoxContainer.ALIGNMENT_CENTER)
	UI.full_rect(tv)
	toggle_btn.add_child(tv)
	var ti := UI.icon("ui_map", 46)
	ti.name = "Icon"
	ti.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tv.add_child(ti)
	toggle_label = UI.outline(UI.label(U.t("MAPA"), 20, UI.TEXT, "game"), 6)
	toggle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(toggle_label)

	menu_bar = UI.hbox(8)
	add_child(menu_bar)
	for entry: Array in [["missions", U.t("Misiones"), "ui_missions"], ["reports", U.t("Informes"), "ui_reports"], ["alliance", U.t("Alianza"), "ui_alliance"], ["galaxy", U.t("Galaxia"), "ui_galaxy"], ["shop", U.t("Tienda"), "ui_shop"], ["inventory", U.t("Objetos"), "ui_inventory"], ["lab", U.t("Laboratorio"), "ui_lab"], ["settings", U.t("Menú"), "ui_settings"]]:
		var b := Button.new()
		b.theme_type_variation = "TabButton"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(88, 72)
		var v := UI.vbox(2, BoxContainer.ALIGNMENT_CENTER)
		UI.full_rect(v)
		var ic := UI.icon(entry[2], 30, UI.TEXT)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var l := UI.label(entry[1], 13, UI.TEXT_DIM, "semibold")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		b.add_child(v)
		var key: String = entry[0]
		b.pressed.connect(func() -> void:
			if key == "lab":
				game.open_panel("room", {"room": "lab"})
			else:
				game.open_panel(key))
		var bd := UI.badge("!", UI.RED)
		bd.position = Vector2(62, -4)
		bd.visible = false
		b.add_child(bd)
		menu_badges[key] = bd
		menu_bar.add_child(b)


## Columna de accesos destacados (estilo Lords Mobile): bono diario, eventos…
func _build_features() -> void:
	feature_bar = UI.vbox(8)
	add_child(feature_bar)
	for entry: Array in [["login", U.t("Bono"), "ui_calendar", Color("43b83a")], ["events", U.t("Eventos"), "ui_event", Color("f2a81d")], ["liveops", U.t("Pase"), "ui_trophy", Color("e0567a")], ["crew", U.t("Tripul."), "ui_crew", Color("b06be0")]]:
		add_feature(entry[0], entry[1], entry[2], entry[3])


func add_feature(key: String, text: String, icon_name: String, col: Color) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(72, 72)
	var st := UI.sb(col.darkened(0.35), col.lightened(0.35), 36, 3, 0)
	st.shadow_color = Color(col, 0.35)
	st.shadow_size = 8
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", UI.sb(col.darkened(0.2), col.lightened(0.5), 36, 3, 0))
	b.add_theme_stylebox_override("pressed", UI.sb(col.darkened(0.5), col, 36, 3, 0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var v := UI.vbox(0, BoxContainer.ALIGNMENT_CENTER)
	UI.full_rect(v)
	b.add_child(v)
	var ic := UI.icon(icon_name, 34)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := UI.outline(UI.label(text, 13, UI.TEXT, "game"), 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.pressed.connect(func() -> void: game.open_panel(key))
	var bd := UI.badge("!", UI.RED)
	bd.position = Vector2(52, -4)
	bd.visible = false
	b.add_child(bd)
	feature_badges[key] = bd
	feature_bar.add_child(b)


func _build_minimap() -> void:
	minimap = Minimap.new()
	add_child(minimap)
	minimap.jump_to.connect(func(t: Vector2) -> void: game.focus_tile(t))
	coords_chip = UI.panel("Chip")
	add_child(coords_chip)
	var h := UI.hbox(6)
	coords_chip.add_child(h)
	coords_label = UI.label("X:0 Y:0", 14, UI.TEXT_DIM, "semibold")
	h.add_child(coords_label)
	system_chip = UI.button("", "GhostButton", "ui_galaxy", Vector2(0, 40))
	system_chip.add_theme_font_size_override("font_size", 15)
	system_chip.pressed.connect(func() -> void: game.open_panel("galaxy"))
	add_child(system_chip)
	var home := UI.icon_button("ui_home", 34, "GhostButton")
	home.pressed.connect(func() -> void: game.focus_tile(GameClient.base_pos()))
	h.add_child(home)


func _build_incoming() -> void:
	incoming_banner = UI.panel("CardRed")
	incoming_banner.visible = false
	add_child(incoming_banner)
	var h := UI.hbox(10)
	incoming_banner.add_child(h)
	h.add_child(UI.icon("ui_warning", 30, UI.RED))
	incoming_label = UI.label("", 17, Color("ffd0da"), "bold")
	h.add_child(incoming_label)
	var see := UI.button(U.t("Ver"), "DangerButton", "", Vector2(70, 40))
	see.pressed.connect(func() -> void:
		game.show_map()
		game.focus_tile(GameClient.base_pos()))
	h.add_child(see)
	var shield := UI.button(U.t("Escudo"), "GhostButton", "ui_shield", Vector2(110, 40))
	shield.name = "ShieldBtn"
	shield.pressed.connect(func() -> void: game.use_shield())
	h.add_child(shield)
	var esc := UI.button(U.t("Escapar"), "GoldButton", "ui_escape", Vector2(120, 40))
	esc.name = "EscapeBtn"
	esc.pressed.connect(func() -> void: game.escape_jump())
	h.add_child(esc)


func _build_popup() -> void:
	popup = UI.panel("")
	popup.visible = false
	popup.custom_minimum_size = Vector2(520, 0)
	add_child(popup)
	popup_body = UI.vbox(8)
	popup.add_child(popup_body)


func _build_hint() -> void:
	hint_banner = UI.panel("CardHi")
	hint_banner.visible = false
	add_child(hint_banner)
	var h := UI.hbox(10)
	hint_banner.add_child(h)
	h.add_child(UI.icon("ui_relocate", 26, UI.CYAN))
	hint_label = UI.label("", 17, UI.TEXT, "semibold")
	h.add_child(hint_label)
	var cancel := UI.button(U.t("Cancelar"), "GhostButton", "", Vector2(110, 40))
	cancel.pressed.connect(func() -> void: game.cancel_relocation())
	h.add_child(cancel)


# ---------------------------------------------------------------- layout

func _process(delta: float) -> void:
	_layout()
	_accum += delta
	if _accum >= 0.25:
		_accum = 0.0
		_tick()


func _layout() -> void:
	var s: Vector2 = size
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(s.x, 0)
	var top_h: float = top_bar.size.y
	mission_card.position = Vector2(10, top_h + 10)
	mission_card.size = Vector2(300, 0)
	fleet_panel.visible = not (GameClient.me.get("fleets", []) as Array).is_empty() or not in_base
	fleet_panel.position = Vector2(s.x - fleet_panel.size.x - 10, top_h + 10)
	fleet_panel.size = Vector2(280, 0)
	toggle_btn.position = Vector2(14, s.y - 122)
	feature_bar.position = Vector2(10, mission_card.position.y + mission_card.size.y + 12)
	feature_bar.size = feature_bar.get_combined_minimum_size()
	feature_bar.visible = feature_bar.position.y + feature_bar.size.y < toggle_btn.position.y - 4
	var mb: Vector2 = menu_bar.get_combined_minimum_size()
	menu_bar.size = mb
	menu_bar.position = Vector2((s.x - mb.x) / 2.0, s.y - mb.y - 10)
	menu_bar.visible = not popup.visible and Time.get_ticks_msec() - _popup_hidden_ms >= MENU_REAPPEAR_MS
	minimap.visible = not in_base
	coords_chip.visible = not in_base
	minimap.size = Vector2(170, 170)
	minimap.position = Vector2(s.x - 184, s.y - 184)
	var cs: Vector2 = coords_chip.get_combined_minimum_size()
	coords_chip.size = cs
	coords_chip.position = Vector2(s.x - 184 + (170 - cs.x) / 2.0, s.y - 184 - cs.y - 6)
	system_chip.visible = not in_base
	var sc: Vector2 = system_chip.get_combined_minimum_size()
	system_chip.size = sc
	system_chip.position = Vector2(s.x - 14 - sc.x, coords_chip.position.y - sc.y - 6)
	var ib: Vector2 = incoming_banner.get_combined_minimum_size()
	incoming_banner.size = ib
	incoming_banner.position = Vector2((s.x - ib.x) / 2.0, top_h + 10)
	var hb: Vector2 = hint_banner.get_combined_minimum_size()
	hint_banner.size = hb
	hint_banner.position = Vector2((s.x - hb.x) / 2.0, top_h + (64 if incoming_banner.visible else 10))
	if popup.visible:
		var ps: Vector2 = popup.get_combined_minimum_size()
		popup.size = Vector2(maxf(ps.x, 520), 0)
		popup.position = Vector2((s.x - popup.size.x) / 2.0, s.y - popup.get_combined_minimum_size().y - 12.0 - _bottom_inset())


# ---------------------------------------------------------------- actualización

func set_mode(base_mode: bool) -> void:
	in_base = base_mode
	(toggle_btn.get_child(0).get_node("Icon") as TextureRect).texture = UI.icon_tex("ui_map" if base_mode else "ui_ship")
	toggle_label.text = U.t("MAPA") if base_mode else U.t("NAVE")
	if base_mode:
		hide_popup()


func refresh() -> void:
	var me: Dictionary = GameClient.me
	if me.is_empty():
		return
	avatar_rect.texture = UI.portrait_tex(str(me.get("avatar", "p01")))
	var tag: String = str(me.get("tag", ""))
	name_label.text = ("[%s] " % tag if not tag.is_empty() else "") + str(me.get("name", ""))
	# Nivel del Comandante: rojo si está capturado, verde si tiene puntos sin asignar.
	var cmd: Dictionary = me.get("commander", {})
	var captured: bool = not (cmd.get("captured", {}) as Dictionary).is_empty()
	power_label.text = (U.t("CAPTURADO") if captured else U.t("Poder") + " " + U.fmt_num(int(me.get("power", 0)))) + " · " + U.t("Nv %d") % int(cmd.get("level", 1))
	if not captured and int(cmd.get("points", 0)) > 0:
		power_label.text += " (+%d)" % int(cmd.get("points", 0))
	power_label.add_theme_color_override("font_color", UI.RED if captured else (UI.GREEN if int(cmd.get("points", 0)) > 0 else UI.GOLD))
	var sys: Dictionary = me.get("system", {})
	system_chip.text = "S%d · %s" % [int(sys.get("index", 0)), str(sys.get("name", ""))]
	_tick()
	menu_badges["reports"].visible = GameClient.unread_reports() > 0
	(menu_badges["reports"].get_child(0) as Label).text = str(GameClient.unread_reports())
	menu_badges["missions"].visible = GameClient.story_claimable() or GameClient.daily_claimable()
	var caps: int = (me.get("capsules", []) as Array).size()
	menu_badges["alliance"].visible = caps > 0
	(menu_badges["alliance"].get_child(0) as Label).text = str(caps)
	menu_badges["lab"].visible = false
	feature_badges["login"].visible = bool(me.get("shop", {}).get("login", {}).get("available", false))
	feature_badges["liveops"].visible = preload("res://ui/panels/liveops_panel.gd").claimable(me.get("liveops", {})) > 0
	menu_badges["alliance"].visible = caps > 0 or int(me.get("guild_brief", {}).get("chests", 0)) > 0
	(menu_badges["alliance"].get_child(0) as Label).text = str(caps + int(me.get("guild_brief", {}).get("chests", 0)))
	if not popup_entity_id.is_empty() or popup_tile.x >= 0:
		if _pointer_on_popup():
			# Reconstruir la tarjeta ahora destruiría el botón que el jugador
			# está tocando y el toque se perdería: se aplaza hasta que suelte.
			_popup_refresh_pending = true
		else:
			_refresh_popup()


## Alto (en coordenadas del juego) de la zona inferior reservada por el sistema
## en móviles: barra de gestos o de navegación de Android.
func _bottom_inset() -> float:
	if not OS.has_feature("mobile"):
		return 0.0
	var win: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if win.y <= 0 or safe.size.y <= 0:
		return 0.0
	var inset_px: int = maxi(0, win.y - safe.end.y)
	return float(inset_px) * size.y / float(win.y)


## ¿Hay un dedo/clic presionado sobre la tarjeta del objetivo?
func _pointer_on_popup() -> bool:
	return popup.visible and _pointer_down and popup.get_global_rect().has_point(_pointer_pos)


## Sigue el primer dedo (o el clic) sin consumir el evento.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_pointer_down = (event as InputEventMouseButton).pressed
		_pointer_pos = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).index == 0:
		_pointer_down = (event as InputEventScreenTouch).pressed
		_pointer_pos = (event as InputEventScreenTouch).position


func _tick() -> void:
	if _popup_refresh_pending and not _pointer_on_popup():
		_popup_refresh_pending = false
		if popup.visible:
			_refresh_popup()
	var me: Dictionary = GameClient.me
	if me.is_empty():
		return
	for id: String in res_labels:
		var v: int = GameClient.res(id)
		var l: Label = res_labels[id]
		if id == "energy":
			l.text = "%d/%d" % [v, int(me.get("energy_max", 100))]
		else:
			l.text = U.fmt_num(v)
		if id in TOP_RES:
			l.add_theme_color_override("font_color", UI.TEXT if v > int(me.get("caps", {}).get("vault", 0)) else Color("9fe0b9"))
	_update_mission_card()
	_update_fleets()
	_update_incoming()
	var c: Vector2 = game.map_view.center_tiles()
	coords_label.text = "X:%d  Y:%d" % [int(c.x), int(c.y)]
	minimap.view_center = c
	var vs: Vector2 = get_viewport_rect().size / game.map_view.zoom_level() / 32.0
	minimap.view_extent = vs / 2.0


func _update_mission_card() -> void:
	var me: Dictionary = GameClient.me
	var s: Dictionary = me.get("story", {})
	var d: Dictionary = me.get("daily", {})
	var eb0: Dictionary = me.get("event_brief", {})
	var sig: String = "%s|%s|%s|%s|%s|%s|%s" % [str(s.get("id", "")), str(s.get("progress", 0)), str(d.get("points", 0)), str(d.get("claimed", [])), str(eb0.get("resource", "")), str(eb0.get("tournament", "")), str(eb0.get("my_rank", 0))]
	for et0: Label in _event_timers:
		if is_instance_valid(et0):
			et0.text = U.fmt_duration_short(maxf(0.0, float(int(et0.get_meta("end")) - GameClient.server_now()) / 1000.0))
	if sig == _mission_sig:
		return
	_mission_sig = sig
	_event_timers.clear()
	UI.clear(mission_card)
	var v := UI.vbox(6)
	mission_card.add_child(v)
	if not s.is_empty():
		var hh := UI.hbox(6)
		hh.add_child(UI.icon("ui_missions", 18, UI.GOLD))
		hh.add_child(UI.label(U.t("MISIÓN %d/%d") % [int(s.get("index", 0)) + 1, int(s.get("total", 1))], 13, UI.GOLD, "bold"))
		v.add_child(hh)
		v.add_child(UI.wrap(UI.label(str(s.get("title", "")), 16, UI.TEXT, "bold"), 276))
		var done: bool = int(s.get("progress", 0)) >= int(s.get("target", 1))
		var row := UI.hbox(8)
		var bar := UI.progress(minf(float(s.get("progress", 0)), float(s.get("target", 1))), float(s.get("target", 1)), UI.GOLD if done else UI.CYAN, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		row.add_child(UI.label("%s/%s" % [U.fmt_num(mini(int(s.get("progress", 0)), int(s.get("target", 1)))), U.fmt_num(int(s.get("target", 1)))], 13, UI.TEXT_DIM))
		v.add_child(row)
		var btn := UI.button(U.t("¡Reclamar!") if done else U.t("Ir"), "GoldButton" if done else "GhostButton", "ui_gift" if done else "", Vector2(0, 40))
		btn.pressed.connect(func() -> void:
			if done:
				game.claim_story()
			else:
				game.goto_mission(s))
		v.add_child(btn)
	else:
		v.add_child(UI.label(U.t("Historia completada"), 15, UI.GREEN, "bold"))
	v.add_child(UI.separator())
	var tiers: Array = d.get("tiers", [])
	var maxp: float = float(tiers[tiers.size() - 1]["points"]) if not tiers.is_empty() else 1.0
	var eb: Dictionary = me.get("event_brief", {})
	var dh := UI.hbox(6)
	dh.add_child(UI.label(str(d.get("name", U.t("Órdenes del Día"))), 13, UI.PURPLE, "bold"))
	dh.add_child(UI.spacer())
	dh.add_child(UI.label(U.t("%d pts") % int(d.get("points", 0)), 13, UI.TEXT_DIM, "semibold"))
	v.add_child(dh)
	v.add_child(UI.progress(float(d.get("points", 0)), maxp, UI.PURPLE, 8))
	if not eb.is_empty():
		v.add_child(UI.separator())
		var er := UI.hbox(6)
		er.add_child(UI.icon("ui_event", 16, UI.GOLD))
		var el := UI.label(str(eb.get("resource", "")), 13, UI.GOLD, "bold")
		el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		el.clip_text = true
		er.add_child(el)
		var et := UI.label("", 13, UI.TEXT_DIM, "semibold")
		et.set_meta("end", int(eb.get("resource_end", 0)))
		_event_timers.append(et)
		er.add_child(et)
		v.add_child(er)
		var trow := UI.hbox(6)
		trow.add_child(UI.icon("ui_trophy", 16, UI.CYAN))
		var tl := UI.label(str(eb.get("tournament", "")), 13, UI.CYAN, "bold")
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.clip_text = true
		trow.add_child(tl)
		var rank: int = int(eb.get("my_rank", 0))
		trow.add_child(UI.label(("#%d" % rank) if rank > 0 else "—", 13, UI.TEXT, "bold"))
		v.add_child(trow)


func _update_fleets() -> void:
	var me: Dictionary = GameClient.me
	var fl: Array = me.get("fleets", [])
	fleet_header.text = U.t("FLOTAS  %d/%d") % [fl.size(), int(me.get("caps", {}).get("march_slots", 2))]
	var sig: String = ""
	for f: Dictionary in fl:
		sig += "%s:%s:%s;" % [f["id"], f["state"], str(f.get("arrive_ts", 0))]
	if sig != _fleet_sig:
		_fleet_sig = sig
		UI.clear(fleet_rows)
		if fl.is_empty():
			fleet_rows.add_child(UI.label(U.t("Sin flotas activas"), 13, UI.TEXT_MUTED))
		for f: Dictionary in fl:
			fleet_rows.add_child(_fleet_row(f))
	var now: int = GameClient.server_now()
	for row: Node in fleet_rows.get_children():
		if not row.has_meta("fleet"):
			continue
		var f2: Dictionary = row.get_meta("fleet")
		var t0: int = int(f2.get("work_start", f2["depart_ts"])) if f2["state"] == "working" else int(f2["depart_ts"])
		var t1: int = int(f2.get("work_end", f2["arrive_ts"])) if f2["state"] == "working" else int(f2["arrive_ts"])
		var bar: ProgressBar = row.get_meta("bar")
		bar.value = clampf(float(now - t0) / maxf(1.0, float(t1 - t0)), 0.0, 1.0) * 100.0
		(row.get_meta("timer") as Label).text = "%s · %s" % [U.t(STATE_NAMES.get(f2["state"], "")), U.fmt_time(float(t1 - now) / 1000.0)]


func _fleet_row(f: Dictionary) -> Control:
	var card := UI.panel("Card")
	var h := UI.hbox(8)
	card.add_child(h)
	var col: Color = UI.GOLD if f["mission"] == "gather" else (UI.RED if f["mission"] == "attack" else (UI.PURPLE if f["mission"] == "hunt" else UI.CYAN))
	h.add_child(UI.icon(MISSION_ICONS.get(f["mission"], "ui_ship"), 26, col))
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name: String = U.t(MISSION_NAMES.get(f["mission"], U.t("Flota")))
	if f["state"] == "working" and not str(f.get("element", "")).is_empty():
		name += " · " + Catalog.res_name(str(f["element"]))
	v.add_child(UI.label(name + "  (%s)" % U.fmt_num(int(f.get("troops_total", 0))), 14, UI.TEXT, "bold"))
	var timer := UI.label("", 12, UI.TEXT_DIM)
	v.add_child(timer)
	var bar := UI.progress(0, 100, col, 6)
	v.add_child(bar)
	h.add_child(v)
	if f["state"] != "returning":
		var rb := UI.icon_button("ui_recall", 38, "GhostButton")
		rb.pressed.connect(func() -> void: game.recall_fleet(str(f["id"])))
		h.add_child(rb)
	card.set_meta("fleet", f)
	card.set_meta("bar", bar)
	card.set_meta("timer", timer)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			game.show_map()
			game.focus_tile(GameClient.entity_position(f)))
	return card


func _update_incoming() -> void:
	var inc: Array = GameClient.me.get("incoming", [])
	var now: int = GameClient.server_now()
	var soonest: Dictionary = {}
	for i: Dictionary in inc:
		if i["mission"] != "attack":
			continue
		if soonest.is_empty() or int(i["arrive_ts"]) < int(soonest["arrive_ts"]):
			soonest = i
	incoming_banner.visible = not soonest.is_empty()
	if not soonest.is_empty():
		var aid: String = str(soonest.get("fleet_id", soonest.get("arrive_ts", "")))
		if not _alerted_ids.has(aid):
			_alerted_ids[aid] = true
			UI.Sfx.play("alert")
		var what: String = U.t("tu flota minera") if str(soonest.get("target_kind", "")) == "asteroid" else U.t("tu nave")
		incoming_label.text = U.t("¡ATAQUE ENTRANTE contra %s!  %s  ·  %s") % [what, str(soonest["from"]), U.fmt_time(float(int(soonest["arrive_ts"]) - now) / 1000.0)]
		var pulse: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 160.0)
		incoming_banner.modulate = Color(1, pulse, pulse)
		incoming_banner.get_child(0).get_node("ShieldBtn").visible = GameClient.res("peace_field_15m") > 0 and str(soonest.get("target_kind", "")) == "base"
		incoming_banner.get_child(0).get_node("EscapeBtn").visible = GameClient.res("escape_jump") > 0 and str(soonest.get("target_kind", "")) == "base" and (GameClient.me.get("fleets", []) as Array).is_empty()


func set_hint(text: String) -> void:
	hint_banner.visible = not text.is_empty()
	hint_label.text = text


# ---------------------------------------------------------------- ficha contextual

func show_entity(id: String) -> void:
	popup_entity_id = id
	popup_tile = Vector2i(-1, -1)
	_refresh_popup()


func show_tile(tile: Vector2i) -> void:
	popup_entity_id = ""
	popup_tile = tile
	_refresh_popup()


func hide_popup() -> void:
	if popup.visible:
		_popup_hidden_ms = Time.get_ticks_msec()
	popup.visible = false
	popup_entity_id = ""
	popup_tile = Vector2i(-1, -1)


func _refresh_popup() -> void:
	UI.clear(popup_body)
	if not popup_entity_id.is_empty():
		var e: Dictionary = GameClient.entities.get(popup_entity_id, {})
		if e.is_empty():
			hide_popup()
			return
		game.build_entity_card(popup_body, e)
	elif popup_tile.x >= 0:
		game.build_tile_card(popup_body, popup_tile)
	popup.visible = true
	popup.reset_size()
