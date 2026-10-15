class_name MiningService
extends RefCounted
## Compuesto con mundo, sin referencia de vuelta que forme un ciclo RefCounted.

var _registry: EntityRegistry
var _changes: WorldChangeSet
var _system_id: String
var _max_intentions: int
var _requests: Dictionary = {} # player_id -> request_id -> decisión original
var _operations: Dictionary = {} # mining_id -> MiningOperation
var _active_by_actor: Dictionary = {} # entity_id -> mining_id


func _init(registry: EntityRegistry, changes: WorldChangeSet, system_id: String, config: MiningConfig) -> void:
	_registry = registry
	_changes = changes
	_system_id = system_id
	_max_intentions = config.max_intentions_per_player


static func is_valid_request_id(value: String) -> bool:
	if value.length() != 36:
		return false
	var parts: PackedStringArray = value.split("-")
	if parts.size() != 5:
		return false
	var lengths: Array[int] = [8, 4, 4, 4, 12]
	for index: int in range(5):
		if parts[index].length() != lengths[index]:
			return false
		for offset: int in range(parts[index].length()):
			if not "0123456789abcdefABCDEF".contains(parts[index].substr(offset, 1)):
				return false
	return true


func start(player_id: String, request_id: String, asteroid_id: String, now_ms: int) -> Dictionary:
	if player_id.is_empty():
		return _error("MINING_NOT_AUTHENTICATED")
	if not is_valid_request_id(request_id) or asteroid_id.is_empty():
		return _error("MINING_INVALID_REQUEST")
	request_id = request_id.to_lower()
	var journal: Dictionary = _requests.get(player_id, {})
	if journal.has(request_id):
		var entry: Dictionary = journal[request_id]
		if str(entry["asteroid_id"]) != asteroid_id:
			return _error("MINING_REQUEST_CONFLICT")
		var original: Dictionary = entry["decision"].duplicate(true)
		if original.has("mining_id"):
			var operation: MiningOperation = _operations[original["mining_id"]]
			_touch_current_ship(player_id)
			original["replayed"] = true
			if operation.status != "ACTIVE":
				original["result"] = operation.get_result()
		return original
	if journal.size() >= _max_intentions:
		return _error("MINING_LIMIT_REACHED")
	var actor: EntityState = _ship_for_player(player_id)
	var asteroid: AsteroidState = _registry.get_entity(asteroid_id) as AsteroidState
	var decision: Dictionary = _validate_start(player_id, actor, asteroid)
	if decision.is_empty():
		var operation := MiningOperation.new(_new_uuid(), request_id, player_id, actor, asteroid, now_ms)
		_operations[operation.mining_id] = operation
		_active_by_actor[actor.entity_id] = operation.mining_id
		asteroid.set_resource_state(asteroid.remaining_quantity, actor.entity_id)
		_changes.update_entity(asteroid, asteroid.position)
		_publish_active(operation)
		decision = {"ok": true, "mining_id": operation.mining_id}
	journal[request_id] = {"asteroid_id": asteroid_id, "decision": decision.duplicate(true)}
	_requests[player_id] = journal
	return decision


func stop(player_id: String, mining_id: String, now_ms: int) -> Dictionary:
	if player_id.is_empty():
		return _error("MINING_NOT_AUTHENTICATED")
	if mining_id.is_empty():
		return _error("MINING_INVALID_REQUEST")
	var operation: MiningOperation = _operations.get(mining_id)
	if operation == null:
		return _error("MINING_OPERATION_NOT_FOUND")
	if operation.player_id != player_id:
		return _error("MINING_NOT_OWNER")
	if operation.status != "ACTIVE":
		_touch_current_ship(player_id)
		return {"ok": true, "mining_id": mining_id, "replayed": true, "result": operation.get_result()}
	_advance(operation, now_ms)
	if operation.status == "ACTIVE":
		_finish(operation, "CANCELLED", "USER_CANCELLED", now_ms)
	return {"ok": true, "mining_id": mining_id}


func tick(now_ms: int) -> void:
	# Copia porque _advance puede finalizar y quitar una entrada activa.
	for mining_id: Variant in _active_by_actor.values():
		_advance(_operations[mining_id], now_ms)


## Se invoca únicamente después de validar un viaje, antes de mutar TRAVELING.
func cancel_for_travel(actor_entity_id: String, now_ms: int) -> void:
	_cancel_for_actor(actor_entity_id, now_ms, "TRAVEL_STARTED")


func cancel_for_combat(actor_entity_id: String, now_ms: int) -> void:
	_cancel_for_actor(actor_entity_id, now_ms, "COMBAT_STARTED")


