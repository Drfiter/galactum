extends Node3D
## Interior de la Astronave en 3D (estilo aldea de Clash of Clans): una cubierta
## flotante con las salas como edificios. Tocar un edificio abre su ventana;
## las burbujas verdes recolectan producción. Vive lejos del mapa en el mismo
## mundo 3D y usa su propia cámara.

const UI = preload("res://ui/ui.gd")
const U = preload("res://shared/util.gd")
const Kit = preload("res://ui/world3d/mesh_kit.gd")
const Entity3D = preload("res://ui/world3d/entity_3d.gd")
const FLOOR = preload("res://assets/shaders/space_floor.gdshader")
const BLOB = preload("res://assets/shaders/blob_shadow.gdshader")
const BAR = preload("res://assets/shaders/billboard_bar.gdshader")
const RING = preload("res://assets/shaders/glow_ring.gdshader")

const ORIGIN := Vector3(-2000, 0, -2000)
const COLS_X: Array = [-9.6, -3.2, 3.2, 9.6]
const ROWS_Z: Array = [-12.0, -5.0, 2.0, 9.5, 16.5, 23.5]
const TAP_SLOP: float = 14.0

signal room_tapped(room_id: String)
signal bubble_tapped(room_id: String)
signal locked_tapped(info: Dictionary)

var camera := Camera3D.new()
var active: bool = false
var buildings: Dictionary = {}   # id -> {root, model, name, level, bubble, bubble_label, scaffold, bar, bar_mat, timer, locked}
var _target := Vector2(-1.5, 0.5)
var _dist: float = 62.0
## Distancia máxima de zoom; crece si el encuadre automático necesita alejarse
## más (pantallas bajas como las de 20:9).
var _max_dist: float = 78.0
const YAW_DEG: float = 32.0
var _t: float = 0.0
var _touches: Dictionary = {}
var _tap_valid: bool = false
var _moved: float = 0.0
var _pinch_dist: float = 0.0
var _pinch_cam: float = 62.0
var _mouse_down: bool = false
var _levels_sig: String = ""


func _ready() -> void:
	position = ORIGIN
	_build_space()
	_build_deck()
	camera.fov = 40.0
	camera.near = 0.5
	camera.far = 260.0
	add_child(camera)
	_update_camera()
	_layout_buildings()
	GameClient.player_updated.connect(_on_player)


func activate(on: bool) -> void:
	active = on
	visible = on
	if on:
		camera.make_current()
		_on_player()


# ---------------------------------------------------------------- escenario

func _build_space() -> void:
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	floor.mesh = pm
	var fm := ShaderMaterial.new()
	fm.shader = FLOOR
	fm.set_shader_parameter("grid_alpha", 0.35)
	fm.set_shader_parameter("map_tiles", 4000.0)
	floor.material_override = fm
	floor.position = Vector3(0, -26, 0)
	add_child(floor)


func _hull_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -27), Vector2(7, -21), Vector2(14, -14), Vector2(16, -2), Vector2(16, 21),
		Vector2(13, 29), Vector2(-13, 29), Vector2(-16, 21), Vector2(-16, -2), Vector2(-14, -14), Vector2(-7, -21),
	])


func _build_deck() -> void:
	var b := Kit.Builder.new()
	var pts: PackedVector2Array = _hull_points()
	var top: float = 0.0
	var bottom: float = -2.2
	var deck_col := Color("4a5a86")
	var wall_col := Color("2a3358")
	var tris := PackedVector3Array()
	var c := Vector3(0, top, 0)
	for i: int in range(pts.size()):
		var a: Vector2 = pts[i]
		var d: Vector2 = pts[(i + 1) % pts.size()]
		tris.append(c)
		tris.append(Vector3(d.x, top, d.y))
		tris.append(Vector3(a.x, top, a.y))
	b.add_flat_tris(tris, deck_col)
	var walls := PackedVector3Array()
	for i: int in range(pts.size()):
		var a2: Vector2 = pts[i]
		var d2: Vector2 = pts[(i + 1) % pts.size()]
		var a_t := Vector3(a2.x, top, a2.y)
		var d_t := Vector3(d2.x, top, d2.y)
		var a_b := Vector3(a2.x * 0.86, bottom, a2.y * 0.9)
		var d_b := Vector3(d2.x * 0.86, bottom, d2.y * 0.9)
		walls.append_array(PackedVector3Array([a_t, d_t, d_b, a_t, d_b, a_b]))
	b.add_flat_tris(walls, wall_col)
	# Franja luminosa del borde
	for i: int in range(pts.size()):
		var a3: Vector2 = pts[i]
		var d3: Vector2 = pts[(i + 1) % pts.size()]
		var mid: Vector2 = (a3 + d3) / 2.0
		var dir: Vector2 = d3 - a3
		b.add(Kit.box(Vector3(dir.length(), 0.18, 0.28)), Transform3D(Basis(Vector3.UP, -dir.angle()), Vector3(mid.x, 0.1, mid.y)), Color("3fd0ff"), 0.9)
	# Placas de las parcelas
	for zi: int in range(ROWS_Z.size()):
		for xi: int in range(COLS_X.size()):
			var col: Color = Color("5d6fa3") if zi >= 1 and zi <= 3 else Color("454f73")
			b.add(Kit.box(Vector3(5.6, 0.25, 5.6)), Kit.xf(Vector3(COLS_X[xi], 0.12, ROWS_Z[zi])), col)
			b.add(Kit.box(Vector3(5.9, 0.12, 5.9)), Kit.xf(Vector3(COLS_X[xi], 0.04, ROWS_Z[zi])), Color("2b3a66"))
	# Pasillos y detalles
	b.add(Kit.box(Vector3(1.2, 0.08, 34)), Kit.xf(Vector3(0, 0.06, 2.5)), Color("8fa3d8"))
	for s: float in [-1.0, 1.0]:
		b.add(Kit.box(Vector3(9, 0.6, 7)), Kit.xf(Vector3(19.5 * s, -0.8, 6), Vector3(0, 0, -8 * s)), Color("3a4878"))
		b.add(Kit.box(Vector3(0.3, 0.25, 6.6)), Kit.xf(Vector3(23.6 * s, -0.4, 6)), Color("ff4d6d"), 0.9)
		b.add(Kit.cyl(2.0, 2.4, 4.5, 14), Kit.xf(Vector3(8 * s, -1.0, 24.5), Vector3(90, 0, 0)), Color("8a96b8"))
		b.add(Kit.cyl(1.6, 1.6, 0.4, 14), Kit.xf(Vector3(8 * s, -1.0, 26.9), Vector3(90, 0, 0)), Color("ffa040"), 1.0)
	b.add(Kit.cyl(2.6, 3.0, 5.0, 14), Kit.xf(Vector3(0, -1.2, 25), Vector3(90, 0, 0)), Color("8a96b8"))
	b.add(Kit.cyl(2.2, 2.2, 0.4, 14), Kit.xf(Vector3(0, -1.2, 27.6), Vector3(90, 0, 0)), Color("ffb850"), 1.0)
	b.add(Kit.sphere(1.0, 12, 6), Kit.xf(Vector3(0, -2.4, 0), Vector3.ZERO, Vector3(12, 1.2, 20)), Color("3fd0ff"), 0.35)
	var deck := MeshInstance3D.new()
	deck.mesh = b.commit()
	deck.material_override = Kit.material(0.06)
	add_child(deck)


