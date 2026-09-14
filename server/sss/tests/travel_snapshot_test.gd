extends SceneTree
## TEAM3-M2-I: full_snapshot (reconnect) con nave TRAVELING — state + position + travel completo.

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")

var _failures: int = 0
var _now: int = 10_000_000


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)
	world.set_now_provider(func() -> int: return _now)

	# Viaje en curso.
	var res: Dictionary = world.start_travel(seed.player_id, Vector2i(420, 180))
	_check(res.get("ok", false), "start_travel debe tener éxito")
	var ship: EntityState = world.entity_registry.get_entity(seed.entity_id)
	var depart_ts_value: int = int(ship.travel.get("depart_ts", 0))
	var arrive_ts_value: int = int(ship.travel.get("arrive_ts", 0))
	world.acknowledge_changes()

	# A mitad de viaje: la nave está en (300,300) + lerp(420,180) ~ a los 500 ms.
	_now += 500
	world.tick()
	world.acknowledge_changes()

	var snapshot: Dictionary = world.full_snapshot_for(seed.player_id)
	var added: Array = snapshot.get("added", [])
	var found: Dictionary = {}
	for entity: Dictionary in added:
		if str(entity.get("entity_id", "")) == seed.entity_id:
			found = entity
			break
	_check(not found.is_empty(), "el snapshot debe contener la nave del jugador")
	if not found.is_empty():
		_check(found.get("state") == "TRAVELING", "snapshot debe incluir state TRAVELING")
		var t: Dictionary = found.get("travel", {})
		_check(not t.is_empty(), "snapshot debe incluir travel")
		_check(t.get("origin") == [300, 300], "travel.origin debe estar en snapshot")
		_check(t.get("destination") == [420, 180], "travel.destination debe estar en snapshot")
		_check(int(t.get("depart_ts", 0)) == depart_ts_value, "depart_ts debe estar en snapshot")
		_check(int(t.get("arrive_ts", 0)) == arrive_ts_value, "arrive_ts debe estar en snapshot")
		_check(found.get("position") == [ship.position.x, ship.position.y],
			"snapshot position debe ser la derivada actual")

	if _failures == 0:
		print("TRAVEL_SNAPSHOT_TEST_OK")
		quit(0)
	else:
		print("TRAVEL_SNAPSHOT_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("TRAVEL_SNAPSHOT_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)