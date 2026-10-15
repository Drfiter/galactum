extends SceneTree

var _failures: int = 0
var _results: int = 0


func _initialize() -> void:
	var world := WorldState.new()
	world.apply_full_snapshot({"seq": 1, "full": true, "map_size": [600, 600], "added": [
		{"entity_id": "own", "kind": "ship", "player_id": "p1", "position": [300, 300], "state": "ANCHORED"},
		{"entity_id": "a", "kind": "asteroid", "position": [310, 290], "asteroid_state": "AVAILABLE"},
		{"entity_id": "foreign", "kind": "ship", "player_id": "p2", "position": [320, 300]},
	]})
	var selection := ShipSelectionState.new(world)
	var intent := MiningIntentState.new(world)
	intent.set_player_id("p1")
	intent.result_received.connect(func(_result: Dictionary) -> void: _results += 1)
	selection.select_entity("own")
	intent.observe_selection(selection)
	_check(intent.begin_choose_asteroid(), "actor propio preparado")
	selection.select_entity("a")
	intent.observe_selection(selection)
	_check(selection.get_selected_ship() == null and intent.actor_entity_id == "own", "misma selección con actor como contexto")
	_check(intent.can_start(), "objetivo preparado")
	var action: Dictionary = intent.begin_start("request-1")
	_check(action == {"type": "start_mining", "request_id": "request-1", "asteroid_entity_id": "a"}, "intención sin autoridad de actor/recompensa")
	_check(intent.begin_start("request-2").is_empty(), "sólo una intención pendiente")
	world.apply_map_delta({"seq": 2, "removed": ["a"]})
	intent.observe_selection(selection)
	_check(intent.is_pending() and intent.asteroid_entity_id == "", "removed no confirma solicitud")
	_check(not intent.handle_error({"error_code": "MINING_OUT_OF_RANGE", "request_type": "start_mining", "request_id": "other"}), "error ajeno no resuelve")
	_check(not intent.handle_error({"error_code": "INVALID_DESTINATION", "request_type": "start_mining", "request_id": "request-1"}), "error Travel no resuelve minería")
	intent.reset_transient()
	_check(intent.has_uncertain_request() and not intent.is_pending(), "reconexión conserva intención incierta")
	_check(intent.begin_retry() == action, "reintento conserva request_id")
	_check(intent.handle_error({"error_code": "MINING_OUT_OF_RANGE", "request_type": "start_mining", "request_id": "request-1"}), "rechazo correlacionado")
	_check(not intent.has_uncertain_request(), "rechazo confirmado libera incertidumbre")
	var terminal: Dictionary = {"mining_id": "op1", "request_id": "request-1", "status": "COMPLETED", "quantity": 10}
	intent.apply_authoritative_ship({"player_id": "p1", "last_mining_result": terminal})
	intent.apply_authoritative_ship({"player_id": "p1", "last_mining_result": terminal})
	_check(_results == 1, "resultado deduplicado entre snapshots")
	world.apply_map_delta({"seq": 3, "updated": [{"entity_id": "own", "mining": {"mining_id": "op2", "request_id": "request-2"}}]})
	_check(intent.begin_stop() == {"type": "stop_mining", "mining_id": "op2"}, "parada sin selección")
	intent.apply_authoritative_ship({"player_id": "p1", "last_mining_result": terminal})
	_check(intent.is_pending(), "resultado viejo no confirma parada nueva")
	var done: Dictionary = {"mining_id": "op2", "request_id": "request-2", "status": "CANCELLED", "quantity": 1}
	_check(not intent.handle_replay({"request_type": "stop_mining", "mining_id": "op2", "result": {"mining_id": "op2", "status": "ACTIVE"}}), "replay inválido no confirma")
	_check(intent.handle_replay({"request_type": "stop_mining", "mining_id": "op2", "result": done}), "replay terminal correlacionado")
	_check(_results == 2 and not intent.is_pending(), "parada resuelta una vez")
	intent.reset_transient()
	intent.apply_authoritative_ship({"player_id": "p1", "last_mining_result": done})
	_check(_results == 2, "reconexión no repite notificación")
	selection.select_entity("foreign")
	intent.observe_selection(selection)
	_check(not intent.can_choose_asteroid(), "nave ajena no prepara acción")
	intent.set_player_id("p2")
	_check(intent.last_result.is_empty(), "cambio de jugador no arrastra resultados")
	print("M3_MINING_INTENT_TEST_OK" if _failures == 0 else "M3_MINING_INTENT_TEST_FAILED")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("M3_MINING_INTENT_TEST_FAILED: %s" % message)
