extends SceneTree
## Detecta confusión de IDs/ownership, alias mutables y datos obsoletos tras deltas.

var _failures: int = 0


func _initialize() -> void:
	var world := WorldState.new()
	if not world.has_method("get_ship"):
		_check(false, "falta consulta tipada de nave")
		_finish()
		return
	world.apply_full_snapshot(_snapshot())
	var ship: RefCounted = world.call("get_ship", "entity-own")
	_check(ship != null, "nave visible disponible")
	_check(ship.entity_id == "entity-own" and ship.ship_id == "ship-own", "IDs separados")
	_check(ship.player_id == "player-own" and ship.system_id == "system-1", "ownership y sistema recibidos")
	_check(ship.is_owned_by("player-own") and not ship.is_owned_by(""), "ownership requiere identidad autenticada")
	var foreign: RefCounted = world.call("get_ship", "entity-foreign")
	_check(not foreign.is_owned_by("player-own") and not foreign.is_owned_by(""), "propietario desconocido no se infiere")
	_check(world.call("get_ship", "rock") == null, "asteroide no es nave")
	_check(world.call("get_ship", "missing") == null, "ausente no inventa nave")
	var own: RefCounted = world.call("get_ship_for_player", "player-own")
	_check(own.entity_id == "entity-own", "no usa primera nave ajena")
	ship.position = Vector2(999, 999)
	var copied: Dictionary = ship.to_entity()
	copied["travel"]["destination"][0] = 999
	_check(world.get_entity("entity-own")["position"] == [100, 100], "modelo no muta réplica")
	_check(world.get_entity("entity-own")["travel"]["destination"] == [200, 100], "copia anidada no muta réplica")
	var projected: Vector2 = TravelProjection.display_position(own.to_entity(), 1500)
	_check(projected == Vector2(150, 100) and own.position == Vector2(100, 100), "proyección no reemplaza posición autoritativa")
	world.apply_map_delta({"seq": 2, "updated": [{"entity_id": "entity-own", "state": "ANCHORED", "position": [200, 100], "travel": null}]})
	var arrived: RefCounted = world.call("get_ship", "entity-own")
	_check(arrived.state == "ANCHORED" and arrived.position == Vector2(200, 100), "consulta refleja llegada")
	_check(arrived.to_entity().get("travel") == null, "travel null preservado")
	world.clear()
	_check(world.call("get_ship", "entity-own") == null, "clear no conserva modelos obsoletos")
	_finish()


func _snapshot() -> Dictionary:
	return {"seq": 1, "system_id": "system-1", "map_size": [600, 600], "added": [
		{"entity_id": "entity-foreign", "ship_id": "ship-foreign", "kind": "ship", "position": [140, 100]},
		{"entity_id": "entity-own", "ship_id": "ship-own", "player_id": "player-own", "system_id": "system-1", "kind": "ship", "state": "TRAVELING", "position": [100, 100], "travel": {"origin": [100, 100], "destination": [200, 100], "depart_ts": 1000, "arrive_ts": 2000}},
		{"entity_id": "rock", "kind": "asteroid", "position": [110, 100]},
	]}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_SHIP_REPRESENTATION_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("M3_SHIP_REPRESENTATION_TEST_OK" if _failures == 0 else "M3_SHIP_REPRESENTATION_TEST_FAILED")
	quit(0 if _failures == 0 else 1)
