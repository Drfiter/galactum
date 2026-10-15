extends SceneTree
## Creación válida/atómica, identidad y configuración aislada sin balance oficial.

const CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
var _failures: int = 0


func _initialize() -> void:
	var world := SolarSystemWorld.new(CONFIG.duplicate(true), SEED.duplicate(true))
	if not world.has_method("spawn_xenoform"):
		_check(false, "falta creación autoritativa PvE")
		_finish()
		return
	var script: Script = load("res://pve/xenoform_config.gd")
	var definition: Resource = script.new()
	definition.config_id = "test-definition"
	definition.display_name = "Fixture PvE"
	var first: EntityState = world.call("spawn_xenoform", "pve-1", definition, Vector2i(300, 300))
	var second: EntityState = world.call("spawn_xenoform", "pve-2", definition, Vector2i(320, 300))
	_check(first != null and second != null, "dos instancias creadas")
	_check(first.entity_id == "pve-1" and second.entity_id == "pve-2", "identidad de instancia distinta de config")
	_check(first.kind == "xenoform" and first.state == "IDLE", "tipo y estado técnico")
	_check(world.entity_registry.get_entity("pve-1") == first and world.spatial_hash.has("pve-1"), "registro e índice contienen misma instancia")
	var visible: Dictionary = first.to_add_snapshot()
	_check(visible["xenoform"] == {"config_id": "test-definition"}, "config visible separada de identidad")
	_check(visible["system_id"] == SEED.system_id and visible["position"] == [300, 300], "sistema y posición autoritativos")
	_check(not visible.has("player_id") and not visible.has("ship_id") and not visible.has("energy_cost") and not visible.has("travel"), "whitelist sin ownership, energía o viaje")
	visible["xenoform"]["config_id"] = "local-only"
	first.payload["energy_cost"] = 999
	_check(first.to_add_snapshot()["xenoform"]["config_id"] == "test-definition" and not first.to_add_snapshot().has("energy_cost"), "serialización anidada aislada y payload interno no filtrado")
	definition.display_name = "Changed source"
	var copy: Resource = first.call("get_configuration")
	copy.display_name = "Changed copy"
	_check(first.to_add_snapshot()["display_name"] == "Fixture PvE" and second.to_add_snapshot()["display_name"] == "Fixture PvE", "configuración fuente/copia no muta instancias")
	world.set_entity_position("pve-1", Vector2i(301, 302))
	_check(first.position == Vector2i(301, 302) and second.position == Vector2i(320, 300), "estado mutable por instancia")
	world.acknowledge_changes()
	world.set_entity_position("pve-1", Vector2i(600, 302))
	_check(first.position == Vector2i(301, 302) and not world.change_set.has_changes(), "update fuera del mapa no altera posición ni changeset")
	_check(first.call("get_configuration").has_energy_cost == false, "sin tabla energética predeterminada")
	definition.has_energy_cost = true
	definition.energy_cost = 37 # Valor artificial de prueba; no balance.
	var configured: EntityState = world.call("spawn_xenoform", "energy-test", definition, Vector2i(0, 0))
	_check(configured.call("get_configuration").energy_cost == 37, "costo configurable sin aplicarlo")
	var before_count: int = world.entity_registry.all().size()
	world.acknowledge_changes()
	_check(world.call("spawn_xenoform", "pve-1", definition, Vector2i(500, 500)) == null, "duplicado rechazado")
	_check(first.position == Vector2i(301, 302), "duplicado no altera índice/posición")
	_check(world.call("spawn_xenoform", "", definition, Vector2i.ZERO) == null, "ID vacío rechazado")
	_check(world.call("spawn_xenoform", "outside", definition, Vector2i(600, 0)) == null, "límite superior rechazado")
	_check(world.call("spawn_xenoform", "negative", definition, Vector2i(-1, 0)) == null, "posición negativa rechazada")
	_check(world.call("spawn_xenoform", "null-config", null, Vector2i.ZERO) == null, "config ausente rechazada")
	definition.energy_cost = 0
	_check(world.call("spawn_xenoform", "invalid-energy", definition, Vector2i.ZERO) == null, "costo activo no positivo rechazado")
	definition.config_id = ""
	definition.energy_cost = 37
	_check(world.call("spawn_xenoform", "invalid-definition", definition, Vector2i.ZERO) == null, "config ID vacío rechazado")
	definition.config_id = "test-definition"
	definition.display_name = " "
	_check(world.call("spawn_xenoform", "invalid-name", definition, Vector2i.ZERO) == null, "nombre vacío rechazado")
	definition.display_name = "Fixture PvE"
	_check(world.entity_registry.all().size() == before_count and not world.change_set.has_changes(), "rechazos no dejan estado parcial ni deltas")
	_check(world.call("remove_xenoform", "pve-1"), "retirada explícita")
	_check(not world.spatial_hash.has("pve-1") and world.entity_registry.get_entity("pve-1") == null, "retirada limpia registro e índice")
	_check(not world.call("remove_xenoform", "pve-1") and not world.call("remove_xenoform", SEED.entity_id), "retirada repetida o de nave no afecta mundo")
	definition.config_id = "test-definition"
	definition.energy_cost = 37
	_check(world.call("spawn_xenoform", "pve-1", definition, Vector2i.ZERO) == null, "ID retirado no se recicla durante ejecución")
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_XENOFORM_CREATION_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("M3_XENOFORM_CREATION_TEST_OK" if _failures == 0 else "M3_XENOFORM_CREATION_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
