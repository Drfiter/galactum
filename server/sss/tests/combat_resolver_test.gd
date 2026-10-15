extends SceneTree
## TEAM3-M3: casos canónicos del resolver provisional, puro y determinista.

const DEFAULT_RULES: CombatRules = preload("res://config/default_combat_rules.tres")

var _failures: int = 0


func _initialize() -> void:
	_test_canonical_simultaneous_damage()
	_test_input_order_does_not_change_result()
	_test_equal_remaining_power_is_draw()
	_test_partial_damage_does_not_remove_a_unit()
	_test_inputs_are_not_mutated()
	_test_invalid_rules_are_rejected()
	_test_invalid_participants_are_rejected()
	_finish()


func _test_canonical_simultaneous_damage() -> void:
	var attacker := _participant("attacker", [
		CombatUnitStack.new("mock_unit_alpha", 3),
	])
	var defender := _participant("defender", [
		CombatUnitStack.new("mock_unit_beta", 2),
	])

	var result: CombatResolution = CombatResolver.resolve(attacker, defender, _rules())

	_check(result.ok, "el combate canónico debe resolverse")
	_check(result.combat_version == "m3-provisional-1", "el resultado conserva combat_version")
	_check(result.outcome == CombatResolution.OUTCOME_DEFENDER_WIN, "la fuerza restante del defensor debe ganar")
	_check(_quantity(result.attacker_casualties, "mock_unit_alpha") == 2, "el atacante pierde dos unidades alpha")
	_check(_quantity(result.defender_casualties, "mock_unit_beta") == 1, "el defensor pierde una unidad beta")
	_check(_quantity(result.attacker_remaining, "mock_unit_alpha") == 1, "queda una unidad atacante")
	_check(_quantity(result.defender_remaining, "mock_unit_beta") == 1, "queda una unidad defensora")


func _test_input_order_does_not_change_result() -> void:
	var attacker_a := _participant("attacker", [
		CombatUnitStack.new("mock_unit_alpha", 4),
		CombatUnitStack.new("mock_unit_beta", 2),
	])
	var attacker_b := _participant("attacker", [
		CombatUnitStack.new("mock_unit_beta", 2),
		CombatUnitStack.new("mock_unit_alpha", 4),
	])
	var defender := _participant("defender", [
		CombatUnitStack.new("mock_unit_beta", 3),
		CombatUnitStack.new("mock_unit_alpha", 1),
	])

	var first: CombatResolution = CombatResolver.resolve(attacker_a, defender, _rules())
	var second: CombatResolution = CombatResolver.resolve(attacker_b, defender, _rules())

	_check(first.ok and second.ok, "ambos órdenes de entrada deben ser válidos")
	_check(first.to_dictionary() == second.to_dictionary(), "el orden de entrada no debe alterar el resultado")
	_check(_is_sorted(first.attacker_remaining),
		"los stacks atacantes de salida deben quedar canonicalizados")
	_check(_is_sorted(first.defender_remaining),
		"los stacks defensores de salida deben quedar canonicalizados")


func _test_equal_remaining_power_is_draw() -> void:
	var attacker := _participant("attacker", [CombatUnitStack.new("mock_unit_alpha", 2)])
	var defender := _participant("defender", [CombatUnitStack.new("mock_unit_alpha", 2)])

	var result: CombatResolution = CombatResolver.resolve(attacker, defender, _rules())

	_check(result.ok, "el empate debe resolverse")
	_check(result.outcome == CombatResolution.OUTCOME_DRAW, "fuerza restante igual debe ser empate")
	_check(_quantity(result.attacker_casualties, "mock_unit_alpha") == 1, "el daño se aplica simultáneamente al atacante")
	_check(_quantity(result.defender_casualties, "mock_unit_alpha") == 1, "el daño se aplica simultáneamente al defensor")


func _test_partial_damage_does_not_remove_a_unit() -> void:
	var rules := CombatRules.new()
	rules.combat_version = "partial-damage-test"
	rules.unit_definitions.append(CombatUnitDefinition.new("mock_unit_alpha", 1, 10))
	var attacker := _participant("attacker", [CombatUnitStack.new("mock_unit_alpha", 1)])
	var defender := _participant("defender", [CombatUnitStack.new("mock_unit_alpha", 1)])

	var result: CombatResolution = CombatResolver.resolve(attacker, defender, rules)

	_check(result.ok, "la configuración de daño parcial debe ser válida")
	_check(result.attacker_casualties.is_empty() and result.defender_casualties.is_empty(),
		"daño menor a durability no debe redondear una baja")
	_check(result.outcome == CombatResolution.OUTCOME_DRAW, "fuerzas intactas e iguales empatan")


