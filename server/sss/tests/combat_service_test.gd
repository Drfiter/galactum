extends SceneTree
## TEAM3-M3 ETAPA 3: autoridad, validaciones e idempotencia del flujo Combat.

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
const DEFAULT_RULES: CombatRules = preload("res://config/default_combat_rules.tres")

var _failures: int = 0


class CountingResolver extends CombatResolverPort:
	var calls: int = 0

	func resolve(
			attacker: CombatParticipantSnapshot,
			defender: CombatParticipantSnapshot,
			rules: CombatRules,
	) -> CombatResolution:
		calls += 1
		return CombatResolver.resolve(attacker, defender, rules)


func _initialize() -> void:
	_test_request_identifiers_and_attacker_must_be_valid()
	_test_valid_attack_derives_attacker()
	_test_missing_and_unsupported_target()
	_test_own_target_is_rejected()
	_test_target_must_be_visible()
	_test_traveling_ships_are_rejected()
	_test_snapshot_and_configuration_must_be_available()
	_test_duplicate_request_is_exactly_idempotent()
	_test_same_request_with_other_target_conflicts()
	_finish()


func _test_request_identifiers_and_attacker_must_be_valid() -> void:
	var fixture: Dictionary = _fixture()
	var service: CombatService = fixture["service"]
	var seed: MockWorldSeed = fixture["seed"]
	var target_id: String = _default_target_id(seed)

	var missing_request: Dictionary = service.request_attack(seed.player_id, "", target_id)
	_check(missing_request.get("error_code") == CombatService.ERROR_INVALID_ATTACK_REQUEST,
		"request_id vacío debe rechazarse")
	var invalid_target: Dictionary = service.request_attack(seed.player_id, "request-no-target", "")
	_check(invalid_target.get("error_code") == CombatService.ERROR_INVALID_ATTACK_REQUEST,
		"target_entity_id vacío debe rechazarse")
	var missing_attacker: Dictionary = service.request_attack("player-without-ship", "request-no-attacker", target_id)
	_check(missing_attacker.get("error_code") == CombatService.ERROR_ATTACKER_NOT_FOUND,
		"jugador autenticado sin nave debe rechazarse")


func _test_valid_attack_derives_attacker() -> void:
	var fixture: Dictionary = _fixture()
	var service: CombatService = fixture["service"]
	var seed: MockWorldSeed = fixture["seed"]
	var provider: MockCombatSnapshotProvider = fixture["provider"]
	var resolver: CountingResolver = fixture["resolver"]
	var world: SolarSystemWorld = fixture["world"]
	var target_id: String = _default_target_id(seed)

	var result: Dictionary = service.request_attack(seed.player_id, "request-valid", target_id)

	_check(result.get("type") == "combat_result", "ataque válido devuelve combat_result")
	_check(str(result.get("request_id", "")) == "request-valid", "resultado correlaciona request_id")
	_check(not str(result.get("combat_id", "")).is_empty(), "el servidor genera combat_id")
	_check(result.get("combat_version") == "m3-provisional-1", "resultado incluye combat_version")
	_check(result.get("attacker", {}).get("entity_id") == seed.entity_id,
		"atacante se deriva del player_id autenticado")
	_check(result.get("defender", {}).get("entity_id") == target_id, "objetivo conserva target_entity_id")
	_check(resolver.calls == 1, "resolver se ejecuta una vez")
	_check(provider.application_count_for(str(result.get("combat_id", ""))) == 1,
		"resultado se aplica una vez al estado mock")
	_check(world.get_entity(seed.entity_id) != null and world.get_entity(target_id) != null,
		"el combate no destruye ni retira naves del mundo")


func _test_missing_and_unsupported_target() -> void:
	var fixture: Dictionary = _fixture()
	var service: CombatService = fixture["service"]
	var seed: MockWorldSeed = fixture["seed"]
	var world: SolarSystemWorld = fixture["world"]

	var missing: Dictionary = service.request_attack(seed.player_id, "request-missing", "missing")
	_check(missing.get("error_code") == CombatService.ERROR_TARGET_NOT_FOUND,
		"objetivo inexistente debe rechazarse")

	world.add_mock_entity("asteroid-target", "asteroid", Vector2i(310, 300))
	var unsupported: Dictionary = service.request_attack(seed.player_id, "request-asteroid", "asteroid-target")
	_check(unsupported.get("error_code") == CombatService.ERROR_UNSUPPORTED_TARGET_KIND,
		"el corte sólo acepta target kind ship")