func _cancel_for_actor(actor_entity_id: String, now_ms: int, reason: String) -> void:
	if not _active_by_actor.has(actor_entity_id):
		return
	var operation: MiningOperation = _operations[_active_by_actor[actor_entity_id]]
	_advance(operation, now_ms)
	if operation.status == "ACTIVE":
		_finish(operation, "CANCELLED", reason, now_ms)


func _validate_start(player_id: String, actor: EntityState, asteroid: AsteroidState) -> Dictionary:
	if actor == null:
		return _error("MINING_SHIP_NOT_FOUND")
	if str(actor.payload.get("player_id", "")) != player_id:
		return _error("MINING_NOT_OWNER")
	if asteroid == null:
		return _error("MINING_ASTEROID_NOT_FOUND")
	if (str(actor.payload.get("system_id", "")) != _system_id or asteroid.system_id != _system_id):
		return _error("MINING_SYSTEM_MISMATCH")
	if actor.state != "ANCHORED":
		return _error("MINING_SHIP_NOT_ANCHORED")
	if Vector2(actor.position).distance_to(Vector2(asteroid.position)) > asteroid.get_configuration().mining_range:
		return _error("MINING_OUT_OF_RANGE")
	if _active_by_actor.has(actor.entity_id):
		return _error("MINING_ALREADY_ACTIVE")
	if asteroid.remaining_quantity == 0:
		return _error("MINING_DEPLETED")
	if not asteroid.occupant_entity_id.is_empty():
		return _error("MINING_ASTEROID_OCCUPIED")
	return {}


func _advance(operation: MiningOperation, now_ms: int) -> void:
	if operation.status != "ACTIVE":
		return
	var actor: EntityState = _registry.get_entity(operation.actor_entity_id)
	var asteroid: AsteroidState = _registry.get_entity(operation.asteroid_entity_id) as AsteroidState
	if (actor == null or asteroid == null or actor.kind != "ship"
		or str(actor.payload.get("player_id", "")) != operation.player_id
		or str(actor.payload.get("system_id", "")) != _system_id
		or asteroid.system_id != _system_id or actor.state != "ANCHORED"
		or asteroid.occupant_entity_id != actor.entity_id
		or Vector2(actor.position).distance_to(Vector2(asteroid.position)) > operation.mining_range):
		_finish(operation, "CANCELLED", "INVALIDATED", now_ms)
		return
	operation.updated_ts = maxi(operation.updated_ts, now_ms)
	var elapsed_ms: int = operation.updated_ts - operation.started_ts
	var target_quantity: int = operation.rate_units_per_second * elapsed_ms / 1000
	var quantity: int = mini(target_quantity - operation.extracted_quantity, asteroid.remaining_quantity)
	if quantity > 0:
		operation.extracted_quantity += quantity
		var remaining: int = asteroid.remaining_quantity - quantity
		asteroid.set_resource_state(remaining, "" if remaining == 0 else actor.entity_id)
		_changes.update_entity(asteroid, asteroid.position)
	if asteroid.remaining_quantity == 0:
		_finish(operation, "COMPLETED", "DEPLETED", now_ms)
	else:
		_publish_active(operation)


func _finish(operation: MiningOperation, final_status: String, reason: String, now_ms: int) -> void:
	if not operation.finish(final_status, reason, now_ms):
		return
	_active_by_actor.erase(operation.actor_entity_id)
	var asteroid: AsteroidState = _registry.get_entity(operation.asteroid_entity_id) as AsteroidState
	if asteroid != null and asteroid.occupant_entity_id == operation.actor_entity_id:
		asteroid.set_resource_state(asteroid.remaining_quantity, "")
		_changes.update_entity(asteroid, asteroid.position)
	var actor: EntityState = _registry.get_entity(operation.actor_entity_id)
	if actor != null and str(actor.payload.get("player_id", "")) == operation.player_id:
		actor.mining = {}
		actor.last_mining_result = operation.get_result()
		_changes.update_entity(actor, actor.position)


func _publish_active(operation: MiningOperation) -> void:
	var actor: EntityState = _registry.get_entity(operation.actor_entity_id)
	var snapshot: Dictionary = operation.to_active_snapshot()
	if actor != null and actor.mining != snapshot:
		actor.mining = snapshot
		_changes.update_entity(actor, actor.position)


func _touch_current_ship(player_id: String) -> void:
	var actor: EntityState = _ship_for_player(player_id)
	if actor != null:
		_changes.update_entity(actor, actor.position)


func _ship_for_player(player_id: String) -> EntityState:
	for entity: EntityState in _registry.all():
		if entity.kind == "ship" and str(entity.payload.get("player_id", "")) == player_id:
			return entity
	return null


func _error(code: String) -> Dictionary:
	return {"error_code": code, "message": code}


func _new_uuid() -> String:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex: String = bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
