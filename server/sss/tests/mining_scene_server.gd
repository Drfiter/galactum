extends SceneTree
## Fixture E2E: runtime real, viaje acelerado sólo para pruebas de escena.

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
var _world: SolarSystemWorld
var _gateway: WebSocketGateway


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var config: SssConfig = CONFIG.duplicate(true) as SssConfig
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			config.port = int(argument.trim_prefix("--port="))
	config.travel_speed_tiles_per_min = 600.0
	var seed: MockWorldSeed = SEED.duplicate(true) as MockWorldSeed
	_world = SolarSystemWorld.new(config, seed)
	var provider := MockCombatSnapshotProvider.new(seed.combat_units_by_entity())
	var rules: CombatRules = load("res://config/default_combat_rules.tres").duplicate(true) as CombatRules
	var combat := CombatService.new(_world, provider, LocalCombatResolver.new(), rules)
	_gateway = WebSocketGateway.new(config, MockClientAuthenticator.new(seed), _world, combat)
	root.add_child(_gateway)
	if _gateway.start() != OK:
		quit(1)
		return
	var timer := Timer.new()
	timer.wait_time = 1.0 / config.tick_hz
	timer.timeout.connect(_tick)
	root.add_child(timer)
	timer.start()
	print("MINING_SCENE_SSS_READY port=%d" % config.port)


func _tick() -> void:
	_world.tick()
	_gateway.flush_pending_deltas()
	_world.acknowledge_changes()


func _finalize() -> void:
	if _gateway != null and is_instance_valid(_gateway):
		_gateway.stop()
