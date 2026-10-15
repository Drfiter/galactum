class_name CombatSnapshotProvider
extends RefCounted
## Límite de datos Combat. La implementación mock mantiene fuerzas y bajas fuera
## del mundo; una integración futura podrá obtener snapshots desde Equipo 2/SGM.


func snapshot_for(_entity: EntityState) -> CombatParticipantSnapshot:
	return null


func apply_resolution(
		_combat_id: String,
		_attacker_entity_id: String,
		_defender_entity_id: String,
		_resolution: CombatResolution,
) -> bool:
	return false
