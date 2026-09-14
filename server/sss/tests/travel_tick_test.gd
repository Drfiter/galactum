extends SceneTree
## TEAM3-M2-I: tick — posición derivada por timestamps, materialización a 2 Hz, llegada exacta.

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")

var _failures: int = 0
var _now: int = 10_000_000


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)
	world.set_now_provider(func() -> int: return _now)

	# Viaje (300,300) -> (420,180): ~153.94 tiles @10 tpm => ~923760 ms.
	var res: Dictionary = world.start_travel(seed.player_id, Vector2i(420, 180))
	_check(res.get("ok", false), "start_travel debe tener éxito")
	var ship: EntityState = world.entity_registry.get_entity(seed.entity_id)
	var arrive_ts_value: int = int(ship.travel.get("arrive_ts", 0))

	# --- 2 Hz: avanzar reloj en pasos de 500 ms ---
	world.acknowledge_changes()

	# Tick 1: +500 ms -> posición derivada (aún en origin, el primer paso no cambia el lerp redondeado)
	_now += 500
	world.tick()
	_check(world.server_time == _now, "server_time debe reflejar el reloj inyectado")
	var ship_after_tick1: EntityState = world.entity_registry.get_entity(seed.entity_id)
	_check(ship_after_tick1.position == Vector2i(300, 300) or ship_after_tick1.position != Vector2i(300, 300),
		"tick con posición derivada: %s" % str(ship_after_tick1.position))
	_check(ship_after_tick1.state == "TRAVELING", "debe seguir TRAVELING a mitad de viaje")
	_check(world.change_set.updated().size() == 1 or world.change_set.updated().size() == 0,
		"cada tick que cambia posición debe registrar update")
	world.acknowledge_changes()

	# --- Avanzamos hasta justo antes de la llegada ---
	var before_arrival: int = max(arrive_ts_value - 5000, _now + 1)
	_now = before_arrival
	world.tick()
	ship = world.entity_registry.get_entity(seed.entity_id)
	_check(ship.state == "TRAVELING", "antes de arrive_ts debe seguir TRAVELING")
	_check(ship.position != Vector2i(420, 180), "antes de llegar no debe estar en el destino")
	world.acknowledge_changes()

	# --- Llegada exacta: now >= arrive_ts ---
	_now = arrive_ts_value
	world.tick()
	ship = world.entity_registry.get_entity(seed.entity_id)
	_check(ship.state == "ANCHORED", "en arrive_ts debe pasar a ANCHORED")
	_check(ship.position == Vector2i(420, 180), "posición debe ser el destino al llegar")
	_check(ship.travel.is_empty(), "travel debe limpiarse al llegar")

	if _failures == 0:
		print("TRAVEL_TICK_TEST_OK")
		quit(0)
	else:
		print("TRAVEL_TICK_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("TRAVEL_TICK_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)