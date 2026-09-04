extends SceneTree
## Test unitario del cliente TEAM3-M1: WorldState multi-entidad.
## Ejecutar: godot --headless --path . --script res://tests/m1_client_world_state_test.gd
## Verifica full_snapshot, map_delta incremental (added/updated/removed),
## merge de updates y que WorldState no exija seq consecutivo entre deltas.

var _failures: int = 0
var _change_notifications: int = 0


func _initialize() -> void:
	_test_full_snapshot()
	_test_incremental_delta()
	_test_updated_merge()
	_test_removed()
	_test_clear()
	_test_no_consecutive_seq_requirement()

	if _failures == 0:
		print("M1_CLIENT_WORLD_STATE_TEST_OK")
		quit(0)
	else:
		print("M1_CLIENT_WORLD_STATE_TEST_FAILED (%d fallos)" % _failures)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: %s" % label)


func _test_full_snapshot() -> void:
	var ws := WorldState.new()
	var message := {
		"type": "map_delta",
		"protocol_version": "team3-m1.0",
		"seq": 2,
		"server_time": 1780000000000,
		"full": true,
		"system_id": "sys-1",
		"map_size": [600, 600],
		"added": [
			{"entity_id": "e1", "kind": "ship", "position": [100, 200]},
			{"entity_id": "e2", "kind": "asteroid", "position": [300, 300]},
		],
		"updated": [],
		"removed": [],
	}
	_check(ws.apply_full_snapshot(message), "full_snapshot se aplica")
	_check(ws.seq == 2, "seq del snapshot registrado")
	_check(ws.map_size == Vector2i(600, 600), "map_size 600x600")
	_check(ws.entities.size() == 2, "dos entidades cargadas")
	_check(ws.get_entity("e1").get("kind", "") == "ship", "get_entity devuelve entidad")


func _test_incremental_delta() -> void:
	var ws := WorldState.new()
	ws.apply_full_snapshot({
		"type": "map_delta", "protocol_version": "team3-m1.0", "seq": 2,
		"server_time": 1780000000000, "full": true, "system_id": "sys-1",
		"map_size": [600, 600], "added": [
			{"entity_id": "e1", "kind": "ship", "position": [100, 200]},
		], "updated": [], "removed": [],
	})
	var delta := {
		"type": "map_delta", "protocol_version": "team3-m1.0", "seq": 8,
		"server_time": 1780000004000, "full": false, "system_id": "sys-1",
		"added": [
			{"entity_id": "e3", "kind": "xenoform", "position": [500, 500]},
		],
		"updated": [],
		"removed": [],
	}
	_check(ws.apply_map_delta(delta), "delta incremental se aplica")
	_check(ws.seq == 8, "seq del delta registrado")
	_check(ws.entities.size() == 2, "added se suma a la réplica")
	_check(ws.get_entity("e1").get("kind", "") == "ship", "entidad previa conservada")


func _test_updated_merge() -> void:
	var ws := WorldState.new()
	ws.apply_full_snapshot({
		"type": "map_delta", "protocol_version": "team3-m1.0", "seq": 2,
		"server_time": 1780000000000, "full": true, "system_id": "sys-1",
		"map_size": [600, 600], "added": [
			{"entity_id": "e1", "kind": "ship", "position": [100, 200], "ship_id": "s1"},
		], "updated": [], "removed": [],
	})
	# update solo con entity_id + campos cambiados
	var delta := {
		"type": "map_delta", "protocol_version": "team3-m1.0", "seq": 3,
		"server_time": 1780000001000, "full": false, "system_id": "sys-1",
		"added": [], "updated": [
			{"entity_id": "e1", "position": [250, 250]},
		], "removed": [],
	}
	_check(ws.apply_map_delta(delta), "update merge aplica")
	var e: Dictionary = ws.get_entity("e1")
	_check(e.get("position", []) == [250, 250], "posición actualizada")
	_check(e.get("ship_id", "") == "s1", "campo no presente en update se preserva")


func _test_removed() -> void:
	var ws := WorldState.new()
	ws.apply_full_snapshot({
		"type": "map_delta", "protocol_version": "team3-m1.0", "seq": 2,
		"server_time": 1780000000000, "full": true, "system_id": "sys-1",
		"map_size": [600, 600], "added": [
			{"entity_id": "e1", "kind": "ship", "position": [100, 200]},
			{"entity_id": "e2", "kind": "asteroid", "position": [300, 300]},
		], "updated": [], "removed": [],
	})
	var delta := {
		"type": "map_delta", "protocol_version": "team3-m1.0", "seq": 3,
		"server_time": 1780000001000, "full": false, "system_id": "sys-1",
		"added": [], "updated": [], "removed": ["e1"],
	}
	_check(ws.apply_map_delta(delta), "removed aplica")
	_check(ws.entities.has("e1") == false, "entidad removida de la réplica visible")
	_check(ws.entities.has("e2"), "entidad no removida se conserva")


func _test_clear() -> void:
	var ws := WorldState.new()
	ws.changed.connect(_on_world_state_changed)
	ws.apply_full_snapshot({
		"type": "map_delta", "protocol_version": "team3-m1.0", "seq": 2,
		"server_time": 1780000000000, "full": true, "system_id": "sys-1",
		"map_size": [600, 600], "added": [{"entity_id": "e1", "kind": "ship"}],
		"updated": [], "removed": [],
	})
	var notifications_before_clear: int = _change_notifications
	ws.clear()
	_check(ws.entities.is_empty(), "clear vacía entidades")
	_check(ws.seq == -1, "clear resetea seq")
	_check(_change_notifications == notifications_before_clear + 1,
		"clear emite changed para retirar marcadores obsoletos")


func _test_no_consecutive_seq_requirement() -> void:
	var ws := WorldState.new()
	ws.apply_full_snapshot({
		"type": "map_delta", "protocol_version": "team3-m1.0", "seq": 2,
		"server_time": 1780000000000, "full": true, "system_id": "sys-1",
		"map_size": [600, 600], "added": [{"entity_id": "e1", "kind": "ship"}],
		"updated": [], "removed": [],
	})
	# Un delta con seq muy posterior (incluye otros mensajes del SSS entre medias:
	# pong, errors, etc.) NO debe ser rechazado por WorldState.
	var delta := {
		"type": "map_delta", "protocol_version": "team3-m1.0", "seq": 40,
		"server_time": 1780000005000, "full": false, "system_id": "sys-1",
		"added": [{"entity_id": "e2", "kind": "fleet"}],
		"updated": [], "removed": [],
	}
	_check(ws.apply_map_delta(delta), "WorldState acepta deltas con seq no consecutivo")
	_check(ws.seq == 40, "ultimo seq aplicado registrado")
	_check(ws.entities.size() == 2, "fleet agregada")


func _on_world_state_changed() -> void:
	_change_notifications += 1
