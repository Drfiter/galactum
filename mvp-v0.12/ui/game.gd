extends Node
## Escena de partida: orquesta mapa, interior de la nave, HUD, ventanas y avisos.

const UI = preload("res://ui/ui.gd")
const U = preload("res://shared/util.gd")
const MapView = preload("res://ui/world3d/map_view_3d.gd")
const ShipDeck = preload("res://ui/base/ship_deck_3d.gd")
const Hud = preload("res://ui/hud/hud.gd")
const BaseView = preload("res://ui/base/base_view.gd")

const PANELS: Dictionary = {
	"room": preload("res://ui/panels/room_panel.gd"),
	"fleet": preload("res://ui/panels/fleet_dialog.gd"),
	"reports": preload("res://ui/panels/reports_panel.gd"),
	"missions": preload("res://ui/panels/missions_panel.gd"),
	"alliance": preload("res://ui/panels/alliance_panel.gd"),
	"inventory": preload("res://ui/panels/inventory_panel.gd"),
	"elements": preload("res://ui/panels/elements_panel.gd"),
	"settings": preload("res://ui/panels/settings_panel.gd"),
	"reward": preload("res://ui/panels/reward_popup.gd"),
	"confirm": preload("res://ui/panels/confirm_dialog.gd"),
	"galaxy": preload("res://ui/panels/galaxy_panel.gd"),
	"shop": preload("res://ui/panels/shop_panel.gd"),
	"login": preload("res://ui/panels/login_panel.gd"),
	"events": preload("res://ui/panels/events_panel.gd"),
	"crew": preload("res://ui/panels/crew_panel.gd"),
	"commander": preload("res://ui/panels/commander_panel.gd"),
	"armory": preload("res://ui/panels/armory_panel.gd"),
	"alliance_hq": preload("res://ui/panels/alliance_hq_panel.gd"),
	"research": preload("res://ui/panels/research_panel.gd"),
	"battle": preload("res://ui/panels/battle_panel.gd"),
	"liveops": preload("res://ui/panels/liveops_panel.gd"),
	"expedition": preload("res://ui/panels/expedition_panel.gd"),
	"expedition_battle": preload("res://ui/panels/expedition_battle_panel.gd"),
	"endgame": preload("res://ui/panels/endgame_panel.gd"),
}

var map_view: Node3D
var deck: Node3D
var hud: Control
var base_view: Control
var modal_root: Control
var toast_box: VBoxContainer
var connecting_overlay: PanelContainer
var _stack: Array = []
var relocation_mode: String = ""   # "", "plasma", "warp"
var _welcomed: bool = false
var _login_offered: bool = false
var _last_base_pos: Vector2 = Vector2(-1, -1)
var hyper_layer: CanvasLayer
var hyper_rect: ColorRect
var hyper_label: Label


func _ready() -> void:
	UI.apply_global_theme()
	UI.Sfx.start_music()
	map_view = MapView.new()
	add_child(map_view)
	map_view.entity_tapped.connect(_on_entity_tapped)
	map_view.empty_tapped.connect(_on_empty_tapped)
	deck = ShipDeck.new()
	add_child(deck)
	deck.room_tapped.connect(func(id: String) -> void: open_panel("room", {"room": id}))
	deck.locked_tapped.connect(func(info: Dictionary) -> void: toast(U.t("%s: disponible en %s del roadmap. %s") % [info.get("name", ""), info.get("phase", U.t("Fase 2")), info.get("desc", "")], "info"))

	var base_layer := CanvasLayer.new()
	base_layer.layer = 3
	add_child(base_layer)
	base_view = BaseView.new()
	base_layer.add_child(base_view)
	base_view.setup(self)
	base_view.deck = deck
	deck.bubble_tapped.connect(base_view.collect)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = Hud.new()
	hud_layer.add_child(hud)
	hud.setup(self)

	var modal_layer := CanvasLayer.new()
	modal_layer.layer = 10
	add_child(modal_layer)
	modal_root = Control.new()
	modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full_rect(modal_root)
	modal_layer.add_child(modal_root)

	var toast_layer := CanvasLayer.new()
	toast_layer.layer = 20
	add_child(toast_layer)
	var toast_root := Control.new()
	toast_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full_rect(toast_root)
	toast_layer.add_child(toast_root)
	toast_box = UI.vbox(6)
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.offset_left = -270
	toast_box.offset_right = 270
	toast_box.offset_top = 76
	toast_root.add_child(toast_box)
	_build_connecting_overlay(toast_root)
	_build_hyperspace()

	GameClient.player_updated.connect(_on_first_player)
	GameClient.player_updated.connect(_on_base_moved)
	get_viewport().size_changed.connect(_fit_deck_later)
	GameClient.toast.connect(toast)
	GameClient.report_received.connect(_on_report)
	GameClient.welcomed.connect(_on_welcome)
	GameClient.connection_changed.connect(_on_connection_changed)
	GameClient.system_changed.connect(_on_system_changed)
	GameClient.chat_received.connect(func(m: Dictionary) -> void:
		if str(m.get("kind", "")) == "rally":
			toast("%s: %s" % [str(m.get("from", "")), str(m.get("text", ""))], "danger"))
	if GameClient.connected:
		_on_welcome()
	show_base()


