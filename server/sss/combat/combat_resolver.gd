class_name CombatResolver
extends RefCounted
## PROVISIONAL M3: resolver puro de daño simultáneo para la prueba técnica.
## No representa el balance definitivo de Galactum y no realiza I/O ni usa azar.


static func resolve(
		attacker: CombatParticipantSnapshot,
		defender: CombatParticipantSnapshot,
		rules: CombatRules,
) -> CombatResolution:
	var rules_error: String = _validate_rules(rules)
	if not rules_error.is_empty():
		return CombatResolution.failure(CombatResolution.ERROR_INVALID_RULES, rules_error)

	var attacker_error: String = _validate_participant(attacker, rules, "attacker")
	if not attacker_error.is_empty():
		return CombatResolution.failure(CombatResolution.ERROR_INVALID_PARTICIPANT, attacker_error)
	var defender_error: String = _validate_participant(defender, rules, "defender")
	if not defender_error.is_empty():
		return CombatResolution.failure(CombatResolution.ERROR_INVALID_PARTICIPANT, defender_error)

	var attacker_units: Array[CombatUnitStack] = _canonical_stacks(attacker.units)
	var defender_units: Array[CombatUnitStack] = _canonical_stacks(defender.units)
	var attacker_damage: int = _attack_power(attacker_units, rules)
	var defender_damage: int = _attack_power(defender_units, rules)

	var result := CombatResolution.new()
	result.ok = true
	result.combat_version = rules.combat_version
	# Ambos daños parten de los snapshots iniciales: las bajas de un lado no
	# reducen el daño que ese lado inflige durante esta resolución simultánea.
	_resolve_incoming_damage(
		attacker_units,
		defender_damage,
		rules,
		result.attacker_casualties,
		result.attacker_remaining,
	)
	_resolve_incoming_damage(
		defender_units,
		attacker_damage,
		rules,
		result.defender_casualties,
		result.defender_remaining,
	)

	var attacker_remaining_power: int = _attack_power(result.attacker_remaining, rules)
	var defender_remaining_power: int = _attack_power(result.defender_remaining, rules)
	if attacker_remaining_power > defender_remaining_power:
		result.outcome = CombatResolution.OUTCOME_ATTACKER_WIN
	elif defender_remaining_power > attacker_remaining_power:
		result.outcome = CombatResolution.OUTCOME_DEFENDER_WIN
	else:
		result.outcome = CombatResolution.OUTCOME_DRAW
	return result


static func _validate_rules(rules: CombatRules) -> String:
	if rules == null:
		return "Combat rules are required"
	if rules.combat_version.strip_edges().is_empty():
		return "combat_version is required"
	var known_types: Dictionary = {}
	for definition: CombatUnitDefinition in rules.unit_definitions:
		if definition == null:
			return "Unit definitions cannot contain null"
		var unit_type_id: String = definition.unit_type_id.strip_edges()
		if unit_type_id.is_empty():
			return "unit_type_id is required"
		if known_types.has(unit_type_id):
			return "Duplicate unit_type_id: %s" % unit_type_id
		if definition.attack <= 0:
			return "attack must be positive for %s" % unit_type_id
		if definition.durability <= 0:
			return "durability must be positive for %s" % unit_type_id
		known_types[unit_type_id] = true
	return ""


static func _validate_participant(
		participant: CombatParticipantSnapshot,
		rules: CombatRules,
		role: String,
) -> String:
	if participant == null:
		return "%s participant is required" % role
	if participant.entity_id.strip_edges().is_empty():
		return "%s entity_id is required" % role
	if participant.kind.strip_edges().is_empty():
		return "%s kind is required" % role
	if participant.kind == "ship":
		if participant.ship_id.strip_edges().is_empty():
			return "%s ship_id is required for a ship" % role
		if participant.player_id.strip_edges().is_empty():
			return "%s player_id is required for a ship" % role

	var known_stacks: Dictionary = {}
	for stack: CombatUnitStack in participant.units:
		if stack == null:
			return "%s units cannot contain null" % role
		var unit_type_id: String = stack.unit_type_id.strip_edges()
		if unit_type_id.is_empty():
			return "%s unit_type_id is required" % role
		if stack.quantity < 0:
			return "%s quantity cannot be negative for %s" % [role, unit_type_id]
		if known_stacks.has(unit_type_id):
			return "%s has duplicate stack %s" % [role, unit_type_id]
		if rules.definition_for(unit_type_id) == null:
			return "%s uses unknown unit_type_id %s" % [role, unit_type_id]
		known_stacks[unit_type_id] = true
	return ""


static func _canonical_stacks(stacks: Array[CombatUnitStack]) -> Array[CombatUnitStack]:
	var canonical: Array[CombatUnitStack] = []
	for stack: CombatUnitStack in stacks:
		if stack.quantity > 0:
			canonical.append(stack.copy())
	canonical.sort_custom(func(a: CombatUnitStack, b: CombatUnitStack) -> bool:
		return a.unit_type_id < b.unit_type_id
	)
	return canonical


static func _attack_power(stacks: Array[CombatUnitStack], rules: CombatRules) -> int:
	var power: int = 0
	for stack: CombatUnitStack in stacks:
		var definition: CombatUnitDefinition = rules.definition_for(stack.unit_type_id)
		power += stack.quantity * definition.attack
	return power


static func _resolve_incoming_damage(
		stacks: Array[CombatUnitStack],
		incoming_damage: int,
		rules: CombatRules,
		casualties: Array[CombatUnitStack],
		remaining: Array[CombatUnitStack],
) -> void:
	var damage_left: int = incoming_damage
	for stack: CombatUnitStack in stacks:
		var definition: CombatUnitDefinition = rules.definition_for(stack.unit_type_id)
		var removable: int = int(damage_left / definition.durability)
		var casualty_quantity: int = mini(stack.quantity, removable)
		if casualty_quantity > 0:
			casualties.append(CombatUnitStack.new(stack.unit_type_id, casualty_quantity))
			damage_left -= casualty_quantity * definition.durability
		var remaining_quantity: int = stack.quantity - casualty_quantity
		if remaining_quantity > 0:
			remaining.append(CombatUnitStack.new(stack.unit_type_id, remaining_quantity))
