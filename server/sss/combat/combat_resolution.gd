class_name CombatResolution
extends RefCounted
## Valor de retorno del resolver puro. No contiene combat_id ni timestamps:
## esas responsabilidades pertenecen a la futura orquestación autoritativa.

const OUTCOME_ATTACKER_WIN: String = "attacker_win"
const OUTCOME_DEFENDER_WIN: String = "defender_win"
const OUTCOME_DRAW: String = "draw"

const ERROR_INVALID_RULES: String = "INVALID_COMBAT_RULES"
const ERROR_INVALID_PARTICIPANT: String = "INVALID_COMBAT_PARTICIPANT"

var ok: bool = false
var error_code: String = ""
var error_message: String = ""
var combat_version: String = ""
var outcome: String = ""
var attacker_casualties: Array[CombatUnitStack] = []
var defender_casualties: Array[CombatUnitStack] = []
var attacker_remaining: Array[CombatUnitStack] = []
var defender_remaining: Array[CombatUnitStack] = []


func to_dictionary() -> Dictionary:
	return {
		"ok": ok,
		"error_code": error_code,
		"error_message": error_message,
		"combat_version": combat_version,
		"outcome": outcome,
		"casualties": {
			"attacker": _serialize_stacks(attacker_casualties),
			"defender": _serialize_stacks(defender_casualties),
		},
		"remaining_forces": {
			"attacker": _serialize_stacks(attacker_remaining),
			"defender": _serialize_stacks(defender_remaining),
		},
	}


static func failure(code: String, message: String) -> CombatResolution:
	var result := CombatResolution.new()
	result.error_code = code
	result.error_message = message
	return result


static func _serialize_stacks(stacks: Array[CombatUnitStack]) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	for stack: CombatUnitStack in stacks:
		serialized.append(stack.to_dictionary())
	return serialized
