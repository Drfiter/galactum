extends "res://ui/panels/window.gd"
## Mapa Galáctico: los Sistemas Solares (cada uno, un servidor SSS) y el salto
## interestelar entre ellos. Un sistema nuevo se abre cada mes; los veteranos
## esperan una ventana de tiempo antes de entrar a los sistemas nuevos.

const STATUS_COLORS: Dictionary = {
	"newest": Color("ffc24a"), "open": Color("8fd3ff"), "protected": Color("b388ff"), "upcoming": Color("5b6d94"),
}

var galaxy: Dictionary = {}
var selected: String = ""
var starmap: Control
var detail: VBoxContainer


func _init() -> void:
	desired_size = Vector2(1200, 660)


func window_title() -> String:
	return U.t("Mapa Galáctico")


func window_icon() -> String:
	return "ui_galaxy"


func build() -> void:
	if galaxy.is_empty():
		body.add_child(UI.label(U.t("Consultando el Servidor Galáctico Maestro…"), 18, UI.TEXT_DIM))
		_fetch()
		return
	var h := UI.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(h)
	var map_panel := UI.panel("Card")
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(map_panel)
	starmap = StarMap.new()
	starmap.panel = self
	starmap.custom_minimum_size = Vector2(600, 470)
	map_panel.add_child(starmap)
	var right := UI.vbox(10)
	right.custom_minimum_size = Vector2(470, 0)
	h.add_child(right)
	detail = UI.vbox(8)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail)
	var rules := UI.panel("Chip")
	var rv := UI.vbox(4)
	rules.add_child(rv)
	rv.add_child(UI.label(U.t("Reglas de la galaxia"), 14, UI.GOLD, "bold"))
	rv.add_child(UI.wrap(UI.label(U.t("Se abre un sistema nuevo cada %d días. Los comandantes nuevos nacen en el más nuevo; los veteranos esperan %d días para entrar en él. Al saltar conservas tu Alianza.") % [int(galaxy.get("new_system_days", 30)), int(galaxy.get("veteran_lock_days", 180))], 13, UI.TEXT_DIM), 440))
	right.add_child(rules)
	if selected.is_empty():
		selected = str(galaxy.get("current", ""))
	_build_detail()


func _fetch() -> void:
	GameClient.intent("galaxy", {}, func(ok: bool, payload: Dictionary) -> void:
		if not ok or not is_inside_tree():
			return
		galaxy = payload.get("galaxy", {})
		rebuild())


func system_list() -> Array:
	return galaxy.get("systems", [])


func select_system(id: String) -> void:
	selected = id
	_build_detail()
	if starmap != null:
		starmap.queue_redraw()


func _sys(id: String) -> Dictionary:
	for s: Dictionary in system_list():
		if str(s["id"]) == id:
			return s
	return {}


func _status_text(s: Dictionary) -> String:
	match str(s.get("status", "")):
		"newest":
			return U.t("Sistema más nuevo")
		"protected":
			return U.t("Sistema reciente")
		"upcoming":
			return U.t("Próximamente")
	return U.t("Sistema consolidado")


