class_name CombatParticipantSnapshot
extends RefCounted
## Snapshot de entrada congelado para una resolución.
## Conserva separadas las identidades de mundo, nave y propietario.

var entity_id: String = ""
var ship_id: String = ""
var player_id: String = ""
var kind: String = ""
var units: Array[CombatUnitStack] = []


func _init(
		p_entity_id: String = "",
		p_ship_id: String = "",
		p_player_id: String = "",
		p_kind: String = "",
		p_units: Array[CombatUnitStack] = [],
) -> void:
	entity_id = p_entity_id
	ship_id = p_ship_id
	player_id = p_player_id
	kind = p_kind
	for stack: CombatUnitStack in p_units:
		units.append(null if stack == null else stack.copy())


func copy() -> CombatParticipantSnapshot:
	return CombatParticipantSnapshot.new(entity_id, ship_id, player_id, kind, units)
