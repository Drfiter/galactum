extends SceneTree

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")

var _failures: int = 0


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)

	# --- Sección 1: WorldChangeSet add/update/remove básico ---

	var added_entity := EntityState.new("test_add", "ship", Vector2i(100, 100))
	_check(not world.change_set.has_changes(), "change_set no debería tener cambios al inicio")
	world.change_set.add_entity(added_entity)
	_check(world.change_set.has_changes(), "change_set debería tener cambios después de add_entity")

	var updated_entity := EntityState.new("test_update", "asteroid", Vector2i(200, 200))
	updated_entity.payload = {"hp": 100}
	world.change_set.update_entity(updated_entity, Vector2i(190, 190))

	world.change_set.remove_entity("test_remove", Vector2i(300, 300))

	_check(world.change_set.added().size() == 1, "added debería tener 1 elemento")
	_check(world.change_set.updated().size() == 1, "updated debería tener 1 elemento")
	_check(world.change_set.removed().size() == 1, "removed debería tener 1 elemento")

	# Limpiamos para iniciar pruebas controladas de transiciones
	world.acknowledge_changes()
	_check(not world.change_set.has_changes(), "acknowledge_changes no limpió el changeset")

	# --- Sección 2: Las 4 transiciones AOI por sesión (Jugador en 300, 300, radio 50 => [250, 350]) ---

	# Creamos entidades de prueba iniciales
	world.add_mock_entity("ent_trans", "asteroid", Vector2i(550, 550)) # Inicialmente FUERA del AOI
	world.add_mock_entity("ent_stay_in", "ship", Vector2i(310, 310))    # Inicialmente DENTRO del AOI
	world.add_mock_entity("ent_stay_out", "xenoform", Vector2i(580, 580)) # Inicialmente FUERA del AOI
	world.acknowledge_changes() # Limpiamos cambios de creación

	# Caso 1: outside -> inside => added
	world.set_entity_position("ent_trans", Vector2i(320, 320))
	var d1: Dictionary = world.delta_for(seed.player_id)
	_check(not d1.is_empty(), "d1 debería contener cambios")
	var d1_added: Array = d1.get("added", [])
	_check(d1_added.size() == 1 and str(d1_added[0].get("entity_id", "")) == "ent_trans",
		"Caso 1 (outside -> inside) debe generar added con entidad completa")
	_check(d1.get("updated", []).is_empty(), "Caso 1 no debe generar updated")
	_check(d1.get("removed", []).is_empty(), "Caso 1 no debe generar removed")
	world.acknowledge_changes()

	# Caso 2: inside -> inside => updated
	world.set_entity_position("ent_stay_in", Vector2i(315, 315))
	var d2: Dictionary = world.delta_for(seed.player_id)
	_check(not d2.is_empty(), "d2 debería contener cambios")
	var d2_updated: Array = d2.get("updated", [])
	_check(d2_updated.size() == 1 and str(d2_updated[0].get("entity_id", "")) == "ent_stay_in",
		"Caso 2 (inside -> inside) debe generar updated")
	_check(d2_updated[0].get("position", []) == [315, 315], "Caso 2 debe incluir nueva posición")
	_check(d2.get("added", []).is_empty(), "Caso 2 no debe generar added")
	_check(d2.get("removed", []).is_empty(), "Caso 2 no debe generar removed")
	world.acknowledge_changes()

	# Caso 3: inside -> outside => removed
	world.set_entity_position("ent_trans", Vector2i(550, 550)) # Se mueve de (320, 320) a (550, 550)
	var d3: Dictionary = world.delta_for(seed.player_id)
	_check(not d3.is_empty(), "d3 debería contener cambios")
	var d3_removed: Array = d3.get("removed", [])
	_check(d3_removed.size() == 1 and str(d3_removed[0]) == "ent_trans",
		"Caso 3 (inside -> outside) debe generar removed con solo entity_id")
	_check(d3.get("added", []).is_empty(), "Caso 3 no debe generar added")
	_check(d3.get("updated", []).is_empty(), "Caso 3 no debe generar updated")
	world.acknowledge_changes()

	# Caso 4: outside -> outside => nada
	world.set_entity_position("ent_stay_out", Vector2i(590, 590)) # Se mueve de (580, 580) a (590, 590)
	var d4: Dictionary = world.delta_for(seed.player_id)
	_check(d4.is_empty(), "Caso 4 (outside -> outside) debe generar delta vacío (nada)")
	world.acknowledge_changes()

	# --- Sección 3: Multi-sesión independiente con ChangeSet compartido ---

	# Registramos dos jugadores adicionales con posiciones distintas
	var player2_entity := EntityState.new("ship_p2", "ship", Vector2i(550, 550))
	player2_entity.payload = {"player_id": "player_02", "ship_id": "ship_02"}
	world.entity_registry.add(player2_entity)
	world.spatial_hash.insert("ship_p2", Vector2i(550, 550))

	var player3_entity := EntityState.new("ship_p3", "ship", Vector2i(100, 100))
	player3_entity.payload = {"player_id": "player_03", "ship_id": "ship_03"}
	world.entity_registry.add(player3_entity)
	world.spatial_hash.insert("ship_p3", Vector2i(100, 100))

	# Creamos una entidad móvil que se moverá de la zona de Player 1 (300, 300) a la zona de Player 2 (550, 550)
	world.add_mock_entity("traveler", "asteroid", Vector2i(310, 310))
	world.acknowledge_changes()

	# Movemos 'traveler' de (310, 310) a (540, 540)
	world.set_entity_position("traveler", Vector2i(540, 540))

	# Player 1 (300, 300): traveler estaba DENTRO y ahora está FUERA => removed
	var delta_p1: Dictionary = world.delta_for(seed.player_id)
	_check(not delta_p1.is_empty(), "delta_p1 no debe estar vacío")
	_check(delta_p1.get("removed", []) == ["traveler"],
		"Player 1 debe recibir removed para traveler: %s" % str(delta_p1.get("removed", [])))
	_check(delta_p1.get("added", []).is_empty(), "Player 1 no debe recibir added")
	_check(delta_p1.get("updated", []).is_empty(), "Player 1 no debe recibir updated")

	# Player 2 (550, 550): traveler estaba FUERA y ahora está DENTRO => added
	var delta_p2: Dictionary = world.delta_for("player_02")
	_check(not delta_p2.is_empty(), "delta_p2 no debe estar vacío")
	var p2_added: Array = delta_p2.get("added", [])
	_check(p2_added.size() == 1 and str(p2_added[0].get("entity_id", "")) == "traveler",
		"Player 2 debe recibir added para traveler: %s" % str(p2_added))
	_check(delta_p2.get("removed", []).is_empty(), "Player 2 no debe recibir removed")
	_check(delta_p2.get("updated", []).is_empty(), "Player 2 no debe recibir updated")

	# Player 3 (100, 100): traveler estaba FUERA y sigue FUERA => nada
	var delta_p3: Dictionary = world.delta_for("player_03")
	_check(delta_p3.is_empty(), "Player 3 debe recibir delta vacío (nada)")

	# Comprobamos que el ChangeSet sigue intacto después de todas las lecturas de sesión
	_check(world.change_set.updated().size() == 1,
		"El ChangeSet compartido no debe haberse vaciado ni alterado")

	world.acknowledge_changes()

	if _failures == 0:
		print("WORLD_DELTA_TEST_OK")
		quit(0)
	else:
		print("WORLD_DELTA_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("WORLD_DELTA_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)