# ---------------------------------------------------------------- edificios

func _plot(index: int) -> Vector3:
	return Vector3(COLS_X[index % 4], 0.25, ROWS_Z[index / 4])


func _layout_buildings() -> void:
	# Filas centrales (1-3) = salas iniciales; filas 0, 4 y 5 = salas que se
	# construyen (Fase 2). 24 salas en 6 filas de 4.
	var slots: Array = range(4, 24) + [0, 1, 2, 3]
	var i: int = 0
	for id: String in Catalog.room_order:
		if i >= slots.size():
			break
		_slot_of[id] = int(slots[i])
		_make_building(id, _plot(int(slots[i])), false, {})
		i += 1
	var locked: Array = Catalog.rooms_data.get("locked", [])
	for j: int in range(locked.size()):
		var slot: int = j if j < 4 else 16 + (j - 4)
		_make_building(str(locked[j]["id"]), _plot(slot), true, locked[j])


var _slot_of: Dictionary = {}


## Sala de Fase 2 que aún no se construyó (se compra en la ventana de la sala).
func _is_unbuilt(id: String) -> bool:
	return Catalog.room(id).has("unlock") and GameClient.room_level(id) <= 0


func _make_building(id: String, pos: Vector3, locked: bool, info: Dictionary) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var shadow := MeshInstance3D.new()
	shadow.mesh = Kit.quad(Vector2(5.4, 5.4))
	var sm := ShaderMaterial.new()
	sm.shader = BLOB
	sm.set_shader_parameter("color", Color(0, 0, 0.05, 0.45))
	shadow.material_override = sm
	shadow.position.y = 0.03
	root.add_child(shadow)
	var model := MeshInstance3D.new()
	var unbuilt: bool = not locked and _is_unbuilt(id)
	model.mesh = construction_site() if locked or unbuilt else building_mesh(id)
	model.material_override = Kit.material(0.045)
	root.add_child(model)
	var name_l := Entity3D.label3d(str(info.get("name", "")) if locked else _short_name(id), 26, UI.TEXT if not locked else UI.TEXT_DIM, 9)
	name_l.position.y = 5.2
	name_l.offset = Vector2(0, 26)
	root.add_child(name_l)
	var lvl_l := Entity3D.label3d("", 30, UI.GOLD, 10)
	lvl_l.position.y = 5.2
	root.add_child(lvl_l)
	if locked:
		lvl_l.text = str(info.get("phase", U.t("Fase 2")))
		lvl_l.modulate = Color("9aa6c8")
	if unbuilt:
		lvl_l.text = U.t("Construir")
		lvl_l.modulate = Color("ffd36a")
	var entry: Dictionary = {"root": root, "model": model, "name": name_l, "level": lvl_l, "locked": locked, "info": info, "unbuilt": unbuilt}
	if not locked:
		var scaffold := MeshInstance3D.new()
		scaffold.mesh = scaffold_mesh()
		scaffold.material_override = Kit.material(0.03)
		scaffold.visible = false
		root.add_child(scaffold)
		entry["scaffold"] = scaffold
		var bar := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(3.2, 0.32)
		bar.mesh = q
		var bm := ShaderMaterial.new()
		bm.shader = BAR
		bm.set_shader_parameter("fill_color", Color("3fd0ff"))
		bar.material_override = bm
		bar.position.y = 4.3
		bar.visible = false
		root.add_child(bar)
		entry["bar"] = bar
		entry["bar_mat"] = bm
		var timer := Entity3D.label3d("", 28, Color("bff6ff"), 9)
		timer.position.y = 3.75
		timer.visible = false
		root.add_child(timer)
		entry["timer"] = timer
		if Catalog.room(id).has("produces"):
			var bubble := Node3D.new()
			bubble.position.y = 6.9
			bubble.visible = false
			root.add_child(bubble)
			var disc := MeshInstance3D.new()
			var dq := QuadMesh.new()
			dq.size = Vector2(1.9, 1.9)
			disc.mesh = dq
			var dm := StandardMaterial3D.new()
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dm.albedo_texture = _bubble_tex()
			dm.no_depth_test = true
			dm.render_priority = 5
			disc.material_override = dm
			bubble.add_child(disc)
			var first: String = (Catalog.room(id)["produces"] as Dictionary).keys()[0]
			var icon := Sprite3D.new()
			icon.texture = UI.icon_tex(UI.res_icon_name(first))
			icon.pixel_size = 0.016
			icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			icon.no_depth_test = true
			icon.render_priority = 6
			icon.position = Vector3(0, 0.05, 0.02)
			bubble.add_child(icon)
			var amt := Entity3D.label3d("", 30, Color.WHITE, 10)
			amt.position.y = 1.25
			bubble.add_child(amt)
			entry["bubble"] = bubble
			entry["bubble_label"] = amt
	buildings[id] = entry


