extends Node3D
## Mapa del Sistema Solar en 3D estilizado (1 casilla = 1 unidad de mundo).
## Misma interfaz pública que la vista 2D anterior, así el HUD no cambia:
## center_on_tile, center_tiles, zoom_level, set_zoom, select, etc.

const UI = preload("res://ui/ui.gd")
const U = preload("res://shared/util.gd")
const FX = preload("res://ui/world3d/combat_fx.gd")
const Kit = preload("res://ui/world3d/mesh_kit.gd")
const Entity3D = preload("res://ui/world3d/entity_3d.gd")
const FLOOR = preload("res://assets/shaders/space_floor.gdshader")
const RING = preload("res://assets/shaders/glow_ring.gdshader")
const VORTEX = preload("res://assets/shaders/portal_vortex.gdshader")

const PITCH_DEG: float = 52.0
const FOV: float = 38.0
const MIN_DIST: float = 16.0
const MAX_DIST: float = 78.0
const TAP_SLOP: float = 14.0

signal entity_tapped(id: String)
signal empty_tapped(tile: Vector2i)
signal camera_moved(center_tiles: Vector2)

var camera := Camera3D.new()
var nodes: Dictionary = {}
var selected_id: String = ""
var dest_marker_tile: Vector2i = Vector2i(-1, -1)
var input_enabled: bool = true

var _target: Vector2 = Vector2(300, 300)
var _dist: float = 34.0
var _entities_root := Node3D.new()
var _routes_root := Node3D.new()
var _fx_root := Node3D.new()
var _terrain_root := Node3D.new()
var _sel_ring: MeshInstance3D
var _target_ring: MeshInstance3D
var _target_label: Label3D
var _dest_ring: MeshInstance3D
var _portal_rings: Array = []
var _planets: Array = []
var _touches: Dictionary = {}
var _tap_valid: bool = false
var _moved: float = 0.0
var _pinch_dist: float = 0.0
var _pinch_cam: float = 34.0
var _mouse_down: bool = false
var _velocity: Vector2 = Vector2.ZERO
var _focus_tween: Tween
var _t: float = 0.0
var _labels_on: bool = true
var _shake: float = 0.0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("03050f")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.9)
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 0.9
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)

	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(760, 760)
	floor.mesh = pm
	var fm := ShaderMaterial.new()
	fm.shader = FLOOR
	floor.material_override = fm
	_floor_mat = fm
	floor.position = Vector3(300, -0.6, 300)
	add_child(floor)

	add_child(_terrain_root)
	add_child(_routes_root)
	add_child(_entities_root)
	add_child(_fx_root)
	_sel_ring = _ring_mesh(Color("ffe07a"), 8.0, 1.6)
	_dest_ring = _ring_mesh(Color("3fd0ff"), 6.0, 1.2)
	_sel_ring.visible = false
	_dest_ring.visible = false
	# Objetivo de Alianza: retícula roja sobre la nave marcada.
	_target_ring = _ring_mesh(Color("ff3355"), 4.0, 9.0)
	(_target_ring.material_override as ShaderMaterial).set_shader_parameter("intensity", 1.4)
	_target_ring.visible = false
	_target_label = Entity3D.label3d(U.t("OBJETIVO DE ALIANZA"), 30, Color("ff6680"), 10)
	_target_label.visible = false
	add_child(_target_label)

	camera.fov = FOV
	camera.near = 0.5
	camera.far = 600.0
	add_child(camera)
	camera.make_current()
	_update_camera()

	GameClient.world_changed.connect(_on_world_changed)
	GameClient.fx.connect(_on_fx)
	GameClient.welcomed.connect(_rebuild_all)
	_rebuild_all()


