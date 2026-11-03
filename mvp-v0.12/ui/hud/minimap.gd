extends Control
## Minimapa del sistema: Portal, gigantes gaseosos, tu nave, tus flotas y la vista.

const U = preload("res://shared/util.gd")
const UI = preload("res://ui/ui.gd")

signal jump_to(tile: Vector2)

var view_center: Vector2 = Vector2(300, 300)
var view_extent: Vector2 = Vector2(40, 22)


func _ready() -> void:
	custom_minimum_size = Vector2(170, 170)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(_d: float) -> void:
	queue_redraw()


func _to_local(tile: Vector2) -> Vector2:
	return tile / float(GameClient.map_size) * size


func _draw() -> void:
	var c: Vector2 = size / 2.0
	var r: float = minf(size.x, size.y) / 2.0
	draw_circle(c, r, Color(0.02, 0.04, 0.1, 0.92))
	draw_circle(c, r * 0.32, Color(0.35, 0.22, 0.6, 0.18))
	draw_arc(c, r - 1.0, 0, TAU, 64, Color("2b4a8a"), 2.0, true)
	for ring: float in [0.33, 0.55, 0.75]:
		draw_arc(c, r * ring, 0, TAU, 48, Color(0.2, 0.35, 0.7, 0.18), 1.0, true)
	for t: Dictionary in GameClient.terrain:
		var p: Vector2 = _to_local(U.v2(t["pos"]))
		var rr: float = maxf(2.0, float(t["radius"]) / GameClient.map_size * size.x)
		var col: Color = Color("b388ff") if t["kind"] == "portal" else Color(str(t.get("color", "#8888ff")))
		draw_circle(p, rr, Color(col, 0.8))
	for id: String in GameClient.entities:
		var e: Dictionary = GameClient.entities[id]
		if e.get("kind", "") == "fleet" and str(e.get("owner", "")) == GameClient.player_id:
			draw_circle(_to_local(GameClient.entity_position(e)), 2.5, UI.CYAN)
		elif e.get("kind", "") == "fleet" and str(e.get("target_kind", "")) == "base" and str(e.get("mission", "")) == "attack":
			draw_circle(_to_local(GameClient.entity_position(e)), 3.0, UI.RED)
	var own: Vector2 = _to_local(GameClient.base_pos())
	draw_circle(own, 6.0, Color(UI.CYAN, 0.3))
	draw_circle(own, 3.5, UI.CYAN)
	var vr := Rect2(_to_local(view_center - view_extent), _to_local(view_extent * 2.0))
	draw_rect(vr, Color(1, 1, 1, 0.75), false, 1.5)


func _gui_input(event: InputEvent) -> void:
	var pos: Vector2 = Vector2(-1, -1)
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pos = (event as InputEventMouseButton).position
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pos = (event as InputEventMouseMotion).position
	if pos.x >= 0:
		jump_to.emit(pos / size * float(GameClient.map_size))
		accept_event()