static func _short_name(id: String) -> String:
	var short: Dictionary = {"fleet_hq": U.t("Coord. de Flota"), "platform": U.t("2ª Plataforma"), "sensors": U.t("Sensores"), "perimeter": U.t("Escudo Perimetral"), "vault": U.t("Bóveda Cuántica"), "crew": U.t("Tripulación")}
	return str(short.get(id, Catalog.room(id).get("name", id)))


static var _bubble_texture: Texture2D


static func _bubble_tex() -> Texture2D:
	if _bubble_texture != null:
		return _bubble_texture
	var s: int = 96
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s / 2.0, s / 2.0)
	for y: int in range(s):
		for x: int in range(s):
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / (s / 2.0)
			var col := Color(0, 0, 0, 0)
			if d < 0.86:
				col = Color("26b56f").lerp(Color("7cf2b3"), clampf(1.0 - (y / float(s)) - d * 0.3, 0.0, 1.0))
			elif d < 0.97:
				col = Color("eafff4")
			elif d < 1.0:
				col = Color(0.92, 1, 0.96, (1.0 - d) / 0.03)
			img.set_pixel(x, y, col)
	_bubble_texture = ImageTexture.create_from_image(img)
	return _bubble_texture


static func building_mesh(id: String) -> ArrayMesh:
	var b := Kit.Builder.new()
	var steel := Color("c9d3e8")
	var dark := Color("39456e")
	# Zócalo común
	b.add(Kit.box(Vector3(4.4, 0.45, 4.4)), Kit.xf(Vector3(0, 0.22, 0)), Color("6f7fae"))
	match id:
		"bridge":
			b.add(Kit.cyl(1.9, 2.1, 1.4, 8), Kit.xf(Vector3(0, 1.1, 0)), steel)
			b.add(Kit.cyl(1.1, 1.4, 2.0, 8), Kit.xf(Vector3(0, 2.8, 0)), Color("f0c050"))
			b.add(Kit.sphere(1.05, 14, 8), Kit.xf(Vector3(0, 3.9, 0), Vector3.ZERO, Vector3(1, 0.75, 1)), Color("5ff2ff"), 0.6)
			b.add(Kit.cyl(0.06, 0.06, 1.4, 6), Kit.xf(Vector3(0, 4.9, 0)), dark)
			b.add(Kit.sphere(0.16, 8, 4), Kit.xf(Vector3(0, 5.65, 0)), Color("ff5d73"), 1.0)
			for s: float in [-1.0, 1.0]:
				b.add(Kit.box(Vector3(0.5, 1.6, 0.5)), Kit.xf(Vector3(1.6 * s, 1.2, 1.4)), Color("f0c050"))
		"factory":
			b.add(Kit.box(Vector3(3.6, 2.0, 3.0)), Kit.xf(Vector3(0, 1.45, 0.2)), Color("e88a3a"))
			b.add(Kit.box(Vector3(3.8, 0.3, 3.2)), Kit.xf(Vector3(0, 2.55, 0.2)), dark)
			for s: float in [-1.0, 1.0]:
				b.add(Kit.cyl(0.35, 0.45, 2.4, 10), Kit.xf(Vector3(1.1 * s, 3.6, 0.8)), steel)
				b.add(Kit.cyl(0.36, 0.36, 0.25, 10), Kit.xf(Vector3(1.1 * s, 4.85, 0.8)), Color("ff6b3d"), 0.9)
			b.add(Kit.torus(0.5, 0.85, 12, 6), Kit.xf(Vector3(0, 1.6, -1.35), Vector3(90, 0, 0)), Color("ffd54a"))
			b.add(Kit.box(Vector3(1.4, 1.0, 0.1)), Kit.xf(Vector3(-1.0, 1.0, -1.32)), Color("1d2442"))
		"platform":
			b.add(Kit.box(Vector3(4.0, 0.5, 4.0)), Kit.xf(Vector3(0, 0.6, 0)), Color("4f7f5f"))
			var spots: Array = [Vector3(-1.0, 0.85, -0.9), Vector3(1.1, 0.85, -0.6), Vector3(0, 0.85, 1.1)]
			for i: int in range(3):
				b.add(Kit.sphere(1.0, 12, 6), Kit.xf(spots[i], Vector3.ZERO, Vector3(1, 0.9, 1) * (1.1 - i * 0.12)), Color("7cf28f"), 0.35)
				b.add(Kit.torus(0.95, 1.1, 16, 4), Kit.xf(spots[i], Vector3.ZERO, Vector3(1, 0.4, 1) * (1.1 - i * 0.12)), steel)
		"bank":
			b.add(Kit.box(Vector3(3.8, 0.4, 3.4)), Kit.xf(Vector3(0, 0.65, 0)), Color("e9e2d0"))
			for x: float in [-1.3, -0.45, 0.45, 1.3]:
				b.add(Kit.cyl(0.22, 0.25, 2.2, 10), Kit.xf(Vector3(x, 1.95, -1.1)), Color("f6f0e0"))
			b.add(Kit.box(Vector3(3.4, 2.0, 2.0)), Kit.xf(Vector3(0, 1.85, 0.5)), Color("dcd3bd"))
			b.add(Kit.box(Vector3(3.9, 0.35, 3.0)), Kit.xf(Vector3(0, 3.2, 0)), Color("f0c050"))
			var prism := PrismMesh.new()
			prism.size = Vector3(3.9, 1.1, 3.0)
			b.add(prism, Kit.xf(Vector3(0, 3.9, 0)), Color("ffcf4a"))
			b.add(Kit.cyl(0.55, 0.55, 0.16, 16), Kit.xf(Vector3(0, 3.95, -1.52), Vector3(90, 0, 0)), Color("ffe48a"), 0.7)
		"hangar":
			b.add(Kit.cyl(1.9, 1.9, 4.0, 14), Kit.xf(Vector3(0, 0.9, 0), Vector3(90, 0, 0), Vector3(1, 1, 1)), Color("6e86b8"))
			b.add(Kit.box(Vector3(4.2, 1.0, 4.2)), Kit.xf(Vector3(0, 0.3, 0)), Color("6f7fae"))
			b.add(Kit.box(Vector3(2.2, 1.9, 0.2)), Kit.xf(Vector3(0, 1.4, -2.0)), Color("1d2442"))
			b.add(Kit.box(Vector3(2.4, 0.2, 0.25)), Kit.xf(Vector3(0, 2.45, -2.02)), Color("3ddc97"), 0.9)
			b.add(Kit.box(Vector3(0.2, 0.8, 3.6)), Kit.xf(Vector3(0, 2.85, 0)), Color("3ddc97"))
		"lab":
			b.add(Kit.cyl(1.7, 1.9, 1.3, 12), Kit.xf(Vector3(0, 1.05, 0)), steel)
			b.add(Kit.sphere(1.5, 16, 8), Kit.xf(Vector3(0, 2.0, 0), Vector3.ZERO, Vector3(1, 0.85, 1)), Color("4fd8ff"), 0.45)
			b.add(Kit.cyl(0.35, 0.35, 2.2, 10), Kit.xf(Vector3(1.5, 2.0, 1.2)), Color("b388ff"), 0.4)
			b.add(Kit.sphere(0.45, 10, 6), Kit.xf(Vector3(1.5, 3.25, 1.2)), Color("d6b8ff"), 0.8)
			b.add(Kit.cyl(0.05, 0.05, 1.4, 6), Kit.xf(Vector3(0, 3.6, 0)), dark)
			b.add(Kit.torus(0.25, 0.4, 12, 4), Kit.xf(Vector3(0, 4.3, 0), Vector3(90, 0, 0)), Color("5ff2ff"), 0.9)
		"fleet_hq":
			b.add(Kit.box(Vector3(3.4, 1.6, 3.4)), Kit.xf(Vector3(0, 1.2, 0)), Color("d24f86"))
			b.add(Kit.cyl(0.18, 0.25, 1.6, 8), Kit.xf(Vector3(0, 2.8, 0)), steel)
			b.add(Kit.sphere(1.4, 14, 6), Kit.xf(Vector3(0, 3.7, -0.2), Vector3(-35, 0, 0), Vector3(1, 0.3, 1)), Color("eef2fb"))
			b.add(Kit.sphere(0.2, 8, 4), Kit.xf(Vector3(0, 4.1, -0.7)), Color("ff8fc8"), 1.0)
			b.add(Kit.box(Vector3(3.5, 0.25, 0.25)), Kit.xf(Vector3(0, 1.6, -1.72)), Color("ff8fc8"), 0.9)
		"medbay":
			b.add(Kit.box(Vector3(3.6, 2.2, 3.2)), Kit.xf(Vector3(0, 1.55, 0)), Color("f2f6fb"))
			b.add(Kit.box(Vector3(0.5, 1.5, 0.12)), Kit.xf(Vector3(0, 1.6, -1.62)), Color("3ddc97"), 0.9)
			b.add(Kit.box(Vector3(1.5, 0.5, 0.12)), Kit.xf(Vector3(0, 1.6, -1.62)), Color("3ddc97"), 0.9)
			b.add(Kit.sphere(0.9, 12, 6), Kit.xf(Vector3(0, 2.7, 0.4), Vector3.ZERO, Vector3(1, 0.6, 1)), Color("bff7dc"), 0.3)
		"cryo":
			for i: int in range(3):
				var x: float = (i - 1) * 1.25
				b.add(Kit.cyl(0.5, 0.5, 3.2, 12), Kit.xf(Vector3(x, 2.1, 0)), Color("8fe9ff"), 0.45)
				b.add(Kit.cyl(0.58, 0.58, 0.3, 12), Kit.xf(Vector3(x, 0.6, 0)), steel)
				b.add(Kit.cyl(0.58, 0.58, 0.3, 12), Kit.xf(Vector3(x, 3.75, 0)), steel)
			b.add(Kit.box(Vector3(4.0, 0.3, 1.4)), Kit.xf(Vector3(0, 2.1, 0.9)), dark)
		"vault":
			b.add(Kit.box(Vector3(3.2, 3.0, 3.2)), Kit.xf(Vector3(0, 1.95, 0)), Color("e3a83a"))
			b.add(Kit.cyl(1.0, 1.0, 0.25, 18), Kit.xf(Vector3(0, 1.95, -1.62), Vector3(90, 0, 0)), Color("8a6a2a"))
			b.add(Kit.torus(0.75, 1.0, 18, 4), Kit.xf(Vector3(0, 1.95, -1.75), Vector3(90, 0, 0)), Color("ffe48a"), 0.6)
			b.add(Kit.box(Vector3(3.3, 0.25, 3.3)), Kit.xf(Vector3(0, 3.5, 0)), Color("ffcf4a"))
		"perimeter":
			b.add(Kit.cyl(0.6, 1.1, 3.2, 10), Kit.xf(Vector3(0, 2.0, 0)), Color("6d5ab8"))
			b.add(Kit.torus(1.5, 1.8, 24, 6), Kit.xf(Vector3(0, 3.4, 0)), Color("c9a8ff"), 0.9)
			b.add(Kit.sphere(0.55, 12, 6), Kit.xf(Vector3(0, 3.9, 0)), Color("e6d6ff"), 1.0)
			for i: int in range(4):
				var a: float = TAU * i / 4.0
				b.add(Kit.box(Vector3(0.4, 1.2, 0.4)), Kit.xf(Vector3(cos(a) * 1.6, 1.0, sin(a) * 1.6)), steel)
		"sensors":
			b.add(Kit.box(Vector3(2.6, 1.0, 2.6)), Kit.xf(Vector3(0, 0.9, 0)), Color("3aa6a0"))
			b.add(Kit.cyl(0.16, 0.3, 3.0, 8), Kit.xf(Vector3(0, 2.8, 0)), steel)
			b.add(Kit.sphere(1.5, 14, 6), Kit.xf(Vector3(0, 4.2, 0), Vector3(-50, 30, 0), Vector3(1, 0.28, 1)), Color("eef2fb"))
			b.add(Kit.cyl(0.03, 0.03, 1.2, 4), Kit.xf(Vector3(0, 4.6, -0.3), Vector3(-50, 30, 0)), dark)
			b.add(Kit.sphere(0.18, 8, 4), Kit.xf(Vector3(-0.3, 5.0, -0.6)), Color("5ff2ff"), 1.0)
		"cantina":
			b.add(Kit.box(Vector3(3.8, 1.8, 3.0)), Kit.xf(Vector3(0, 1.35, 0.3)), Color("8a4fd1"))
			b.add(Kit.box(Vector3(4.0, 0.3, 3.2)), Kit.xf(Vector3(0, 2.35, 0.3)), Color("2a1f4a"))
			b.add(Kit.box(Vector3(2.6, 0.7, 0.12)), Kit.xf(Vector3(0, 3.0, -1.2)), Color("ff4fd8"), 1.0)
			b.add(Kit.box(Vector3(0.12, 1.6, 0.12)), Kit.xf(Vector3(-1.2, 2.6, -1.2)), dark)
			b.add(Kit.box(Vector3(0.12, 1.6, 0.12)), Kit.xf(Vector3(1.2, 2.6, -1.2)), dark)
			for x: float in [-1.2, 0.0, 1.2]:
				b.add(Kit.cyl(0.42, 0.42, 0.1, 12), Kit.xf(Vector3(x, 0.95, -1.75)), Color("ffd36a"))
				b.add(Kit.cyl(0.06, 0.06, 0.5, 6), Kit.xf(Vector3(x, 0.7, -1.75)), dark)
			b.add(Kit.box(Vector3(1.0, 1.0, 0.1)), Kit.xf(Vector3(0, 1.0, -1.22)), Color("ffcf8a"), 0.7)
		"crew":
			for i2: int in range(3):
				var y: float = 0.95 + i2 * 1.05
				b.add(Kit.capsule(0.48, 3.4), Kit.xf(Vector3(0, y, -0.4 + i2 * 0.4), Vector3(0, 0, 90)), Color("4fb0a8").lightened(i2 * 0.1))
				for w: float in [-1.0, 0.0, 1.0]:
					b.add(Kit.sphere(0.2, 8, 4), Kit.xf(Vector3(w, y, -0.85 + i2 * 0.4)), Color("bff7ff"), 0.9)
			b.add(Kit.box(Vector3(0.3, 3.6, 0.3)), Kit.xf(Vector3(1.9, 1.9, 0.6)), steel)
			b.add(Kit.sphere(0.3, 8, 4), Kit.xf(Vector3(1.9, 3.85, 0.6)), Color("3ddc97"), 1.0)
		"armory":
			b.add(Kit.box(Vector3(3.6, 1.6, 3.4)), Kit.xf(Vector3(0, 1.2, 0.2)), Color("8a5a3a"))
			b.add(Kit.box(Vector3(3.8, 0.3, 3.6)), Kit.xf(Vector3(0, 2.1, 0.2)), dark)
			b.add(Kit.cyl(0.9, 1.0, 0.7, 12), Kit.xf(Vector3(0, 2.55, 0.4)), steel)
			b.add(Kit.cyl(0.28, 0.32, 2.8, 10), Kit.xf(Vector3(0, 3.2, -0.9), Vector3(-62, 0, 0)), Color("5a6178"))
			b.add(Kit.cyl(0.33, 0.33, 0.25, 10), Kit.xf(Vector3(0, 3.85, -2.15), Vector3(-62, 0, 0)), Color("ff6b3d"), 0.9)
			for x2: float in [-1.4, -0.7, 0.7, 1.4]:
				b.add(Kit.box(Vector3(0.18, 1.1, 0.18)), Kit.xf(Vector3(x2, 1.1, -1.55)), Color("ffd36a"))
		"workshop":
			b.add(Kit.box(Vector3(3.4, 1.5, 3.2)), Kit.xf(Vector3(0, 1.1, 0.3)), Color("5f7fa8"))
			b.add(Kit.torus(0.7, 1.05, 10, 6), Kit.xf(Vector3(-0.9, 2.1, -1.35), Vector3(90, 0, 0)), Color("ffcf3a"))
			b.add(Kit.torus(0.4, 0.65, 8, 6), Kit.xf(Vector3(0.6, 1.4, -1.35), Vector3(90, 0, 0)), Color("f0c050"))
			b.add(Kit.box(Vector3(0.25, 3.2, 0.25)), Kit.xf(Vector3(1.4, 2.4, 1.2)), steel)
			b.add(Kit.box(Vector3(2.8, 0.22, 0.22)), Kit.xf(Vector3(0.1, 3.95, 1.2)), Color("ffcf3a"))
			b.add(Kit.box(Vector3(0.6, 0.6, 0.6)), Kit.xf(Vector3(-1.1, 3.2, 1.2)), Color("3fd0ff"), 0.7)
		"dock":
			b.add(Kit.box(Vector3(3.8, 0.6, 3.8)), Kit.xf(Vector3(0, 0.75, 0)), Color("4f6a9a"))
			for x3: float in [-1.3, 1.3]:
				b.add(Kit.box(Vector3(0.5, 2.4, 0.5)), Kit.xf(Vector3(x3, 1.9, -1.2)), steel)
				b.add(Kit.box(Vector3(0.9, 0.25, 2.6)), Kit.xf(Vector3(x3, 3.1, 0.0)), Color("ffcf3a"))
			b.add(Kit.sphere(0.35, 10, 6), Kit.xf(Vector3(0, 1.4, 1.2)), Color("5ff2ff"), 0.8)
		"airlock":
			b.add(Kit.cyl(1.6, 1.8, 1.0, 12), Kit.xf(Vector3(0, 0.95, 0)), steel)
			b.add(Kit.torus(1.0, 1.55, 16, 8), Kit.xf(Vector3(0, 2.4, 0), Vector3(90, 0, 0)), Color("c77dff"), 0.5)
			b.add(Kit.cyl(0.8, 0.8, 0.2, 12), Kit.xf(Vector3(0, 2.4, 0), Vector3(90, 0, 0)), Color("2b1d4a"))
		"cargo_bay":
			for zi2: float in [-0.9, 0.9]:
				for xi2: float in [-0.9, 0.9]:
					b.add(Kit.box(Vector3(1.5, 1.2, 1.5)), Kit.xf(Vector3(xi2, 1.05, zi2)), Color("d9a441") if xi2 < 0.0 else Color("6f8fc4"))
			b.add(Kit.box(Vector3(1.5, 1.2, 1.5)), Kit.xf(Vector3(-0.9, 2.25, -0.9)), Color("6f8fc4"))
		"trade_port":
			b.add(Kit.box(Vector3(3.6, 1.2, 3.0)), Kit.xf(Vector3(0, 1.0, 0.3)), Color("3f8f6f"))
			b.add(Kit.cyl(0.18, 0.18, 2.6, 8), Kit.xf(Vector3(1.3, 2.6, -1.1)), steel)
			b.add(Kit.box(Vector3(2.6, 0.2, 0.2)), Kit.xf(Vector3(0.1, 3.8, -1.1)), Color("ffcf3a"))
			b.add(Kit.sphere(0.6, 12, 6), Kit.xf(Vector3(-0.9, 2.0, 0.6)), Color("ffd36a"), 0.6)
		"containment":
			b.add(Kit.box(Vector3(3.4, 2.2, 3.4)), Kit.xf(Vector3(0, 1.5, 0)), Color("4a3a5a"))
			for x4: float in [-1.2, -0.4, 0.4, 1.2]:
				b.add(Kit.box(Vector3(0.14, 1.8, 0.14)), Kit.xf(Vector3(x4, 1.5, -1.75)), Color("ff5d73"), 0.6)
			b.add(Kit.box(Vector3(3.6, 0.3, 3.6)), Kit.xf(Vector3(0, 2.75, 0)), dark)
		"cloak":
			b.add(Kit.sphere(1.7, 16, 8), Kit.xf(Vector3(0, 1.3, 0), Vector3.ZERO, Vector3(1, 0.7, 1)), Color("4fa8ff"), 0.35)
			b.add(Kit.cyl(1.9, 1.9, 0.3, 16), Kit.xf(Vector3(0, 0.6, 0)), dark)
		"incubator":
			for xi3: float in [-1.0, 1.0]:
				b.add(Kit.cyl(0.6, 0.6, 2.0, 12), Kit.xf(Vector3(xi3, 1.5, 0)), Color("5ce08a"), 0.45)
				b.add(Kit.sphere(0.6, 12, 6), Kit.xf(Vector3(xi3, 2.5, 0)), Color("8cff9a"), 0.6)
			b.add(Kit.box(Vector3(3.4, 0.5, 1.6)), Kit.xf(Vector3(0, 0.7, 0)), steel)
		"foundry":
			b.add(Kit.cyl(1.3, 1.6, 2.2, 10), Kit.xf(Vector3(0, 1.5, 0)), Color("5a4a40"))
			b.add(Kit.cyl(0.9, 1.1, 0.4, 10), Kit.xf(Vector3(0, 2.8, 0)), Color("ff7a2f"), 1.0)
			b.add(Kit.cyl(0.25, 0.3, 2.0, 8), Kit.xf(Vector3(1.4, 2.6, -1.0)), dark)
		_:
			b.add(Kit.box(Vector3(3, 2, 3)), Kit.xf(Vector3(0, 1.4, 0)), steel)
	return b.commit()


