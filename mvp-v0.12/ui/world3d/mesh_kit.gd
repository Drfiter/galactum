extends RefCounted

const U = preload("res://shared/util.gd")
## Generador de modelos 3D low-poly estilo "juego móvil" (Clash of Clans / Mobile
## Legends): todo se construye con primitivas en UNA sola malla por modelo, con
## color por vértice (COLOR.a = máscara de emisión). Pocas llamadas de dibujo =
## buen rendimiento en Android. Las mallas se cachean por clave.

const TOON = preload("res://assets/shaders/toon.gdshader")
const OUTLINE = preload("res://assets/shaders/outline.gdshader")

static var _cache: Dictionary = {}
static var _materials: Dictionary = {}


class Builder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func add(mesh: PrimitiveMesh, xf: Transform3D, color: Color, emissive: float = 0.0) -> void:
		var arr: Array = mesh.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var base: int = verts.size()
		var nb: Basis = xf.basis.inverse().transposed()
		var c := Color(color.r, color.g, color.b, emissive)
		for i: int in range(v.size()):
			verts.append(xf * v[i])
			norms.append((nb * n[i]).normalized())
			cols.append(c)
		if ind.is_empty():
			for i: int in range(v.size()):
				idx.append(base + i)
		else:
			for i: int in ind:
				idx.append(base + i)

	## Triángulos con normal plana (aspecto facetado).
	func add_flat_tris(points: PackedVector3Array, color: Color, emissive: float = 0.0) -> void:
		var c := Color(color.r, color.g, color.b, emissive)
		for i: int in range(0, points.size(), 3):
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			var d: Vector3 = points[i + 2]
			var nrm: Vector3 = (b - a).cross(d - a).normalized()
			for p: Vector3 in [a, b, d]:
				idx.append(verts.size())
				verts.append(p)
				norms.append(nrm)
				cols.append(c)

	func commit() -> ArrayMesh:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


# ---------------------------------------------------------------- primitivas

