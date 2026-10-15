extends SceneTree
## Frontera de datos PvE para Combat: copias actuales sin escenas ni resolver.

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
var _failures: int = 0


func _initialize() -> void:
	var world := SolarSystemWorld.new(CONFIG.duplicate(true), SEED.duplicate(true))
	if not world.has_method("get_xenoform_target"):
		_check(false, "falta consulta desacoplada get_xenoform_target")
		_finish()
		return
	_test_target_data_and_isolation(world)
	_test_visibility_and_absence(world)
	_finish()


func _test_target_data_and_isolation(world: SolarSystemWorld) -> void:
	var definition := XenoformConfig.new()
	definition.config_id = "target-fixture"
	definition.display_name = "Target fixture"
	definition.has_energy_cost = true
	definition.energy_cost = 17 # Valor técnico de test, sin tabla de balance.
	world.spawn_xenoform("target-1", definition, Vector2i(310, 320))
	world.acknowledge_changes()
	var target: Dictionary = world.call("get_xenoform_target", "target-1")
	var expected: Dictionary = {
		"entity_id": "target-1", "kind": "xenoform", "system_id": SEED.system_id,
		"position": [310, 320], "state": "IDLE",
		"config_id": "target-fixture", "energy_cost": 17,
	}
	_check(target == expected, "frontera estable entrega sólo datos mínimos acordados")
	target["position"][0] = 1
	target["config_id"] = "changed"
	target["energy_cost"] = 999
	definition.energy_cost = 29
	_check(world.call("get_xenoform_target", "target-1") == expected,
		"consumidor y Resource fuente no alteran objetivo ni configuración autoritativa")
	world.set_entity_position("target-1", Vector2i(330, 340))
	var current: Dictionary = world.call("get_xenoform_target", "target-1")
	_check(current["position"] == [330, 340] and current["energy_cost"] == 17,
		"consulta renueva posición autoritativa y conserva configuración de instancia")
	_check(target["position"] == [1, 320], "copia anterior no se actualiza por referencia")
	world.spawn_xenoform("target-2", definition, Vector2i(315, 320))
	var configured: Dictionary = world.call("get_xenoform_target", "target-2")
	_check(configured["energy_cost"] == 29, "otra configuración usa su costo sin tabla hardcodeada")
	definition.has_energy_cost = false
	definition.energy_cost = 777
	world.spawn_xenoform("target-3", definition, Vector2i(315, 325))
	var unconfigured: Dictionary = world.call("get_xenoform_target", "target-3")
	_check(unconfigured.has("energy_cost") and unconfigured["energy_cost"] == null,
		"costo deshabilitado es desconocido, no cero ni valor residual")
	world.acknowledge_changes()
	world.call("get_xenoform_target", "target-1")
	_check(not world.change_set.has_changes(), "consultar no publica cambios ni inicia interacción")
	var snapshot: Dictionary = world.full_snapshot_for(SEED.player_id)
	for entity: Dictionary in snapshot["added"]:
		_check(not entity.has("energy_cost"), "frontera interna no filtra configuración al contrato de red")


func _test_visibility_and_absence(world: SolarSystemWorld) -> void:
	_check(world.call("get_xenoform_target", "") == {}, "ID vacío devuelve ausencia")
	_check(world.call("get_xenoform_target", "missing") == {}, "ID inexistente devuelve ausencia")
	_check(world.call("get_xenoform_target", SEED.entity_id) == {}, "nave no es objetivo PvE")
	world.add_mock_entity("legacy-xeno", "xenoform", Vector2i(300, 300))
	_check(world.call("get_xenoform_target", "legacy-xeno") == {}, "kind histórico sin modelo tipado no inventa configuración")
	var known: Array[String] = world.visible_entity_ids_for(SEED.player_id)
	_check(known.has("target-1"), "fixture empieza visible")
	world.set_entity_position("target-1", Vector2i(500, 500))
	var delta: Dictionary = world.delta_for(SEED.player_id, known)
	_check(delta["removed"].has("target-1"), "salida AOI retira réplica visible")
	var outside: Dictionary = world.call("get_xenoform_target", "target-1")
	_check(outside["entity_id"] == "target-1" and outside["position"] == [500, 500],
		"SSS conserva consulta global fuera de AOI; removed no significa muerte")
	_check(not world.visible_entity_ids_for(SEED.player_id).has("target-1"), "consulta no altera AOI")
	world.remove_xenoform("target-1")
	_check(world.call("get_xenoform_target", "target-1") == {}, "retirada real invalida consulta por ID")
	_check(outside["entity_id"] == "target-1", "dato retenido es copia histórica, requiere reconsulta antes de resolver")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_XENOFORM_TARGET_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("M3_XENOFORM_TARGET_TEST_OK" if _failures == 0 else "M3_XENOFORM_TARGET_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