func _build_detail() -> void:
	if detail == null:
		return
	UI.clear(detail)
	var s: Dictionary = _sys(selected)
	if s.is_empty():
		return
	var col: Color = STATUS_COLORS.get(str(s["status"]), UI.TEXT)
	var card := UI.panel("CardHi")
	detail.add_child(card)
	var v := UI.vbox(8)
	card.add_child(v)
	var hh := UI.hbox(10)
	hh.add_child(UI.icon("ui_galaxy", 40, col))
	var tv := UI.vbox(0)
	tv.add_child(UI.title("%s %d · %s" % [U.t("Sistema"), int(s["index"]), str(s["name"])], 22, col))
	tv.add_child(UI.label(_status_text(s) + ("  ·  " + U.t("Estás aquí") if bool(s["current"]) else ""), 15, UI.TEXT_DIM, "semibold"))
	hh.add_child(tv)
	v.add_child(hh)
	var stats := UI.hbox(22)
	var age: int = int(s.get("age_days", 0))
	stats.add_child(_stat(U.t("Antigüedad"), (U.t("%d días") % age) if age >= 0 else U.t("Se abre en %d días") % -age, "ui_timer"))
	stats.add_child(_stat(U.t("Comandantes"), str(int(s.get("commanders", 0))), "ui_users"))
	var threat: String = ""
	for i: int in range(5):
		threat += "★" if i < int(s.get("threat", 1)) else "☆"
	stats.add_child(_stat(U.t("Amenaza"), threat, "ui_attack"))
	v.add_child(stats)
	var desc: String = ""
	match str(s["status"]):
		"newest":
			desc = U.t("Recién abierto: todos parten de cero. Los veteranos de otros sistemas no pueden entrar hasta que pase la ventana de protección.")
		"protected":
			desc = U.t("Sistema joven: las alianzas aún se están formando. Solo accesible para comandantes nacidos después de su apertura o cuando termine la protección.")
		"upcoming":
			desc = U.t("Este sistema aún no abre. Los comandantes que se registren cuando abra nacerán aquí.")
		_:
			desc = U.t("Sistema maduro, abierto a todos: alianzas poderosas, asteroides ricos y comandantes veteranos.")
	v.add_child(UI.wrap(UI.label(desc, 14, UI.TEXT), 430))
	var blocked: String = str(s.get("blocked", ""))
	if bool(s["current"]):
		var btn := UI.button(U.t("Ir al Portal de Salto"), "GhostButton", "ui_target", Vector2(0, 52))
		btn.pressed.connect(func() -> void:
			close_window()
			game.show_map()
			game.focus_tile(Vector2(GameClient.map_size / 2.0, GameClient.map_size / 2.0)))
		detail.add_child(btn)
		return
	if not blocked.is_empty():
		var bl := UI.panel("CardRed")
		bl.add_child(UI.wrap(UI.label(blocked, 15, Color("ffd0da"), "semibold"), 430))
		detail.add_child(bl)
		return
	var near: bool = bool(galaxy.get("near_portal", false))
	var plasma: int = int(galaxy.get("portal_plasma", 80))
	var pb := UI.button(U.t("Saltar por el Portal  (%d Plasma)") % plasma, "PrimaryButton", "ui_warp", Vector2(0, 56))
	pb.disabled = not near or GameClient.res("plasma") < plasma
	pb.pressed.connect(func() -> void: _confirm_jump(s, "portal"))
	detail.add_child(pb)
	if not near:
		detail.add_child(UI.wrap(UI.label(U.t("Acerca tu Astronave a %d casillas del Portal de Salto (centro del sistema) para saltar con Plasma.") % int(galaxy.get("portal_range", 40)), 13, UI.TEXT_MUTED), 430))
	var qty: int = GameClient.res("interstellar_jump")
	var ib := UI.button(U.t("Usar Motor de Salto Interestelar  (×%d)") % qty, "GoldButton", "ui_galaxy", Vector2(0, 56))
	ib.disabled = qty <= 0
	ib.pressed.connect(func() -> void: _confirm_jump(s, "item"))
	detail.add_child(ib)
	detail.add_child(UI.wrap(UI.label(U.t("Requisitos: nave anclada y todas tus flotas en casa. Llegas con 5 minutos de protección."), 13, UI.TEXT_MUTED), 430))


func _confirm_jump(s: Dictionary, method: String) -> void:
	var name: String = "%s %d · %s" % [U.t("Sistema"), int(s["index"]), str(s["name"])]
	game.confirm(U.t("¿Saltar al %s? Tu Astronave abandonará este sistema con todas tus tropas y recursos.") % name, func() -> void:
		close_window()
		game.interstellar_jump(str(s["id"]), method, name), U.t("¡Saltar!"), "GoldButton")


func _stat(label_text: String, value: String, icon_name: String) -> HBoxContainer:
	var h := UI.hbox(6)
	h.add_child(UI.icon(icon_name, 22, UI.TEXT_DIM))
	var v := UI.vbox(0)
	v.add_child(UI.label(label_text, 12, UI.TEXT_MUTED))
	v.add_child(UI.label(value, 15, UI.TEXT, "semibold"))
	h.add_child(v)
	return h


