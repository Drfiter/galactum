class_name AsteroidConfig
extends Resource
## Datos de demostración aprobados para M3; no contienen estado de una partida.

@export var asteroid_type: String = "demo_asteroid"
@export var resource_type: String = "demo_ore"
@export_range(1, 1000000, 1) var initial_quantity: int = 10
@export_range(1, 1000000, 1) var rate_units_per_second: int = 1
@export_range(0.0, 1000.0, 0.1) var mining_range: float = 1.0


func is_valid() -> bool:
	return (not asteroid_type.is_empty() and not resource_type.is_empty()
		and initial_quantity > 0 and rate_units_per_second > 0
		and is_finite(mining_range) and mining_range >= 0.0)
