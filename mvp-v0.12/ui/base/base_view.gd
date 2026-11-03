extends Control
## Interior de la Astronave (Equipo 2): salas con nivel, mejoras en curso,
## burbujas de producción para recolectar y colas activas.

const UI = preload("res://ui/ui.gd")
const U = preload("res://shared/util.gd")

const QUEUE_INFO: Array = [
	["build", "Construcción", "ui_build", "bridge"],
	["research", "Investigación", "ui_lab", "lab"],
	["train", "Hangar", "troop_infantry", "hangar"],
	["heal", "Bahía Médica", "ui_medic", "medbay"],
	["revive", "Criosantuario", "ui_cryo", "cryo"],
]

var game: Node
var deck: Node3D
var _content: Control
var _queue_row: HBoxContainer
var _queue_chips: Dictionary = {}
var _accum: float = 0.0
var _stats_label: Label
var _title_label: Label


func setup(game_node: Node) -> void:
	game = game_node
	UI.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	var v := UI.vbox(8)
	UI.full_rect(v)
	_content.add_child(v)
	var head := UI.hbox(12)
	_title_label = UI.title(U.t("ASTRONAVE"), 24, Color("ffe08a"))
	UI.outline(_title_label, 8)
	head.add_child(_title_label)
	head.add_child(UI.spacer())
	_stats_label = UI.outline(UI.label("", 15, UI.TEXT, "semibold"), 6)
	head.add_child(_stats_label)
	v.add_child(head)
	_queue_row = UI.hbox(8)
	v.add_child(_queue_row)
	for q: Array in QUEUE_INFO:
		var chip := _queue_chip(q)
		_queue_row.add_child(chip)
		_queue_chips[q[0]] = chip
	GameClient.player_updated.connect(_tick)


func _queue_chip(q: Array) -> PanelContainer:
	var p := UI.panel("Chip")
	p.custom_minimum_size = Vector2(170, 58)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UI.hbox(8)
	p.add_child(h)
	h.add_child(UI.icon(q[2], 30, UI.TEXT_DIM if str(q[2]).begins_with("ui_") else Color.WHITE))
	var v := UI.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name := UI.label(q[1], 13, UI.TEXT_DIM, "bold")
	var status := UI.label(U.t("Libre"), 14, UI.TEXT_MUTED, "semibold")
	status.clip_text = true
	var bar := UI.progress(0, 100, UI.CYAN, 6)
	v.add_child(name)
	v.add_child(status)
	v.add_child(bar)
	h.add_child(v)
	p.set_meta("status", status)
	p.set_meta("bar", bar)
	var room_id: String = q[3]
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			game.open_panel("room", {"room": room_id}))
	return p


func _process(delta: float) -> void:
	var s: Vector2 = size
	_content.position = Vector2(326, 74)
	_content.size = Vector2(s.x - 326 - 16, 0)
	if not visible:
		return
	_accum += delta
	if _accum >= 0.25:
		_accum = 0.0
		_tick()


func collect(room_id: String) -> void:
	GameClient.intent("collect", {"room": room_id}, func(ok: bool, payload: Dictionary) -> void:
		if not ok:
			game.toast(str(payload.get("message", "")), "warning")
			return
		var at: Vector2 = deck.building_screen_pos(room_id) if deck != null else size / 2.0
		deck.pop_bubble(room_id)
		_float_gains(at, payload.get("gained", {})))


func _float_gains(at: Vector2, gained: Dictionary) -> void:
	var i: int = 0
	for k: String in gained:
		var h := UI.amount_chip(k, int(gained[k]), 20, UI.GREEN)
		(h.get_child(1) as Label).text = "+" + U.fmt_num(int(gained[k]))
		(h.get_child(1) as Label).add_theme_font_override("font", UI.font("game"))
		UI.outline(h.get_child(1) as Label, 7)
		add_child(h)
		h.position = at + Vector2(-34, -20 - i * 28)
		h.z_index = 50
		var tw := create_tween().set_parallel(true)
		tw.tween_property(h, "position:y", h.position.y - 70, 1.2).set_ease(Tween.EASE_OUT)
		tw.tween_property(h, "modulate:a", 0.0, 1.2).set_delay(0.55)
		tw.chain().tween_callback(h.queue_free)
		i += 1


func _tick() -> void:
	var me: Dictionary = GameClient.me
	if me.is_empty():
		return
	var traveling: bool = str(me.get("base_state", "")) != "ANCHORED"
	_title_label.text = U.t("ASTRONAVE DE %s") % str(me.get("name", "")).to_upper()
	var bp: Vector2 = GameClient.base_pos()
	_stats_label.text = U.t("%s · X:%d Y:%d   ·   Tropas %s   ·   Heridos %s   ·   Criostasis %s") % [U.t("EN TRÁNSITO") if traveling else U.t("ANCLADA"), int(bp.x), int(bp.y), U.fmt_int(U.sum_values(me.get("troops", {}))), U.fmt_int(U.sum_values(me.get("wounded", {}))), U.fmt_int(U.sum_values(me.get("cryo", {})))]
	var now: int = GameClient.server_now()
	for q: Array in QUEUE_INFO:
		var chip: PanelContainer = _queue_chips[q[0]]
		var job: Dictionary = GameClient.queue(q[0])
		var st: Label = chip.get_meta("status")
		var bar: ProgressBar = chip.get_meta("bar")
		if job.is_empty():
			st.text = U.t("Libre")
			st.add_theme_color_override("font_color", UI.TEXT_MUTED)
			bar.value = 0
		else:
			var rem: float = float(int(job["end"]) - now) / 1000.0
			st.text = "%s · %s" % [U.fmt_time(rem), str(job.get("label", ""))]
			st.add_theme_color_override("font_color", UI.TEXT)
			bar.value = clampf(1.0 - rem * 1000.0 / maxf(1.0, float(job.get("total", 1))), 0.0, 1.0) * 100.0