func _build_connecting_overlay(root: Control) -> void:
	connecting_overlay = UI.panel("Dim")
	UI.full_rect(connecting_overlay)
	var c := CenterContainer.new()
	connecting_overlay.add_child(c)
	var v := UI.vbox(14, BoxContainer.ALIGNMENT_CENTER)
	c.add_child(v)
	v.add_child(UI.title(U.t("SINCRONIZANDO SISTEMA…"), 26, UI.CYAN))
	var l := UI.label(U.t("Conectando con el Servidor de Sistema Solar"), 18, UI.TEXT_DIM)
	l.name = "Detail"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var back := UI.button(U.t("Volver al título"), "GhostButton", "", Vector2(220, 48))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(back_to_title)
	v.add_child(back)
	root.add_child(connecting_overlay)
	connecting_overlay.visible = not GameClient.connected


func _build_hyperspace() -> void:
	hyper_layer = CanvasLayer.new()
	hyper_layer.layer = 15
	hyper_layer.visible = false
	add_child(hyper_layer)
	hyper_rect = ColorRect.new()
	UI.full_rect(hyper_rect)
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/hyperspace.gdshader")
	hyper_rect.material = m
	hyper_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	hyper_layer.add_child(hyper_rect)
	var c := CenterContainer.new()
	UI.full_rect(c)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hyper_rect.add_child(c)
	hyper_label = UI.title("", 34, Color("d9f3ff"))
	hyper_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(hyper_label)


## Secuencia de salto: estelas -> (el servidor cambia de sistema) -> destello.
func play_hyperspace(text: String, duration: float = 2.4) -> void:
	var m: ShaderMaterial = hyper_rect.material
	hyper_layer.visible = true
	hyper_label.text = text
	hyper_label.modulate.a = 0.0
	m.set_shader_parameter("alpha", 0.0)
	m.set_shader_parameter("intensity", 0.0)
	m.set_shader_parameter("flash", 0.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("alpha", v), 0.0, 1.0, 0.35)
	tw.parallel().tween_method(func(v: float) -> void: m.set_shader_parameter("intensity", v), 0.0, 1.0, duration * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(hyper_label, "modulate:a", 1.0, 0.5).set_delay(0.3)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("flash", v), 0.0, 1.0, 0.18)
	tw.tween_callback(func() -> void:
		m.set_shader_parameter("intensity", 0.15)
		hyper_label.modulate.a = 0.0)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("flash", v), 1.0, 0.0, 0.25)
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("alpha", v), 1.0, 0.0, 0.45)
	tw.tween_callback(func() -> void: hyper_layer.visible = false)


func interstellar_jump(system_id: String, method: String, name: String) -> void:
	play_hyperspace(U.t("SALTO INTERESTELAR") + "\n" + name)
	var params: Dictionary = {"system": system_id}
	var action: String = "jump"
	if method == "item":
		action = "use_item"
		params["item"] = "interstellar_jump"
	else:
		params["method"] = "portal"
	GameClient.intent(action, params, func(ok: bool, payload: Dictionary) -> void:
		if not ok:
			hyper_layer.visible = false
			toast(str(payload.get("message", "")), "error"))


func _on_system_changed(info: Dictionary) -> void:
	close_all_panels()
	hud.hide_popup()
	map_view.clear_selection()
	show_map()
	_welcomed = false
	await get_tree().create_timer(2.6).timeout
	toast(U.t("Bienvenido al Sistema %d · %s. Tu Alianza te acompaña.") % [int(info.get("index", 0)), str(info.get("name", ""))], "success")


func escape_jump() -> void:
	confirm(U.t("¿Usar Salto de Emergencia? Tu Astronave aparecerá al instante en un punto ALEATORIO y lejano del sistema. Las flotas enemigas en camino perderán tu rastro."), func() -> void:
		send("use_item", {"item": "escape_jump"}, func(p: Dictionary) -> void:
			show_map()
			hud.hide_popup()
			map_view.clear_selection()
			focus_tile(U.v2(p.get("pos", [300, 300])))), U.t("¡Saltar!"), "GoldButton")


func _on_welcome() -> void:
	connecting_overlay.visible = false
	_welcomed = false
	if not GameClient.me.is_empty():
		_on_first_player()


func _on_first_player() -> void:
	if _welcomed or GameClient.me.is_empty():
		return
	_welcomed = true
	map_view.center_on_tile(GameClient.base_pos(), false)
	_fit_deck_later()
	# Bono diario: se ofrece al entrar si hay una caja disponible.
	if not _login_offered and bool(GameClient.me.get("shop", {}).get("login", {}).get("available", false)) and int(GameClient.me.get("story", {}).get("index", 0)) >= 1:
		_login_offered = true
		await get_tree().create_timer(0.8).timeout
		if _stack.is_empty():
			open_panel("login")


## Cuando la Astronave cambia de casilla (llega de un viaje, Salto Warp o Salto
## de Emergencia) la cámara del mapa la acompaña, así el indicador de
## coordenadas muestra la posición nueva y no la anterior.
func _on_base_moved() -> void:
	if GameClient.me.is_empty():
		return
	var bp: Vector2 = GameClient.base_pos()
	if _last_base_pos.x >= 0.0 and bp.distance_to(_last_base_pos) > 0.5:
		map_view.center_on_tile(bp, map_view.visible)
	_last_base_pos = bp


