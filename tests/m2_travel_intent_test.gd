extends SceneTree
## Estado local de selección/confirmación. No requiere servidor.

const TRAVEL_INTENT_STATE = preload("res://modules/team3/travel/travel_intent_state.gd")

var _failures: int = 0


func _initialize() -> void:
	_test_own_and_foreign_ship()
	_test_destination_and_cancel()
	_test_exactly_one_pending_request_and_rejection()
	_test_authoritative_travel_clears_provisional()
	if _failures == 0:
		print("M2_TRAVEL_INTENT_TEST_OK")
		quit(0)
	else:
		print("M2_TRAVEL_INTENT_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _test_own_and_foreign_ship() -> void:
	var state: RefCounted = TRAVEL_INTENT_STATE.new()
	state.set_player_id("player-1")
	_check(state.select_entity(_ship("own", "player-1", "ANCHORED")), "nave propia identificada")
	_check(state.can_choose_destination(), "nave propia ANCHORED permite destino")
	_check(not state.select_entity(_ship("foreign", "player-2", "ANCHORED")), "nave ajena no es propia")
	_check(not state.can_choose_destination(), "nave ajena no permite viaje")
	_check(state.select_entity(_ship("traveling", "player-1", "TRAVELING")), "nave propia viajando se identifica")
	_check(not state.can_choose_destination(), "TRAVELING no permite otra intención")


func _test_destination_and_cancel() -> void:
	var state := _ready_state()
	_check(not state.choose_destination(Vector2i(-1, 20), Vector2i(600, 600)), "destino negativo rechazado")
	_check(not state.choose_destination(Vector2i(600, 20), Vector2i(600, 600)), "destino fuera del mapa rechazado")
	_check(state.choose_destination(Vector2i(420, 180), Vector2i(600, 600)), "destino válido aceptado")
	_check(state.has_provisional_destination, "destino queda provisional")
	_check(state.cancel_destination(), "cancelación aceptada")
	_check(not state.has_provisional_destination, "cancelación limpia destino")
	_check(not state.awaiting_resolution, "cancelación no crea solicitud pendiente")


func _test_exactly_one_pending_request_and_rejection() -> void:
	var state := _ready_state()
	state.choose_destination(Vector2i(420, 180), Vector2i(600, 600))
	_check(state.begin_request(), "primera confirmación inicia solicitud")
	_check(state.awaiting_resolution, "solicitud queda pendiente")
	_check(not state.begin_request(), "segunda confirmación queda bloqueada")
	_check(not state.cancel_destination(), "cancelar queda bloqueado mientras espera")
	_check(state.reject_request("INVALID_DESTINATION"), "rechazo resuelve solicitud pendiente")
	_check(not state.awaiting_resolution, "rechazo habilita nueva resolución")
	_check(state.has_provisional_destination, "rechazo conserva destino para corrección")
	_check(state.last_rejection_code == "INVALID_DESTINATION", "rechazo conserva código")


func _test_authoritative_travel_clears_provisional() -> void:
	var state := _ready_state()
	state.choose_destination(Vector2i(420, 180), Vector2i(600, 600))
	state.begin_request()
	state.apply_authoritative_ship(_ship("own", "player-1", "TRAVELING"))
	_check(not state.awaiting_resolution, "TRAVELING autoritativo resuelve espera")
	_check(not state.has_provisional_destination, "TRAVELING limpia marcador provisional")
	_check(state.authoritative_state == "TRAVELING", "estado local refleja réplica")


func _ready_state() -> RefCounted:
	var state: RefCounted = TRAVEL_INTENT_STATE.new()
	state.set_player_id("player-1")
	state.select_entity(_ship("own", "player-1", "ANCHORED"))
	return state


func _ship(entity_id: String, player_id: String, state: String) -> Dictionary:
	return {
		"entity_id": entity_id,
		"kind": "ship",
		"player_id": player_id,
		"state": state,
		"position": [100, 100],
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M2_TRAVEL_INTENT_TEST_FAILED: %s" % message)