static func construction_site() -> ArrayMesh:
	var b := Kit.Builder.new()
	b.add(Kit.box(Vector3(4.4, 0.3, 4.4)), Kit.xf(Vector3(0, 0.15, 0)), Color("5a6178"))
	for i: int in range(6):
		var col: Color = Color("ffcf3a") if i % 2 == 0 else Color("1d1f2a")
		b.add(Kit.box(Vector3(0.7, 0.35, 0.18)), Kit.xf(Vector3(-1.75 + i * 0.7, 0.5, -2.05)), col)
	for x: float in [-1.6, 1.6]:
		for z: float in [-1.6, 1.6]:
			b.add(Kit.box(Vector3(0.14, 2.6, 0.14)), Kit.xf(Vector3(x, 1.6, z)), Color("c0c8dc"))
	b.add(Kit.box(Vector3(3.4, 0.12, 0.12)), Kit.xf(Vector3(0, 2.0, -1.6)), Color("c0c8dc"))
	b.add(Kit.box(Vector3(3.4, 0.12, 0.12)), Kit.xf(Vector3(0, 2.0, 1.6)), Color("c0c8dc"))
	b.add(Kit.box(Vector3(0.25, 4.2, 0.25)), Kit.xf(Vector3(1.4, 2.4, 1.2)), Color("ffcf3a"))
	b.add(Kit.box(Vector3(3.2, 0.25, 0.25)), Kit.xf(Vector3(0.1, 4.4, 1.2)), Color("ffcf3a"))
	b.add(Kit.box(Vector3(0.9, 0.6, 0.9)), Kit.xf(Vector3(-0.6, 0.6, 0.4)), Color("8a6a4a"))
	b.add(Kit.box(Vector3(0.8, 0.8, 0.1)), Kit.xf(Vector3(0, 1.0, -2.2)), Color("e9edf6"))
	return b.commit()


