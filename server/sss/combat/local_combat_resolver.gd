class_name LocalCombatResolver
extends CombatResolverPort
## Adaptador provisional entre CombatService y el resolver puro de ETAPA 2.


func resolve(
		attacker: CombatParticipantSnapshot,
		defender: CombatParticipantSnapshot,
		rules: CombatRules,
) -> CombatResolution:
	return CombatResolver.resolve(attacker, defender, rules)
