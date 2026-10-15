extends SceneTree
## Política estática reproducible; modos/estados sin reglas no se activan por config.

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
var _failures: int = 0
var _now: int = 10000


func _initialize() -> void:
	_test_unimplemented_policy_is_rejected()
	_test_static_policy_reproducible()
	print("M3_XENOFORM_BEHAVIOR_TEST_OK" if _failures == 0 else "M3_XENOFORM_BEHAVIOR_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _test_unimplemented_policy_is_rejected() -> void:
	var world := SolarSystemWorld.new(CONFIG.duplicate(true), SEED.duplicate(true))
	var definition := XenoformConfig.new()
	definition.config_id = "policy-fixture"
	definition.display_name = "Policy fixture"
	var original_count: int = world.entity_registry.all().size()
	# set permite probar contra la versión previa sin un error de compilación.
	definition.set("behavior_mode", "CHASE")
	_check(world.spawn_xenoform("unsupported-mode", definition, Vector2i(300, 300)) == null,
		"config no puede activar persecución sin implementación aprobada")
	_check(not world.entity_registry.has("unsupported-mode") and not world.spatial_hash.has("unsupported-mode"), "modo rechazado no altera mundo")
	definition.set("behavior_mode", "STATIC")
	definition.set("initial_state", "ATTACKING")
	_check(world.spawn_xenoform("unsupported-state", definition, Vector2i(300, 300)) == null,
		"config no puede activar un estado de ataque no acordado")
	_check(world.entity_registry.all().size() == original_count and not world.change_set.has_changes(), "rechazos atómicos sin deltas")


func _test_static_policy_reproducible() -> void:
	var world_a := SolarSystemWorld.new(CONFIG.duplicate(true), SEED.duplicate(true))
	var world_b := SolarSystemWorld.new(CONFIG.duplicate(true), SEED.duplicate(true))
	world_a.set_now_provider(func() -> int: return _now)
	world_b.set_now_provider(func() -> int: return _now)
	var definition := XenoformConfig.new()
	definition.config_id = "static-fixture"
	definition.display_name = "Static fixture"
	definition.set("behavior_mode", "STATIC")
	definition.set("initial_state", "IDLE")
	var enemy_a: XenoformState = world_a.spawn_xenoform("static-1", definition, Vector2i(320, 330))
	var enemy_b: XenoformState = world_b.spawn_xenoform("static-1", definition, Vector2i(320, 330))
	_check(enemy_a != null and enemy_b != null, "política estática crea instancias")
	var replica_a: RefCounted = preload("res://tests/support/aoi_test_replica.gd").new(world_a.full_snapshot_for(SEED.player_id))
	var replica_b: RefCounted = preload("res://tests/support/aoi_test_replica.gd").new(world_b.full_snapshot_for(SEED.player_id))
	world_a.acknowledge_changes()
	world_b.acknowledge_changes()
	var expected: Dictionary = {
		"entity_id": "static-1", "kind": "xenoform", "system_id": SEED.system_id,
		"position": [320, 330], "state": "IDLE", "display_name": "Static fixture",
		"xenoform": {"config_id": "static-fixture"},
	}
	# Cambiar Resource fuente después de spawn no cambia política/estado de instancias.
	definition.set("behavior_mode", "CHASE")
	definition.set("initial_state", "ATTACKING")
	for timestamp: int in [10000, 10000, 10500, 86400000, 10000]:
		_now = timestamp
		world_a.tick()
		world_b.tick()
		_check(enemy_a.to_add_snapshot() == expected and enemy_b.to_add_snapshot() == expected,
			"misma entrada conserva IDLE/posición sin decisiones aleatorias o temporales")
		_check(not world_a.change_set.has_changes() and not world_b.change_set.has_changes(), "ticks estáticos no inventan cambios")
		_check(world_a.delta_for(SEED.player_id, replica_a.known_ids).is_empty()
			and world_b.delta_for(SEED.player_id, replica_b.known_ids).is_empty(), "no updates periódicos espurios")
		_check(world_a.full_snapshot_for(SEED.player_id) == world_b.full_snapshot_for(SEED.player_id), "snapshot reproducible entre mundos")
		_check(world_a.spatial_hash.has("static-1") and not enemy_a.is_traveling(), "política conserva registro espacial sin simular viaje")
		world_a.acknowledge_changes()
		world_b.acknowledge_changes()
	var copied_config: XenoformConfig = enemy_a.get_configuration()
	_check(copied_config.get("behavior_mode") == "STATIC" and copied_config.get("initial_state") == "IDLE", "política inicial queda aislada de Resource fuente")
	var snapshot: Dictionary = enemy_a.to_add_snapshot()
	_check(not snapshot.has("behavior_mode") and not snapshot["xenoform"].has("initial_state"), "config interna no cambia contrato público")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_XENOFORM_BEHAVIOR_TEST_FAILED: %s" % message)
