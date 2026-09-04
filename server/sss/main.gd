extends Node

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")

var _config: SssConfig
var _world: SolarSystemWorld
var _gateway: WebSocketGateway


func _ready() -> void:
	_config = DEFAULT_CONFIG.duplicate(true) as SssConfig
	_apply_runtime_overrides()
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	_world = SolarSystemWorld.new(_config, seed)
	var authenticator := MockClientAuthenticator.new(seed)
	_gateway = WebSocketGateway.new(_config, authenticator, _world)
	add_child(_gateway)
	var error: Error = _gateway.start()
	if error != OK:
		push_error("No se pudo iniciar el SSS en el puerto %d: %s" % [_config.port, error_string(error)])
		get_tree().quit(1)
		return
	_start_simulation_loop()
	print("SSS_READY protocol=%s port=%d tick_hz=%.1f system_id=%s" % [
		_config.protocol_version,
		_config.port,
		_config.tick_hz,
		_world.system_id,
	])


func _start_simulation_loop() -> void:
	var tick_timer := Timer.new()
	tick_timer.name = "SimulationTick"
	tick_timer.wait_time = 1.0 / _config.tick_hz
	tick_timer.timeout.connect(_on_tick)
	add_child(tick_timer)
	tick_timer.start()


func _on_tick() -> void:
	_world.tick()
	_gateway.flush_pending_deltas()
	_world.acknowledge_changes()


func _apply_runtime_overrides() -> void:
	var environment_port: String = OS.get_environment("SSS_PORT")
	if environment_port.is_valid_int():
		_config.port = clampi(int(environment_port), 1, 65535)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			var raw_port: String = argument.trim_prefix("--port=")
			if raw_port.is_valid_int():
				_config.port = clampi(int(raw_port), 1, 65535)


func _exit_tree() -> void:
	if _gateway != null:
		_gateway.stop()