func _ring_mesh(col: Color, dashes: float, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.quad(Vector2(1, 1))
	var m := ShaderMaterial.new()
	m.shader = RING
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("dashes", dashes)
	mi.material_override = m
	mi.scale = Vector3.ONE * size
	add_child(mi)
	return mi


# ---------------------------------------------------------------- API pública

func center_on_tile(tile: Vector2, animate: bool = true) -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_velocity = Vector2.ZERO
	if animate:
		_focus_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_focus_tween.tween_method(func(v: Vector2) -> void:
			_target = v
			_after_camera_change(), _target, tile, 0.5)
	else:
		_target = tile
		_after_camera_change()


func center_tiles() -> Vector2:
	return _target


## Equivalente al zoom 2D (px por casilla / 32) para el minimapa y pruebas.
func zoom_level() -> float:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var vis_h: float = 2.0 * _dist * tan(deg_to_rad(FOV) / 2.0)
	var vis_w: float = vis_h * vs.x / maxf(1.0, vs.y)
	return vs.x / (vis_w * 32.0)


func set_zoom(z: float) -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var vis_w: float = vs.x / (maxf(0.05, z) * 32.0)
	var vis_h: float = vis_w * vs.y / maxf(1.0, vs.x)
	_dist = clampf(vis_h / (2.0 * tan(deg_to_rad(FOV) / 2.0)), MIN_DIST, MAX_DIST)
	_after_camera_change()


func select(id: String) -> void:
	selected_id = id
	dest_marker_tile = Vector2i(-1, -1)


func set_destination_marker(tile: Vector2i) -> void:
	dest_marker_tile = tile
	selected_id = ""


func clear_selection() -> void:
	selected_id = ""
	dest_marker_tile = Vector2i(-1, -1)


# ---------------------------------------------------------------- réplica

var _floor_mat: ShaderMaterial


## Cada Sistema Solar tiene su propia nebulosa (tono derivado del sistema).
func _apply_system_tint() -> void:
	if _floor_mat == null:
		return
	var h: float = float(GameClient.system.get("hue", 0.72))
	_floor_mat.set_shader_parameter("neb_a", Color.from_hsv(h, 0.75, 0.55))
	_floor_mat.set_shader_parameter("neb_b", Color.from_hsv(fmod(h + 0.42, 1.0), 0.85, 0.55))


func _rebuild_all() -> void:
	_apply_system_tint()
	for id: String in nodes.keys():
		(nodes[id] as Node).queue_free()
	nodes.clear()
	_build_terrain()
	for id: String in GameClient.entities:
		_upsert(GameClient.entities[id])


func _build_terrain() -> void:
	for c: Node in _terrain_root.get_children():
		c.queue_free()
	_portal_rings.clear()
	_planets.clear()
	for t: Dictionary in GameClient.terrain:
		var p: Vector2 = U.v2(t["pos"])
		var r: float = float(t["radius"])
		if t["kind"] == "portal":
			var root := Node3D.new()
			root.position = Vector3(p.x, 0.0, p.y)
			_terrain_root.add_child(root)
			var cols: Array = [Color("b388ff"), Color("3fd0ff"), Color("ffffff")]
			for i: int in range(3):
				var mi := MeshInstance3D.new()
				var b := Kit.Builder.new()
				b.add(Kit.torus(r * (0.55 + i * 0.2) - 0.35, r * (0.55 + i * 0.2), 48, 6), Transform3D.IDENTITY, cols[i], 0.9)
				mi.mesh = b.commit()
				mi.material_override = Kit.material(0.0)
				mi.position.y = 1.5 + i * 0.6
				root.add_child(mi)
				_portal_rings.append(mi)
			var v := MeshInstance3D.new()
			v.mesh = Kit.quad(Vector2(r * 1.5, r * 1.5))
			var vm := ShaderMaterial.new()
			vm.shader = VORTEX
			v.material_override = vm
			v.position.y = 0.4
			root.add_child(v)
			var core := MeshInstance3D.new()
			var cb := Kit.Builder.new()
			cb.add(Kit.sphere(1.6, 16, 10), Transform3D.IDENTITY, Color("e9ddff"), 1.0)
			core.mesh = cb.commit()
			core.material_override = Kit.material(0.0)
			core.position.y = 2.2
			root.add_child(core)
			var l := Entity3D.label3d(U.t("PORTAL DE SALTO"), 44, Color("d9c8ff"), 14)
			l.position.y = 9.0
			root.add_child(l)
			var l2 := Entity3D.label3d(U.t("Salto interestelar · toca para abrir la Galaxia"), 28, Color(0.75, 0.75, 0.95), 10)
			l2.position.y = 9.0
			l2.offset = Vector2(0, -34)
			root.add_child(l2)
		elif t["kind"] == "planet":
			var pn := MeshInstance3D.new()
			pn.mesh = Kit.planet(Color(str(t.get("color", "#8888ff"))))
			pn.material_override = Kit.material(0.0)
			pn.scale = Vector3.ONE * r * 0.42
			pn.position = Vector3(p.x, r * 0.42 + 0.5, p.y)
			var zone := _ring_mesh(Color(str(t.get("color", "#8888ff"))), 24.0, r * 2.2)
			remove_child(zone)
			zone.position = Vector3(p.x, 0.02, p.y)
			(zone.material_override as ShaderMaterial).set_shader_parameter("intensity", 0.45)
			_terrain_root.add_child(zone)
			pn.rotation_degrees = Vector3(18, 0, 12)
			_terrain_root.add_child(pn)
			_planets.append(pn)
			var pl := Entity3D.label3d(str(t.get("name", "")), 28, Color(str(t.get("color", "#ffffff"))).lightened(0.4), 10)
			pl.position = Vector3(p.x, r * 0.95 + 2.0, p.y)
			_terrain_root.add_child(pl)


func _on_world_changed(added: Array, updated: Array, removed: Array) -> void:
	for e: Dictionary in added:
		_upsert(e)
	for e2: Dictionary in updated:
		_upsert(e2)
	for id: Variant in removed:
		var sid: String = str(id)
		if nodes.has(sid):
			(nodes[sid] as Node).queue_free()
			nodes.erase(sid)
		if sid == selected_id:
			selected_id = ""


func _upsert(e: Dictionary) -> void:
	var id: String = str(e["id"])
	if nodes.has(id):
		(nodes[id] as Node3D).refresh(e)
		return
	var n: Node3D = Entity3D.new()
	_entities_root.add_child(n)
	n.setup(e, _routes_root)
	n.set_labels_visible(_labels_on)
	nodes[id] = n


func _on_fx(kind: String, pos: Vector2, own: bool) -> void:
	var col: Color = Color("b388ff") if kind == "hunt" else (Color("3fd0ff") if own else Color("ffb347"))
	var center := Vector3(pos.x, 1.4, pos.y)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var shots: int = 7 if kind != "hunt" else 5
	# Ráfaga de láseres desde los cazas que rodean el objetivo.
	for i: int in range(shots):
		var ang: float = TAU * i / float(shots) + rng.randf_range(-0.3, 0.3)
		var from := center + Vector3(cos(ang) * rng.randf_range(5.5, 8.0), rng.randf_range(1.0, 3.0), sin(ang) * rng.randf_range(5.5, 8.0))
		var to := center + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.3, 0.6), rng.randf_range(-0.8, 0.8))
		for k: int in range(2):
			FX.laser(_fx_root, from, to, col, i * 0.11 + k * 0.42, 0.14)
	var main_col: Color = Color("7cf2b3") if kind == "hunt" else col
	FX.burst(_fx_root, center, main_col, 1.25 if kind != "hunt" else 0.95, 14, 0.95)
	if kind != "hunt":
		for j: int in range(2):
			FX.burst(_fx_root, center + Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(0.0, 1.5), rng.randf_range(-2.5, 2.5)), Color("ff8a3d"), 0.5, 5, 1.15 + j * 0.18)
	if own and Vector2(_target).distance_to(pos) < _dist * 0.9:
		var tw := create_tween()
		tw.tween_interval(0.95)
		tw.tween_callback(func() -> void: _shake = 0.45)
	for id: String in nodes:
		var n: Node3D = nodes[id]
		if n.kind == "xenoform" and Vector2(n.position.x, n.position.z).distance_to(pos) < 1.0:
			n.hit_flash()


