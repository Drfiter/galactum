class_name CombatUnitStack
extends RefCounted
## Valor runtime de una cantidad de unidades genéricas del mismo tipo.

var unit_type_id: String = ""
var quantity: int = 0


func _init(p_unit_type_id: String = "", p_quantity: int = 0) -> void:
	unit_type_id = p_unit_type_id
	quantity = p_quantity


func copy() -> CombatUnitStack:
	return CombatUnitStack.new(unit_type_id, quantity)


func to_dictionary() -> Dictionary:
	return {
		"unit_type_id": unit_type_id,
		"quantity": quantity,
	}
