class_name MockCombatSnapshotProvider
extends CombatSnapshotProvider
## Estado Combat exclusivamente mock. No escribe EntityState, economía, inventario
## ni datos de otros equipos.

var _forces_by_entity: Dictionary = {}
var _application_counts: Dictionary = {}


func _init(initial_forces: Dictionary = {}) -> void:
	for raw_entity_id: Variant in initial_forces.keys():
		var entity_id: String = str(raw_entity_id)
		var stacks: Array[CombatUnitStack] = []
		var raw_stacks: Variant = initial_forces[raw_entity_id]
		if raw_stacks is Array:
			for raw_stack: Variant in raw_stacks:
				if raw_stack is CombatUnitStack:
					stacks.append((raw_stack as CombatUnitStack).copy())
				elif raw_stack is Dictionary:
					stacks.append(CombatUnitStack.new(
						str(raw_stack.get("unit_type_id", "")),
						int(raw_stack.get("quantity", 0)),
					))
		set_units(entity_id, stacks)


func set_units(entity_id: String, stacks: Array[CombatUnitStack]) -> void:
	var stored: Array[CombatUnitStack] = []
	for stack: CombatUnitStack in stacks:
		stored.append(null if stack == null else stack.copy())
	_forces_by_entity[entity_id] = stored


func units_for(entity_id: String) -> Array[CombatUnitStack]:
	var copied: Array[CombatUnitStack] = []
	if not _forces_by_entity.has(entity_id):
		return copied
	var stored: Array = _forces_by_entity[entity_id]
	for stack: CombatUnitStack in stored:
		copied.append(null if stack == null else stack.copy())
	return copied


func snapshot_for(entity: EntityState) -> CombatParticipantSnapshot:
	if entity == null or not _forces_by_entity.has(entity.entity_id):
		return null
	return CombatParticipantSnapshot.new(
		entity.entity_id,
		str(entity.payload.get("ship_id", "")),
		str(entity.payload.get("player_id", "")),
		entity.kind,
		units_for(entity.entity_id),
	)


func apply_resolution(
		combat_id: String,
		attacker_entity_id: String,
		defender_entity_id: String,
		resolution: CombatResolution,
) -> bool:
	if combat_id.is_empty() or resolution == null or not resolution.ok:
		return false
	if _application_counts.has(combat_id):
		return true
	if not _forces_by_entity.has(attacker_entity_id) or not _forces_by_entity.has(defender_entity_id):
		return false
	set_units(attacker_entity_id, resolution.attacker_remaining)
	set_units(defender_entity_id, resolution.defender_remaining)
	_application_counts[combat_id] = 1
	return true


func application_count_for(combat_id: String) -> int:
	return int(_application_counts.get(combat_id, 0))


func total_application_count() -> int:
	var total: int = 0
	for count: Variant in _application_counts.values():
		total += int(count)
	return total
