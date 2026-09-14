extends SceneTree
## TEAM3-M2-I: AOI multi-sesión con una nave en viaje — las 4 transiciones por sesión.

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")

var _failures: int = 0
var _now: int = 10_000_000


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	# Velocidad alta para que el viaje cruce AOIs en pocos ticks (test de integración).
	config.travel_speed_tiles_per_min = 3000.0
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)
	world.set_now_provider(func() -> int: return _now)

	# Jugadores adicionales.
	var player_b := EntityState.new("ship_pb", "ship", Vector2i(100, 500))
	player_b.payload = {"player_id": "player_b", "ship_id": "ship_pb"}
	world.entity_registry.add(player_b)
	world.spatial_hash.insert("ship_pb", Vector2i(100, 500))

	var player_c := EntityState.new("ship_pc", "ship", Vector2i(560, 560))
	player_c.payload = {"player_id": "player_c", "ship_id": "ship_pc"}
	world.entity_registry.add(player_c)
	world.spatial_hash.insert("ship_pc", Vector2i(560, 560))

	# Viaje corto: (300,300) -> (100,500) (el centro del AOI de B).
	var res: Dictionary = world.start_travel(seed.player_id, Vector2i(100, 500))
	_check(res.get("ok", false), "start_travel debe tener éxito")

	# En t ≈ 0, sin acknowledge: el updated de start_travel está visible.
	var d_main0: Dictionary = world.delta_for(seed.player_id)
	_check(d_main0.get("updated", []).size() == 1, "player principal debe ver TRAVELING al inicio")
	_check(d_main0.get("added", []).is_empty(), "player principal no debe recibir added de su propia nave")
	var d_b0: Dictionary = world.delta_for("player_b")
	_check(d_b0.is_empty(), "player B no debe ver la nave aún")
	var d_c0: Dictionary = world.delta_for("player_c")
	_check(d_c0.is_empty(), "player C no debe ver la nave aún")
	world.acknowledge_changes()

	# Avanzar hasta que la nave entre al AOI de B (o llegue).
	var ship: EntityState = world.entity_registry.get_entity(seed.entity_id)
	var arrive_ts_value: int = int(ship.travel.get("arrive_ts", 0))
	var crossed_b: bool = false
	var remaining: int = 200
	while remaining > 0 and _now < arrive_ts_value:
		_now += 500
		world.tick()
		var pos: Vector2i = world.entity_registry.get_entity(seed.entity_id).position
		var in_b: bool = abs(pos.x - 100) <= 50 and abs(pos.y - 500) <= 50
		if in_b:
			var d_b: Dictionary = world.delta_for("player_b")
			if not d_b.is_empty():
				crossed_b = true
				break
		world.acknowledge_changes()
		remaining -= 1
	_check(crossed_b, "la nave debe entrar al AOI de player B durante el viaje")

	# El delta de B debe contener added con la nave (transición fuera -> dentro).
	var d_b_entry: Dictionary = world.delta_for("player_b")
	var added_b: Array = d_b_entry.get("added", [])
	_check(added_b.size() == 1 and str(added_b[0].get("entity_id", "")) == seed.entity_id,
		"player B debe recibir added de la nave al entrar a su AOI")
	world.acknowledge_changes()

	# Al llegar, la nave queda ANCHORED dentro del AOI de B: sin re-added.
	_now = arrive_ts_value
	world.tick()
	ship = world.entity_registry.get_entity(seed.entity_id)
	_check(ship.state == "ANCHORED" and ship.position == Vector2i(100, 500),
		"la nave debe llegar y anclarse en el destino")
	var d_b_arrive: Dictionary = world.delta_for("player_b")
	var added_again: Array = d_b_arrive.get("added", [])
	_check(added_again.is_empty(), "no debe re-enviar added al llegar (ya estaba dentro)")

	if _failures == 0:
		print("TRAVEL_AOI_TEST_OK")
		quit(0)
	else:
		print("TRAVEL_AOI_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("TRAVEL_AOI_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)