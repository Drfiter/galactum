class_name CombatResolverPort
extends RefCounted
## Puerto consumido por CombatService. La implementación local provisional puede
## reemplazarse por un adaptador SGM sin cambiar el flujo autoritativo del SSS.


func resolve(
		_attacker: CombatParticipantSnapshot,
		_defender: CombatParticipantSnapshot,
		_rules: CombatRules,
) -> CombatResolution:
	return CombatResolution.failure(
		CombatResolution.ERROR_INVALID_RULES,
		"CombatResolverPort.resolve must be implemented",
	)
