extends SceneTree

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
const ASTEROID: String = "018f0000-0000-7000-8000-000000000007"
var _now: int = 10_000_000
var _failures: int = 0


func _initialize() -> void:
	var seed: MockWorldSeed = SEED.duplicate(true) as MockWorldSeed
	seed.ship_position = Vector2i(310, 290)
	seed.asteroid_config.rate_units_per_second = 3
	var world := SolarSystemWorld.new(CONFIG.duplicate(true) as SssConfig, seed)
	world.set_now_provider(func() -> int: return _now)
	var asteroid: AsteroidState = world.entity_registry.get_entity(ASTEROID) as AsteroidState
	var ship: EntityState = world.entity_registry.get_entity(seed.entity_id)
	var start: Dictionary = world.start_mining(seed.player_id, _id(1), ASTEROID)
	_check(start.get("ok", false), "inicio válido")
	_check(ship.state == "ANCHORED" and ship.mining["status"] == "ACTIVE", "minería independiente del viaje")
	_check(asteroid.occupant_entity_id == ship.entity_id, "ocupación")
	var started: int = _now
	_now += 333
	world.tick()
	_check(asteroid.remaining_quantity == 10, "fracción no se extrae antes de tiempo")
	_now += 1
	world.tick()
	_check(ship.mining["extracted_quantity"] == 1 and asteroid.remaining_quantity == 9, "fracción conservada entre ticks")
	world.tick()
	_check(asteroid.remaining_quantity == 9, "tick con mismo tiempo no repite extracción")
	_now -= 100
	world.tick()
	_check(ship.mining["updated_ts"] == started + 334 and asteroid.remaining_quantity == 9, "reloj hacia atrás no duplica")
	_now = started + 1000
	world.tick()
	_check(ship.mining["extracted_quantity"] == 3 and asteroid.remaining_quantity == 7, "tick retrasado usa tiempo acumulado")
	var m3_snapshot: Dictionary = _entity(world.full_snapshot_for(seed.player_id, true)["added"], ship.entity_id)
	_check(m3_snapshot["mining"]["extracted_quantity"] == 3, "snapshot durante minería")
	_check(not _entity(world.full_snapshot_for(seed.player_id)["added"], ship.entity_id).has("mining"), "snapshot M2 sin bloque nuevo")
	_now = started + 1500
	_check(world.stop_mining(seed.player_id, start["mining_id"]).get("ok", false), "cancelación")
	_check(ship.mining.is_empty() and asteroid.remaining_quantity == 6, "cancelación liquida 4 unidades y descarta fracción")
	_check(ship.last_mining_result["quantity"] == 4 and ship.last_mining_result["reason"] == "USER_CANCELLED", "resultado cancelado autoritativo")
	_check(asteroid.asteroid_state == "AVAILABLE", "ocupación liberada")
	var result: Dictionary = ship.last_mining_result.duplicate(true)
	world.stop_mining(seed.player_id, start["mining_id"])
	_check(ship.last_mining_result == result and asteroid.remaining_quantity == 6, "parada duplicada sin efecto")
	var second: Dictionary = world.start_mining(seed.player_id, _id(2), ASTEROID)
	_check(second.get("ok", false) and ship.last_mining_result == result, "nuevo inicio preserva resultado anterior")
	_now += 4000
	world.tick()
	_check(asteroid.remaining_quantity == 0 and asteroid.asteroid_state == "DEPLETED", "agotamiento sin negativos")
	_check(ship.mining.is_empty() and ship.last_mining_result["quantity"] == 6, "última operación extrae sólo restante")
	_check(ship.last_mining_result["status"] == "COMPLETED" and ship.last_mining_result["reason"] == "DEPLETED", "resultado completo")
	_check(world.entity_registry.has(ASTEROID), "agotado no destruido")
	var terminal: Dictionary = ship.last_mining_result.duplicate(true)
	world.tick()
	world.stop_mining(seed.player_id, second["mining_id"])
	_check(ship.last_mining_result == terminal and asteroid.remaining_quantity == 0, "terminal no vuelve a liquidar")
	var final_snapshot: Dictionary = _entity(world.full_snapshot_for(seed.player_id, true)["added"], ship.entity_id)
	_check(final_snapshot["mining"] == null and final_snapshot["last_mining_result"] == terminal, "snapshot terminal reconstruible")
	print("MINING_LIFECYCLE_TEST_OK" if _failures == 0 else "MINING_LIFECYCLE_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _id(index: int) -> String:
	return "00000000-0000-4000-8000-%012d" % index


func _entity(entities: Array, entity_id: String) -> Dictionary:
	for entity: Dictionary in entities:
		if entity["entity_id"] == entity_id:
			return entity
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("MINING_LIFECYCLE_TEST_FAILED: %s" % message)
