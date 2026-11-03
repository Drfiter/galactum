extends Node3D
func _ready() -> void:
	var cam := Camera3D.new(); cam.position = Vector3(0, 6, 6); add_child(cam); cam.look_at(Vector3.ZERO)
	var bg := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(20, 20); bg.mesh = pm
	var bm := StandardMaterial3D.new(); bm.albedo_color = Color(0.3, 0.3, 0.8); bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; bg.material_override = bm; add_child(bg)
	for i: int in range(3):
		var q := MeshInstance3D.new(); var qm := QuadMesh.new(); qm.size = Vector2(2, 2); qm.orientation = PlaneMesh.FACE_Y; q.mesh = qm
		var m := ShaderMaterial.new(); m.shader = load(["res://assets/shaders/blob_shadow.gdshader", "res://assets/shaders/glow_ring.gdshader", "res://assets/shaders/route_dash.gdshader"][i])
		q.material_override = m; q.position = Vector3(-3 + i * 3, 0.05, 0); add_child(q)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/home/claude/shots3d/probe.png")
	get_tree().quit()
