extends "res://ui/panels/window.gd"
## Visor de batalla 3D: reproduce un informe de combate (PvP o caza) ronda a
## ronda con cazas, láseres, escudo perimetral y explosiones. Usa los datos
## deterministas del informe (vivos por ronda), así que la película coincide
## exactamente con el resultado del servidor.

const Kit = preload("res://ui/world3d/mesh_kit.gd")
const FX = preload("res://ui/world3d/combat_fx.gd")
const FLOOR = preload("res://assets/shaders/space_floor.gdshader")

var report: Dictionary = {}
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _att: Array = []        # [{node, alive}]
var _def: Array = []
var _target_node: Node3D    # nave base o xenoforma
var _dome: MeshInstance3D
var _dome_mat: StandardMaterial3D
var _round_label: Label
var _att_label: Label
var _def_label: Label
var _banner: PanelContainer
var _t: float = 0.0
var _hp_bar: ProgressBar
var _playing: bool = false


func _init() -> void:
	desired_size = Vector2(1200, 660)


func window_title() -> String:
	return U.t("Repetición de batalla")


func window_icon() -> String:
	return "ui_attack"


func build() -> void:
	report = args.get("report", {})
	var frame := UI.panel("Card")
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(frame)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.custom_minimum_size = Vector2(1100, 470)
	frame.add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	svc.add_child(_vp)
	_build_overlay(svc)
	_build_scene()
	var bar := UI.hbox(10, BoxContainer.ALIGNMENT_CENTER)
	body.add_child(bar)
	var again := UI.button(U.t("Repetir"), "PrimaryButton", "ui_recall", Vector2(180, 50))
	again.pressed.connect(func() -> void: rebuild())
	bar.add_child(again)
	var close := UI.button(U.t("Cerrar"), "GhostButton", "ui_close", Vector2(160, 50))
	close.pressed.connect(close_window)
	bar.add_child(close)
	_play.call_deferred()


func _build_overlay(svc: Control) -> void:
	var ov := Control.new()
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full_rect(ov)
	svc.add_child(ov)
	var top := UI.hbox(20)
	top.position = Vector2(16, 12)
	top.size = Vector2(1080, 40)
	ov.add_child(top)
	var is_hunt: bool = str(report.get("type", "")) == "hunt"
	var a: Dictionary = report.get("attacker", {})
	var d: Dictionary = report.get("defender", {})
	_att_label = UI.outline(UI.label("", 18, Color("8fe9ff"), "game"), 6)
	_att_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_att_label)
	_round_label = UI.outline(UI.label("", 22, UI.GOLD, "game"), 7)
	top.add_child(_round_label)
	_def_label = UI.outline(UI.label("", 18, Color("ffb3a0"), "game"), 6)
	_def_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_def_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_def_label)
	if is_hunt:
		var x: Dictionary = report.get("xeno", {})
		_hp_bar = UI.progress(float(x.get("max_hp", 1)), float(x.get("max_hp", 1)), UI.RED, 14)
		_hp_bar.position = Vector2(700, 56)
		_hp_bar.size = Vector2(380, 14)
		ov.add_child(_hp_bar)
	_att_label.set_meta("name", str(a.get("name", "")))
	_def_label.set_meta("name", str(d.get("name", report.get("xeno", {}).get("name", ""))))
	_banner = PanelContainer.new()
	_banner.visible = false
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.5
	_banner.anchor_bottom = 0.5
	_banner.offset_left = -240
	_banner.offset_right = 240
	_banner.offset_top = -50
	_banner.offset_bottom = 50
	ov.add_child(_banner)


func _team(mine: bool) -> Color:
	return Color("3fd0ff") if mine else Color("ff7a4d")


func _count_for(total: int) -> int:
	return clampi(int(ceil(sqrt(float(maxi(total, 1))) / 1.4)), 3, 14)