func _on_connection_changed(state: String, detail: String) -> void:
	if state in ["closed", "error"]:
		connecting_overlay.visible = true
		var lbl: Label = connecting_overlay.find_child("Detail", true, false)
		if lbl != null:
			lbl.text = detail


## Botón "atrás" de Android: cierra ventanas/fichas o vuelve a la nave.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not _stack.is_empty():
			_close_modal(_stack[_stack.size() - 1])
		elif hud != null and hud.popup.visible:
			hud.hide_popup()
			map_view.clear_selection()
		elif not relocation_mode.is_empty():
			cancel_relocation()
		elif base_view != null and not base_view.visible:
			show_base()


func _process(_delta: float) -> void:
	# Los avisos se apilan bajo la alerta de ataque/indicación cuando están visibles.
	var top: float = 76.0
	if hud != null and (hud.incoming_banner.visible or hud.hint_banner.visible):
		top = 146.0
	toast_box.offset_top = top


# ---------------------------------------------------------------- navegación

func show_map() -> void:
	base_view.visible = false
	deck.activate(false)
	map_view.visible = true
	map_view.camera.make_current()
	map_view.input_enabled = true
	hud.set_mode(false)


func show_base() -> void:
	base_view.visible = true
	map_view.visible = false
	deck.activate(true)
	map_view.input_enabled = false
	map_view.clear_selection()
	cancel_relocation()
	hud.set_mode(true)
	_fit_deck_later()


## La cubierta se encuadra cuando el HUD ya calculó su tamaño (2 cuadros).
func _fit_deck_later() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	fit_deck()


## Encuadra la cubierta en el espacio libre: bajo la barra de colas, sobre la
## barra inferior y a la derecha de la tarjeta de misiones.
func fit_deck() -> void:
	if not base_view.visible:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var left: float = hud.mission_card.get_global_rect().end.x + 12.0
	var top: float = base_view.free_area_top() + 10.0
	var bottom: float = hud.menu_bar.get_global_rect().position.y - 10.0
	deck.fit_to(Rect2(left, top, vp.x - 12.0 - left, bottom - top))


func focus_tile(tile: Vector2) -> void:
	map_view.center_on_tile(tile)


## Cambia el idioma en caliente: recarga catálogos y reconstruye la escena
## (la partida y la conexión siguen vivas en GameClient).
func change_language(locale: String) -> void:
	preload("res://shared/i18n.gd").set_locale(locale)
	Catalog.reload()
	get_tree().reload_current_scene()


func back_to_title() -> void:
	GameClient.disconnect_all()
	get_tree().change_scene_to_file("res://ui/title.tscn")


# ---------------------------------------------------------------- ventanas

func open_panel(name: String, args: Dictionary = {}) -> Control:
	if not PANELS.has(name):
		return null
	# Sin alianza, el botón Alianza lleva a buscar o crear una.
	if name == "alliance" and str(GameClient.me.get("tag", "")).is_empty():
		name = "alliance_hq"
		args = {"tab": "search"}
	hud.hide_popup()
	map_view.clear_selection()
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.04, 0.68)
	UI.full_rect(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_root.add_child(dim)
	var center := CenterContainer.new()
	UI.full_rect(center)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var w: Control = PANELS[name].new()
	var vs: Vector2 = modal_root.get_viewport_rect().size
	var want: Vector2 = w.desired_size
	w.custom_minimum_size = Vector2(minf(want.x, vs.x - 40), minf(want.y, vs.y - 30))
	center.add_child(w)
	w.open(self, args)
	w.closed.connect(func() -> void: _close_modal(dim))
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and not w.get_global_rect().has_point((ev as InputEventMouseButton).global_position):
			if w.get("dismissable") != false:
				_close_modal(dim))
	_stack.append(dim)
	w.scale = Vector2(0.94, 0.94)
	w.pivot_offset = w.custom_minimum_size / 2.0
	w.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(w, "scale", Vector2.ONE, 0.18)
	tw.tween_property(w, "modulate:a", 1.0, 0.12)
	return w


func _close_modal(dim: Control) -> void:
	_stack.erase(dim)
	if is_instance_valid(dim):
		dim.queue_free()


func close_all_panels() -> void:
	for d: Control in _stack.duplicate():
		_close_modal(d)