# ---------------------------------------------------------------- cámara

func _update_camera() -> void:
	var pitch: float = deg_to_rad(PITCH_DEG)
	var off := Vector3(0, sin(pitch), cos(pitch)) * _dist
	var jitter := Vector3.ZERO
	if _shake > 0.0:
		jitter = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.6
	camera.position = Vector3(_target.x, 0, _target.y) + off + jitter
	camera.look_at(Vector3(_target.x, 0, _target.y) + jitter * 0.5, Vector3.UP)


func _after_camera_change() -> void:
	var limit: float = float(GameClient.map_size)
	_target = _target.clamp(Vector2.ZERO, Vector2(limit, limit))
	_update_camera()
	var radius: float = 0.0
	var vs: Vector2 = get_viewport().get_visible_rect().size
	for corner: Vector2 in [Vector2.ZERO, Vector2(vs.x, 0), Vector2(0, vs.y), vs]:
		var g: Vector3 = _ground_at(corner)
		if g != Vector3.INF:
			radius = maxf(radius, Vector2(g.x, g.z).distance_to(_target))
	if radius <= 0.0:
		radius = _dist * 1.4
	GameClient.set_view(_target, minf(radius + 3.0, 90.0))
	var show: bool = _dist < 48.0
	if show != _labels_on:
		_labels_on = show
		for id: String in nodes:
			(nodes[id] as Node3D).set_labels_visible(show)
	camera_moved.emit(_target)


