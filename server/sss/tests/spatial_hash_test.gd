extends SceneTree

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")

var _failures: int = 0


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	# cell_size = 50
	# Celda (0,0): [0,49]x[0,49]
	# Celda (2,2): [100,149]x[100,149]
	# Celda (4,4): [200,249]x[200,249]
	var spatial := SpatialHash.new(config.spatial_cell_size)

	# 1. insert + has
	spatial.insert("a", Vector2i(10, 10))    # Celda (0,0)
	spatial.insert("b", Vector2i(110, 110))  # Celda (2,2)
	spatial.insert("c", Vector2i(120, 120))  # Celda (2,2)
	_check(spatial.has("a"), "insert no agregó a")
	_check(spatial.has("b"), "insert no agregó b")
	_check(spatial.has("c"), "insert no agregó c")
	_check(not spatial.has("z"), "has() devolvió true para entidad inexistente")

	# 2. query_rect: consulta sobre celda (0,0) → [0,0] + extent [49,49] = solo a
	var result: Array = []
	spatial.query_rect(Vector2i(0, 0), Vector2i(49, 49), result)
	_check(result.size() == 1 and result[0] == "a", "query celda (0,0) devolvió %d elementos: %s" % [result.size(), str(result)])

	# 3. query_rect: consulta sobre celda (2,2) → [100,100] + extent [49,49] = b y c
	result.clear()
	spatial.query_rect(Vector2i(100, 100), Vector2i(49, 49), result)
	_check(result.size() == 2, "query celda (2,2) devolvió %d elementos" % result.size())
	_check(result.has("b") and result.has("c"), "query celda (2,2) no encontró b y c: %s" % str(result))

	# 4. move: mover b de (110,110) en celda (2,2) a (210,210) en celda (4,4)
	spatial.move("b", Vector2i(110, 110), Vector2i(210, 210))
	# Celda (2,2) ahora solo debe tener c
	result.clear()
	spatial.query_rect(Vector2i(100, 100), Vector2i(49, 49), result)
	_check(result.size() == 1 and result[0] == "c", "move no sacó a b de celda (2,2): %s" % str(result))
	# Celda (4,4) ahora debe tener b
	result.clear()
	spatial.query_rect(Vector2i(200, 200), Vector2i(49, 49), result)
	_check(result.size() == 1 and result[0] == "b", "move no colocó a b en celda (4,4): %s" % str(result))

	# 5. remove: eliminar c de celda (2,2)
	spatial.remove("c", Vector2i(120, 120))
	_check(not spatial.has("c"), "remove no eliminó a c de has()")
	result.clear()
	spatial.query_rect(Vector2i(100, 100), Vector2i(49, 49), result)
	_check(result.size() == 0, "remove no dejó celda (2,2) vacía: %s" % str(result))

	# 6. cell_size independiente
	_check(spatial.cell_size() == config.spatial_cell_size, "cell_size incorrecto")

	# 7. cell_size configurable a otro valor (ej: 10)
	var spatial10 := SpatialHash.new(10)
	spatial10.insert("x", Vector2i(5, 5))    # Celda (0,0)
	spatial10.insert("y", Vector2i(15, 15))  # Celda (1,1)
	result.clear()
	spatial10.query_rect(Vector2i(0, 0), Vector2i(9, 9), result)
	_check(result.size() == 1 and result[0] == "x", "cell_size 10 no aisló celda (0,0)")

	if _failures == 0:
		print("SPATIAL_HASH_TEST_OK")
		quit(0)
	else:
		print("SPATIAL_HASH_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("SPATIAL_HASH_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)