extends Node
## Capturas del estado actual del MVP para el informe de avance frente al
## feedback del 26/10/2026 (lo que ya existe en el juego).
## Uso: GALACTUM_SHOTS_DIR=/ruta/ godot --path . --resolution 1600x720 res://tests/evidence_estado.tscn

var game: Node
var out_dir: String = OS.get_environment("GALACTUM_SHOTS_DIR") if not OS.get_environment("GALACTUM_SHOTS_DIR").is_empty() else "user://"


func _ready() -> void:
	preload("res://shared/i18n.gd").set_locale("es")
	GameClient.start_local("Mateo", "p05", true)
	game = load("res://ui/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await _wait(3.0)
	for spec: Array in [
		["crew", {"tab": "recruit"}, "e01_tripulantes_reclutar"],
		["crew", {"tab": "active"}, "e02_tripulantes_activos"],
		["shop", {}, "e03_tienda"],
		["events", {}, "e04_eventos"],
		["alliance", {"tab": "goals"}, "e05_alianza_metas"],
		["galaxy", {}, "e06_galaxia"],
	]:
		game.open_panel(spec[0], spec[1])
		await _wait(0.9)
		await shot(spec[2])
		game.close_all_panels()
		await _wait(0.3)
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir + name + ".png")
	print("shot ", name)
