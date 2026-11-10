extends Node3D
## Representación 3D de una entidad del mapa (nave, flota, asteroide, xenoforma).
## Solo presentación: la posición sale de la réplica, interpolada por timestamps.

const UI = preload("res://ui/ui.gd")
const U = preload("res://shared/util.gd")
const Kit = preload("res://ui/world3d/mesh_kit.gd")
const BLOB = preload("res://assets/shaders/blob_shadow.gdshader")
const RING = preload("res://assets/shaders/glow_ring.gdshader")
const BAR = preload("res://assets/shaders/billboard_bar.gdshader")
const ROUTE = preload("res://assets/shaders/route_dash.gdshader")

const HOVER: Dictionary = {"base": 1.25, "asteroid": 0.75, "xenoform": 0.15, "fleet": 1.8, "platform": 0.9}

var id: String = ""
var kind: String = ""
var data: Dictionary = {}
var relation: String = "enemy"
var model: Node3D
var _fighters: Array = []
var _name_label: Label3D
var _sub_label: Label3D
var _ring: MeshInstance3D
var _bar: MeshInstance3D
var _bar_mat: ShaderMaterial
var _route: MeshInstance3D
var _route_mat: ShaderMaterial
var _beam: MeshInstance3D
var _t: float = 0.0
var _seed: float = 0.0
var routes_root: Node3D
var labels_visible: bool = true


