extends SceneTree
## TEAM3-M3: invariantes exhaustivas del resolver provisional sin aleatoriedad.

const DEFAULT_RULES: CombatRules = preload("res://config/default_combat_rules.tres")

var _failures: int = 0


func _initialize() -> void:
	var rules: CombatRules = DEFAULT_RULES.duplicate(true) as CombatRules
	for attacker_quantity: int in range(0, 9):
		for defender_quantity: int in range(0, 9):
			_check_pair(attacker_quantity, defender_quantity, rules)
	_finish()


func _check_pair(attacker_quantity: int, defender_quantity: int, rules: CombatRules) -> void:
	var attacker := _participant("attacker", attacker_quantity)
	var defender := _participant("defender", defender_quantity)
	var first: CombatResolution = CombatResolver.resolve(attacker, defender, rules)
	var second: CombatResolution = CombatResolver.resolve(attacker, defender, rules)

	_check(first.ok, "todas las cantidades no negativas deben ser válidas")
	_check(first.to_dictionary() == second.to_dictionary(),
		"mismo input y configuración deben producir el mismo resultado")
	var attacker_casualties: int = _total(first.attacker_casualties)
	var defender_casualties: int = _total(first.defender_casualties)
	var attacker_remaining: int = _total(first.attacker_remaining)
	var defender_remaining: int = _total(first.defender_remaining)
	_check(attacker_casualties >= 0 and attacker_casualties <= attacker_quantity,
		"bajas atacantes deben estar dentro del stack original")
	_check(defender_casualties >= 0 and defender_casualties <= defender_quantity,
		"bajas defensoras deben estar dentro del stack original")
	_check(attacker_casualties + attacker_remaining == attacker_quantity,
		"las unidades atacantes se conservan entre bajas y restantes")
	_check(defender_casualties + defender_remaining == defender_quantity,
		"las unidades defensoras se conservan entre bajas y restantes")


func _participant(label: String, quantity: int) -> CombatParticipantSnapshot:
	var stacks: Array[CombatUnitStack] = []
	stacks.append(CombatUnitStack.new("mock_unit_alpha", quantity))
	return CombatParticipantSnapshot.new(
		"entity-%s" % label,
		"ship-%s" % label,
		"player-%s" % label,
		"ship",
		stacks,
	)


func _total(stacks: Array[CombatUnitStack]) -> int:
	var total: int = 0
	for stack: CombatUnitStack in stacks:
		total += stack.quantity
	return total


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("COMBAT_RESOLVER_PROPERTIES_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("COMBAT_RESOLVER_PROPERTIES_TEST_OK" if _failures == 0
		else "COMBAT_RESOLVER_PROPERTIES_TEST_FAILED failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)
