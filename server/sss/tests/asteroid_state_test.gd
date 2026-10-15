extends SceneTree

const CONFIG: AsteroidConfig = preload("res://config/default_asteroid_config.tres")
var _failures: int = 0


func _initialize() -> void:
	var config: AsteroidConfig = CONFIG.duplicate(true) as AsteroidConfig
	_check(config.is_valid(), "configuración demo válida")
	var first := AsteroidState.new("a", "system", Vector2i(310, 290), config)
	var second := AsteroidState.new("b", "system", Vector2i(550, 500), config)
	_check(first.remaining_quantity == 10 and first.asteroid_state == "AVAILABLE", "estado inicial")
	_check(first.set_resource_state(7, "actor"), "mutación válida")
	_check(first.asteroid_state == "OCCUPIED", "ocupante determina estado")
	_check(second.remaining_quantity == 10 and second.occupant_entity_id == "", "instancias independientes")
	config.initial_quantity = 100
	config.resource_type = "changed"
	var copy: AsteroidConfig = first.get_configuration()
	copy.initial_quantity = 200
	_check(first.get_configuration().initial_quantity == 10, "configuración externa no altera instancia")
	var full: Dictionary = first.to_add_snapshot()
	_check(full["entity_id"] == "a" and full["kind"] == "asteroid", "identidad serializada")
	_check(full["system_id"] == "system" and full["position"] == [310, 290], "sistema y posición")
	_check(full["resource_type"] == "demo_ore" and full["remaining_quantity"] == 7, "datos separados")
	_check(full["occupant_entity_id"] == "actor", "ocupante serializado")
	full["remaining_quantity"] = 0
	_check(first.remaining_quantity == 7, "snapshot es copia")
	_check(not first.set_resource_state(-1, ""), "rechaza cantidad negativa")
	_check(not first.set_resource_state(11, ""), "rechaza cantidad mayor al depósito")
	_check(not first.set_resource_state(0, "actor"), "agotado no admite ocupante")
	_check(first.remaining_quantity == 7 and first.occupant_entity_id == "actor", "rechazo es atómico")
	_check(first.set_resource_state(7, ""), "libera ocupación")
	var update: Dictionary = first.to_updated_snapshot()
	_check(update["occupant_entity_id"] == null and update["asteroid_state"] == "AVAILABLE", "null limpia ocupante")
	_check(not update.has("resource_type"), "update preserva datos estáticos del cliente")
	_check(first.set_resource_state(0, "") and first.asteroid_state == "DEPLETED", "agotamiento del modelo")
	var legacy: Dictionary = first.to_m2_add_snapshot()
	_check(legacy.keys().size() == 4 and legacy["state"] == "ANCHORED", "forma M2 sin extensión silenciosa")
	_check(not first.to_m2_updated_snapshot().has("remaining_quantity"), "update M2 sin campos nuevos")
	config.mining_range = -1.0
	_check(not config.is_valid(), "configuración inválida detectable")
	print("ASTEROID_STATE_TEST_OK" if _failures == 0 else "ASTEROID_STATE_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("ASTEROID_STATE_TEST_FAILED: %s" % message)
