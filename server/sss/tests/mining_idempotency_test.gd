extends SceneTree

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
const ASTEROID: String = "018f0000-0000-7000-8000-000000000007"
var _now: int = 10_000_000
var _failures: int = 0


func _initialize() -> void:
	_check(not MiningService.is_valid_request_id("+0000000-0000-4000-8000-000000000001"), "UUID no admite signo")
	_check(not MiningService.is_valid_request_id("0000000z-0000-4000-8000-000000000001"), "UUID requiere caracteres hexadecimales")
	_check(not MiningService.is_valid_request_id("00000000000040008000000000000001"), "UUID requiere grupos separados")
	var seed: MockWorldSeed = SEED.duplicate(true) as MockWorldSeed
	seed.ship_position = Vector2i(310, 290)
	var config: SssConfig = CONFIG.duplicate(true) as SssConfig
	config.mining_config.max_intentions_per_player = 4
	var world := SolarSystemWorld.new(config, seed)
	world.set_now_provider(func() -> int: return _now)
	var ship: EntityState = world.entity_registry.get_entity(seed.entity_id)
	var asteroid: AsteroidState = world.entity_registry.get_entity(ASTEROID) as AsteroidState
	var first: Dictionary = world.start_mining(seed.player_id, _id(1), ASTEROID)
	_check(MiningService.is_valid_request_id(first["mining_id"]), "ID generado por servidor")
	var replay: Dictionary = world.start_mining(seed.player_id, _id(1), ASTEROID)
	_check(replay["mining_id"] == first["mining_id"] and replay["replayed"], "intención repetida no crea proceso")
	_check(world.start_mining(seed.player_id, _id(1), "other").get("error_code") == "MINING_REQUEST_CONFLICT", "UUID ligado al objetivo")
	_now += 1000
	world.tick()
	world.start_mining(seed.player_id, _id(1), ASTEROID)
	world.tick()
	_check(asteroid.remaining_quantity == 9 and ship.mining["extracted_quantity"] == 1, "replay/tick no duplica extracción")
	world.stop_mining(seed.player_id, first["mining_id"])
	var original_result: Dictionary = ship.last_mining_result.duplicate(true)
	var second: Dictionary = world.start_mining(seed.player_id, _id(2), ASTEROID)
	replay = world.start_mining(seed.player_id, _id(1), ASTEROID)
	_check(replay["result"] == original_result and ship.mining["mining_id"] == second["mining_id"], "replay antiguo no sobrescribe minería nueva")
	var result_copy: Dictionary = replay["result"]
	result_copy["quantity"] = 999
	_check(world.stop_mining(seed.player_id, first["mining_id"])["result"]["quantity"] == 1, "resultado terminal protegido por copia")
	_check(ship.mining["mining_id"] == second["mining_id"], "stop antiguo no detiene operación nueva")
	world.stop_mining(seed.player_id, second["mining_id"])
	world.set_entity_position(seed.entity_id, Vector2i(300, 300))
	_check(world.start_mining(seed.player_id, _id(3), ASTEROID).get("error_code") == "MINING_OUT_OF_RANGE", "decisión rechazada registrada")
	world.set_entity_position(seed.entity_id, Vector2i(310, 290))
	_check(world.start_mining(seed.player_id, _id(3), ASTEROID).get("error_code") == "MINING_OUT_OF_RANGE", "reintento conserva rechazo original")
	var fourth: Dictionary = world.start_mining(seed.player_id, _id(4), ASTEROID)
	_check(fourth.get("ok", false), "UUID nuevo reevalúa condiciones")
	_check(world.start_mining(seed.player_id, _id(5), ASTEROID).get("error_code") == "MINING_LIMIT_REACHED", "límite no expulsa claves antiguas")
	_check(world.stop_mining(seed.player_id, fourth["mining_id"]).get("ok", false), "parada permitida con diario lleno")
	_check(world.start_mining(seed.player_id, _id(1), ASTEROID)["result"] == original_result, "replay permitido con diario lleno")
	# Eliminación del actor y del objetivo invalida y deja resultado recuperable.
	var fresh := SolarSystemWorld.new(CONFIG.duplicate(true) as SssConfig, seed)
	fresh.set_now_provider(func() -> int: return _now)
	var removed: Dictionary = fresh.start_mining(seed.player_id, _id(6), ASTEROID)
	fresh.remove_mock_entity(seed.entity_id)
	_now += 2000
	fresh.tick()
	_check(fresh.start_mining(seed.player_id, _id(6), ASTEROID)["result"]["reason"] == "INVALIDATED", "resultado recuperable sin actor")
	_check((fresh.entity_registry.get_entity(ASTEROID) as AsteroidState).occupant_entity_id == "", "eliminar actor libera ocupación")
	_check(fresh.stop_mining(seed.player_id, removed["mining_id"]).get("replayed", false), "stop de invalidada idempotente")
	var target_removed := SolarSystemWorld.new(CONFIG.duplicate(true) as SssConfig, seed)
	target_removed.set_now_provider(func() -> int: return _now)
	target_removed.start_mining(seed.player_id, _id(7), ASTEROID)
	target_removed.remove_mock_entity(ASTEROID)
	target_removed.tick()
	_check(target_removed.entity_registry.get_entity(seed.entity_id).last_mining_result["reason"] == "INVALIDATED", "objetivo eliminado cancela sin extracción")
	print("MINING_IDEMPOTENCY_TEST_OK" if _failures == 0 else "MINING_IDEMPOTENCY_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _id(index: int) -> String:
	return "00000000-0000-4000-8000-%012d" % index


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("MINING_IDEMPOTENCY_TEST_FAILED: %s" % message)
