extends SceneTree
## TEAM3-M2-I: start_travel — flujo de éxito, validaciones y errores del contrato.

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")

var _failures: int = 0
var _now: int = 10_000_000


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)
	world.set_now_provider(func() -> int: return _now)

	var ship: EntityState = world.entity_registry.get_entity(seed.entity_id)
	_check(ship != null, "la nave del seed debe existir")
	_check(ship.state == "ANCHORED", "la nave debe iniciar ANCHORED")
	_check(not ship.is_traveling(), "la nave no debe viajar al inicio")

	# --- Éxito: ANCHORED -> TRAVELING ---
	var res: Dictionary = world.start_travel(seed.player_id, Vector2i(420, 180))
	_check(res.get("ok", false) == true, "start_travel debe devolver ok")
	_check(ship.state == "TRAVELING", "state debe ser TRAVELING tras el viaje")
	_check(ship.travel.get("origin") == [300, 300], "origin debe ser [300,300]")
	_check(ship.travel.get("destination") == [420, 180], "destination debe ser [420,180]")
	_check(int(ship.travel.get("depart_ts", 0)) == _now, "depart_ts debe ser el reloj actual al aceptar")
	var dist: float = Vector2(300, 300).distance_to(Vector2(420, 180))
	var expected_duration: int = int(dist / 10.0 * 60_000.0)
	_check(int(ship.travel.get("arrive_ts", 0)) == _now + expected_duration,
		"arrive_ts debe ser depart_ts + duración: %d != %d" % [ship.travel.get("arrive_ts", 0), _now + expected_duration])
	_check(ship.position == Vector2i(300, 300), "posición debe seguir en origin al iniciar")
	_check(world.change_set.updated().size() == 1, "el change_set debe tener 1 update (inicio de viaje)")

	# --- SHIP_NOT_ANCHORED: ya viajando ---
	var res2: Dictionary = world.start_travel(seed.player_id, Vector2i(100, 100))
	_check(str(res2.get("error_code", "")) == "SHIP_NOT_ANCHORED", "segundo start_travel debe dar SHIP_NOT_ANCHORED")

	world.acknowledge_changes()
	# --- SHIP_NOT_FOUND: player sin nave ---
	var res3: Dictionary = world.start_travel("player_inexistente", Vector2i(100, 100))
	_check(str(res3.get("error_code", "")) == "SHIP_NOT_FOUND", "player sin nave debe dar SHIP_NOT_FOUND")

	# --- INVALID_DESTINATION: fuera de mapa ---
	var res4: Dictionary = world.start_travel(seed.player_id, Vector2i(600, 300))
	_check(str(res4.get("error_code", "")) == "INVALID_DESTINATION", "destino fuera de mapa debe dar INVALID_DESTINATION")
	var res5: Dictionary = world.start_travel(seed.player_id, Vector2i(-10, 300))
	_check(str(res5.get("error_code", "")) == "INVALID_DESTINATION", "destino negativo debe dar INVALID_DESTINATION")

	# --- INVALID_DESTINATION: destino == origen ---
	var res6: Dictionary = world.start_travel(seed.player_id, Vector2i(300, 300))
	_check(str(res6.get("error_code", "")) == "INVALID_DESTINATION", "destino == origen debe dar INVALID_DESTINATION")

	if _failures == 0:
		print("TRAVEL_START_TEST_OK")
		quit(0)
	else:
		print("TRAVEL_START_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("TRAVEL_START_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)