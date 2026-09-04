extends SceneTree

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")

var _failures: int = 0


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)
	world.tick()

	var snapshot: Dictionary = world.full_snapshot_for(seed.player_id)

	# full = true
	_check(bool(snapshot.get("full", false)), "full_snapshot no tiene full=true")

	# system_id
	_check(str(snapshot.get("system_id", "")) == seed.system_id, "system_id incorrecto en snapshot")

	# map_size
	var map_size: Array = snapshot.get("map_size", [])
	_check(map_size.size() == 2 and int(map_size[0]) == 600 and int(map_size[1]) == 600,
		"map_size incorrecto en snapshot: %s" % str(map_size))

	# added: múltiples entidades
	var added: Array = snapshot.get("added", [])
	_check(added.size() >= 3, "snapshot no contiene al menos 3 entidades: %d" % added.size())

	# La nave del jugador debe estar en added con IDs correctos
	var found_player: bool = false
	for entity: Dictionary in added:
		if str(entity.get("entity_id", "")) == seed.entity_id:
			found_player = true
			_check(str(entity.get("ship_id", "")) == seed.ship_id, "ship_id incorrecto en snapshot")
			_check(str(entity.get("player_id", "")) == seed.player_id, "player_id incorrecto en snapshot")
			_check(str(entity.get("kind", "")) == "ship", "kind incorrecto para nave jugador")
			_check(entity.get("position", []) == [300, 300], "posición incorrecta para nave jugador")
			break
	_check(found_player, "snapshot no contiene la nave del jugador")

	# other_ship (340, 300) debe estar
	var found_other: bool = false
	for entity: Dictionary in added:
		if str(entity.get("entity_id", "")) == "018f0000-0000-7000-8000-000000000005":
			found_other = true
			_check(str(entity.get("kind", "")) == "ship", "other_ship kind incorrecto")
			_check(entity.get("position", []) == [340, 300], "other_ship posición incorrecta")
			break
	_check(found_other, "snapshot no contiene other_ship")

	# asteroid B (550, 500) NO debe estar (fuera del AOI)
	var found_asteroid_b: bool = false
	for entity: Dictionary in added:
		if str(entity.get("entity_id", "")) == "018f0000-0000-7000-8000-000000000008":
			found_asteroid_b = true
			break
	_check(not found_asteroid_b, "asteroid B (550,500) NO debería estar en el snapshot (fuera del AOI)")

	# updated y removed vacíos
	_check(snapshot.get("updated", []) is Array and snapshot.get("updated", []).size() == 0,
		"updated no es array vacío")
	_check(snapshot.get("removed", []) is Array and snapshot.get("removed", []).size() == 0,
		"removed no es array vacío")

	if _failures == 0:
		print("WORLD_SNAPSHOT_MULTI_TEST_OK")
		quit(0)
	else:
		print("WORLD_SNAPSHOT_MULTI_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("WORLD_SNAPSHOT_MULTI_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)