func _build_scene() -> void:
	_world = Node3D.new()
	_vp.add_child(_world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.01, 0.015, 0.05)
	env.environment = e
	_world.add_child(env)
	# Campo de estrellas lejano
	var stars := MeshInstance3D.new()
	var am := ArrayMesh.new()
	var pts := PackedVector3Array()
	var cols := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in range(900):
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 0.2)).normalized()
		pts.append(dir * rng.randf_range(90.0, 140.0))
		var b: float = rng.randf_range(0.4, 1.0)
		cols.append(Color(b, b, minf(1.0, b * 1.15)))
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	arr[Mesh.ARRAY_COLOR] = cols
	am.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
	stars.mesh = am
	var stm := StandardMaterial3D.new()
	stm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stm.vertex_color_use_as_albedo = true
	stm.use_point_size = true
	stm.point_size = 2.0
	stars.material_override = stm
	_world.add_child(stars)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	floor.mesh = pm
	var fm := ShaderMaterial.new()
	fm.shader = FLOOR
	fm.set_shader_parameter("map_tiles", 160.0)
	fm.set_shader_parameter("grid_alpha", 0.35)
	floor.material_override = fm
	floor.position = Vector3(0, -3.0, 0)
	_world.add_child(floor)
	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.position = Vector3(0, 14, 26)
	_world.add_child(_cam)
	_cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	_cam.make_current()
	var my_id: String = GameClient.player_id
	var a: Dictionary = report.get("attacker", {})
	var d: Dictionary = report.get("defender", {})
	var a_mine: bool = str(a.get("id", my_id)) == my_id or str(report.get("type", "")) in ["attack", "tile_hit", "hunt"]
	var d_mine: bool = str(d.get("id", "")) == my_id
	var a_col: Color = _team(a_mine)
	var d_col: Color = _team(d_mine and not a_mine)
	# Atacantes: formación en cuña a la izquierda.
	var na: int = _count_for(U.sum_values(a.get("initial", {})))
	for i: int in range(na):
		var n := MeshInstance3D.new()
		n.mesh = Kit.fighter(a_col)
		n.material_override = Kit.material(0.03)
		var row: int = i / 4
		var col: int = i % 4
		n.position = Vector3(-30.0 - row * 2.5, 1.5 + (col % 2) * 1.2, (col - 1.5) * 3.0 + row * 0.6)
		n.rotation_degrees = Vector3(0, -90, 0)
		n.scale = Vector3.ONE * 1.6
		_world.add_child(n)
		_att.append({"node": n, "alive": true, "home": Vector3(-11.0 - row * 2.6, n.position.y, n.position.z)})
	var t: String = str(report.get("type", ""))
	if t == "hunt":
		var x: Dictionary = report.get("xeno", {})
		var sp: Dictionary = Catalog.species_by_id.get(str(x.get("species", "")), {})
		_target_node = MeshInstance3D.new()
		(_target_node as MeshInstance3D).mesh = Kit.xenoform(str(x.get("species", "x01")), int(x.get("level", 1)), Color(str(sp.get("color", "#66e15e"))))
		(_target_node as MeshInstance3D).material_override = Kit.material(0.04)
		_target_node.position = Vector3(9, -0.5, 0)
		_target_node.scale = Vector3.ONE * (3.0 + int(x.get("level", 1)) * 0.4)
		_target_node.rotation_degrees = Vector3(0, -110, 0)
		_world.add_child(_target_node)
	else:
		if t in ["attack", "defense"]:
			_target_node = MeshInstance3D.new()
			(_target_node as MeshInstance3D).mesh = Kit.ship(d_col)
			(_target_node as MeshInstance3D).material_override = Kit.material(0.04)
			_target_node.position = Vector3(14, 0, 0)
			_target_node.scale = Vector3.ONE * 2.6
			_target_node.rotation_degrees = Vector3(0, 90, 0)
			_world.add_child(_target_node)
			if int(d.get("perimeter_initial", 0)) > 0:
				_dome = MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 7.5
				sm.height = 15.0
				sm.radial_segments = 24
				sm.rings = 12
				_dome.mesh = sm
				_dome_mat = StandardMaterial3D.new()
				_dome_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				_dome_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_dome_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				_dome_mat.albedo_color = Color(0.55, 0.45, 1.0, 0.22)
				_dome_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				_dome.material_override = _dome_mat
				_dome.position = Vector3(14, 0, 0)
				_world.add_child(_dome)
		var nd: int = _count_for(U.sum_values(d.get("initial", {})))
		for i: int in range(nd):
			var n2 := MeshInstance3D.new()
			n2.mesh = Kit.fighter(d_col)
			n2.material_override = Kit.material(0.03)
			var row2: int = i / 4
			var col2: int = i % 4
			n2.position = Vector3(7.0 + row2 * 2.6, 1.5 + (col2 % 2) * 1.2, (col2 - 1.5) * 3.0 - row2 * 0.6)
			n2.rotation_degrees = Vector3(0, 90, 0)
			n2.scale = Vector3.ONE * 1.6
			_world.add_child(n2)
			_def.append({"node": n2, "alive": true, "home": n2.position})


