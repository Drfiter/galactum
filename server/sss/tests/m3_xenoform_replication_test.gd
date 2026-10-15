extends SceneTree
## Snapshot, delta y reconstrucción a partir del contrato, sin UI ni Combat.

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
var _failures: int = 0


func _initialize() -> void:
	var world := SolarSystemWorld.new(CONFIG.duplicate(true), SEED.duplicate(true))
	if not world.has_method("spawn_xenoform"):
		_check(false, "falta entidad tipada y sincronización PvE")
		_finish()
		return
	var snapshot: Dictionary = world.full_snapshot_for(SEED.player_id)
	var known: Array[String] = _ids(snapshot["added"])
	_check(snapshot["full"] and snapshot["updated"].is_empty() and snapshot["removed"].is_empty(), "sobre de snapshot")
	var demo: EntityState = world.entity_registry.get_entity("018f0000-0000-7000-8000-000000000009")
	_check(demo != null and demo.has_method("get_configuration"), "seed instancia Xenoform real")
	_check(known.count(demo.entity_id) == 1 and not world.change_set.has_changes(), "bootstrap sin duplicar fixture ni dejar cambios")
	var definition: Resource = demo.call("get_configuration")
	var enemy: EntityState = world.call("spawn_xenoform", "runtime-pve", definition, Vector2i(330, 320))
	var delta: Dictionary = world.call("delta_for", SEED.player_id, known)
	_check(_ids(delta["added"]) == ["runtime-pve"], "creación después del snapshot produce added")
	_check(delta["added"][0]["xenoform"]["config_id"] == definition.config_id, "alta completa con definición")
	var replica: Dictionary = {}
	for entity: Dictionary in snapshot["added"]:
		replica[entity["entity_id"]] = entity.duplicate(true)
	_apply(replica, delta)
	known.append("runtime-pve")
	_check(world.change_set.has_changes(), "leer delta no drena changeset")
	world.acknowledge_changes()
	world.set_entity_position("runtime-pve", Vector2i(331, 321))
	world.set_entity_position("runtime-pve", Vector2i(332, 322))
	delta = world.call("delta_for", SEED.player_id, known)
	_check(delta["updated"].size() == 1 and delta["added"].is_empty(), "actualizaciones múltiples se publican una vez por ID")
	_check(delta["updated"][0]["position"] == [332, 322] and delta["updated"][0]["state"] == "IDLE", "último estado autoritativo")
	_check(delta["updated"][0]["xenoform"] == {"config_id": definition.config_id}, "update incluye bloque específico completo")
	_check(not delta["updated"][0].has("travel"), "update PvE no expone viaje")
	_apply(replica, delta)
	_check(replica["runtime-pve"] == enemy.to_add_snapshot(), "réplica reconstruida equivale al snapshot actual")
	world.acknowledge_changes()
	world.call("remove_xenoform", "runtime-pve")
	delta = world.call("delta_for", SEED.player_id, known)
	_check(delta["removed"] == ["runtime-pve"] and delta["updated"].is_empty() and delta["added"].is_empty(), "removed sólo identifica baja visible")
	_apply(replica, delta)
	known.erase("runtime-pve")
	_check(not replica.has("runtime-pve"), "removed elimina réplica")
	world.acknowledge_changes()
	world.call("spawn_xenoform", "brief-pve", definition, Vector2i(300, 300))
	world.call("remove_xenoform", "brief-pve")
	_check(world.call("delta_for", SEED.player_id, known).is_empty(), "alta/baja antes de publicar no deja fantasma")
	var rebuilt: Dictionary = world.full_snapshot_for(SEED.player_id)
	_check(_ids(rebuilt["added"]) == _ids(snapshot["added"]), "snapshot posterior reconstruye sólo entidades existentes")
	_check(rebuilt["added"] == snapshot["added"], "config y estado completo preservados tras reconstrucción")
	_finish()


func _ids(entities: Array) -> Array[String]:
	var ids: Array[String] = []
	for entity: Dictionary in entities:
		ids.append(str(entity["entity_id"]))
	return ids


func _apply(replica: Dictionary, delta: Dictionary) -> void:
	for entity: Dictionary in delta["added"]:
		replica[entity["entity_id"]] = entity.duplicate(true)
	for entity: Dictionary in delta["updated"]:
		for key: Variant in entity:
			replica[entity["entity_id"]][key] = entity[key]
	for entity_id: String in delta["removed"]:
		replica.erase(entity_id)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_XENOFORM_REPLICATION_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("M3_XENOFORM_REPLICATION_TEST_OK" if _failures == 0 else "M3_XENOFORM_REPLICATION_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
