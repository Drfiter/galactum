class_name WorldDebugView
extends Control
## Vista diagnóstica 2D del mundo (TEAM3-M1).
## Herramienta de diagnóstico, no la presentación final de Galactum.
##
## - Proyecta la réplica local (WorldState) usando una WorldCamera2D (paneo/zoom).
## - Dibuja marcadores temporales por tipo: ship/fleet/asteroid/xenoform.
## - Soporta click de mouse y tap táctil para selección técnica de entidades.
## - Preparada para Area of Interest: solo dibuja lo que hay en WorldState
##   (no asume que el cliente recibe siempre todo el mapa).
## Sin gameplay: no emite órdenes de movimiento (eso es TEAM3-M2).

signal entity_selected(entity_id: String)

@onready var _world: WorldState
var _camera := WorldCamera2D.new()

# Gestión de input (tap vs. drag)
var _pressed: bool = false
var _press_pos_screen: Vector2 = Vector2.ZERO
var _dragged: bool = false
const TAP_SLOP_PX: float = 8.0

# Selección técnica actual
var _selected_entity_id: String = ""

const MARKER_COLORS := {
	"ship": Color("63d7ff"),
	"fleet": Color("ffd763"),
	"asteroid": Color("d7b48a"),
	"xenoform": Color("e06c6c"),
}


func set_world_state(world_state: WorldState) -> void:
	if _world != null and _world.changed.is_connected(queue_redraw):
		_world.changed.disconnect(queue_redraw)
	_world = world_state
	if _world != null:
		_world.changed.connect(queue_redraw)
	queue_redraw()


func get_selected_entity_id() -> String:
	return _selected_entity_id


func get_camera() -> WorldCamera2D:
	return _camera


func _draw() -> void:
	_camera.set_screen_size(size)
	# Fondo del control
	draw_rect(Rect2(Vector2.ZERO, size), Color("08111f"), true)
	if _world == null:
		return

	var map_rect := _compute_map_rect()
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return
	# Borde del mundo lógico (600×600)
	draw_rect(map_rect, Color("28405f"), false, 2.0)

	for raw_entity: Variant in _world.entities.values():
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		var entity_id: String = str(entity.get("entity_id", ""))
		var kind: String = str(entity.get("kind", ""))
		var raw_position: Array = entity.get("position", [0, 0])
		if raw_position.size() != 2:
			continue
		var world_pos := Vector2(float(raw_position[0]), float(raw_position[1]))
		var screen_pos: Vector2 = _camera.world_to_screen(world_pos)
		# Culling por visibilidad en la cámara (preparado para Area of Interest:
		# solo dibujamos lo que realmente está en el viewport).
		if not Rect2(Vector2.ZERO, size).has_point(screen_pos):
			continue
		_draw_entity(entity_id, kind, world_pos, screen_pos)


func _compute_map_rect() -> Rect2:
	if _world == null or _world.map_size.x <= 0 or _world.map_size.y <= 0:
		return Rect2()
	var top_left: Vector2 = _camera.world_to_screen(Vector2.ZERO)
	var bottom_right: Vector2 = _camera.world_to_screen(Vector2(_world.map_size.x, _world.map_size.y))
	# Rect en coordenadas de pantalla que contiene el rectángulo del mundo.
	var tl := Vector2(minf(top_left.x, bottom_right.x), minf(top_left.y, bottom_right.y))
	var br := Vector2(maxf(top_left.x, bottom_right.x), maxf(top_left.y, bottom_right.y))
	return Rect2(tl, br - tl)


func _draw_entity(entity_id: String, kind: String, _world_pos: Vector2, screen_pos: Vector2) -> void:
	var color: Color = MARKER_COLORS.get(kind, Color("9aa5b1"))
	var selected := (entity_id == _selected_entity_id)
	# Tamaño base por tipo (diagnóstico), sin arte final.
	var radius: float = 6.0 if not selected else 9.0
	if kind == "asteroid":
		radius = 7.0 if not selected else 10.0

	draw_circle(screen_pos, radius, color)
	# Marcador "+" central para diferenciar entidades
	draw_line(screen_pos + Vector2(-5.0, 0.0), screen_pos + Vector2(5.0, 0.0), Color("08111f"), 1.0)
	draw_line(screen_pos + Vector2(0.0, -5.0), screen_pos + Vector2(0.0, 5.0), Color("08111f"), 1.0)
	if selected:
		draw_arc(screen_pos, radius + 4.0, 0.0, TAU, 32, Color.WHITE, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		var magnify: InputEventMagnifyGesture = event
		_camera.zoom_at_screen(magnify.position, 1.0 + 0.5 * (magnify.factor - 1.0))
		queue_redraw()
		accept_event()
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_press_pos_screen = mb.position
				_dragged = false
			else:
				if _pressed and not _dragged:
					_handle_tap(mb.position)
				_pressed = false
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom_at_screen(mb.position, 1.2)
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom_at_screen(mb.position, 1.0 / 1.2)
			queue_redraw()
			accept_event()
		return

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _pressed and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			if not _dragged and _press_pos_screen.distance_to(mm.position) > TAP_SLOP_PX:
				_dragged = true
			if _dragged:
				_camera.pan_by_pixels(mm.relative)
				queue_redraw()
			accept_event()
		return

	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_pressed = true
			_press_pos_screen = st.position
			_dragged = false
		else:
			if _pressed and not _dragged:
				_handle_tap(st.position)
			_pressed = false
		accept_event()
		return

	if event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		if not _dragged and _press_pos_screen.distance_to(sd.position) > TAP_SLOP_PX:
			_dragged = true
		if _dragged:
			_camera.pan_by_pixels(sd.relative)
			queue_redraw()
		accept_event()


## Al tocar/cliquear: selecciona la entidad más cercana a la posición del mundo.
## No emite órdenes de movimiento (TEAM3-M2).
func _handle_tap(screen_pos: Vector2) -> void:
	if _world == null:
		return
	var world_pos: Vector2 = _camera.screen_to_world(screen_pos)
	var closest_id: String = ""
	var closest_dist_sq: float = 64.0 * 64.0  # radio de selección técnico (px en mundo)
	for raw_entity: Variant in _world.entities.values():
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		var raw_position: Array = entity.get("position", [0, 0])
		if raw_position.size() != 2:
			continue
		var entity_world := Vector2(float(raw_position[0]), float(raw_position[1]))
		var d_sq: float = entity_world.distance_squared_to(world_pos)
		if d_sq < closest_dist_sq:
			closest_dist_sq = d_sq
			closest_id = str(entity.get("entity_id", ""))
	_selected_entity_id = closest_id
	entity_selected.emit(_selected_entity_id)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_camera.set_screen_size(size)
		queue_redraw()