func _test_own_target_is_rejected() -> void:
	var fixture: Dictionary = _fixture()
	var service: CombatService = fixture["service"]
	var seed: MockWorldSeed = fixture["seed"]
	var world: SolarSystemWorld = fixture["world"]
	var provider: MockCombatSnapshotProvider = fixture["provider"]

	var self_result: Dictionary = service.request_attack(seed.player_id, "request-self", seed.entity_id)
	_check(self_result.get("error_code") == CombatService.ERROR_CANNOT_ATTACK_SELF,
		"una entidad no puede atacarse a sí misma")

	_add_ship(world, provider, "own-second-entity", "own-second-ship", seed.player_id, Vector2i(320, 300))
	var own_result: Dictionary = service.request_attack(seed.player_id, "request-own", "own-second-entity")
	_check(own_result.get("error_code") == CombatService.ERROR_CANNOT_ATTACK_OWN_SHIP,
		"otra nave del mismo player_id debe rechazarse")


func _test_target_must_be_visible() -> void:
	var fixture: Dictionary = _fixture()
	var service: CombatService = fixture["service"]
	var seed: MockWorldSeed = fixture["seed"]
	var world: SolarSystemWorld = fixture["world"]
	var provider: MockCombatSnapshotProvider = fixture["provider"]
	_add_ship(world, provider, "far-entity", "far-ship", "far-player", Vector2i(500, 500))

	var result: Dictionary = service.request_attack(seed.player_id, "request-far", "far-entity")

	_check(result.get("error_code") == CombatService.ERROR_TARGET_NOT_VISIBLE,
		"objetivo fuera del AOI autoritativo debe rechazarse")


func _test_traveling_ships_are_rejected() -> void:
	var attacker_fixture: Dictionary = _fixture()
	var attacker_world: SolarSystemWorld = attacker_fixture["world"]
	var attacker_seed: MockWorldSeed = attacker_fixture["seed"]
	attacker_world.get_entity(attacker_seed.entity_id).state = "TRAVELING"
	var attacker_result: Dictionary = attacker_fixture["service"].request_attack(
		attacker_seed.player_id,
		"request-traveling-attacker",
		_default_target_id(attacker_seed),
	)
	_check(attacker_result.get("error_code") == CombatService.ERROR_ATTACKER_NOT_ANCHORED,
		"atacante TRAVELING no puede participar")

	var target_fixture: Dictionary = _fixture()
	var target_world: SolarSystemWorld = target_fixture["world"]
	var target_seed: MockWorldSeed = target_fixture["seed"]
	var target_id: String = _default_target_id(target_seed)
	target_world.get_entity(target_id).state = "TRAVELING"
	var target_result: Dictionary = target_fixture["service"].request_attack(
		target_seed.player_id,
		"request-traveling-target",
		target_id,
	)
	_check(target_result.get("error_code") == CombatService.ERROR_TARGET_NOT_ANCHORED,
		"objetivo TRAVELING no puede participar")


func _test_snapshot_and_configuration_must_be_available() -> void:
	var snapshot_fixture: Dictionary = _fixture()
	var snapshot_world: SolarSystemWorld = snapshot_fixture["world"]
	var snapshot_seed: MockWorldSeed = snapshot_fixture["seed"]
	snapshot_world.add_mock_entity(
		"no-combat-data",
		"ship",
		Vector2i(320, 300),
		{"ship_id": "ship-no-data", "player_id": "player-no-data"},
	)
	var snapshot_result: Dictionary = snapshot_fixture["service"].request_attack(
		snapshot_seed.player_id,
		"request-no-data",
		"no-combat-data",
	)
	_check(snapshot_result.get("error_code") == CombatService.ERROR_COMBAT_DATA_UNAVAILABLE,
		"snapshot Combat ausente debe rechazarse")

	var config_fixture: Dictionary = _fixture(false)
	var config_seed: MockWorldSeed = config_fixture["seed"]
	var config_result: Dictionary = config_fixture["service"].request_attack(
		config_seed.player_id,
		"request-invalid-config",
		_default_target_id(config_seed),
	)
	_check(config_result.get("error_code") == CombatService.ERROR_INVALID_COMBAT_CONFIGURATION,
		"configuración inválida debe diferenciarse de snapshot ausente")


