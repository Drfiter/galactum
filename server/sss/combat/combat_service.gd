class_name CombatService
extends RefCounted
## Orquestación autoritativa e idempotente de Combat durante la vida del SSS.

const ERROR_INVALID_ATTACK_REQUEST: String = "INVALID_ATTACK_REQUEST"
const ERROR_ATTACKER_NOT_FOUND: String = "ATTACKER_NOT_FOUND"
const ERROR_TARGET_NOT_FOUND: String = "TARGET_NOT_FOUND"
const ERROR_UNSUPPORTED_ATTACKER_KIND: String = "UNSUPPORTED_ATTACKER_KIND"
const ERROR_UNSUPPORTED_TARGET_KIND: String = "UNSUPPORTED_TARGET_KIND"
const ERROR_CANNOT_ATTACK_SELF: String = "CANNOT_ATTACK_SELF"
const ERROR_CANNOT_ATTACK_OWN_SHIP: String = "CANNOT_ATTACK_OWN_SHIP"
const ERROR_ATTACKER_NOT_ANCHORED: String = "ATTACKER_NOT_ANCHORED"
const ERROR_TARGET_NOT_ANCHORED: String = "TARGET_NOT_ANCHORED"
const ERROR_TARGET_NOT_VISIBLE: String = "TARGET_NOT_VISIBLE"
const ERROR_COMBAT_DATA_UNAVAILABLE: String = "COMBAT_DATA_UNAVAILABLE"
const ERROR_INVALID_COMBAT_CONFIGURATION: String = "INVALID_COMBAT_CONFIGURATION"
const ERROR_COMBAT_ID_GENERATION_FAILED: String = "COMBAT_ID_GENERATION_FAILED"
const ERROR_COMBAT_RESULT_APPLY_FAILED: String = "COMBAT_RESULT_APPLY_FAILED"
const ERROR_ATTACK_REQUEST_CONFLICT: String = "ATTACK_REQUEST_CONFLICT"

const MAX_REQUEST_ID_LENGTH: int = 128
const MAX_ENTITY_ID_LENGTH: int = 128

var _world: SolarSystemWorld
var _snapshot_provider: CombatSnapshotProvider
var _resolver: CombatResolverPort
var _rules: CombatRules
## player_id -> request_id -> {target_entity_id, result}
var _requests_by_player: Dictionary = {}
var _applied_combat_ids: Dictionary = {}
var _known_combat_ids: Dictionary = {}


func _init(
		world: SolarSystemWorld,
		snapshot_provider: CombatSnapshotProvider,
		resolver: CombatResolverPort,
		rules: CombatRules,
) -> void:
	_world = world
	_snapshot_provider = snapshot_provider
	_resolver = resolver
	_rules = rules