func _ground_at(screen: Vector2) -> Vector3:
	var o: Vector3 = camera.project_ray_origin(screen)
	var d: Vector3 = camera.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t: float = -o.y / d.y
	if t < 0.0:
		return Vector3.INF
	return o + d * t


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	_t += delta
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		_update_camera()
	if _velocity.length() > 0.5 and _touches.is_empty() and not _mouse_down:
		_target -= _velocity * delta
		_velocity = _velocity.lerp(Vector2.ZERO, clampf(delta * 5.0, 0.0, 1.0))
		_after_camera_change()
	for i: int in range(_portal_rings.size()):
		var r: Node3D = _portal_rings[i]
		r.rotation.y += delta * (0.4 - i * 0.25)
		r.rotation.x = sin(_t * 0.5 + i) * 0.18
	for pn: Node3D in _planets:
		pn.rotation.y += delta * 0.05
	if not selected_id.is_empty() and nodes.has(selected_id):
		var n: Node3D = nodes[selected_id]
		_sel_ring.visible = true
		_sel_ring.position = Vector3(n.position.x, 0.08, n.position.z)
		var s: float = {"base": 7.0, "asteroid": 3.6, "xenoform": 3.8, "fleet": 3.0}.get(n.kind, 3.0)
		_sel_ring.scale = Vector3.ONE * (s + sin(_t * 4.0) * 0.15)
		_sel_ring.rotation.y += delta * 0.8
	else:
		_sel_ring.visible = false
	var tid: String = str(GameClient.me.get("guild_brief", {}).get("target_id", ""))
	if not tid.is_empty() and nodes.has(tid):
		var tn: Node3D = nodes[tid]
		_target_ring.visible = true
		_target_label.visible = _labels_on
		_target_ring.position = Vector3(tn.position.x, 0.1, tn.position.z)
		_target_ring.scale = Vector3.ONE * (9.0 + sin(_t * 6.0) * 0.8)
		_target_ring.rotation.y -= delta * 1.6
		_target_label.position = Vector3(tn.position.x, 7.5, tn.position.z)
		_target_label.offset = Vector2(0, 52)
	else:
		_target_ring.visible = false
		_target_label.visible = false
	_dest_ring.visible = dest_marker_tile.x >= 0
	if _dest_ring.visible:
		_dest_ring.position = Vector3(dest_marker_tile.x, 0.08, dest_marker_tile.y)
		_dest_ring.scale = Vector3.ONE * (2.4 + sin(_t * 5.0) * 0.3)


# ---------------------------------------------------------------- entrada

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not is_visible_in_tree():
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and _mouse_down:
		var mm: InputEventMouseMotion = event
		_pan(mm.position - mm.relative, mm.position)
		_moved += mm.relative.length()
		if _moved > TAP_SLOP:
			_tap_valid = false
	elif event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event
		_zoom_at(mg.position, 1.0 / mg.factor)


