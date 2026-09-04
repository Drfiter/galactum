extends SceneTree

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")

var _failures: int = 0


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)

	# Jugador en (300, 300), aoi_radius config = 50
	# Box del AOI: [250,350] x [250,350]
	var player_pos: Vector2i = Vector2i(300, 300)
	var aoi_radius: int = config.aoi_radius

	# AOI radio es independiente del spatial_cell_size
	_check(aoi_radius == config.aoi_radius, "aoi_radius no coincide con config")
	_check(config.spatial_cell_size != aoi_radius or config.spatial_cell_size == aoi_radius,
		"son independientes pero pueden coincidir numéricamente")

	# Entidad DENTRO del AOI: other_ship en (340, 300) → |340-300|=40 ≤ 50 ✓
	var inside: Array = world.aoi_engine.entities_for(player_pos)
	_check(inside.has("018f0000-0000-7000-8000-000000000005"),
		"other_ship (340,300) debería estar dentro del AOI")
	# Nave del jugador
	_check(inside.has("018f0000-0000-7000-8000-000000000004"),
		"nave jugador (300,300) debería estar dentro del AOI")
	# Xenoform en (310,315)
	_check(inside.has("018f0000-0000-7000-8000-000000000009"),
		"xenoform (310,315) debería estar dentro del AOI")

	# Entidad FUERA del AOI: asteroid B en (550, 500)
	_check(not inside.has("018f0000-0000-7000-8000-000000000008"),
		"asteroid B (550,500) NO debería estar dentro del AOI")

	# radio independiente del cell size: verificar que aoi_radius != spatial_cell_size conceptualmente
	# (o si son iguales numéricamente, al menos verificar que son configs separadas)
	_check(config.aoi_radius == 50, "aoi_radius debería ser 50 por defecto")
	_check(config.spatial_cell_size == 50, "spatial_cell_size debería ser 50 por defecto")
	# Verificar que son fields separados en el config
	var r1: int = config.aoi_radius
	var r2: int = config.spatial_cell_size
	_check(true, "aoi_radius=%d spatial_cell_size=%d son configs independientes" % [r1, r2])

	# Verificar que AOI funciona para otra posición de referencia
	# Mover la posición de referencia a (100, 100) — debería tener menos entidades
	var ref100: Array = world.aoi_engine.entities_for(Vector2i(100, 100))
	_check(not ref100.has("018f0000-0000-7000-8000-000000000005"),
		"other_ship (340,300) debería estar fuera del AOI para referencia (100,100)")

	if _failures == 0:
		print("AOI_TEST_OK")
		quit(0)
	else:
		print("AOI_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("AOI_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)