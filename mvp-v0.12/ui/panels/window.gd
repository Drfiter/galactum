extends PanelContainer
## Ventana modal base: barra de título con ícono, título y botón de cierre.
## Los paneles concretos heredan y llenan `body` en `build()`.

const UI = preload("res://ui/ui.gd")
const U = preload("res://shared/util.gd")

signal closed

var game: Node
var body: VBoxContainer
var header: HBoxContainer
var title_label: Label
var args: Dictionary = {}
var desired_size: Vector2 = Vector2(1000, 600)
var _refresh_accum: float = 0.0
var live_refresh: float = 0.0   # >0: reconstruye cada N s mientras está abierta


func open(game_node: Node, p_args: Dictionary = {}) -> void:
	game = game_node
	args = p_args
	var root := UI.vbox(10)
	add_child(root)
	header = UI.hbox(12)
	root.add_child(header)
	var icon_name: String = window_icon()
	if not icon_name.is_empty():
		header.add_child(UI.icon(icon_name, 34, UI.CYAN))
	title_label = UI.title(window_title(), 22, UI.TEXT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)
	extra_header(header)
	var close := UI.icon_button("ui_close", 48, "GhostButton")
	close.pressed.connect(close_window)
	header.add_child(close)
	root.add_child(UI.separator())
	body = UI.vbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	GameClient.player_updated.connect(_on_player_updated)
	build()


func window_title() -> String:
	return ""


func window_icon() -> String:
	return ""


func extra_header(_h: HBoxContainer) -> void:
	pass


func build() -> void:
	pass


func rebuild() -> void:
	for c: Node in body.get_children():
		body.remove_child(c)
		c.queue_free()
	build()


## Se llama cuando llega un estado nuevo del jugador. Por defecto no reconstruye
## (evita parpadeos); los paneles que lo necesiten lo sobreescriben.
func on_player_updated() -> void:
	pass


func _on_player_updated() -> void:
	if is_inside_tree():
		on_player_updated()


func _process(delta: float) -> void:
	if live_refresh > 0.0:
		_refresh_accum += delta
		if _refresh_accum >= live_refresh:
			_refresh_accum = 0.0
			tick()


func tick() -> void:
	pass


func close_window() -> void:
	closed.emit()


func scroll_body(content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


func send(action: String, params: Dictionary = {}, on_ok: Callable = Callable()) -> void:
	GameClient.intent(action, params, func(ok: bool, payload: Dictionary) -> void:
		if not ok:
			game.toast(str(payload.get("message", U.t("Acción rechazada"))), "error")
		elif on_ok.is_valid():
			on_ok.call(payload))
