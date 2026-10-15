extends SceneTree
## Enemigo inmóvil con observador que viaja; removed no destruye el objetivo.

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
var _failures: int = 0
var _now: int = 10000000


func _initialize() -> void:
	var world := SolarSystemWorld.new(CONFIG.duplicate(true), SEED.duplicate(true))
	world.set_now_provider(func() -> int: return _now)
	var enemy_id: String = "018f0000-0000-7000-8000-000000000009"
	var replica: RefCounted = preload("res://tests/support/aoi_test_replica.gd").new(world.full_snapshot_for(SEED.player_id))
	world.start_travel(SEED.player_id, Vector2i(500, 500))
	var ship: EntityState = world.entity_registry.get_entity(SEED.entity_id)
	var start_delta: Dictionary = world.delta_for(SEED.player_id, replica.known_ids)
	_check(start_delta["added"].is_empty() and start_delta["updated"].size() == 1, "inicio sigue siendo updated de nave conocida")
	_check(start_delta["updated"][0]["state"] == "TRAVELING", "confirmación M2 conservada")
	world.acknowledge_changes()
	_now += 6000
	world.tick()
	var mid_delta: Dictionary = world.delta_for(SEED.player_id, replica.known_ids)
	_check(mid_delta["updated"].size() == 1 and mid_delta["updated"][0]["position"] == [301, 301], "posición de viaje M2 derivada y sincronizada")
	_check(mid_delta["updated"][0]["travel"]["origin"] == [300, 300] and mid_delta["updated"][0]["travel"]["destination"] == [500, 500], "trayectoria M2 completa durante viaje")
	world.acknowledge_changes()
	_now = int(ship.travel["arrive_ts"])
	world.tick()
	var delta: Dictionary = world.delta_for(SEED.player_id, replica.known_ids)
	replica.apply(delta)
	_check(delta.get("removed", []).has(enemy_id), "observador móvil debe retirar enemigo inmóvil de réplica")
	_check(world.entity_registry.get_entity(enemy_id) != null, "salir del AOI no destruye entidad")
	_check(not replica.known_ids.has(enemy_id), "baseline visible retira objetivo")
	_check(delta["updated"][0]["state"] == "ANCHORED" and delta["updated"][0]["travel"] == null, "llegada M2 limpia travel sin re-added")
	world.acknowledge_changes()
	world.start_travel(SEED.player_id, Vector2i(300, 300))
	_now = int(ship.travel["arrive_ts"])
	world.tick()
	delta = world.delta_for(SEED.player_id, replica.known_ids)
	var added_ids: Array[String] = []
	for entity: Dictionary in delta["added"]:
		added_ids.append(str(entity["entity_id"]))
	_check(added_ids.has(enemy_id), "observador vuelve y recibe added del estacionario")
	replica.apply(delta)
	world.acknowledge_changes()
	_check(world.delta_for(SEED.player_id, replica.known_ids).is_empty(), "sin cambios no repite entidades")
	var older_connection: Array[String] = [SEED.entity_id]
	_check(not world.delta_for(SEED.player_id, older_connection)["added"].is_empty(), "otra conexión del mismo jugador conserva baseline independiente")
	_check(world.delta_for(SEED.player_id, replica.known_ids).is_empty(), "leer otra sesión no modifica baseline existente")
	world.set_entity_position(enemy_id, Vector2i(350, 350))
	delta = world.delta_for(SEED.player_id, replica.known_ids)
	_check(delta["removed"].is_empty() and delta["updated"].size() == 1, "borde inclusivo del AOI conservado")
	world.acknowledge_changes()
	world.set_entity_position(enemy_id, Vector2i(351, 350))
	delta = world.delta_for(SEED.player_id, replica.known_ids)
	_check(delta["removed"] == [enemy_id], "salida por posición genera removed")
	replica.apply(delta)
	world.acknowledge_changes()
	world.call("remove_xenoform", enemy_id)
	_check(world.delta_for(SEED.player_id, replica.known_ids).is_empty(), "retirada fuera del AOI no informa baja desconocida")
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_XENOFORM_AOI_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("M3_XENOFORM_AOI_TEST_OK" if _failures == 0 else "M3_XENOFORM_AOI_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
