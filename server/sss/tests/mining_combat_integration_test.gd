extends SceneTree
## Combate aceptado interrumpe ambos mineros; rechazo/replay no interrumpe.

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
const RULES: CombatRules = preload("res://config/default_combat_rules.tres")
const TARGET: String = "018f0000-0000-7000-8000-000000000005"
const NEAR: String = "018f0000-0000-7000-8000-000000000007"
const OTHER: String = "combat-test-asteroid"
var _now: int = 10_000_000
var _failures: int = 0


class RejectingProvider extends CombatSnapshotProvider:
	var source: MockCombatSnapshotProvider

	func snapshot_for(entity: EntityState) -> CombatParticipantSnapshot:
		return source.snapshot_for(entity)

	func apply_resolution(_combat_id: String, _attacker_id: String, _defender_id: String, _resolution: CombatResolution) -> bool:
		return false


func _initialize() -> void:
	var seed: MockWorldSeed = SEED.duplicate(true) as MockWorldSeed
	seed.ship_position = Vector2i(310, 290)
	var world := SolarSystemWorld.new(CONFIG.duplicate(true) as SssConfig, seed)
	world.set_now_provider(func() -> int: return _now)
	var attacker: EntityState = world.get_entity(seed.entity_id)
	var defender: EntityState = world.get_entity(TARGET)
	defender.payload["system_id"] = seed.system_id
	var defender_player: String = str(defender.payload["player_id"])
	world.add_mock_entity(OTHER, "asteroid", defender.position)
	var provider := MockCombatSnapshotProvider.new(seed.combat_units_by_entity())
	var rules: CombatRules = RULES.duplicate(true) as CombatRules
	var service := CombatService.new(world, provider, LocalCombatResolver.new(), rules)
	var first: Dictionary = world.start_mining(seed.player_id, _id(1), NEAR)
	var second: Dictionary = world.start_mining(defender_player, _id(2), OTHER)
	_check(first.get("ok", false) and second.get("ok", false), "ambas naves minan")
	var visible: Array[String] = []
	for entity: Dictionary in world.full_snapshot_for(seed.player_id, true)["added"]:
		visible.append(str(entity["entity_id"]))
	world.acknowledge_changes()
	_now += 2500
	_check(service.request_attack(seed.player_id, "bad-target", "missing").get("type") == "error",
		"objetivo inválido rechazado")
	_check(not attacker.mining.is_empty() and not defender.mining.is_empty(), "rechazo no cancela")
	var original_version: String = rules.combat_version
	rules.combat_version = ""
	_check(service.request_attack(seed.player_id, "bad-rules", TARGET).get("type") == "error",
		"configuración inválida rechazada")
	_check(not attacker.mining.is_empty() and not defender.mining.is_empty(), "fallo de resolver no cancela")
	rules.combat_version = original_version
	var rejecting := RejectingProvider.new()
	rejecting.source = provider
	var rejected_service := CombatService.new(world, rejecting, LocalCombatResolver.new(), rules)
	_check(rejected_service.request_attack(seed.player_id, "bad-application", TARGET).get("error_code") == "COMBAT_RESULT_APPLY_FAILED",
		"fallo al aplicar combate rechazado")
	_check(not attacker.mining.is_empty() and not defender.mining.is_empty(), "fallo de aplicación no cancela")
	var result: Dictionary = service.request_attack(seed.player_id, "accepted", TARGET)
	_check(result.get("type") == "combat_result", "combate aceptado")
	for actor: EntityState in [attacker, defender]:
		_check(actor.mining.is_empty(), "combate cancela participante")
		_check(actor.last_mining_result.get("reason") == "COMBAT_STARTED", "motivo correlacionado")
		_check(actor.last_mining_result.get("quantity") == 2, "liquida tiempo hasta combate")
		_check(actor.last_mining_result.get("finished_ts") == _now, "timestamp autoritativo")
	for asteroid_id: String in [NEAR, OTHER]:
		var asteroid: AsteroidState = world.get_entity(asteroid_id) as AsteroidState
		_check(asteroid.remaining_quantity == 8 and asteroid.occupant_entity_id.is_empty(),
			"remanente y ocupación liberados")
	var delta: Dictionary = world.delta_for_session(seed.player_id, visible, true)
	var published: int = 0
	for entity: Dictionary in delta.get("updated", []):
		if str(entity["entity_id"]) in [attacker.entity_id, defender.entity_id]:
			_check(entity.get("mining") == null, "delta limpia minería")
			_check(entity.get("last_mining_result", {}).get("reason") == "COMBAT_STARTED",
				"delta publica resultado")
			published += 1
	_check(published == 2, "AOI publica ambos participantes")
	for entity: Dictionary in world.full_snapshot_for(seed.player_id, false)["added"]:
		_check(not entity.has("mining") and not entity.has("last_mining_result"), "M2 conserva forma")
	var newer: Dictionary = world.start_mining(seed.player_id, _id(3), NEAR)
	var defender_newer: Dictionary = world.start_mining(defender_player, _id(4), OTHER)
	_now += 1000
	_check(service.request_attack(seed.player_id, "accepted", TARGET) == result, "replay conserva combate")
	_check(attacker.mining.get("mining_id") == newer.get("mining_id")
		and defender.mining.get("mining_id") == defender_newer.get("mining_id"),
		"replay antiguo no cancela minería nueva")
	_check(service.request_attack(seed.player_id, "accepted", NEAR).get("error_code") == "ATTACK_REQUEST_CONFLICT",
		"conflicto de request rechazado")
	_check(not attacker.mining.is_empty() and not defender.mining.is_empty(), "conflicto no cancela")
	world.tick()
	_check(attacker.mining.get("extracted_quantity") == 1, "minería nueva continúa sin duplicar")
	_check(world.stop_mining(seed.player_id, first["mining_id"])["result"]["quantity"] == 2,
		"stop antiguo recupera resultado de combate")
	_check(attacker.mining.get("mining_id") == newer.get("mining_id"), "stop antiguo no cancela nueva")
	var depleted := SolarSystemWorld.new(CONFIG.duplicate(true) as SssConfig, seed)
	depleted.set_now_provider(func() -> int: return _now)
	depleted.start_mining(seed.player_id, _id(5), NEAR)
	_now += 10_000
	var depleted_service := CombatService.new(depleted, MockCombatSnapshotProvider.new(seed.combat_units_by_entity()), LocalCombatResolver.new(), rules)
	_check(depleted_service.request_attack(seed.player_id, "depleted", TARGET).get("type") == "combat_result",
		"combate en instante de agotamiento aceptado")
	var terminal: Dictionary = depleted.get_entity(seed.entity_id).last_mining_result
	_check(terminal.get("status") == "COMPLETED" and terminal.get("reason") == "DEPLETED" and terminal.get("quantity") == 10,
		"agotamiento simultáneo conserva único resultado completo")
	print("MINING_COMBAT_INTEGRATION_TEST_OK" if _failures == 0 else "MINING_COMBAT_INTEGRATION_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _id(index: int) -> String:
	return "00000000-0000-4000-8000-%012d" % index


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("MINING_COMBAT_INTEGRATION_TEST_FAILED: %s" % message)