## Dibujo del mapa estelar: los sistemas en espiral, unidos por rutas de salto.
class StarMap extends Control:
	var panel: Node
	var _t: float = 0.0
	var _points: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _layout() -> void:
		_points.clear()
		var list: Array = panel.system_list()
		var c: Vector2 = size / 2.0
		var n: int = list.size()
		var max_r: float = minf(size.x, size.y) * 0.44
		for i: int in range(n):
			var s: Dictionary = list[i]
			var f: float = float(i) / maxf(1.0, float(n - 1))
			var ang: float = f * TAU * 1.55 + 0.6
			var r: float = 40.0 + f * (max_r - 40.0)
			_points[str(s["id"])] = c + Vector2(cos(ang) * r * 1.25, sin(ang) * r)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			var pos: Vector2 = (ev as InputEventMouseButton).position
			var best: String = ""
			var bd: float = 40.0
			for id: String in _points:
				var d: float = (_points[id] as Vector2).distance_to(pos)
				if d < bd:
					bd = d
					best = id
			if not best.is_empty():
				panel.select_system(best)

	func _draw() -> void:
		_layout()
		var list: Array = panel.system_list()
		var c: Vector2 = size / 2.0
		# Brazo galáctico de fondo
		for k: int in range(220):
			var h: float = fmod(float(k) * 0.618034, 1.0)
			var ang: float = h * TAU * 1.55 + 0.6 + sin(k * 3.1) * 0.25
			var r: float = 30.0 + h * minf(size.x, size.y) * 0.46 + sin(k * 7.7) * 18.0
			var p: Vector2 = c + Vector2(cos(ang) * r * 1.25, sin(ang) * r)
			var tw: float = 0.35 + 0.35 * sin(_t * 1.5 + k)
			draw_circle(p, 1.0 + fmod(k * 0.37, 1.4), Color(0.6, 0.75, 1.0, 0.12 + 0.18 * tw))
		draw_circle(c, 46.0, Color(0.55, 0.45, 1.0, 0.07))
		draw_circle(c, 22.0, Color(0.75, 0.65, 1.0, 0.12))
		# Rutas de salto
		for i: int in range(list.size() - 1):
			var a: Vector2 = _points[str(list[i]["id"])]
			var b: Vector2 = _points[str(list[i + 1]["id"])]
			var upcoming: bool = str(list[i + 1]["status"]) == "upcoming"
			draw_dashed_line(a, b, Color(0.5, 0.65, 1.0, 0.18 if upcoming else 0.35), 2.0, 6.0 if upcoming else 3.0)
		var font: Font = get_theme_default_font()
		for s: Dictionary in list:
			var id: String = str(s["id"])
			var p: Vector2 = _points[id]
			var col: Color = STATUS_COLORS.get(str(s["status"]), Color.WHITE)
			var rad: float = 9.0 if str(s["status"]) != "upcoming" else 7.0
			if bool(s["current"]):
				var pulse: float = 0.5 + 0.5 * sin(_t * 3.0)
				draw_arc(p, 18.0 + pulse * 6.0, 0.0, TAU, 40, Color(0.25, 0.82, 1.0, 0.9 - pulse * 0.5), 3.0)
				col = Color("3fd0ff")
			draw_circle(p, rad + 6.0, Color(col, 0.18))
			draw_circle(p, rad, col)
			draw_circle(p, rad * 0.45, Color(1, 1, 1, 0.9))
			if id == panel.selected:
				draw_arc(p, rad + 10.0, _t, _t + TAU * 0.75, 30, Color("ffe07a"), 2.5)
			var txt: String = "%d · %s" % [int(s["index"]), str(s["name"])]
			var off := Vector2(28 if bool(s["current"]) else 16, 5)
			draw_string_outline(font, p + off, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color(0.01, 0.02, 0.06, 0.9))
			draw_string(font, p + off, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col.lightened(0.25))
		# Leyenda
		var ly: float = size.y - 70.0
		var legend: Array = [["newest", U.t("Más nuevo")], ["protected", U.t("Reciente (protegido)")], ["open", U.t("Consolidado")], ["upcoming", U.t("Próximamente")]]
		for i: int in range(legend.size()):
			var lp := Vector2(16, ly + i * 16)
			draw_circle(lp, 5.0, STATUS_COLORS[legend[i][0]])
			draw_string(font, lp + Vector2(12, 5), str(legend[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.78, 0.92))