func toast(text: String, kind: String = "info") -> void:
	if text.is_empty():
		return
	var colors: Dictionary = {"success": UI.GREEN, "error": UI.RED, "danger": UI.RED, "warning": UI.GOLD, "mission": UI.GOLD, "help": UI.GREEN, "info": UI.CYAN}
	var icons: Dictionary = {"success": "ui_check", "error": "ui_warning", "danger": "ui_warning", "warning": "ui_warning", "mission": "ui_missions", "help": "ui_help", "info": "ui_info"}
	var col: Color = colors.get(kind, UI.CYAN)
	if kind == "error":
		UI.Sfx.play("error")
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.sb(Color(0.03, 0.05, 0.12, 0.95), col, 12, 2, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UI.hbox(10)
	p.add_child(h)
	h.add_child(UI.icon(icons.get(kind, "ui_info"), 24, col))
	var l := UI.wrap(UI.label(text, 16, UI.TEXT, "semibold"), 440)
	h.add_child(l)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 3:
		toast_box.get_child(0).queue_free()
		toast_box.remove_child(toast_box.get_child(0))
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(3.0 if kind != "danger" else 4.5)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func show_reward(reward: Dictionary, title: String) -> void:
	UI.Sfx.play("reward")
	open_panel("reward", {"reward": reward, "title": title})


func confirm(text: String, on_yes: Callable, yes_label: String = "Confirmar", variation: String = "PrimaryButton") -> void:
	open_panel("confirm", {"text": text, "on_yes": on_yes, "yes": yes_label, "variation": variation})


# ---------------------------------------------------------------- acciones

func send(action: String, params: Dictionary = {}, on_ok: Callable = Callable()) -> void:
	GameClient.intent(action, params, func(ok: bool, payload: Dictionary) -> void:
		if not ok:
			toast(str(payload.get("message", U.t("Acción rechazada"))), "error")
		elif on_ok.is_valid():
			on_ok.call(payload))


func claim_story() -> void:
	var title: String = str(GameClient.me.get("story", {}).get("title", U.t("Misión")))
	send("claim_mission", {}, func(p: Dictionary) -> void: show_reward(p.get("reward", {}), U.t("Misión completada: ") + title))


func recall_fleet(fleet_id: String) -> void:
	send("recall", {"fleet_id": fleet_id}, func(_p: Dictionary) -> void: toast(U.t("Flota retirada: regresa a la nave"), "info"))


func use_shield() -> void:
	confirm(U.t("¿Activar Campo de Distorsión (15 min)? Tu nave no podrá ser atacada ni espiada. Se rompe si atacas."), func() -> void:
		send("use_item", {"item": "peace_field_15m"}, func(_p: Dictionary) -> void: toast(U.t("Campo de Distorsión activo"), "success")))


func open_fleet_dialog(mission: String, entity: Dictionary) -> void:
	if mission == "scout":
		var cost: int = int(Catalog.cfg("scout_cost_credits", 50))
		send("march", {"mission": "scout", "target_id": entity["id"], "troops": {}}, func(_p: Dictionary) -> void:
			UI.Sfx.play("launch")
			toast(U.t("Sonda de espionaje enviada (-%d Créditos)") % cost, "info")
			hud.hide_popup())
		return
	open_panel("fleet", {"mission": mission, "entity": entity})


func start_relocation(mode: String) -> void:
	relocation_mode = mode
	show_map()
	hud.hide_popup()
	hud.set_hint(U.t("Toca un punto libre del mapa para %s") % (U.t("el Salto Warp") if mode == "warp" else U.t("mover la Astronave")))


func cancel_relocation() -> void:
	relocation_mode = ""
	if hud != null:
		hud.set_hint("")


func goto_mission(s: Dictionary) -> void:
	var ev: String = str(s.get("event", ""))
	match ev:
		"collect":
			show_base()
			toast(U.t("Toca la burbuja de producción sobre una sala productora"), "info")
		"room_level:factory":
			open_panel("room", {"room": "factory"})
		"room_level:bridge":
			open_panel("room", {"room": "bridge"})
		"troops_trained":
			open_panel("room", {"room": "hangar"})
		"research_started":
			open_panel("room", {"room": "lab"})
		"capsule_opened":
			open_panel("alliance", {"tab": "capsules"})
		"gather_started", "resources_delivered":
			_focus_nearest("asteroid", func(e: Dictionary) -> bool: return str(e.get("occupant_owner", "")).is_empty())
		"xeno_hunted":
			_focus_nearest("xenoform", func(e: Dictionary) -> bool: return int(e.get("level", 1)) <= 2 and not bool(e.get("hive", false)))
		"xeno_hunted_l3":
			_focus_nearest("xenoform", func(e: Dictionary) -> bool: return int(e.get("level", 1)) == 3 and not bool(e.get("hive", false)))
		"scout_done", "pvp_win":
			_focus_nearest("base", func(e: Dictionary) -> bool: return GameClient.relation_of(str(e.get("owner", "")), str(e.get("tag", ""))) == "enemy" and not bool(e.get("shield", false)))
		_:
			show_map()


func _focus_nearest(kind: String, filter: Callable) -> void:
	show_map()
	var home: Vector2 = GameClient.base_pos()
	var best: Dictionary = {}
	var best_d: float = INF
	for id: String in GameClient.entities:
		var e: Dictionary = GameClient.entities[id]
		if str(e.get("kind", "")) != kind or not filter.call(e):
			continue
		var d: float = GameClient.entity_position(e).distance_to(home)
		if d < best_d:
			best_d = d
			best = e
	if best.is_empty():
		focus_tile(home)
		toast(U.t("Explora el mapa: arrastra para buscar más objetivos"), "info")
		return
	focus_tile(GameClient.entity_position(best))
	map_view.select(str(best["id"]))
	hud.show_entity(str(best["id"]))


# ---------------------------------------------------------------- mapa

func _on_entity_tapped(id: String) -> void:
	if not relocation_mode.is_empty():
		toast(U.t("Ese punto está ocupado; elige un espacio libre"), "warning")
		return
	hud.show_entity(id)


func _on_empty_tapped(tile: Vector2i) -> void:
	if not relocation_mode.is_empty():
		var mode: String = relocation_mode
		cancel_relocation()
		_request_relocate(tile, mode == "warp")
		return
	hud.show_tile(tile)


func _request_relocate(tile: Vector2i, warp: bool) -> void:
	if warp:
		send("use_item", {"item": "warp_jump", "x": tile.x, "y": tile.y}, func(_p: Dictionary) -> void:
			hud.hide_popup()
			map_view.clear_selection()
			focus_tile(Vector2(tile)))
	else:
		send("relocate", {"x": tile.x, "y": tile.y}, func(_p: Dictionary) -> void:
			hud.hide_popup()
			map_view.clear_selection()
			toast(U.t("Astronave en tránsito. No produce mientras viaja."), "info"))


func relocate_cost(tile: Vector2i) -> int:
	var d: float = GameClient.base_pos().distance_to(Vector2(tile))
	return int(Catalog.cfg("relocate_plasma_base", 10)) + int(ceil(d * float(Catalog.cfg("relocate_plasma_per_tile", 0.25))))


func _card_header(container: VBoxContainer, art: Control, title: String, subtitle: String, title_color: Color = UI.TEXT) -> void:
	var h := UI.hbox(12)
	container.add_child(h)
	if art != null:
		h.add_child(art)
	var v := UI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label(title, 20, title_color, "bold"))
	v.add_child(UI.wrap(UI.label(subtitle, 14, UI.TEXT_DIM)))
	h.add_child(v)
	var close := UI.icon_button("ui_close", 42, "GhostButton")
	close.pressed.connect(func() -> void:
		hud.hide_popup()
		map_view.clear_selection())
	h.add_child(close)


