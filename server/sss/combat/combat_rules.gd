class_name CombatRules
extends Resource
## Datos versionados del resolver. No contiene estado mutable de una partida.

@export var combat_version: String = ""
@export var unit_definitions: Array[CombatUnitDefinition] = []


func definition_for(unit_type_id: String) -> CombatUnitDefinition:
	for definition: CombatUnitDefinition in unit_definitions:
		if definition != null and definition.unit_type_id == unit_type_id:
			return definition
	return null