static func scaffold_mesh() -> ArrayMesh:
	var b := Kit.Builder.new()
	for x: float in [-2.2, 2.2]:
		for z: float in [-2.2, 2.2]:
			b.add(Kit.box(Vector3(0.12, 3.8, 0.12)), Kit.xf(Vector3(x, 2.1, z)), Color("ffcf3a"))
	for y: float in [1.2, 2.6, 3.9]:
		b.add(Kit.box(Vector3(4.5, 0.1, 0.1)), Kit.xf(Vector3(0, y, -2.2)), Color("ffcf3a"))
		b.add(Kit.box(Vector3(4.5, 0.1, 0.1)), Kit.xf(Vector3(0, y, 2.2)), Color("ffcf3a"))
	return b.commit()


# ---------------------------------------------------------------- estado

func _on_player() -> void:
	if GameClient.me.is_empty():
		return
	for id: String in Catalog.room_order:
		var e: Dictionary = buildings.get(id, {})
		if e.is_empty():
			continue
		if bool(e.get("unbuilt", false)) != _is_unbuilt(id):
			# Se terminó de construir una sala de Fase 2: aparece su edificio.
			(e["root"] as Node).queue_free()
			buildings.erase(id)
			_make_building(id, _plot(int(_slot_of.get(id, 0))), false, {})
			e = buildings[id]
		if bool(e.get("unbuilt", false)):
			continue
		var lvl: int = GameClient.room_level(id)
		(e["level"] as Label3D).text = U.t("Nv %d") % lvl
		(e["model"] as Node3D).scale = Vector3.ONE * (0.92 + 0.035 * lvl)


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	var now: int = GameClient.server_now()
	var build: Dictionary = GameClient.queue("build")
	for id: String in Catalog.room_order:
		var e: Dictionary = buildings.get(id, {})
		if e.is_empty():
			continue
		var upgrading: bool = not build.is_empty() and str(build.get("room", "")) == id
		(e["scaffold"] as Node3D).visible = upgrading
		(e["bar"] as Node3D).visible = upgrading
		(e["timer"] as Node3D).visible = upgrading
		if upgrading:
			var rem: float = float(int(build["end"]) - now) / 1000.0
			(e["timer"] as Label3D).text = U.fmt_time(rem)
			(e["bar_mat"] as ShaderMaterial).set_shader_parameter("fill", clampf(1.0 - rem * 1000.0 / maxf(1.0, float(build.get("total", 1))), 0.0, 1.0))
			(e["model"] as Node3D).position.y = sin(_t * 12.0) * 0.02
		else:
			(e["model"] as Node3D).position.y = 0.0
		if e.has("bubble"):
			var pend: Dictionary = GameClient.pending_amount(id)
			var total: float = 0.0
			for k: String in pend:
				total += float(pend[k])
			var bubble: Node3D = e["bubble"]
			bubble.visible = total >= 10.0
			if bubble.visible:
				var first: String = pend.keys()[0]
				(e["bubble_label"] as Label3D).text = "+" + U.fmt_num(float(pend[first]))
				bubble.position.y = 6.9 + sin(_t * 3.0 + id.length()) * 0.25


