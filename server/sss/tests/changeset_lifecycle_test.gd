extends SceneTree
## Regresion del orden runtime de main.gd: tick -> flush -> acknowledge.

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
const MAIN_SCRIPT: GDScript = preload("res://main.gd")

var _failures: int = 0


class RecordingGateway extends WebSocketGateway:
	var observations: Array[bool] = []
	var observed_ticks: Array[int] = []
	var observed_world: SolarSystemWorld

	func _init(
			config: SssConfig,
			authenticator: ClientAuthenticator,
			world: SolarSystemWorld,
	) -> void:
		super(config, authenticator, world)
		observed_world = world

	func flush_pending_deltas() -> void:
		observations.append(observed_world.change_set.has_changes())
		observed_ticks.append(observed_world.tick_count)


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)
	var authenticator := MockClientAuthenticator.new(seed)
	var gateway := RecordingGateway.new(config, authenticator, world)
	var main_node: Node = MAIN_SCRIPT.new()
	main_node.set("_config", config)
	main_node.set("_world", world)
	main_node.set("_gateway", gateway)

	world.add_mock_entity("changeset_runtime_probe", "asteroid", Vector2i(305, 305))
	_check(world.change_set.has_changes(), "el cambio debe existir antes del tick")
	var visible_before_flush: Dictionary = world.delta_for(seed.player_id)
	_check(not visible_before_flush.is_empty(), "delta_for debe ver el cambio antes del flush")
	_check(world.change_set.has_changes(), "delta_for no debe drenar el ChangeSet")

	main_node.call("_on_tick")
	_check(gateway.observations == [true], "flush debe observar el cambio antes del acknowledge")
	_check(gateway.observed_ticks == [1], "tick debe ejecutarse antes del flush")
	_check(not world.change_set.has_changes(), "acknowledge debe limpiar despues del flush")

	main_node.call("_on_tick")
	_check(gateway.observations == [true, false], "el tick siguiente no debe reenviar cambios anteriores")
	_check(gateway.observed_ticks == [1, 2], "cada ciclo debe avanzar un solo tick")

	main_node.free()
	gateway.free()
	if _failures == 0:
		print("CHANGESET_LIFECYCLE_TEST_OK")
		quit(0)
	else:
		print("CHANGESET_LIFECYCLE_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("CHANGESET_LIFECYCLE_TEST_FAILED: %s" % message)
