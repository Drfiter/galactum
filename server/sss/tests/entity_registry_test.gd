extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	var registry := EntityRegistry.new()

	# 1. add + get_entity
	var e1 := EntityState.new("e1", "ship", Vector2i(10, 20))
	e1.payload = {"display_name": "Test Ship"}
	registry.add(e1)
	var got1: EntityState = registry.get_entity("e1")
	_check(got1 != null, "get_entity devolvió null después de add")
	if got1 != null:
		_check(got1.entity_id == "e1", "entity_id incorrecto")
		_check(got1.kind == "ship", "kind incorrecto")
		_check(got1.position == Vector2i(10, 20), "posición incorrecta")
		_check(got1.payload.get("display_name", "") == "Test Ship", "payload incorrecto")

	# 2. add duplicado no sobrescribe (push_error esperado)
	var e1b := EntityState.new("e1", "ship", Vector2i(99, 99))
	e1b.payload = {"display_name": "Overwrite"}
	registry.add(e1b)
	var got1b: EntityState = registry.get_entity("e1")
	_check(got1b != null and got1b.position == Vector2i(10, 20), "add duplicado sobrescribió la entidad original")

	# 3. has
	_check(registry.has("e1"), "has() devolvió false para entidad existente")
	_check(not registry.has("nope"), "has() devolvió true para entidad inexistente")

	# 4. update
	registry.update("e1", func(e: EntityState) -> void:
		e.position = Vector2i(15, 25)
		e.payload["display_name"] = "Updated"
	)
	var got2: EntityState = registry.get_entity("e1")
	_check(got2 != null and got2.position == Vector2i(15, 25), "update no cambió posición")
	if got2 != null:
		_check(got2.payload.get("display_name", "") == "Updated", "update no cambió payload")

	# update a entidad inexistente es un noop controlado (push_error esperado)
	registry.update("ghost", func(e: EntityState) -> void: e.position = Vector2i(0, 0))

	# 5. erase + get_entity vuelve null
	registry.erase("e1")
	_check(not registry.has("e1"), "erase no eliminó la entidad")
	_check(registry.get_entity("e1") == null, "get_entity devolvió entidad después de erase")

	# 6. all + count + ids sobre registro limpio
	var a := EntityState.new("a", "ship", Vector2i(1, 1))
	var b := EntityState.new("b", "asteroid", Vector2i(2, 2))
	var c := EntityState.new("c", "xenoform", Vector2i(3, 3))
	registry.add(a)
	registry.add(b)
	registry.add(c)
	_check(registry.count() == 3, "count incorrecto: %d" % registry.count())
	var ids: Array[String] = registry.ids()
	_check(ids.size() == 3, "ids size incorrecto")
	var all_e: Array[EntityState] = registry.all()
	_check(all_e.size() == 3, "all size incorrecto")

	# 7. all mantiene orden determinista de inserción
	if all_e.size() == 3:
		_check(all_e[0].entity_id == "a", "orden de all[0] incorrecto: %s" % all_e[0].entity_id)
		_check(all_e[1].entity_id == "b", "orden de all[1] incorrecto: %s" % all_e[1].entity_id)
		_check(all_e[2].entity_id == "c", "orden de all[2] incorrecto: %s" % all_e[2].entity_id)

	if _failures == 0:
		print("ENTITY_REGISTRY_TEST_OK")
		quit(0)
	else:
		print("ENTITY_REGISTRY_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("ENTITY_REGISTRY_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)