func _test_inputs_are_not_mutated() -> void:
	var attacker := _participant("attacker", [
		CombatUnitStack.new("mock_unit_beta", 1),
		CombatUnitStack.new("mock_unit_alpha", 2),
	])
	var defender := _participant("defender", [CombatUnitStack.new("mock_unit_alpha", 2)])
	var rules := _rules()
	var original_first_type: String = attacker.units[0].unit_type_id
	var original_first_quantity: int = attacker.units[0].quantity
	var original_rule_attack: int = rules.unit_definitions[0].attack

	CombatResolver.resolve(attacker, defender, rules)

	_check(attacker.units[0].unit_type_id == original_first_type, "el resolver no reordena el input")
	_check(attacker.units[0].quantity == original_first_quantity, "el resolver no cambia cantidades de entrada")
	_check(rules.unit_definitions[0].attack == original_rule_attack, "el resolver no muta configuración")


func _test_invalid_rules_are_rejected() -> void:
	var participant := _participant("attacker", [CombatUnitStack.new("mock_unit_alpha", 1)])
	var missing_version := _rules()
	missing_version.combat_version = ""
	var missing_version_result: CombatResolution = CombatResolver.resolve(participant, participant, missing_version)
	_check(not missing_version_result.ok
		and missing_version_result.error_code == CombatResolution.ERROR_INVALID_RULES,
		"combat_version vacío debe rechazarse")

	var duplicate_rules := CombatRules.new()
	duplicate_rules.combat_version = "duplicate-test"
	duplicate_rules.unit_definitions.append(CombatUnitDefinition.new("mock_unit_alpha", 1, 1))
	duplicate_rules.unit_definitions.append(CombatUnitDefinition.new("mock_unit_alpha", 2, 2))
	var duplicate_result: CombatResolution = CombatResolver.resolve(participant, participant, duplicate_rules)
	_check(not duplicate_result.ok and duplicate_result.error_code == CombatResolution.ERROR_INVALID_RULES,
		"tipos duplicados en configuración deben rechazarse")

	var invalid_stat_rules := CombatRules.new()
	invalid_stat_rules.combat_version = "invalid-stat-test"
	invalid_stat_rules.unit_definitions.append(CombatUnitDefinition.new("mock_unit_alpha", 0, 1))
	var invalid_stat_result: CombatResolution = CombatResolver.resolve(participant, participant, invalid_stat_rules)
	_check(not invalid_stat_result.ok and invalid_stat_result.error_code == CombatResolution.ERROR_INVALID_RULES,
		"attack no positivo debe rechazarse")


func _test_invalid_participants_are_rejected() -> void:
	var valid := _participant("valid", [CombatUnitStack.new("mock_unit_alpha", 1)])
	var unknown := _participant("unknown", [CombatUnitStack.new("not_configured", 1)])
	var unknown_result: CombatResolution = CombatResolver.resolve(unknown, valid, _rules())
	_check(not unknown_result.ok
		and unknown_result.error_code == CombatResolution.ERROR_INVALID_PARTICIPANT,
		"unit_type_id desconocido debe rechazarse")

	var negative := _participant("negative", [CombatUnitStack.new("mock_unit_alpha", -1)])
	var negative_result: CombatResolution = CombatResolver.resolve(negative, valid, _rules())
	_check(not negative_result.ok
		and negative_result.error_code == CombatResolution.ERROR_INVALID_PARTICIPANT,
		"cantidad negativa debe rechazarse")

	var duplicate := _participant("duplicate", [
		CombatUnitStack.new("mock_unit_alpha", 1),
		CombatUnitStack.new("mock_unit_alpha", 1),
	])
	var duplicate_result: CombatResolution = CombatResolver.resolve(duplicate, valid, _rules())
	_check(not duplicate_result.ok
		and duplicate_result.error_code == CombatResolution.ERROR_INVALID_PARTICIPANT,
		"stacks duplicados deben rechazarse en vez de combinarse implícitamente")


func _rules() -> CombatRules:
	return DEFAULT_RULES.duplicate(true) as CombatRules


func _participant(label: String, stacks: Array[CombatUnitStack]) -> CombatParticipantSnapshot:
	return CombatParticipantSnapshot.new(
		"entity-%s" % label,
		"ship-%s" % label,
		"player-%s" % label,
		"ship",
		stacks,
	)


func _quantity(stacks: Array[CombatUnitStack], unit_type_id: String) -> int:
	for stack: CombatUnitStack in stacks:
		if stack.unit_type_id == unit_type_id:
			return stack.quantity
	return 0


func _is_sorted(stacks: Array[CombatUnitStack]) -> bool:
	for index: int in range(1, stacks.size()):
		if stacks[index - 1].unit_type_id > stacks[index].unit_type_id:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("COMBAT_RESOLVER_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("COMBAT_RESOLVER_TEST_OK" if _failures == 0 else "COMBAT_RESOLVER_TEST_FAILED failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)
