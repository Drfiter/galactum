extends SceneTree
## Réplica M2, travel anidado, interpolación, ETA, llegada y reconexión.

const TRAVEL_PROJECTION = preload("res://modules/team3/travel/travel_projection.gd")

const DEPART_TS: int = 1780000000000
const ARRIVE_TS: int = DEPART_TS + 10000

var _failures: int = 0


func _initialize() -> void:
	_test_interpolation_and_eta()
	_test_nested_travel_and_arrival()
	_test_full_snapshot_during_travel()
	_test_own_ship_lookup()
	if _failures == 0:
		print("M2_TRAVEL_PROJECTION_TEST_OK")
		quit(0)
	else:
		print("M2_TRAVEL_PROJECTION_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _test_interpolation_and_eta() -> void:
	var ship: Dictionary = _traveling_ship("own", "player-1")
	var authoritative_position: Array = ship["position"].duplicate()
	_check(TRAVEL_PROJECTION.display_position(ship, DEPART_TS).is_equal_approx(Vector2(100, 200)), "interpolación t=0")
	_check(TRAVEL_PROJECTION.display_position(ship, DEPART_TS + 5000).is_equal_approx(Vector2(200, 300)), "interpolación t=0.5")
	_check(TRAVEL_PROJECTION.display_position(ship, ARRIVE_TS).is_equal_approx(Vector2(300, 400)), "interpolación t=1")
	_check(TRAVEL_PROJECTION.remaining_milliseconds(ship, DEPART_TS) == 10000, "ETA inicial")
	_check(TRAVEL_PROJECTION.remaining_milliseconds(ship, DEPART_TS + 5000) == 5000, "ETA media")
	_check(TRAVEL_PROJECTION.remaining_milliseconds(ship, ARRIVE_TS) == 0, "ETA llegada")
	_check(ship["position"] == authoritative_position, "proyección no modifica position")


func _test_nested_travel_and_arrival() -> void:
	var world := WorldState.new()
	_check(world.apply_full_snapshot(_snapshot([_anchored_ship("own", "player-1")], 2, DEPART_TS)), "snapshot ANCHORED aplicado")
	var traveling: Dictionary = _traveling_ship("own", "player-1")
	var update: Dictionary = {
		"entity_id": "own",
		"kind": "ship",
		"state": traveling["state"],
		"position": traveling["position"],
		"travel": traveling["travel"],
	}
	_check(world.apply_map_delta(_delta([update], 3, DEPART_TS)), "delta TRAVELING aplicado")
	var replicated: Dictionary = world.get_entity("own")
	_check(replicated.get("travel") is Dictionary, "travel permanece anidado")
	_check(int(replicated["travel"]["arrive_ts"]) == ARRIVE_TS, "arrive_ts preservado")

	var arrival := {
		"entity_id": "own",
		"state": "ANCHORED",
		"position": [300, 400],
		"travel": null,
	}
	_check(world.apply_map_delta(_delta([arrival], 4, ARRIVE_TS)), "delta de llegada aplicado")
	replicated = world.get_entity("own")
	_check(str(replicated.get("state", "")) == "ANCHORED", "llegada vuelve a ANCHORED")
	_check(replicated.has("travel") and replicated["travel"] == null, "travel:null limpia trayectoria stale")
	_check(replicated.get("position") == [300, 400], "posición autoritativa de llegada aplicada")


func _test_full_snapshot_during_travel() -> void:
	var reconnected_world := WorldState.new()
	_check(reconnected_world.apply_full_snapshot(
		_snapshot([_traveling_ship("own", "player-1")], 20, DEPART_TS + 5000)),
		"full_snapshot durante viaje aplicado")
	var restored: Dictionary = reconnected_world.ship_for_player("player-1")
	_check(TRAVEL_PROJECTION.has_valid_travel(restored), "reconexión restaura trayectoria completa")
	_check(TRAVEL_PROJECTION.display_position(restored, DEPART_TS + 5000).is_equal_approx(Vector2(200, 300)), "reconexión reconstruye posición visual")
	_check(reconnected_world.estimated_server_time_ms() >= DEPART_TS + 5000, "reloj estimado parte de server_time")


func _test_own_ship_lookup() -> void:
	var world := WorldState.new()
	world.apply_full_snapshot(_snapshot([
		_anchored_ship("foreign", "player-2"),
		_anchored_ship("own", "player-1"),
	], 2, DEPART_TS))
	_check(str(world.ship_for_player("player-1").get("entity_id", "")) == "own", "nave propia por player_id")
	_check(str(world.ship_for_player("player-2").get("entity_id", "")) == "foreign", "nave ajena permanece distinguible")


func _traveling_ship(entity_id: String, player_id: String) -> Dictionary:
	return {
		"entity_id": entity_id,
		"kind": "ship",
		"player_id": player_id,
		"state": "TRAVELING",
		"position": [100, 200],
		"travel": {
			"origin": [100, 200],
			"destination": [300, 400],
			"depart_ts": DEPART_TS,
			"arrive_ts": ARRIVE_TS,
		},
	}


func _anchored_ship(entity_id: String, player_id: String) -> Dictionary:
	return {
		"entity_id": entity_id,
		"kind": "ship",
		"player_id": player_id,
		"state": "ANCHORED",
		"position": [100, 200],
		"travel": null,
	}


func _snapshot(entities: Array, seq: int, server_time: int) -> Dictionary:
	return {
		"type": "map_delta",
		"protocol_version": "team3-m2.0",
		"seq": seq,
		"server_time": server_time,
		"full": true,
		"system_id": "system-1",
		"map_size": [600, 600],
		"added": entities,
		"updated": [],
		"removed": [],
	}


func _delta(updated: Array, seq: int, server_time: int) -> Dictionary:
	return {
		"type": "map_delta",
		"protocol_version": "team3-m2.0",
		"seq": seq,
		"server_time": server_time,
		"full": false,
		"system_id": "system-1",
		"added": [],
		"updated": updated,
		"removed": [],
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M2_TRAVEL_PROJECTION_TEST_FAILED: %s" % message)
