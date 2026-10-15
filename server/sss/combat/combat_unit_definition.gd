class_name CombatUnitDefinition
extends Resource
## Configuración inmutable durante una resolución para un unit_type_id genérico.

@export var unit_type_id: String = ""
@export_range(1, 1_000_000, 1) var attack: int = 1
@export_range(1, 1_000_000, 1) var durability: int = 1


func _init(
		p_unit_type_id: String = "",
		p_attack: int = 1,
		p_durability: int = 1,
) -> void:
	unit_type_id = p_unit_type_id
	attack = p_attack
	durability = p_durability