static func label3d(text: String, size: int, color: Color, outline: int = 10) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UI.font("game")
	l.font_size = size
	l.outline_size = outline
	l.modulate = color
	l.outline_modulate = Color(0.02, 0.03, 0.09, 1.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.00062
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	l.double_sided = true
	return l


func setup(e: Dictionary, routes: Node3D) -> void:
	id = str(e["id"])
	kind = str(e["kind"])
	routes_root = routes
	_seed = float(U.hash_seed(id) % 1000) / 1000.0
	_t = _seed * 10.0
	model = Node3D.new()
	add_child(model)
	var shadow := MeshInstance3D.new()
	shadow.mesh = Kit.quad(Vector2(1, 1))
	var sm := ShaderMaterial.new()
	sm.shader = BLOB
	shadow.material_override = sm
	shadow.position.y = -0.55
	shadow.scale = Vector3.ONE * {"base": 4.6, "asteroid": 2.6, "xenoform": 2.2, "fleet": 2.0, "platform": 5.0}.get(kind, 2.0) * (2.0 if bool(e.get("hive", false)) else 1.0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	match kind:
		"base":
			_ring = MeshInstance3D.new()
			_ring.mesh = Kit.quad(Vector2(1, 1))
			var rm := ShaderMaterial.new()
			rm.shader = RING
			rm.set_shader_parameter("dashes", 10.0)
			rm.set_shader_parameter("speed", 0.08)
			_ring.material_override = rm
			_ring.scale = Vector3.ONE * 6.2
			_ring.position.y = -0.5
			add_child(_ring)
			_name_label = label3d("", 34, UI.TEXT, 12)
			_name_label.position.y = 3.0
			_name_label.offset = Vector2(0, 26)
			add_child(_name_label)
			_sub_label = label3d("", 26, UI.TEXT_DIM, 10)
			_sub_label.position.y = 3.0
			add_child(_sub_label)
		"asteroid":
			var mi := MeshInstance3D.new()
			mi.material_override = Kit.material(0.03)
			model.add_child(mi)
			_name_label = label3d("", 28, UI.TEXT, 10)
			_name_label.position.y = 1.7
			_name_label.offset = Vector2(0, 22)
			add_child(_name_label)
			_sub_label = label3d("", 22, UI.TEXT_DIM, 9)
			_sub_label.position.y = 1.7
			add_child(_sub_label)
		"xenoform":
			var mx := MeshInstance3D.new()
			mx.material_override = Kit.material(0.03)
			model.add_child(mx)
			_name_label = label3d("", 28, Color("ffc2cf"), 10)
			_name_label.position.y = 2.7
			add_child(_name_label)
			_bar = MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(1.6, 0.2)
			_bar.mesh = q
			_bar_mat = ShaderMaterial.new()
			_bar_mat.shader = BAR
			_bar.material_override = _bar_mat
			_bar.position.y = 2.25
			_bar.visible = false
			add_child(_bar)
		"platform":
			_name_label = label3d("", 30, UI.GOLD, 12)
			_name_label.position.y = 6.0
			_name_label.offset = Vector2(0, 24)
			add_child(_name_label)
			_sub_label = label3d("", 24, UI.TEXT_DIM, 10)
			_sub_label.position.y = 6.0
			add_child(_sub_label)
		"fleet":
			for i: int in range(3):
				var f := MeshInstance3D.new()
				f.material_override = Kit.material(0.025)
				f.position = [Vector3(0, 0, -0.5), Vector3(-0.8, -0.1, 0.4), Vector3(0.8, -0.1, 0.4)][i]
				f.scale = Vector3.ONE * (0.75 if i == 0 else 0.6)
				model.add_child(f)
				_fighters.append(f)
			_sub_label = label3d("", 26, UI.TEXT, 9)
			_sub_label.position.y = 1.4
			add_child(_sub_label)
			_route = MeshInstance3D.new()
			_route.mesh = Kit.quad(Vector2(1, 1))
			_route_mat = ShaderMaterial.new()
			_route_mat.shader = ROUTE
			_route.material_override = _route_mat
			routes_root.add_child(_route)
			_beam = MeshInstance3D.new()
			_beam.mesh = Kit.cyl(0.05, 0.05, 1.0, 6)
			_beam.material_override = Kit.material(0.0)
			_beam.visible = false
			add_child(_beam)
	refresh(e)


func _exit_tree() -> void:
	if _route != null and is_instance_valid(_route):
		_route.queue_free()


func refresh(e: Dictionary) -> void:
	data = e
	match kind:
		"base":
			relation = GameClient.relation_of(str(e.get("owner", "")), str(e.get("tag", "")))
			if relation == "enemy" and str(e.get("tag", "")).is_empty():
				relation = "neutral"
			var col: Color = UI.REL_COLORS.get(relation, UI.TEXT)
			_set_model(Kit.ship(col), 1.25, 0.04)
			(_ring.material_override as ShaderMaterial).set_shader_parameter("color", col)
			var tag: String = str(e.get("tag", ""))
			_name_label.text = ("[%s] " % tag if not tag.is_empty() else "") + str(e.get("name", ""))
			_name_label.modulate = col.lightened(0.25)
			var extra: String = U.t("  ·  ESCUDO") if bool(e.get("shield", false)) or bool(e.get("protected", false)) else ""
			_sub_label.text = U.t("Poder %s  ·  Nv %d%s") % [U.fmt_num(int(e.get("power", 0))), int(e.get("level", 1)), extra]
		"asteroid":
			var el: String = str(e.get("element", "ore"))
			var lvl: int = int(e.get("level", 1))
			_set_model(Kit.asteroid(lvl, Catalog.res_color(el), int(e.get("variant", 0))), 1.0, -1.0)
			_name_label.text = U.t("N%d %s") % [lvl, Catalog.res_name(el)]
			_name_label.modulate = Catalog.res_color(el).lightened(0.3)
			var occ: String = str(e.get("occupant_owner", ""))
			if occ.is_empty():
				_sub_label.text = U.t("%s restante") % U.fmt_num(int(e.get("remaining", 0)))
				_sub_label.modulate = UI.TEXT_DIM
			else:
				_sub_label.text = U.t("Minando: ") + str(e.get("occupant_name", ""))
				_sub_label.modulate = UI.REL_COLORS["own" if occ == GameClient.player_id else "enemy"]
		"xenoform":
			var lvl2: int = int(e.get("level", 1))
			var sp: Dictionary = Catalog.species_by_id.get(str(e.get("species", "")), {})
			var hive: bool = bool(e.get("hive", false))
			var hscale: float = (1.5 + 0.35 * int(e.get("tier", 1))) if hive else 1.0
			_set_model(Kit.xenoform(str(e.get("species", "x01")), lvl2, Color(str(sp.get("color", "#66e15e")))), (0.95 + lvl2 * 0.17) * hscale, -1.0)
			_name_label.text = (U.t("COLMENA T%d") % int(e.get("tier", 1))) if hive else U.t("N%d %s") % [lvl2, sp.get("name", U.t("Xenoforma"))]
			_name_label.modulate = Color("ff8fa3") if hive else Color("ffc2cf")
			_name_label.position.y = (1.9 + lvl2 * 0.22) * (hscale * 0.85 if hive else 1.0)
			_bar.position.y = _name_label.position.y - 0.4
			var ratio: float = clampf(float(e.get("hp", 1)) / maxf(1.0, float(e.get("max_hp", 1))), 0.0, 1.0)
			_bar.visible = ratio < 0.999
			_bar_mat.set_shader_parameter("fill", ratio)
			_bar_mat.set_shader_parameter("fill_color", Color("ff4d6d").lerp(Color("3ddc97"), ratio))
		"platform":
			var holder: String = str(e.get("holder", ""))
			var citadel: bool = str(e.get("ptype", "")) == "citadel"
			relation = "neutral" if holder.is_empty() else ("ally" if holder == str(GameClient.me.get("tag", "")) else "enemy")
			var pc: Color = UI.REL_COLORS.get(relation, UI.TEXT)
			_set_model(Kit.platform(pc, citadel), 1.9 if citadel else 1.6, 0.035)
			var pd: Dictionary = {}
			for d: Dictionary in Catalog.endgame.get("platforms", {}).get("list", []):
				if str(d["id"]) == str(e.get("ptype", "")):
					pd = d
			_name_label.text = str(pd.get("name", U.t("Plataforma Orbital")))
			_name_label.modulate = Color("ffd166") if citadel else UI.TEXT
			var shield_s: String = U.t("  ·  ESCUDO") if int(e.get("shield_until", 0)) > GameClient.server_now() else ""
			_sub_label.text = (U.t("Libre") if holder.is_empty() else "[%s]" % holder) + shield_s
			_sub_label.modulate = pc.lightened(0.25)
		"fleet":
			relation = GameClient.relation_of(str(e.get("owner", "")), str(e.get("tag", "")))
			var col2: Color = UI.REL_COLORS.get(relation, UI.TEXT)
			for f: MeshInstance3D in _fighters:
				f.mesh = Kit.fighter(col2)
			_fighters[1].visible = str(e.get("mission", "")) != "scout"
			_fighters[2].visible = str(e.get("mission", "")) != "scout"
			_sub_label.text = U.t("Sonda") if str(e.get("mission", "")) == "scout" else U.fmt_num(int(e.get("troops_total", 0)))
			_sub_label.modulate = col2.lightened(0.2)
			_route_mat.set_shader_parameter("color", col2)
			_beam.material_override = Kit.material(0.0, col2)


func _set_model(mesh: Mesh, scl: float, outline: float) -> void:
	var mi: MeshInstance3D = model.get_child(0) if model.get_child_count() > 0 else null
	if mi == null:
		mi = MeshInstance3D.new()
		model.add_child(mi)
	if outline >= 0.0 and mi.material_override == null:
		mi.material_override = Kit.material(outline)
	mi.mesh = mesh
	model.scale = Vector3.ONE * scl


func set_labels_visible(v: bool) -> void:
	labels_visible = v
	for l: Node in [_name_label, _sub_label]:
		if l != null:
			(l as Node3D).visible = v or kind == "base"


func hit_flash() -> void:
	var tw := create_tween()
	tw.tween_property(model, "scale", model.scale * 1.25, 0.08)
	tw.tween_property(model, "scale", model.scale, 0.25).set_trans(Tween.TRANS_ELASTIC)


func world_pos_of(tile: Vector2, h: float) -> Vector3:
	return Vector3(tile.x, h, tile.y)


func _process(delta: float) -> void:
	_t += delta
	var tile: Vector2 = GameClient.entity_position(data)
	position = Vector3(tile.x, HOVER.get(kind, 1.0), tile.y)
	match kind:
		"base":
			model.position.y = sin(_t * 1.1) * 0.18
			model.rotation.z = sin(_t * 0.7) * 0.04
			if str(data.get("state", "")) == "TRAVELING":
				var tr: Dictionary = data.get("travel", {})
				var dir: Vector2 = U.v2(tr.get("target", [0, 0])) - U.v2(tr.get("origin", [0, 0]))
				if dir.length() > 0.1:
					model.rotation.y = atan2(-dir.x, -dir.y)
			_ring.rotation.y += delta * 0.2
		"asteroid":
			model.rotation.y += delta * (0.12 + _seed * 0.2)
			model.position.y = sin(_t * 0.8 + _seed * 6.0) * 0.12
		"xenoform":
			var squash: float = sin(_t * 3.2) * 0.06
			model.scale = Vector3.ONE * model.scale.x
			model.get_child(0).scale = Vector3(1.0 + squash, 1.0 - squash, 1.0 + squash)
			model.position.y = absf(sin(_t * 1.6)) * 0.12
			model.rotation.y = sin(_t * 0.5 + _seed * 4.0) * 0.6
		"platform":
			model.rotation.y += delta * 0.15
			model.position.y = sin(_t * 0.9) * 0.1
		"fleet":
			_update_fleet(delta)


func _update_fleet(delta: float) -> void:
	var state: String = str(data.get("state", ""))
	var target: Vector2 = U.v2(data.get("target", [0, 0]))
	var cur: Vector2 = GameClient.entity_position(data)
	if state == "working":
		model.rotation.y += delta * 1.2
		model.position = Vector3(cos(_t * 1.2), 0.2 * sin(_t * 2.0), sin(_t * 1.2)) * 1.6
		model.position.y += 0.0
		_route.visible = false
		_beam.visible = true
		var from: Vector3 = model.position
		var to := Vector3(0, -1.0, 0)
		var mid: Vector3 = (from + to) / 2.0
		_beam.position = mid
		var d: Vector3 = to - from
		_beam.scale = Vector3(1, d.length(), 1)
		_beam.basis = Basis(Quaternion(Vector3.UP, d.normalized())).scaled(Vector3(1, d.length(), 1))
		_beam.visible = fmod(_t, 0.6) < 0.45
	else:
		_beam.visible = false
		model.position = Vector3(0, sin(_t * 2.0) * 0.1, 0)
		var dir: Vector2 = target - cur
		if dir.length() > 0.05:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(-dir.x, -dir.y), clampf(delta * 6.0, 0.0, 1.0))
		var len: float = dir.length()
		_route.visible = len > 0.3
		if _route.visible:
			var mid2: Vector2 = (cur + target) / 2.0
			_route.position = Vector3(mid2.x, 0.06, mid2.y)
			_route.rotation = Vector3(0, atan2(-dir.y, dir.x), 0)
			_route.scale = Vector3(len, 1, 0.45)
			_route_mat.set_shader_parameter("length_tiles", len)
