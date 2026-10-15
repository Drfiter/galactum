extends SceneTree

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
const ASTEROID: String = "018f0000-0000-7000-8000-000000000007"
var _now: int = 10_000_000
var _failures: int = 0


func _initialize() -> void:
	var seed: MockWorldSeed = SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(CONFIG.duplicate(true) as SssConfig, seed)
	world.set_now_provider(func() -> int: return _now)
	var ship: EntityState = world.entity_registry.get_entity(seed.entity_id)
	_check_error(world.start_mining("", _id(1), ASTEROID), "MINING_NOT_AUTHENTICATED")
	_check_error(world.start_mining(seed.player_id, "bad", ASTEROID), "MINING_INVALID_REQUEST")
	_check_error(world.start_mining("stranger", _id(2), ASTEROID), "MINING_SHIP_NOT_FOUND")
	_check_error(world.start_mining(seed.player_id, _id(3), "missing"), "MINING_ASTEROID_NOT_FOUND")
	_check_error(world.start_mining(seed.player_id, _id(4), seed.entity_id), "MINING_ASTEROID_NOT_FOUND")
	_check_error(world.start_mining(seed.player_id, _id(5), ASTEROID), "MINING_OUT_OF_RANGE")
	world.set_entity_position(seed.entity_id, Vector2i(311, 291))
	_check_error(world.start_mining(seed.player_id, _id(6), ASTEROID), "MINING_OUT_OF_RANGE")
	world.set_entity_position(seed.entity_id, Vector2i(311, 290))
	ship.state = "TRAVELING"
	_check_error(world.start_mining(seed.player_id, _id(7), ASTEROID), "MINING_SHIP_NOT_ANCHORED")
	ship.state = "ANCHORED"
	ship.payload["system_id"] = "other-system"
	_check_error(world.start_mining(seed.player_id, _id(8), ASTEROID), "MINING_SYSTEM_MISMATCH")
	ship.payload["system_id"] = seed.system_id
	var started: Dictionary = world.start_mining(seed.player_id, _id(9), ASTEROID)
	_check(started.get("ok", false), "rango inclusivo exacto")
	_check_error(world.start_mining(seed.player_id, _id(10), ASTEROID), "MINING_ALREADY_ACTIVE")
	world.add_mock_entity("p2ship", "ship", Vector2i(310, 290), {"player_id": "p2", "system_id": seed.system_id})
	_check_error(world.start_mining("p2", _id(11), ASTEROID), "MINING_ASTEROID_OCCUPIED")
	_check_error(world.stop_mining("p2", started["mining_id"]), "MINING_NOT_OWNER")
	_check(not ship.mining.is_empty(), "jugador ajeno no altera operación")
	_check_error(world.stop_mining(seed.player_id, "missing"), "MINING_OPERATION_NOT_FOUND")
	_check_error(world.stop_mining(seed.player_id, ""), "MINING_INVALID_REQUEST")
	world.stop_mining(seed.player_id, started["mining_id"])
	var takeover: Dictionary = world.start_mining("p2", _id(12), ASTEROID)
	_check(takeover.get("ok", false), "otro jugador ocupa tras liberación")
	world.set_entity_position("p2ship", Vector2i(500, 500))
	_now += 2000
	world.tick()
	var p2: EntityState = world.entity_registry.get_entity("p2ship")
	_check(p2.mining.is_empty() and p2.last_mining_result["reason"] == "INVALIDATED", "invalidación por rango")
	_check((world.entity_registry.get_entity(ASTEROID) as AsteroidState).remaining_quantity == 10, "no extrae fuera del rango")
	world.set_asteroid_resource_state(ASTEROID, 0, "")
	_check_error(world.start_mining(seed.player_id, _id(13), ASTEROID), "MINING_DEPLETED")
	# Viaje rechazado conserva operación; viaje válido liquida y cancela.
	world.set_asteroid_resource_state(ASTEROID, 10, "")
	world.start_mining(seed.player_id, _id(14), ASTEROID)
	_check_error(world.start_travel(seed.player_id, Vector2i(600, 300)), "INVALID_DESTINATION")
	_check(not ship.mining.is_empty(), "viaje rechazado no cancela minería")
	_now += 1500
	_check(world.start_travel(seed.player_id, Vector2i(312, 290)).get("ok", false), "viaje M2 válido")
	_check(ship.state == "TRAVELING" and ship.mining.is_empty(), "viaje y minería no coexisten")
	_check(ship.last_mining_result["reason"] == "TRAVEL_STARTED" and ship.last_mining_result["quantity"] == 1, "viaje liquida hasta su instante")
	print("MINING_VALIDATION_TEST_OK" if _failures == 0 else "MINING_VALIDATION_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _id(index: int) -> String:
	return "00000000-0000-4000-8000-%012d" % index


func _check_error(result: Dictionary, expected: String) -> void:
	_check(str(result.get("error_code", "")) == expected, "rechazo %s: %s" % [expected, result])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("MINING_VALIDATION_TEST_FAILED: %s" % message)
