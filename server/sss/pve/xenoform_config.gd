class_name XenoformConfig
extends Resource
## Definición local sustituible. Nunca contiene estado mutable de partida.
## No establece una tabla de balance oficial ni interpreta energía como vida.

@export var config_id: String = ""
@export var display_name: String = ""
## Sólo política técnica M3 aprobada. Ampliar exige reglas y pruebas acordadas.
@export_enum("STATIC") var behavior_mode: String = "STATIC"
@export_enum("IDLE") var initial_state: String = "IDLE"
@export var has_energy_cost: bool = false
@export var energy_cost: int = 0


func is_valid() -> bool:
	return (not config_id.strip_edges().is_empty()
		and not display_name.strip_edges().is_empty()
		and behavior_mode == "STATIC" and initial_state == "IDLE"
		and (not has_energy_cost or energy_cost > 0))