func request_attack(player_id: String, request_id: String, target_entity_id: String) -> Dictionary:
	if not _is_valid_identifier(request_id, MAX_REQUEST_ID_LENGTH):
		return combat_error(request_id, ERROR_INVALID_ATTACK_REQUEST, "request_id is required and must be at most 128 characters")
	if not _is_valid_identifier(target_entity_id, MAX_ENTITY_ID_LENGTH):
		return combat_error(request_id, ERROR_INVALID_ATTACK_REQUEST, "target_entity_id is required and must be at most 128 characters")

	var existing: Dictionary = _request_record(player_id, request_id)
	if not existing.is_empty():
		if str(existing.get("target_entity_id", "")) != target_entity_id:
			return combat_error(request_id, ERROR_ATTACK_REQUEST_CONFLICT, "request_id was already used with another target")
		return (existing.get("result", {}) as Dictionary).duplicate(true)

	var attacker: EntityState = _world.get_ship_for_player(player_id)
	if attacker == null:
		return combat_error(request_id, ERROR_ATTACKER_NOT_FOUND, "No ship for authenticated player")
	var target: EntityState = _world.get_entity(target_entity_id)
	if target == null:
		return combat_error(request_id, ERROR_TARGET_NOT_FOUND, "Target entity does not exist")
	if attacker.kind != "ship":
		return combat_error(request_id, ERROR_UNSUPPORTED_ATTACKER_KIND, "Attacker must be a ship")
	if target.kind != "ship":
		return combat_error(request_id, ERROR_UNSUPPORTED_TARGET_KIND, "Target must be a ship")
	if attacker.entity_id == target.entity_id:
		return combat_error(request_id, ERROR_CANNOT_ATTACK_SELF, "A ship cannot attack itself")
	if str(target.payload.get("player_id", "")) == player_id:
		return combat_error(request_id, ERROR_CANNOT_ATTACK_OWN_SHIP, "Target belongs to authenticated player")
	if attacker.state != "ANCHORED":
		return combat_error(request_id, ERROR_ATTACKER_NOT_ANCHORED, "Attacker must be anchored")
	if target.state != "ANCHORED":
		return combat_error(request_id, ERROR_TARGET_NOT_ANCHORED, "Target must be anchored")
	if not _world.is_entity_visible_to(player_id, target.entity_id):
		return combat_error(request_id, ERROR_TARGET_NOT_VISIBLE, "Target is outside authoritative AOI")

	var attacker_snapshot: CombatParticipantSnapshot = _snapshot_provider.snapshot_for(attacker)
	var defender_snapshot: CombatParticipantSnapshot = _snapshot_provider.snapshot_for(target)
	if attacker_snapshot == null or defender_snapshot == null:
		return combat_error(request_id, ERROR_COMBAT_DATA_UNAVAILABLE, "Combat snapshot is unavailable")
	if _resolver == null or _rules == null:
		return combat_error(request_id, ERROR_INVALID_COMBAT_CONFIGURATION, "Combat resolver or rules are unavailable")

	var combat_id: String = _new_combat_id()
	if combat_id.is_empty():
		return combat_error(request_id, ERROR_COMBAT_ID_GENERATION_FAILED, "Could not generate combat_id")
	var resolution: CombatResolution = _resolver.resolve(attacker_snapshot, defender_snapshot, _rules)
	if resolution == null or not resolution.ok:
		if resolution != null and resolution.error_code == CombatResolution.ERROR_INVALID_RULES:
			return combat_error(request_id, ERROR_INVALID_COMBAT_CONFIGURATION, resolution.error_message)
		var message: String = "Combat snapshot is invalid" if resolution == null else resolution.error_message
		return combat_error(request_id, ERROR_COMBAT_DATA_UNAVAILABLE, message)

	if not _applied_combat_ids.has(combat_id):
		if not _snapshot_provider.apply_resolution(
				combat_id,
				attacker.entity_id,
				target.entity_id,
				resolution,
		):
			return combat_error(request_id, ERROR_COMBAT_RESULT_APPLY_FAILED, "Combat mock state rejected result")
		_applied_combat_ids[combat_id] = true

	_world.cancel_mining_for_combat(attacker.entity_id, target.entity_id)
	var result: Dictionary = {
		"type": "combat_result",
		"request_id": request_id,
		"combat_id": combat_id,
		"combat_version": resolution.combat_version,
		"resolved_ts": _world.server_time,
		"attacker": {
			"entity_id": attacker_snapshot.entity_id,
			"ship_id": attacker_snapshot.ship_id,
		},
		"defender": {
			"entity_id": defender_snapshot.entity_id,
			"ship_id": defender_snapshot.ship_id,
		},
		"outcome": resolution.outcome,
		"casualties": {
			"attacker": _serialize_stacks(resolution.attacker_casualties),
			"defender": _serialize_stacks(resolution.defender_casualties),
		},
		"remaining_forces": {
			"attacker": _serialize_stacks(resolution.attacker_remaining),
			"defender": _serialize_stacks(resolution.defender_remaining),
		},
	}
	_store_request(player_id, request_id, target_entity_id, result)
	return result.duplicate(true)


static func combat_error(request_id: String, error_code: String, message: String) -> Dictionary:
	var error: Dictionary = {
		"type": "error",
		"error_code": error_code,
		"message": message,
		"request_type": "attack",
	}
	if not request_id.is_empty():
		error["request_id"] = request_id
	return error


func _request_record(player_id: String, request_id: String) -> Dictionary:
	if not _requests_by_player.has(player_id):
		return {}
	var player_requests: Dictionary = _requests_by_player[player_id]
	if not player_requests.has(request_id):
		return {}
	return player_requests[request_id]


func _store_request(
		player_id: String,
		request_id: String,
		target_entity_id: String,
		result: Dictionary,
) -> void:
	var player_requests: Dictionary = _requests_by_player.get(player_id, {})
	player_requests[request_id] = {
		"target_entity_id": target_entity_id,
		"result": result.duplicate(true),
	}
	_requests_by_player[player_id] = player_requests


func _new_combat_id() -> String:
	for _attempt: int in range(8):
		var random_bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
		if random_bytes.size() != 16:
			continue
		var candidate: String = "combat-%s" % random_bytes.hex_encode()
		if not _known_combat_ids.has(candidate):
			_known_combat_ids[candidate] = true
			return candidate
	return ""


static func _is_valid_identifier(value: String, maximum_length: int) -> bool:
	return not value.is_empty() and value == value.strip_edges() and value.length() <= maximum_length


static func _serialize_stacks(stacks: Array[CombatUnitStack]) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	for stack: CombatUnitStack in stacks:
		serialized.append(stack.to_dictionary())
	return serialized