func _on_touch(st: InputEventScreenTouch) -> void:
	if st.pressed:
		_touches[st.index] = st.position
		_velocity = Vector2.ZERO
		if _touches.size() == 1:
			_tap_valid = true
			_moved = 0.0
		elif _touches.size() == 2:
			_tap_valid = false
			var pts: Array = _touches.values()
			_pinch_dist = (pts[0] as Vector2).distance_to(pts[1])
			_pinch_cam = _dist
	else:
		if _tap_valid and _touches.size() == 1 and _moved < TAP_SLOP:
			_handle_tap(st.position)
		_touches.erase(st.index)
		if _touches.size() == 1:
			_tap_valid = false


func _on_drag(sd: InputEventScreenDrag) -> void:
	var prev: Vector2 = _touches.get(sd.index, sd.position - sd.relative)
	_touches[sd.index] = sd.position
	if _touches.size() == 1:
		_pan(prev, sd.position)
		var g0: Vector3 = _ground_at(sd.position - sd.velocity * 0.016)
		var g1: Vector3 = _ground_at(sd.position)
		if g0 != Vector3.INF and g1 != Vector3.INF:
			_velocity = Vector2(g1.x - g0.x, g1.z - g0.z) / 0.016
		_moved += sd.relative.length()
		if _moved > TAP_SLOP:
			_tap_valid = false
	elif _touches.size() >= 2:
		var pts: Array = _touches.values()
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var d: float = a.distance_to(b)
		if _pinch_dist > 0.0 and d > 0.0:
			var want: float = clampf(_pinch_cam * _pinch_dist / d, MIN_DIST, MAX_DIST)
			_zoom_at((a + b) / 2.0, want / _dist)


func _on_mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_down = true
				_tap_valid = true
				_moved = 0.0
				_velocity = Vector2.ZERO
			else:
				_mouse_down = false
				if _tap_valid and _moved < TAP_SLOP:
					_handle_tap(mb.position)
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_zoom_at(mb.position, 1.0 / 1.15)
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_zoom_at(mb.position, 1.15)


func _pan(from_screen: Vector2, to_screen: Vector2) -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	var a: Vector3 = _ground_at(from_screen)
	var b: Vector3 = _ground_at(to_screen)
	if a == Vector3.INF or b == Vector3.INF:
		return
	_target -= Vector2(b.x - a.x, b.z - a.z)
	_after_camera_change()


## factor > 1 aleja; mantiene fijo el punto del suelo bajo el dedo/cursor.
func _zoom_at(screen: Vector2, factor: float) -> void:
	var before: Vector3 = _ground_at(screen)
	_dist = clampf(_dist * factor, MIN_DIST, MAX_DIST)
	_update_camera()
	var after: Vector3 = _ground_at(screen)
	if before != Vector3.INF and after != Vector3.INF:
		_target += Vector2(before.x - after.x, before.z - after.z)
	_after_camera_change()


func _handle_tap(screen: Vector2) -> void:
	var best_id: String = ""
	var best_d: float = INF
	var scale_px: float = 40.0 / _dist
	for id: String in nodes:
		var n: Node3D = nodes[id]
		var wp: Vector3 = n.global_position + Vector3(0, 0.4, 0)
		if camera.is_position_behind(wp):
			continue
		var sp: Vector2 = camera.unproject_position(wp)
		var r: float = {"base": 95.0, "asteroid": 55.0, "xenoform": 60.0, "fleet": 45.0}.get(n.kind, 50.0) * scale_px
		r = maxf(r, 26.0)
		var d: float = sp.distance_to(screen)
		if n.kind == "fleet":
			d += 6.0
		if d < r and d < best_d:
			best_d = d
			best_id = id
	if not best_id.is_empty():
		select(best_id)
		entity_tapped.emit(best_id)
		return
	var g: Vector3 = _ground_at(screen)
	if g == Vector3.INF:
		return
	var tile := Vector2i(roundi(g.x), roundi(g.z))
	if tile.x < 0 or tile.y < 0 or tile.x >= GameClient.map_size or tile.y >= GameClient.map_size:
		return
	set_destination_marker(tile)
	empty_tapped.emit(tile)
