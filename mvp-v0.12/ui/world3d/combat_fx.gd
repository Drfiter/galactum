extends RefCounted
## Efectos de combate reutilizables (mapa y visor de batallas): ráfagas láser,
## bola de fuego, onda expansiva, chispas, escombros que giran y caen y humo.
## Feedback de revisión: "mejorar un poquito la gráfica de combate".

const Kit = preload("res://ui/world3d/mesh_kit.gd")
const Sfx = preload("res://ui/audio.gd")

static var _mats: Dictionary = {}


static func _glow_mat(col: Color) -> StandardMaterial3D:
	var key: String = col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	_mats[key] = m
	return m


static func _smoke_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.16, 0.15, 0.2, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## Rayo láser de `from` a `to` que aparece tras `delay` segundos.
## Reproduce un efecto de sonido sincronizado con el efecto visual.
static func _sound(host: Node, sound: String, delay: float, volume_db: float = 0.0) -> void:
	if delay <= 0.0:
		Sfx.play(sound, volume_db)
	elif host.is_inside_tree():
		host.get_tree().create_timer(delay).timeout.connect(func() -> void: Sfx.play(sound, volume_db))


static func laser(host: Node3D, from: Vector3, to: Vector3, col: Color, delay: float = 0.0, life: float = 0.16, width: float = 0.09) -> void:
	_sound(host, "laser", delay, -6.0)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = width
	cm.bottom_radius = width
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _glow_mat(col.lightened(0.25))
	var dir: Vector3 = to - from
	var len: float = maxf(0.01, dir.length())
	mi.position = from + dir / 2.0
	mi.basis = Basis(Quaternion(Vector3.UP, dir / len)).scaled(Vector3(1, len, 1))
	mi.visible = false
	host.add_child(mi)
	var core := MeshInstance3D.new()
	var cm2 := CylinderMesh.new()
	cm2.top_radius = width * 0.4
	cm2.bottom_radius = width * 0.4
	cm2.height = 1.0
	cm2.radial_segments = 4
	core.mesh = cm2
	core.material_override = _glow_mat(Color(1, 1, 1, 0.9))
	mi.add_child(core)
	var tw := host.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(mi.show)
	tw.tween_interval(life)
	tw.tween_callback(mi.queue_free)
	# Chispazo de impacto
	var hit := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 8
	sm.rings = 4
	hit.mesh = sm
	hit.material_override = _glow_mat(col.lightened(0.4))
	hit.position = to
	hit.scale = Vector3.ZERO
	host.add_child(hit)
	var tw2 := host.create_tween()
	tw2.tween_interval(delay)
	tw2.tween_property(hit, "scale", Vector3.ONE * 1.4, 0.08)
	tw2.tween_property(hit, "scale", Vector3.ZERO, 0.18)
	tw2.tween_callback(hit.queue_free)


## Explosión completa. `size` escala todo (1 = nave pequeña).
static func burst(host: Node3D, at: Vector3, col: Color, size: float = 1.0, debris: int = 12, delay: float = 0.0) -> void:
	_sound(host, "explosion", delay, -3.0 if size >= 1.0 else -8.0)
	var root := Node3D.new()
	root.position = at
	host.add_child(root)
	var tw := host.create_tween().set_parallel(true)
	# Bola de fuego: núcleo blanco, capa naranja y halo del color del bando.
	var layers: Array = [[Color(1, 0.97, 0.85, 0.95), 1.0, 0.22], [Color(1.0, 0.55, 0.15, 0.85), 1.7, 0.32], [Color(col, 0.55), 2.6, 0.45]]
	for L: Array in layers:
		var s := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 1.0
		sp.height = 2.0
		sp.radial_segments = 14
		sp.rings = 8
		s.mesh = sp
		var m: StandardMaterial3D = _glow_mat(L[0]).duplicate()
		s.material_override = m
		s.scale = Vector3.ONE * 0.05
		root.add_child(s)
		var r: float = float(L[1]) * size
		tw.tween_property(s, "scale", Vector3.ONE * r, float(L[2])).set_delay(delay).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "albedo_color:a", 0.0, 0.45).set_delay(delay + float(L[2]))
	# Onda expansiva horizontal
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 6
	ring.mesh = tm
	var rm: StandardMaterial3D = _glow_mat(col.lightened(0.3)).duplicate()
	ring.material_override = rm
	ring.scale = Vector3(0.1, 0.05, 0.1)
	ring.position.y = -0.3
	root.add_child(ring)
	tw.tween_property(ring, "scale", Vector3(5.5, 0.3, 5.5) * size, 0.6).set_delay(delay + 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(rm, "albedo_color:a", 0.0, 0.6).set_delay(delay + 0.05)
	# Chispas
	var p := CPUParticles3D.new()
	p.amount = int(40 * size) + 10
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0 * size
	p.initial_velocity_max = 12.0 * size
	p.gravity = Vector3(0, -9, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var spark := BoxMesh.new()
	spark.size = Vector3(0.12, 0.12, 0.4)
	p.mesh = spark
	p.material_override = _glow_mat(Color(1.0, 0.8, 0.35))
	p.emitting = false
	root.add_child(p)
	tw.tween_callback(func() -> void: p.emitting = true).set_delay(delay)
	# Escombros low-poly que giran y caen
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i: int in range(debris):
		var d := MeshInstance3D.new()
		var b := Kit.Builder.new()
		var dims := Vector3(rng.randf_range(0.2, 0.6), rng.randf_range(0.1, 0.3), rng.randf_range(0.2, 0.7)) * size
		var dc: Color = [Color("c9d3e8"), Color("6f7fae"), Color("39456e"), col][rng.randi() % 4]
		b.add(Kit.box(dims), Transform3D.IDENTITY, dc, 0.3 if dc == col else 0.0)
		d.mesh = b.commit()
		d.material_override = Kit.material(0.0)
		d.visible = false
		root.add_child(d)
		var ang: float = rng.randf() * TAU
		var vel := Vector3(cos(ang) * rng.randf_range(3.0, 8.0), rng.randf_range(4.0, 10.0), sin(ang) * rng.randf_range(3.0, 8.0)) * size
		var spin := Vector3(rng.randf_range(-12, 12), rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		var life: float = rng.randf_range(1.0, 1.7)
		tw.tween_callback(d.show).set_delay(delay)
		tw.tween_method(func(t: float) -> void:
			d.position = vel * t + Vector3(0, -9.0 * t * t, 0)
			d.rotation = spin * t
			d.scale = Vector3.ONE * clampf(1.4 - t / life, 0.0, 1.0), 0.0, life, life).set_delay(delay)
	# Humo
	for i: int in range(5):
		var smk := MeshInstance3D.new()
		var ss := SphereMesh.new()
		ss.radius = 1.0
		ss.height = 2.0
		ss.radial_segments = 10
		ss.rings = 6
		smk.mesh = ss
		var smat := _smoke_mat()
		smk.material_override = smat
		smk.position = Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.2), rng.randf_range(-1, 1)) * size
		smk.scale = Vector3.ONE * 0.1
		root.add_child(smk)
		tw.tween_property(smk, "scale", Vector3.ONE * rng.randf_range(1.2, 2.0) * size, 1.6).set_delay(delay + 0.2 + i * 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(smk, "position:y", smk.position.y + 2.5 * size, 2.0).set_delay(delay + 0.2)
		tw.tween_property(smat, "albedo_color:a", 0.0, 1.4).set_delay(delay + 0.8)
	tw.chain().tween_interval(0.4)
	tw.chain().tween_callback(root.queue_free)