static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func sphere(r: float, radial: int = 14, rings: int = 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = radial
	s.rings = rings
	return s


static func cyl(top: float, bottom: float, h: float, radial: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = radial
	c.rings = 1
	return c


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 3
	return c


static func torus(inner: float, outer: float, rings: int = 28, seg: int = 8) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = rings
	t.ring_segments = seg
	return t


static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(b.scaled(scl), pos)


static func material(outline_width: float = 0.035, tint: Color = Color.WHITE) -> ShaderMaterial:
	var key: String = "%s|%s" % [outline_width, tint.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("tint", tint)
	if outline_width > 0.0:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("width", outline_width)
		m.next_pass = o
	_materials[key] = m
	return m


static func hash01(text: String, salt: int = 0) -> float:
	return float((text + str(salt)).hash() & 0xffff) / 65535.0


# ---------------------------------------------------------------- modelos

## Astronave (base del jugador): fuselaje blanco, alas y franjas del color de relación.
static func ship(team: Color) -> ArrayMesh:
	var key: String = "ship|" + team.to_html()
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var hull := Color("e9eff8")
	var dark := Color("3a4466")
	b.add(sphere(0.5, 16, 10), xf(Vector3(0, 0, 0), Vector3.ZERO, Vector3(1.1, 0.8, 2.6)), hull)
	b.add(cyl(0.0, 0.42, 0.9, 12), xf(Vector3(0, 0, -1.5), Vector3(-90, 0, 0)), team)
	b.add(sphere(0.5, 14, 8), xf(Vector3(0, 0.32, -0.45), Vector3.ZERO, Vector3(0.62, 0.45, 0.95)), Color("5ff2ff"), 0.55)
	b.add(box(Vector3(3.6, 0.14, 1.05)), xf(Vector3(0, -0.08, 0.35), Vector3(0, 0, 0)), team)
	b.add(box(Vector3(3.2, 0.1, 0.35)), xf(Vector3(0, -0.02, 0.05)), hull)
	for s: float in [-1.0, 1.0]:
		b.add(box(Vector3(0.24, 0.6, 0.85)), xf(Vector3(1.8 * s, 0.14, 0.45)), hull)
		b.add(cyl(0.05, 0.05, 0.5, 6), xf(Vector3(1.8 * s, 0.5, 0.3)), dark)
		b.add(sphere(0.09, 8, 4), xf(Vector3(1.8 * s, 0.78, 0.3)), Color("ff5d73"), 1.0)
		b.add(cyl(0.26, 0.3, 0.8, 12), xf(Vector3(0.55 * s, -0.08, 1.15), Vector3(90, 0, 0)), Color("c9d2e4"))
		b.add(cyl(0.2, 0.2, 0.12, 12), xf(Vector3(0.55 * s, -0.08, 1.58), Vector3(90, 0, 0)), Color("ffb040"), 1.0)
	b.add(box(Vector3(0.12, 0.85, 0.7)), xf(Vector3(0, 0.55, 0.95), Vector3(-15, 0, 0)), team)
	b.add(box(Vector3(0.22, 0.05, 2.0)), xf(Vector3(0, 0.41, 0.1)), team)
	b.add(box(Vector3(0.7, 0.18, 0.5)), xf(Vector3(0, -0.36, 0.2)), dark)
	_cache[key] = b.commit()
	return _cache[key]


## Caza pequeño (las flotas se dibujan como formación de 3).
static func fighter(team: Color) -> ArrayMesh:
	var key: String = "fighter|" + team.to_html()
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	b.add(cyl(0.0, 0.26, 1.2, 8), xf(Vector3(0, 0, -0.1), Vector3(-90, 0, 0)), Color("eef3fb"))
	b.add(box(Vector3(1.25, 0.07, 0.42)), xf(Vector3(0, 0, 0.25)), team)
	b.add(box(Vector3(0.07, 0.35, 0.35)), xf(Vector3(0, 0.15, 0.4)), team)
	b.add(sphere(0.12, 8, 4), xf(Vector3(0, 0.1, -0.15), Vector3.ZERO, Vector3(1, 0.8, 1.6)), Color("5ff2ff"), 0.6)
	b.add(cyl(0.14, 0.14, 0.1, 8), xf(Vector3(0, 0, 0.52), Vector3(90, 0, 0)), Color("ffb040"), 1.0)
	_cache[key] = b.commit()
	return _cache[key]


## Asteroide facetado con cristales brillantes del elemento que contiene.
static func asteroid(level: int, crystal: Color, variant: int) -> ArrayMesh:
	var key: String = "ast|%d|%s|%d" % [level, crystal.to_html(), variant]
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = variant * 7919 + level * 131
	var radius: float = 0.55 + level * 0.11
	var rock_cols: Array = [Color("8d7f74"), Color("7c8390"), Color("94806a"), Color("6f7685")]
	var rock: Color = rock_cols[variant % 4]
	# Icosfera irregular (desplazamiento determinista por vértice).
	var sm := sphere(1.0, 9, 6)
	var arr: Array = sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var disp: Dictionary = {}
	var pts := PackedVector3Array()
	for i: int in ind:
		var p: Vector3 = v[i]
		var k: Vector3i = Vector3i((p * 100.0).round())
		if not disp.has(k):
			disp[k] = rng.randf_range(0.78, 1.18)
		pts.append(p * Vector3(1.0, 0.78, 0.92) * radius * float(disp[k]))
	b.add_flat_tris(pts, rock)
	for i: int in range(3 + level):
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1.0), rng.randf_range(-1, 1)).normalized()
		var pos: Vector3 = dir * radius * 0.78
		var basis := Basis(Quaternion(Vector3.UP, dir))
		var h: float = rng.randf_range(0.35, 0.65) * (0.8 + level * 0.12)
		var t := Transform3D(basis, pos + dir * h * 0.4)
		b.add(cyl(0.02, rng.randf_range(0.08, 0.14), h, 6), t, crystal, 0.75)
	_cache[key] = b.commit()
	return _cache[key]


## Criatura xenoforma "cartoon": cuerpo blando, ojos grandes, púas y patas.
static func xenoform(species: String, level: int, body: Color) -> ArrayMesh:
	var key: String = "xeno|%s|%d" % [species, level]
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var belly: Color = body.lightened(0.35)
	var dark: Color = body.darkened(0.35)
	var spike: Color = body.darkened(0.45)
	var eyes: int = 1 + int(hash01(species, 1) * 3.0)
	var spikes: int = 3 + int(hash01(species, 2) * 4.0) + (2 if level >= 4 else 0)
	var tall: float = 0.85 + hash01(species, 3) * 0.35
	b.add(sphere(0.5, 16, 10), xf(Vector3(0, 0.62, 0), Vector3.ZERO, Vector3(1.0, tall, 0.95)), body)
	b.add(sphere(0.5, 12, 8), xf(Vector3(0, 0.52, -0.2), Vector3.ZERO, Vector3(0.72, tall * 0.62, 0.62)), belly)
	for i: int in range(eyes):
		var x: float = (i - (eyes - 1) / 2.0) * 0.26
		var y: float = 0.72 + tall * 0.12 + (0.06 if eyes == 3 and i == 1 else 0.0)
		b.add(sphere(0.135, 10, 6), xf(Vector3(x, y, -0.4)), Color.WHITE)
		b.add(sphere(0.07, 8, 4), xf(Vector3(x, y, -0.515)), Color("10121e"))
		b.add(sphere(0.025, 6, 3), xf(Vector3(x + 0.025, y + 0.03, -0.575)), Color.WHITE, 1.0)
	b.add(box(Vector3(0.42, 0.07, 0.06)), xf(Vector3(0, 0.42, -0.45)), Color("2a0d1a"))
	for i: int in range(4):
		b.add(cyl(0.0, 0.035, 0.09, 4), xf(Vector3(-0.15 + i * 0.1, 0.36, -0.46), Vector3(180, 0, 0)), Color.WHITE)
	for i: int in range(spikes):
		var ang: float = PI * (0.15 + 0.7 * i / maxf(1.0, spikes - 1.0))
		var dir := Vector3(cos(ang) * 0.9, sin(ang), 0.35).normalized()
		var base_pos := Vector3(dir.x * 0.45, 0.62 + dir.y * 0.45 * tall, 0.15)
		b.add(cyl(0.0, 0.09, 0.32 + level * 0.03, 6), Transform3D(Basis(Quaternion(Vector3.UP, dir)), base_pos + dir * 0.12), spike)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.add(capsule(0.085, 0.42), xf(Vector3(0.27 * sx, 0.14, 0.2 * sz), Vector3(10 * sz, 0, -12 * sx)), dark)
	if level >= 5:
		b.add(torus(0.42, 0.5, 24, 6), xf(Vector3(0, 1.15 + tall * 0.25, 0), Vector3(0, 0, 0), Vector3(1, 0.4, 1)), Color("ffd54a"), 0.9)
	_cache[key] = b.commit()
	return _cache[key]


## Planeta con franjas de latitud y anillo.
static func planet(col: Color) -> ArrayMesh:
	var key: String = "planet|" + col.to_html()
	if _cache.has(key):
		return _cache[key]
	var b := Builder.new()
	var sm := sphere(1.0, 28, 16)
	var arr: Array = sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i: int in range(v.size()):
		var band: float = sin(v[i].y * 9.0) * 0.5 + 0.5
		b.verts.append(v[i])
		b.norms.append(n[i])
		var c: Color = col.darkened(0.15).lerp(col.lightened(0.25), band)
		b.cols.append(Color(c.r, c.g, c.b, 0.0))
	for i: int in ind:
		b.idx.append(i)
	b.add(torus(1.45, 1.75, 40, 4), xf(Vector3.ZERO, Vector3(0, 0, 0), Vector3(1, 0.05, 1)), col.lightened(0.45), 0.25)
	_cache[key] = b.commit()
	return _cache[key]


static func quad(size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	q.orientation = PlaneMesh.FACE_Y
	return q