func pop_bubble(room_id: String) -> void:
	var e: Dictionary = buildings.get(room_id, {})
	if e.has("bubble"):
		var b: Node3D = e["bubble"]
		var tw := create_tween()
		tw.tween_property(b, "scale", Vector3.ONE * 1.4, 0.08)
		tw.tween_property(b, "scale", Vector3.ZERO, 0.18)
		tw.tween_callback(func() -> void:
			b.visible = false
			b.scale = Vector3.ONE)


func building_screen_pos(room_id: String) -> Vector2:
	var e: Dictionary = buildings.get(room_id, {})
	if e.is_empty():
		return Vector2.ZERO
	return camera.unproject_position((e["root"] as Node3D).global_position + Vector3(0, 6.9, 0))


# ---------------------------------------------------------------- cámara / entrada

## Rectángulo de pantalla que ocupan los nombres y niveles de todas las salas.
func labels_screen_rect() -> Rect2:
	var out := Rect2()
	var first: bool = true
	for id: String in buildings:
		var e: Dictionary = buildings[id]
		var anchor: Vector3 = (e["root"] as Node3D).global_position + Vector3(0, 5.2, 0)
		if camera.is_position_behind(anchor):
			continue
		var p: Vector2 = camera.unproject_position(anchor)
		var chars: int = maxi((e["name"] as Label3D).text.length(), (e["level"] as Label3D).text.length())
		var half_w: float = 5.0 * float(chars) + 8.0
		var r := Rect2(p.x - half_w, p.y - 34.0, half_w * 2.0, 50.0)
		out = r if first else out.merge(r)
		first = false
	return out