func build_entity_card(c: VBoxContainer, e: Dictionary) -> void:
	var pos: Vector2 = GameClient.entity_position(e)
	var coords: String = "X:%d Y:%d" % [int(pos.x), int(pos.y)]
	var dist: float = pos.distance_to(GameClient.base_pos())
	var actions := UI.hbox(10)
	match str(e.get("kind", "")):
		"asteroid":
			var lvl: int = int(e.get("level", 1))
			var el: String = str(e.get("element", ""))
			_card_header(c, UI.icon(UI.res_icon_name(el), 60), U.t("Asteroide N%d · %s") % [lvl, Catalog.res_name(el)], U.t("%s  ·  a %d casillas de tu nave") % [coords, int(dist)], Catalog.res_color(el).lightened(0.3))
			var info := UI.hbox(18)
			info.add_child(_stat(U.t("Restante"), U.fmt_int(int(e.get("remaining", 0))), "ui_cargo"))
			info.add_child(_stat(U.t("Extracción"), "%d/s" % int(Catalog.asteroid_level(lvl).get("rate", 10)), "ui_mine"))
			c.add_child(info)
			var occ: String = str(e.get("occupant_owner", ""))
			if occ.is_empty():
				var b := UI.button(U.t("Minar"), "PrimaryButton", "ui_mine", Vector2(200, 54))
				b.pressed.connect(func() -> void: open_fleet_dialog("gather", e))
				actions.add_child(b)
			elif occ == GameClient.player_id:
				c.add_child(UI.label(U.t("Tu flota está extrayendo aquí."), 15, UI.CYAN))
				for f: Dictionary in GameClient.me.get("fleets", []):
					if str(f.get("target_id", "")) == str(e["id"]):
						var rb := UI.button(U.t("Retirar flota"), "GhostButton", "ui_recall", Vector2(200, 54))
						rb.pressed.connect(func() -> void: recall_fleet(str(f["id"])))
						actions.add_child(rb)
			else:
				c.add_child(UI.label(U.t("Ocupado por %s (tile hitting: puedes atacar su flota minera)") % str(e.get("occupant_name", "")), 15, UI.RED))
				var ab := UI.button(U.t("Atacar flota minera"), "DangerButton", "ui_attack", Vector2(240, 54))
				ab.pressed.connect(func() -> void: open_fleet_dialog("attack", e))
				actions.add_child(ab)
		"xenoform" when bool(e.get("hive", false)):
			_hive_card(c, actions, e, coords, dist)
		"platform":
			_platform_card(c, actions, e, coords, dist)
		"xenoform":
			var lvl2: int = int(e.get("level", 1))
			var sp: Dictionary = Catalog.species_by_id.get(str(e.get("species", "")), {})
			_card_header(c, UI.image(UI.xeno_tex(str(e.get("species", "")), lvl2), Vector2(72, 72)), U.t("%s · N%d") % [sp.get("name", U.t("Xenoforma")), lvl2], U.t("Xenoforma  ·  %s  ·  a %d casillas") % [coords, int(dist)], Color("ffb3c1"))
			var hp: int = int(e.get("hp", 0))
			var mx: int = int(e.get("max_hp", 1))
			var hrow := UI.hbox(8)
			hrow.add_child(UI.icon("ui_hp", 20, UI.RED))
			var bar := UI.progress(hp, mx, UI.RED, 12)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hrow.add_child(bar)
			hrow.add_child(UI.label("%s / %s" % [U.fmt_num(hp), U.fmt_num(mx)], 14, UI.TEXT_DIM))
			c.add_child(hrow)
			var weak: String = str(sp.get("weakness", "fisica"))
			var info2 := UI.hbox(18)
			info2.add_child(_stat(U.t("Debilidad"), U.t("Física (+50%)") if weak == "fisica" else U.t("Energética (+50%)"), "ui_target"))
			info2.add_child(_stat(U.t("Energía"), "%d" % GameClient.hunt_energy_cost(lvl2), "res_energy"))
			info2.add_child(_stat(U.t("Botín"), U.t("MO, Créditos, Elementos"), "ui_gift"))
			c.add_child(info2)
			var tip: String = U.t("Envía Infantería/Cañoneros/Escudos (daño físico)") if weak == "fisica" else U.t("Envía Drones y Pilotos (daño energético)")
			c.add_child(UI.label(U.t("Consejo: ") + tip, 14, UI.TEXT_DIM))
			var hb := UI.button(U.t("Cazar"), "PrimaryButton", "ui_hunt", Vector2(200, 54))
			hb.pressed.connect(func() -> void: open_fleet_dialog("hunt", e))
			actions.add_child(hb)
		"base":
			var rel: String = GameClient.relation_of(str(e.get("owner", "")), str(e.get("tag", "")))
			var tag: String = str(e.get("tag", ""))
			var alliance_name: String = str(GameClient.alliances.get(tag, {}).get("name", U.t("Sin alianza")))
			var title: String = ("[%s] " % tag if not tag.is_empty() else "") + str(e.get("name", ""))
			var sub: String = U.t("Astronave Nv %d  ·  %s  ·  %s") % [int(e.get("level", 1)), alliance_name, coords]
			_card_header(c, UI.image(UI.portrait_tex(str(e.get("avatar", "p01"))), Vector2(72, 72)), title, sub, UI.REL_COLORS.get(rel, UI.TEXT))
			var info3 := UI.hbox(18)
			info3.add_child(_stat(U.t("Poder"), U.fmt_int(int(e.get("power", 0))), "res_power"))
			info3.add_child(_stat(U.t("Estado"), U.t("En tránsito") if str(e.get("state", "")) == "TRAVELING" else U.t("Anclada"), "ui_ship"))
			if bool(e.get("shield", false)):
				info3.add_child(_stat(U.t("Defensa"), U.t("Campo de Distorsión"), "ui_shield"))
			elif bool(e.get("protected", false)):
				info3.add_child(_stat(U.t("Defensa"), U.t("Protección de novato"), "ui_shield"))
			if rel == "enemy" or rel == "neutral":
				info3.add_child(_stat(U.t("Distancia"), U.t("%d casillas") % int(dist), "ui_relocate"))
			c.add_child(info3)
			match rel:
				"own":
					var enter := UI.button(U.t("Entrar a la nave"), "PrimaryButton", "ui_ship", Vector2(220, 54))
					enter.pressed.connect(show_base)
					actions.add_child(enter)
					var mv := UI.button(U.t("Mover nave"), "GhostButton", "ui_relocate", Vector2(180, 54))
					mv.pressed.connect(func() -> void: start_relocation("plasma"))
					actions.add_child(mv)
					if GameClient.res("warp_jump") > 0:
						var wb := UI.button(U.t("Salto Warp"), "GhostButton", "ui_warp", Vector2(170, 54))
						wb.pressed.connect(func() -> void: start_relocation("warp"))
						actions.add_child(wb)
					if GameClient.res("escape_jump") > 0:
						var eb := UI.button(U.t("Escape"), "GoldButton", "ui_escape", Vector2(140, 54))
						eb.pressed.connect(escape_jump)
						actions.add_child(eb)
					var gb := UI.button(U.t("Galaxia"), "GhostButton", "ui_galaxy", Vector2(140, 54))
					gb.pressed.connect(func() -> void: open_panel("galaxy"))
					actions.add_child(gb)
				"ally":
					c.add_child(UI.label(U.t("Miembro de tu Alianza. Tus refuerzos defienden su nave y te dan Bonos."), 15, UI.GREEN))
					var rb := UI.button(U.t("Enviar refuerzos"), "PrimaryButton", "ui_shield", Vector2(240, 54))
					rb.pressed.connect(func() -> void: open_fleet_dialog("reinforce", e))
					actions.add_child(rb)
				_:
					var spy := UI.button(U.t("Espiar (%d Cr)") % int(Catalog.cfg("scout_cost_credits", 50)), "GhostButton", "ui_scout", Vector2(200, 54))
					spy.pressed.connect(func() -> void: open_fleet_dialog("scout", e))
					actions.add_child(spy)
					var atk := UI.button(U.t("Atacar"), "DangerButton", "ui_attack", Vector2(180, 54))
					atk.pressed.connect(func() -> void: open_fleet_dialog("attack", e))
					actions.add_child(atk)
					if (GameClient.me.get("alliance_hq", {}).get("permissions", []) as Array).has("rally"):
						var rly := UI.button(U.t("Abrir Asedio"), "DangerButton", "ui_rally", Vector2(200, 54))
						rly.pressed.connect(func() -> void: open_fleet_dialog("rally", e))
						actions.add_child(rly)
						if bool(e.get("shield", false)) or bool(e.get("protected", false)):
							rly.disabled = true
					if str(GameClient.me.get("rank", "R2")) in ["R4", "R5"]:
						var marked: bool = str(GameClient.me.get("guild_brief", {}).get("target_id", "")) == str(e["id"])
						var mk := UI.button(U.t("Objetivo marcado") if marked else U.t("Marcar objetivo"), "GoldButton", "ui_rally", Vector2(200, 54))
						mk.disabled = marked
						mk.pressed.connect(func() -> void: send("mark_target", {"target_id": e["id"]}, func(_p: Dictionary) -> void:
							toast(U.t("Objetivo de Alianza marcado: tus aliados atacarán en los próximos minutos"), "success")
							hud.hide_popup()))
						actions.add_child(mk)
					if bool(e.get("shield", false)) or bool(e.get("protected", false)):
						spy.disabled = true
						atk.disabled = true
		"fleet":
			var rel2: String = GameClient.relation_of(str(e.get("owner", "")), str(e.get("tag", "")))
			_card_header(c, UI.icon(Hud.MISSION_ICONS.get(str(e.get("mission", "")), "ui_ship"), 56, UI.REL_COLORS.get(rel2, UI.TEXT)), U.t("Flota de %s") % str(e.get("owner_name", "")), "%s  ·  %s  ·  %s" % [U.t(Hud.MISSION_NAMES.get(str(e.get("mission", "")), U.t("Flota"))), U.t(Hud.STATE_NAMES.get(str(e.get("state", "")), "")), coords], UI.REL_COLORS.get(rel2, UI.TEXT))
			c.add_child(UI.label(U.t("Tropas: %s") % U.fmt_int(int(e.get("troops_total", 0))), 15, UI.TEXT))
			if rel2 == "own" and str(e.get("state", "")) != "returning":
				var rb2 := UI.button(U.t("Retirar"), "GhostButton", "ui_recall", Vector2(160, 54))
				rb2.pressed.connect(func() -> void: recall_fleet(str(e["id"])))
				actions.add_child(rb2)
	if actions.get_child_count() > 0:
		c.add_child(actions)