func _process(delta: float) -> void:
	super._process(delta)
	_t += delta
	for side: Array in [_att, _def]:
		for i: int in range(side.size()):
			var s: Dictionary = side[i]
			if bool(s["alive"]):
				(s["node"] as Node3D).position.y = float((s["home"] as Vector3).y) + sin(_t * 2.2 + i) * 0.25
	if _target_node != null and str(report.get("type", "")) == "hunt":
		_target_node.rotation_degrees.y = -110 + sin(_t * 1.3) * 8.0
	if _cam != null:
		_cam.position = Vector3(sin(_t * 0.12) * 4.0, 14, 26)
		_cam.look_at(Vector3(0, 0, 0), Vector3.UP)


func _alive(side: Array) -> Array:
	return side.filter(func(s: Dictionary) -> bool: return bool(s["alive"]))


func _set_labels(r_idx: int, total: int, a_alive: int, d_alive: int) -> void:
	_round_label.text = U.t("RONDA %d/%d") % [r_idx, total] if r_idx > 0 else U.t("¡COMBATE!")
	_att_label.text = "%s  ·  %s" % [str(_att_label.get_meta("name")), U.fmt_int(a_alive)]
	if str(report.get("type", "")) == "hunt":
		_def_label.text = str(_def_label.get_meta("name"))
	else:
		_def_label.text = "%s  ·  %s" % [U.fmt_int(d_alive), str(_def_label.get_meta("name"))]


