extends Node
## Capturas de la demo «Jugar con cuenta» (registro, JWT, token alterado, entrar).
## Uso: GALACTUM_SHOTS_DIR=/ruta/ godot --path . --resolution 1600x720 res://tests/evidence_cuentas.tscn

var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR") if not OS.get_environment("GALACTUM_SHOTS_DIR").is_empty() else "user://"


func _ready() -> void:
	preload("res://shared/i18n.gd").set_locale("es")
	Catalog.reload()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://galactum_cuentas.json"))
	var title: Node = load("res://ui/title.tscn").instantiate()
	get_tree().root.add_child.call_deferred(title)
	await _wait(1.5)
	# El guion no es la escena actual: así sobrevive al cambio a la partida.
	get_tree().current_scene = title
	(title.find_child("PlayWithAccount", true, false) as Button).pressed.emit()
	await _wait(0.8)
	var demo: Node = title.get_child(title.get_child_count() - 1)
	(demo.find_child("User", true, false) as LineEdit).text = "Lucas"
	(demo.find_child("Pass", true, false) as LineEdit).text = "galactum2026"
	await _wait(0.4)
	await shot("cuentas_01_formulario")
	(demo.find_child("Register", true, false) as Button).pressed.emit()
	for i: int in range(60):
		await _wait(0.25)
		if demo.find_child("Enter", true, false) != null:
			break
	await _wait(0.6)
	await shot("cuentas_02_acceso_concedido")
	(demo.find_child("Tamper", true, false) as Button).pressed.emit()
	await _wait(1.2)
	await shot("cuentas_03_token_alterado")
	(demo.find_child("Enter", true, false) as Button).pressed.emit()
	await _wait(4.0)
	await shot("cuentas_04_en_partida")
	print("player_id=", GameClient.player_id, " name=", GameClient.me.get("name", ""))
	# Segunda vez: contraseña incorrecta.
	GameClient.disconnect_all()
	get_tree().change_scene_to_file("res://ui/title.tscn")
	await _wait(1.5)
	var t2: Node = get_tree().current_scene
	(t2.find_child("PlayWithAccount", true, false) as Button).pressed.emit()
	await _wait(0.6)
	var d2: Node = t2.get_child(t2.get_child_count() - 1)
	(d2.find_child("User", true, false) as LineEdit).text = "Lucas"
	(d2.find_child("Pass", true, false) as LineEdit).text = "equivocada1"
	(d2.find_child("Login", true, false) as Button).pressed.emit()
	await _wait(3.0)
	await shot("cuentas_05_contrasena_incorrecta")
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
	print("shot ", name)
