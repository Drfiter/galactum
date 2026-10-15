class_name CombatResultState
extends RefCounted
## Ultimo resultado de Combat aceptado para presentacion.
## Deduplica por combat_id y nunca modifica WorldState ni datos de economia.

signal changed

var request_id: String = ""
var combat_id: String = ""
var combat_version: String = ""
var resolved_ts: int = 0
var attacker: Dictionary = {}
var defender: Dictionary = {}
var outcome: String = ""
var casualties: Dictionary = {}
var remaining_forces: Dictionary = {}

var _seen_combat_ids: Dictionary = {}


func apply_result(payload: Dictionary) -> bool:
	if str(payload.get("type", "")) != "combat_result":
		return false
	var incoming_combat_id: String = str(payload.get("combat_id", ""))
	if incoming_combat_id == "" or _seen_combat_ids.has(incoming_combat_id):
		return false

	request_id = str(payload.get("request_id", ""))
	combat_id = incoming_combat_id
	combat_version = str(payload.get("combat_version", ""))
	resolved_ts = int(payload.get("resolved_ts", 0))
	attacker = _dictionary_copy(payload.get("attacker", {}))
	defender = _dictionary_copy(payload.get("defender", {}))
	outcome = str(payload.get("outcome", ""))
	casualties = _dictionary_copy(payload.get("casualties", {}))
	remaining_forces = _dictionary_copy(payload.get("remaining_forces", {}))
	_seen_combat_ids[incoming_combat_id] = true
	changed.emit()
	return true


func has_seen(combat: String) -> bool:
	return _seen_combat_ids.has(combat)


func result_count() -> int:
	return _seen_combat_ids.size()


func _dictionary_copy(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value.duplicate(true)
	return {}