func _play() -> void:
	if _playing:
		return
	_playing = true
	var a: Dictionary = report.get("attacker", {})
	var d: Dictionary = report.get("defender", {})
	var rounds: Array = report.get("rounds", [])
	var is_hunt: bool = str(report.get("type", "")) == "hunt"
	var a0: int = U.sum_values(a.get("initial", {}))
	var d0: int = U.sum_values(d.get("initial", {}))
	_set_labels(0, rounds.size(), a0, d0)
	# Entrada de los atacantes en formación.
	var tw := create_tween().set_parallel(true)
	for s: Dictionary in _att:
		tw.tween_property(s["node"], "position:x", float((s["home"] as Vector3).x), 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	if not is_inside_tree():
		return
	var na: int = _att.size()
	var nd: int = _def.size()
	var cum_w: int = 0
	for ri: int in range(rounds.size()):
		var rd: Dictionary = rounds[ri]
		var a_alive_n: int = int(rd.get("attacker_alive", a0))
		var d_alive_n: int = int(rd.get("defender_alive", d0))
		if is_hunt:
			cum_w += int(rd.get("wounded", 0))
			a_alive_n = maxi(0, a0 - cum_w)
		_set_labels(ri + 1, rounds.size(), a_alive_n, d_alive_n if not is_hunt else 0)
		# Ráfaga del atacante
		var shooters: Array = _alive(_att)
		var targets: Array = _alive(_def)
		for k: int in range(mini(10, shooters.size() * 2)):
			var from: Vector3 = (shooters[k % shooters.size()]["node"] as Node3D).position + Vector3(1.2, 0, 0)
			var to: Vector3
			if not targets.is_empty() and (k % 3 != 0 or _target_node == null):
				to = (targets[k % targets.size()]["node"] as Node3D).position
			elif _target_node != null:
				to = _target_node.position + Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 2.5), randf_range(-1.5, 1.5))
			else:
				continue
			FX.laser(_world, from, to, Color("8fe9ff"), k * 0.06, 0.12, 0.08)
		# Respuesta del defensor (o de la xenoforma)
		var back: Array = _alive(_def)
		if is_hunt and _target_node != null:
			for k2: int in range(4):
				if shooters.is_empty():
					break
				FX.laser(_world, _target_node.position + Vector3(-2, 2, 0), (shooters[k2 % shooters.size()]["node"] as Node3D).position, Color("7cf2b3"), 0.35 + k2 * 0.08, 0.16, 0.14)
		else:
			for k3: int in range(mini(8, back.size() * 2)):
				if shooters.is_empty():
					break
				var src: Vector3 = (back[k3 % back.size()]["node"] as Node3D).position + Vector3(-1.2, 0, 0) if not back.is_empty() else _target_node.position
				FX.laser(_world, src, (shooters[k3 % shooters.size()]["node"] as Node3D).position, Color("ffb37a"), 0.3 + k3 * 0.06, 0.12, 0.08)
		await get_tree().create_timer(0.85).timeout
		if not is_inside_tree():
			return
		# Bajas proporcionales a lo que dicta el informe.
		var want_a: int = int(round(na * float(a_alive_n) / maxf(1.0, a0)))
		if a_alive_n > 0:
			want_a = maxi(1, want_a)
		_destroy_to(_att, want_a, Color("8fe9ff"))
		if not is_hunt:
			var want_d: int = int(round(nd * float(d_alive_n) / maxf(1.0, d0)))
			if d_alive_n > 0:
				want_d = maxi(1, want_d)
			_destroy_to(_def, want_d, Color("ffb37a"))
		if _dome != null:
			var pi0: float = float(d.get("perimeter_initial", 1))
			var pl: float = float(rd.get("perimeter_left", 0))
			_dome_mat.albedo_color.a = 0.22 * pl / maxf(1.0, pi0)
			if pl <= 0.0 and _dome.visible:
				FX.burst(_world, _dome.position + Vector3(0, 3, 0), Color("b388ff"), 1.6, 6)
				_dome.visible = false
		if is_hunt and _hp_bar != null:
			create_tween().tween_property(_hp_bar, "value", float(rd.get("xeno_hp", 0)), 0.3)
		await get_tree().create_timer(0.75).timeout
		if not is_inside_tree():
			return
	# Desenlace
	var won: bool = str(report.get("outcome", "")) == "victory"
	if is_hunt:
		won = bool(report.get("xeno", {}).get("killed", false))
		if won and _target_node != null:
			FX.burst(_world, _target_node.position + Vector3(0, 2, 0), Color("7cf2b3"), 2.6, 22)
			var tw2 := create_tween()
			tw2.tween_property(_target_node, "scale", Vector3.ONE * 0.01, 0.5).set_delay(0.25)
	elif str(report.get("type", "")) in ["attack", "defense"] and _target_node != null:
		var att_won: bool = U.sum_values(a.get("survivors", {})) > 0 and U.sum_values(d.get("survivors", {})) == 0
		if att_won:
			for j: int in range(3):
				FX.burst(_world, _target_node.position + Vector3(randf_range(-3, 3), randf_range(0, 3), randf_range(-2, 2)), Color("ff8a3d"), 1.4, 10, j * 0.25)
	await get_tree().create_timer(0.9).timeout
	if not is_inside_tree():
		return
	var mine_won: bool = won
	var col: Color = UI.GREEN if mine_won else UI.RED
	_banner.add_theme_stylebox_override("panel", UI.sb(Color(col, 0.22), col, 14, 3, 12))
	var txt: String = U.t("VICTORIA") if mine_won else U.t("DERROTA")
	if is_hunt:
		txt = U.t("XENOFORMA ABATIDA") if won else U.t("CAZA PARCIAL")
	var l := UI.title(txt, 40, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_child(l)
	_banner.visible = true
	_banner.scale = Vector2(0.6, 0.6)
	_banner.pivot_offset = Vector2(240, 50)
	create_tween().tween_property(_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _destroy_to(side: Array, want_alive: int, col: Color) -> void:
	var alive: Array = _alive(side)
	var kill: int = alive.size() - want_alive
	alive.shuffle()
	for i: int in range(maxi(0, kill)):
		var s: Dictionary = alive[i]
		s["alive"] = false
		var n: Node3D = s["node"]
		FX.burst(_world, n.position, col, 0.8, 8, i * 0.12)
		var tw := create_tween()
		tw.tween_interval(i * 0.12 + 0.05)
		tw.tween_callback(n.hide)