func _can_rally() -> bool:
	return (GameClient.me.get("alliance_hq", {}).get("permissions", []) as Array).has("rally")


func _hive_card(c: VBoxContainer, actions: HBoxContainer, e: Dictionary, coords: String, dist: float) -> void:
	var tier: int = int(e.get("tier", 1))
	var td: Dictionary = {}
	for t: Dictionary in Catalog.endgame.get("hives", {}).get("tiers", []):
		if int(t["tier"]) == tier:
			td = t
	_card_header(c, UI.image(UI.xeno_tex(str(e.get("species", "x24")), 5), Vector2(80, 80)), U.t("%s · T%d") % [str(td.get("name", U.t("Colmena Xeno"))), tier], U.t("Colmena Xeno  ·  %s  ·  a %d casillas") % [coords, int(dist)], Color("ff8fa3"))
	var hp: int = int(e.get("hp", 0))
	var mx: int = int(e.get("max_hp", 1))
	var hrow := UI.hbox(8)
	hrow.add_child(UI.icon("ui_hp", 20, UI.RED))
	var bar := UI.progress(hp, mx, UI.RED, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hrow.add_child(bar)
	hrow.add_child(UI.label("%s / %s" % [U.fmt_num(hp), U.fmt_num(mx)], 14, UI.TEXT_DIM))
	c.add_child(hrow)
	c.add_child(UI.wrap(UI.label(U.t("Solo se ataca con un Asedio de alianza. El daño persiste entre Asedios; cada participante gana premios según su aporte y, al destruirla, el botín de la Colmena."), 14, UI.TEXT_DIM), 480))
	c.add_child(UI.label(U.t("Botín al destruirla:"), 14, UI.GOLD, "bold"))
	var krow := UI.reward_row(td.get("kill", {}), 14)
	krow.custom_minimum_size.x = 460
	c.add_child(krow)
	if str(GameClient.me.get("tag", "")).is_empty():
		c.add_child(UI.label(U.t("Únete a una alianza para atacar Colmenas."), 14, UI.GOLD))
	elif _can_rally():
		var rly := UI.button(U.t("Abrir Asedio"), "DangerButton", "ui_rally", Vector2(220, 54))
		rly.name = "HiveRally"
		rly.pressed.connect(func() -> void: open_fleet_dialog("rally", e))
		actions.add_child(rly)
	else:
		c.add_child(UI.label(U.t("Pide a un R3 o superior que abra el Asedio y súmate desde el Cuartel."), 14, UI.GOLD))


func _platform_card(c: VBoxContainer, actions: HBoxContainer, e: Dictionary, coords: String, dist: float) -> void:
	var pd: Dictionary = {}
	for d: Dictionary in Catalog.endgame.get("platforms", {}).get("list", []):
		if str(d["id"]) == str(e.get("ptype", "")):
			pd = d
	var holder: String = str(e.get("holder", ""))
	var mine: bool = not holder.is_empty() and holder == str(GameClient.me.get("tag", ""))
	var col: Color = UI.GOLD if str(e.get("ptype", "")) == "citadel" else UI.CYAN
	_card_header(c, UI.icon("ui_flag", 64, col), str(pd.get("name", U.t("Plataforma Orbital"))), U.t("Plataforma Orbital  ·  %s  ·  a %d casillas") % [coords, int(dist)], col)
	c.add_child(UI.wrap(UI.label(str(pd.get("desc", "")), 14, UI.TEXT_DIM), 480))
	var info := UI.hbox(18)
	info.add_child(_stat(U.t("Controla"), (U.t("Tu alianza") if mine else "[%s]" % holder) if not holder.is_empty() else U.t("Nadie"), "ui_alliance"))
	var gpow: int = 0
	for k: String in e.get("garrison", {}):
		gpow += int(e["garrison"][k])
	info.add_child(_stat(U.t("Guarnición"), U.t("%s fuerzas") % U.fmt_int(gpow), "ui_defense"))
	var buff: Dictionary = pd.get("buff", {})
	var parts: Array = []
	for k2: String in buff:
		parts.append("+%d%% %s" % [int(round(float(buff[k2]) * 100.0)), preload("res://ui/panels/commander_panel.gd").effect_label(k2)])
	info.add_child(_stat(U.t("Bono"), ", ".join(parts), "ui_star"))
	c.add_child(info)
	var shield_left: float = float(int(e.get("shield_until", 0)) - GameClient.server_now()) / 1000.0
	if shield_left > 0.0:
		c.add_child(UI.label(U.t("Protegida tras su conquista: %s") % U.fmt_time(shield_left), 14, UI.CYAN))
	if mine:
		c.add_child(UI.label(U.t("Tu alianza controla esta plataforma: el bono ya está activo."), 14, UI.GREEN))
	elif str(GameClient.me.get("tag", "")).is_empty():
		c.add_child(UI.label(U.t("Únete a una alianza para conquistar plataformas."), 14, UI.GOLD))
	elif _can_rally():
		var rly := UI.button(U.t("Abrir Asedio"), "DangerButton", "ui_rally", Vector2(220, 54))
		rly.name = "PlatformRally"
		rly.disabled = shield_left > 0.0
		rly.pressed.connect(func() -> void: open_fleet_dialog("rally", e))
		actions.add_child(rly)
	var gb := UI.button(U.t("Guerra del Sistema"), "GhostButton", "ui_flag", Vector2(220, 54))
	gb.pressed.connect(func() -> void: open_panel("endgame", {"tab": "titles" if str(e.get("ptype", "")) == "citadel" else "platforms"}))
	actions.add_child(gb)


func build_tile_card(c: VBoxContainer, tile: Vector2i) -> void:
	var blocked: bool = false
	var blocked_name: String = ""
	var is_portal: bool = false
	for t: Dictionary in GameClient.terrain:
		if Vector2(tile).distance_to(U.v2(t["pos"])) <= float(t["radius"]) + 2.0:
			blocked = true
			blocked_name = str(t.get("name", ""))
			is_portal = str(t.get("kind", "")) == "portal"
	if not blocked:
		for id: String in GameClient.entities:
			var e: Dictionary = GameClient.entities[id]
			if str(e.get("kind", "")) in ["base", "asteroid", "xenoform", "platform"] and GameClient.entity_position(e).distance_to(Vector2(tile)) <= 2.5 and str(e.get("owner", "")) != GameClient.player_id:
				blocked = true
				blocked_name = U.t("ocupado por otra entidad")
	var dist: float = Vector2(tile).distance_to(GameClient.base_pos())
	_card_header(c, UI.icon("ui_target", 52, UI.CYAN), U.t("Coordenada X:%d Y:%d") % [tile.x, tile.y], (U.t("Zona no ocupable: %s") % blocked_name) if blocked else U.t("Espacio libre  ·  a %d casillas de tu nave") % int(dist))
	if blocked:
		if is_portal:
			c.add_child(UI.wrap(UI.label(U.t("El Portal de Salto conecta los Sistemas Solares de la galaxia. Ancla tu Astronave cerca para saltar con Plasma."), 15, UI.TEXT_DIM), 480))
			var gb := UI.button(U.t("Abrir Mapa Galáctico"), "GoldButton", "ui_galaxy", Vector2(260, 54))
			gb.pressed.connect(func() -> void: open_panel("galaxy"))
			c.add_child(gb)
		return
	var actions := UI.hbox(10)
	var cost: int = relocate_cost(tile)
	var mv := UI.button(U.t("Mover Astronave aquí  (%d") % cost + U.t(" Plasma)"), "PrimaryButton", "ui_relocate", Vector2(0, 54))
	mv.disabled = GameClient.res("plasma") < cost
	mv.pressed.connect(func() -> void: _request_relocate(tile, false))
	actions.add_child(mv)
	if GameClient.res("warp_jump") > 0:
		var wb := UI.button(U.t("Salto Warp"), "GoldButton", "ui_warp", Vector2(170, 54))
		wb.pressed.connect(func() -> void: _request_relocate(tile, true))
		actions.add_child(wb)
	c.add_child(actions)
	c.add_child(UI.label(U.t("La nave en tránsito no produce ni puede ser atacada. Todas tus flotas deben estar en casa."), 13, UI.TEXT_MUTED))


func _stat(label_text: String, value: String, icon_name: String) -> HBoxContainer:
	var h := UI.hbox(6)
	h.add_child(UI.icon(icon_name, 22, UI.TEXT_DIM if icon_name.begins_with("ui_") else Color.WHITE))
	var v := UI.vbox(0)
	v.add_child(UI.label(label_text, 12, UI.TEXT_MUTED))
	v.add_child(UI.label(value, 15, UI.TEXT, "semibold"))
	h.add_child(v)
	return h


func _on_report(r: Dictionary) -> void:
	var t: String = str(r.get("type", ""))
	var kind: String = "success" if str(r.get("outcome", "")) == "victory" else ("danger" if str(r.get("outcome", "")) == "defeat" else "info")
	if t in ["attack", "defense", "tile_hit", "tile_defense", "hunt", "scout"]:
		toast(U.t("Nuevo informe: ") + str(r.get("title", "")), kind)
