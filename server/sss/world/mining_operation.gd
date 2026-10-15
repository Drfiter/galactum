class_name MiningOperation
extends RefCounted
## Estado de una operación; sólo MiningService lo muta. No acredita economía.

var mining_id: String
var request_id: String
var player_id: String
var actor_entity_id: String
var asteroid_entity_id: String
var resource_type: String
var rate_units_per_second: int
var mining_range: float
var started_ts: int
var updated_ts: int
var extracted_quantity: int = 0
var status: String = "ACTIVE"
var _result: Dictionary = {}


func _init(
		p_mining_id: String, p_request_id: String, p_player_id: String,
		actor: EntityState, asteroid: AsteroidState, now_ms: int,
) -> void:
	mining_id = p_mining_id
	request_id = p_request_id
	player_id = p_player_id
	actor_entity_id = actor.entity_id
	asteroid_entity_id = asteroid.entity_id
	var config: AsteroidConfig = asteroid.get_configuration()
	resource_type = config.resource_type
	rate_units_per_second = config.rate_units_per_second
	mining_range = config.mining_range
	started_ts = now_ms
	updated_ts = now_ms


func to_active_snapshot() -> Dictionary:
	return {
		"mining_id": mining_id, "request_id": request_id,
		"asteroid_entity_id": asteroid_entity_id, "status": status,
		"resource_type": resource_type, "rate_units_per_second": rate_units_per_second,
		"started_ts": started_ts, "updated_ts": updated_ts,
		"extracted_quantity": extracted_quantity,
	}


## Congela el resultado una única vez; todas las lecturas son copias.
func finish(final_status: String, reason: String, now_ms: int) -> bool:
	if status != "ACTIVE":
		return false
	status = final_status
	_result = {
		"mining_id": mining_id, "request_id": request_id,
		"asteroid_entity_id": asteroid_entity_id, "status": status,
		"reason": reason, "resource_type": resource_type,
		"quantity": extracted_quantity, "finished_ts": maxi(now_ms, updated_ts),
	}
	return true


func get_result() -> Dictionary:
	return _result.duplicate(true)
