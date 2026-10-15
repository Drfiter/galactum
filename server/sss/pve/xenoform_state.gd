class_name XenoformState
extends EntityState
## Instancia PvE autoritativa: identidad/posición/estado separados de configuración.
## Sin IA, resolver de combate o estado mutable compartido mediante Resources.

var system_id: String
var display_name: String
var _configuration: XenoformConfig


func _init(p_entity_id: String, configuration: XenoformConfig,
		p_system_id: String, p_position: Vector2i) -> void:
	super(p_entity_id, "xenoform", p_position)
	_configuration = configuration.duplicate(true) as XenoformConfig
	system_id = p_system_id
	display_name = configuration.display_name
	# spawn_xenoform valida la política; no activar estados desde datos no acordados.
	state = _configuration.initial_state


func get_configuration() -> XenoformConfig:
	return _configuration.duplicate(true) as XenoformConfig


func is_traveling() -> bool:
	# La infraestructura de viaje M2 no simula Xenoforms.
	return false


func to_add_snapshot() -> Dictionary:
	return {
		"entity_id": entity_id,
		"kind": "xenoform",
		"system_id": system_id,
		"position": [position.x, position.y],
		"display_name": display_name,
		"state": state,
		"xenoform": {"config_id": _configuration.config_id},
	}


func to_updated_snapshot() -> Dictionary:
	# Lista explícita de datos públicos; el bloque anidado se reemplaza completo.
	return to_add_snapshot()