## Encuadra la cubierta para que todas las etiquetas queden dentro de `area`
## (coordenadas de pantalla): entre la barra de colas y la barra inferior.
func fit_to(area: Rect2) -> void:
	if buildings.is_empty() or area.size.x < 80.0 or area.size.y < 80.0:
		return
	_max_dist = 78.0
	for i: int in range(10):
		_update_camera()
		var r: Rect2 = labels_screen_rect()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			return
		var k: float = maxf(r.size.x / area.size.x, r.size.y / area.size.y)
		_dist = clampf(_dist * lerpf(1.0, k, 0.85), 30.0, 140.0)
		_update_camera()
		r = labels_screen_rect()
		var g0: Vector3 = _ground_at(r.get_center())
		var g1: Vector3 = _ground_at(area.get_center())
		if g0 != Vector3.INF and g1 != Vector3.INF:
			_target += Vector2(g0.x - g1.x, g0.z - g1.z)
	_max_dist = maxf(78.0, _dist * 1.15)
	_update_camera()

func _update_camera() -> void:
	var pitch: float = deg_to_rad(50.0)
	var yaw: float = deg_to_rad(YAW_DEG)
	var tgt := Vector3(_target.x, 0, _target.y)
	camera.position = tgt + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * _dist
	camera.look_at(global_position + tgt, Vector3.UP)


