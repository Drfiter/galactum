class_name AsteroidState
extends EntityState
## Entidad autoritativa; el ciclo de extracción se compone en MiningService.

const AVAILABLE: String = "AVAILABLE"
const OCCUPIED: String = "OCCUPIED"
const DEPLETED: String = "DEPLETED"

var system_id: String
var _configuration: AsteroidConfig
var _remaining_quantity: int
var _occupant_entity_id: String = ""

var remaining_quantity: int:
	get:
		return _remaining_quantity

var occupant_entity_id: String:
	get:
		return _occupant_entity_id

var asteroid_state: String:
	get:
		if _remaining_quantity == 0:
			return DEPLETED
		return AVAILABLE if _occupant_entity_id.is_empty() else OCCUPIED


func _init(
		p_entity_id: String,
		p_system_id: String,
		p_position: Vector2i,
		configuration: AsteroidConfig,
) -> void:
	super(p_entity_id, "asteroid", p_position)
	system_id = p_system_id
	# Aislar configuración externa además de separar el estado mutable.
	_configuration = configuration.duplicate(true) as AsteroidConfig
	_remaining_quantity = _configuration.initial_quantity


func get_configuration() -> AsteroidConfig:
	return _configuration.duplicate(true) as AsteroidConfig


## Mutación de datos validada; no extrae, acredita ni decide reglas de minería.
func set_resource_state(quantity: int, occupant_id: String) -> bool:
	if quantity < 0 or quantity > _configuration.initial_quantity:
		return false
	if quantity == 0 and not occupant_id.is_empty():
		return false
	_remaining_quantity = quantity
	_occupant_entity_id = occupant_id
	return true


func to_add_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.to_add_snapshot()
	snapshot.merge({
		"system_id": system_id,
		"asteroid_type": _configuration.asteroid_type,
		"resource_type": _configuration.resource_type,
		"remaining_quantity": _remaining_quantity,
		"asteroid_state": asteroid_state,
		"occupant_entity_id": null if _occupant_entity_id.is_empty() else _occupant_entity_id,
	}, true)
	return snapshot


func to_updated_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.to_updated_snapshot()
	snapshot.merge({
		"remaining_quantity": _remaining_quantity,
		"asteroid_state": asteroid_state,
		"occupant_entity_id": null if _occupant_entity_id.is_empty() else _occupant_entity_id,
	}, true)
	return snapshot


## Mantener la forma previa para sesiones que continúan usando M2.
func to_m2_add_snapshot() -> Dictionary:
	return super.to_add_snapshot()


func to_m2_updated_snapshot() -> Dictionary:
	return super.to_updated_snapshot()