func _test_duplicate_request_is_exactly_idempotent() -> void:
	var fixture: Dictionary = _fixture()
	var service: CombatService = fixture["service"]
	var seed: MockWorldSeed = fixture["seed"]
	var provider: MockCombatSnapshotProvider = fixture["provider"]
	var resolver: CountingResolver = fixture["resolver"]
	var target_id: String = _default_target_id(seed)

	var first: Dictionary = service.request_attack(seed.player_id, "request-retry", target_id)
	var units_after_first: Array[CombatUnitStack] = provider.units_for(target_id)
	var second: Dictionary = service.request_attack(seed.player_id, "request-retry", target_id)

	_check(first == second, "retry exacto devuelve el mismo resultado almacenado")
	_check(first.get("combat_id") == second.get("combat_id"), "retry conserva combat_id")
	_check(resolver.calls == 1, "retry no vuelve a ejecutar el resolver")
	_check(provider.application_count_for(str(first.get("combat_id", ""))) == 1,
		"retry no vuelve a aplicar bajas")
	_check(_stacks_equal(units_after_first, provider.units_for(target_id)),
		"estado mock permanece igual tras retry")


func _test_same_request_with_other_target_conflicts() -> void:
	var fixture: Dictionary = _fixture()
	var service: CombatService = fixture["service"]
	var seed: MockWorldSeed = fixture["seed"]
	var world: SolarSystemWorld = fixture["world"]
	var provider: MockCombatSnapshotProvider = fixture["provider"]
	var resolver: CountingResolver = fixture["resolver"]
	_add_ship(world, provider, "alternate-entity", "alternate-ship", "alternate-player", Vector2i(330, 300))
	service.request_attack(seed.player_id, "request-conflict", _default_target_id(seed))

	var conflict: Dictionary = service.request_attack(
		seed.player_id,
		"request-conflict",
		"alternate-entity",
	)

	_check(conflict.get("error_code") == CombatService.ERROR_ATTACK_REQUEST_CONFLICT,
		"mismo request_id con otro target debe entrar en conflicto")
	_check(conflict.get("request_type") == "attack", "error Combat identifica request_type")
	_check(conflict.get("request_id") == "request-conflict", "error Combat conserva request_id")
	_check(resolver.calls == 1, "conflicto no ejecuta otro combate")
	_check(provider.total_application_count() == 1, "conflicto no aplica otro resultado")


func _fixture(valid_rules: bool = true) -> Dictionary:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)
	var provider := MockCombatSnapshotProvider.new(seed.combat_units_by_entity())
	var resolver := CountingResolver.new()
	var rules: CombatRules = DEFAULT_RULES.duplicate(true) as CombatRules
	if not valid_rules:
		rules.combat_version = ""
	var service := CombatService.new(world, provider, resolver, rules)
	return {
		"seed": seed,
		"world": world,
		"provider": provider,
		"resolver": resolver,
		"service": service,
	}


func _default_target_id(seed: MockWorldSeed) -> String:
	for entry: Dictionary in seed.extra_entities():
		if str(entry.get("kind", "")) == "ship":
			return str(entry.get("entity_id", ""))
	return ""


func _add_ship(
		world: SolarSystemWorld,
		provider: MockCombatSnapshotProvider,
		entity_id: String,
		ship_id: String,
		player_id: String,
		position: Vector2i,
) -> void:
	world.add_mock_entity(entity_id, "ship", position, {
		"ship_id": ship_id,
		"player_id": player_id,
	})
	var units: Array[CombatUnitStack] = [CombatUnitStack.new("mock_unit_alpha", 2)]
	provider.set_units(entity_id, units)


func _stacks_equal(left: Array[CombatUnitStack], right: Array[CombatUnitStack]) -> bool:
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if left[index].to_dictionary() != right[index].to_dictionary():
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("COMBAT_SERVICE_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("COMBAT_SERVICE_TEST_OK" if _failures == 0 else "COMBAT_SERVICE_TEST_FAILED failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)