func _ground_at(screen: Vector2) -> Vector3:
	var o: Vector3 = camera.project_ray_origin(screen)
	var d: Vector3 = camera.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t: float = (global_position.y - o.y) / d.y
	return Vector3.INF if t < 0.0 else o + d * t


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_touches[st.index] = st.position
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
				_tap(st.position)
			_touches.erase(st.index)
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		var prev: Vector2 = _touches.get(sd.index, sd.position - sd.relative)
		_touches[sd.index] = sd.position
		if _touches.size() == 1:
			_pan(prev, sd.position)
			_moved += sd.relative.length()
			if _moved > TAP_SLOP:
				_tap_valid = false
		elif _touches.size() >= 2:
			var pts2: Array = _touches.values()
			var d: float = (pts2[0] as Vector2).distance_to(pts2[1])
			if _pinch_dist > 0.0 and d > 0.0:
				_dist = clampf(_pinch_cam * _pinch_dist / d, 30.0, _max_dist)
				_update_camera()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_mouse_down = true
				_tap_valid = true
				_moved = 0.0
			else:
				_mouse_down = false
				if _tap_valid and _moved < TAP_SLOP:
					_tap(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = clampf(_dist / 1.12, 30.0, _max_dist)
			_update_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = clampf(_dist * 1.12, 30.0, _max_dist)
			_update_camera()
	elif event is InputEventMouseMotion and _mouse_down:
		var mm: InputEventMouseMotion = event
		_pan(mm.position - mm.relative, mm.position)
		_moved += mm.relative.length()
		if _moved > TAP_SLOP:
			_tap_valid = false


func _pan(a_s: Vector2, b_s: Vector2) -> void:
	var a: Vector3 = _ground_at(a_s)
	var b: Vector3 = _ground_at(b_s)
	if a == Vector3.INF or b == Vector3.INF:
		return
	_target -= Vector2(b.x - a.x, b.z - a.z)
	_target = _target.clamp(Vector2(-14, -20), Vector2(14, 27))
	_update_camera()


func _tap(screen: Vector2) -> void:
	# Las burbujas tienen prioridad sobre los edificios.
	for id: String in buildings:
		var e: Dictionary = buildings[id]
		if e.has("bubble") and (e["bubble"] as Node3D).visible:
			var sp: Vector2 = camera.unproject_position((e["bubble"] as Node3D).global_position)
			if sp.distance_to(screen) < maxf(34.0, 1500.0 / _dist):
				bubble_tapped.emit(id)
				return
	var best: String = ""
	var best_d: float = INF
	for id2: String in buildings:
		var e2: Dictionary = buildings[id2]
		var sp2: Vector2 = camera.unproject_position((e2["root"] as Node3D).global_position + Vector3(0, 1.8, 0))
		var d: float = sp2.distance_to(screen)
		if d < maxf(50.0, 3600.0 / _dist) and d < best_d:
			best_d = d
			best = id2
	if best.is_empty():
		return
	var tw := create_tween()
	var m: Node3D = buildings[best]["model"]
	var s0: Vector3 = m.scale
	tw.tween_property(m, "scale", s0 * Vector3(1.08, 0.9, 1.08), 0.07)
	tw.tween_property(m, "scale", s0, 0.2).set_trans(Tween.TRANS_ELASTIC)
	if bool(buildings[best]["locked"]):
		locked_tapped.emit(buildings[best]["info"])
	else:
		room_tapped.emit(best)
