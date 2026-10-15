extends SceneTree

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
const NEAR: String = "018f0000-0000-7000-8000-000000000007"
const FAR: String = "018f0000-0000-7000-8000-000000000008"
var _failures: int = 0


func _initialize() -> void:
	var seed: MockWorldSeed = SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(CONFIG.duplicate(true) as SssConfig, seed)
	_check(world.entity_registry.get_entity(NEAR) is AsteroidState, "seed usa modelo autoritativo")
	_check(world.entity_registry.get_entity(FAR).position == Vector2i(550, 500), "ID/posición lejanos intactos")
	var snapshot: Dictionary = world.full_snapshot_for(seed.player_id, true)
	_check(_entity(snapshot["added"], NEAR).get("remaining_quantity") == 10, "full con datos de asteroide")
	_check(_entity(snapshot["added"], FAR).is_empty(), "AOI excluye lejano")
	_check(not _entity(world.full_snapshot_for(seed.player_id)["added"], NEAR).has("asteroid_state"), "full M2 preservado")
	var visible: Array[String] = _ids(snapshot)
	world.add_mock_entity("observer", "ship", Vector2i(330, 300), {"player_id": "p2"})
	world.acknowledge_changes()
	var p2_visible: Array[String] = _ids(world.full_snapshot_for("p2", true))
	# Incorporar observer al conjunto p1 como lo haría el gateway tras un added.
	visible.append("observer")
	_check(world.set_asteroid_resource_state(NEAR, 8, seed.entity_id), "actualización sin movimiento")
	_check(world.set_asteroid_resource_state(NEAR, 6, seed.entity_id), "dos cambios mismo tick")
	var delta: Dictionary = world.delta_for_session(seed.player_id, visible, true)
	_check(delta["updated"].size() == 1, "un update por entidad aunque ChangeSet tenga dos")
	_check(_entity(delta["updated"], NEAR)["remaining_quantity"] == 6, "update publica estado final")
	_check(_entity(world.delta_for_session("p2", p2_visible, true)["updated"], NEAR)["remaining_quantity"] == 6, "dos sesiones reciben el mismo cambio")
	_check(world.change_set.updated().size() == 2, "lectura no drena ChangeSet")
	world.acknowledge_changes()
	_check(world.set_asteroid_resource_state(NEAR, 6, seed.entity_id), "estado igual válido")
	_check(not world.change_set.has_changes(), "estado igual no genera update")
	_check(not world.set_asteroid_resource_state(NEAR, -1, ""), "cantidad inválida")
	_check(not world.set_asteroid_resource_state(seed.entity_id, 5, ""), "nave no es asteroide")
	_check(world.set_asteroid_resource_state(NEAR, 6, ""), "liberación")
	_check(_entity(world.delta_for_session(seed.player_id, visible, true)["updated"], NEAR)["occupant_entity_id"] == null, "null explícito en delta")
	world.acknowledge_changes()
	# La entidad NO se mueve: el centro AOI sí. Debe salir NEAR y entrar FAR.
	world.set_entity_position(seed.entity_id, Vector2i(550, 500))
	delta = world.delta_for_session(seed.player_id, visible, true)
	_check(delta["removed"].has(NEAR), "asteroide inmóvil sale al mover observador")
	_check(_entity(delta["added"], FAR).get("remaining_quantity") == 10, "asteroide inmóvil entra completo")
	_check(_entity(delta["updated"], seed.entity_id).get("position") == [550, 500], "nave propia sigue updated")
	_check(world.entity_registry.has(NEAR), "removed AOI no destruye entidad")
	var p2_delta: Dictionary = world.delta_for_session("p2", p2_visible, true)
	_check(not p2_delta.get("removed", []).has(NEAR), "visibilidad independiente por sesión")
	visible = _ids(world.full_snapshot_for(seed.player_id, true))
	world.acknowledge_changes()
	world.set_entity_position(seed.entity_id, Vector2i(300, 300))
	delta = world.delta_for_session(seed.player_id, visible, true)
	_check(_entity(delta["added"], NEAR).get("remaining_quantity") == 6, "reentrada restaura estado actual completo")
	_check(delta["removed"].has(FAR), "salida lejana")
	visible = _ids(world.full_snapshot_for(seed.player_id, true))
	world.acknowledge_changes()
	world.set_entity_position(NEAR, Vector2i(580, 580))
	delta = world.delta_for_session(seed.player_id, visible, true)
	_check(delta["removed"].has(NEAR), "salida por movimiento de entidad")
	world.set_entity_position(NEAR, Vector2i(310, 290))
	world.acknowledge_changes()
	var count: int = world.entity_registry.count()
	world.add_mock_entity(NEAR, "asteroid", Vector2i(1, 1))
	world.add_mock_entity("", "asteroid", Vector2i(1, 1))
	_check(world.entity_registry.count() == count and not world.change_set.has_changes(), "IDs inválidos/duplicados no alteran mundo")
	_check(world.entity_registry.get_entity(NEAR).position == Vector2i(310, 290), "duplicado conserva índice/identidad")
	world.remove_mock_entity(NEAR)
	delta = world.delta_for_session(seed.player_id, visible, true)
	_check(delta["removed"].has(NEAR) and not world.entity_registry.has(NEAR), "eliminación real también removed")
	var reconnect_ids: Array[String] = []
	var restored: Dictionary = world.delta_for_session(seed.player_id, reconnect_ids, true)
	_check(_entity(restored["added"], NEAR).is_empty(), "reconstrucción no inventa eliminado")
	_check(_entity(restored["added"], seed.entity_id).get("kind") == "ship", "reconstrucción completa del AOI")
	print("ASTEROID_WORLD_SYNC_TEST_OK" if _failures == 0 else "ASTEROID_WORLD_SYNC_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _ids(snapshot: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for entity: Dictionary in snapshot["added"]:
		result.append(str(entity["entity_id"]))
	return result


func _entity(entities: Array, entity_id: String) -> Dictionary:
	for entity: Dictionary in entities:
		if str(entity.get("entity_id", "")) == entity_id:
			return entity
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("ASTEROID_WORLD_SYNC_TEST_FAILED: %s" % message)
