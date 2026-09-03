extends SceneTree

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)
	world.tick()
	var snapshot: Dictionary = world.full_snapshot_for(seed.player_id)
	if world.tick_count != 1:
		_fail("el tick autoritativo no avanzo")
		return
	if snapshot.get("map_size", []) != [600, 600]:
		_fail("map_size no es 600x600")
		return
	var entities: Array = snapshot.get("added", [])
	if entities.size() != 1:
		_fail("snapshot no contiene la nave dummy")
		return
	var ship: Dictionary = entities[0]
	if ship.get("player_id", "") != seed.player_id or ship.get("ship_id", "") != seed.ship_id:
		_fail("IDs de la nave no coinciden con el seed")
		return
	if ship.get("entity_id", "") == ship.get("ship_id", ""):
		_fail("entity_id y ship_id deben ser distintos")
		return
	print("SSS_WORLD_TEST_OK tick_hz=%.1f system_id=%s" % [config.tick_hz, world.system_id])
	quit(0)


func _fail(message: String) -> void:
	push_error("SSS_WORLD_TEST_FAILED: %s" % message)
	quit(1)
