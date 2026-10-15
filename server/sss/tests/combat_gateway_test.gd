extends SceneTree
## TEAM3-M3 ETAPA 3: autenticación, forma de attack y separación de errores.

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")
const DEFAULT_RULES: CombatRules = preload("res://config/default_combat_rules.tres")

var _failures: int = 0


class CountingResolver extends CombatResolverPort:
	var calls: int = 0

	func resolve(
			attacker: CombatParticipantSnapshot,
			defender: CombatParticipantSnapshot,
			rules: CombatRules,
	) -> CombatResolution:
		calls += 1
		return CombatResolver.resolve(attacker, defender, rules)


class RecordingGateway extends WebSocketGateway:
	var sent: Array[Dictionary] = []

	func _init(
			config: SssConfig,
			authenticator: ClientAuthenticator,
			world: SolarSystemWorld,
			combat_service: CombatService,
	) -> void:
		super(config, authenticator, world, combat_service)

	func add_test_session(session_id: int) -> void:
		_sessions[session_id] = {
			"authenticated": false,
			"player_id": "",
			"system_id": "",
			"seq": 0,
		}

	func process_message(session_id: int, payload: Dictionary) -> void:
		_handle_packet(session_id, JSON.stringify(payload))

	func last_message() -> Dictionary:
		return {} if sent.is_empty() else sent[-1]

	func _send(session_id: int, payload: Dictionary) -> void:
		var session: Dictionary = _sessions[session_id]
		session["seq"] = int(session.get("seq", 0)) + 1
		_sessions[session_id] = session
		var message: Dictionary = payload.duplicate(true)
		message["protocol_version"] = _config.protocol_version
		message["seq"] = session["seq"]
		message["server_time"] = _world.server_time
		sent.append(message)


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)
	var provider := MockCombatSnapshotProvider.new(seed.combat_units_by_entity())
	var resolver := CountingResolver.new()
	var rules: CombatRules = DEFAULT_RULES.duplicate(true) as CombatRules
	var service := CombatService.new(world, provider, resolver, rules)
	var gateway := RecordingGateway.new(
		config,
		MockClientAuthenticator.new(seed),
		world,
		service,
	)
	gateway.add_test_session(1)
	var target_id: String = _default_target_id(seed)

	gateway.process_message(1, _attack("unauthenticated", target_id))
	var unauthenticated: Dictionary = gateway.last_message()
	_check(unauthenticated.get("error_code") == "ERR_NOT_AUTHENTICATED",
		"attack debe autenticar antes de procesarse")
	_check(unauthenticated.get("request_type") == "attack", "error de auth identifica Combat")
	_check(unauthenticated.get("request_id") == "unauthenticated", "error de auth correlaciona request_id")
	_check(resolver.calls == 0, "ataque no autenticado no llega al resolver")

	gateway.process_message(1, {
		"type": "auth",
		"protocol_version": "team3-m2.0",
		"jwt": seed.accepted_token,
	})
	_check(gateway.last_message().get("type") == "auth_ok", "sesión mock se autentica")

	var forbidden_fields: Array[String] = ["attacker", "player_id", "ship_id", "units", "damage", "outcome"]
	for field: String in forbidden_fields:
		var spoofed: Dictionary = _attack("spoof-%s" % field, target_id)
		spoofed[field] = "client-controlled-value"
		gateway.process_message(1, spoofed)
		var rejection: Dictionary = gateway.last_message()
		_check(rejection.get("error_code") == CombatService.ERROR_INVALID_ATTACK_REQUEST,
			"campo prohibido %s debe rechazarse" % field)
		_check(rejection.get("request_type") == "attack", "rechazo de spoof identifica Combat")
	_check(resolver.calls == 0, "intentos de suplantación no ejecutan resolver")
	_check(provider.total_application_count() == 0, "intentos de suplantación no aplican bajas")

	gateway.process_message(1, {
		"type": "start_travel",
		"protocol_version": "team3-m2.0",
		"destination": [],
	})
	var travel_error: Dictionary = gateway.last_message()
	_check(travel_error.get("error_code") == "INVALID_REQUEST", "error Travel existente se conserva")
	_check(not travel_error.has("request_type"), "error Travel no se confunde con error Combat")

	gateway.process_message(1, _attack("valid-gateway", target_id))
	var result: Dictionary = gateway.last_message()
	_check(result.get("type") == "combat_result", "gateway devuelve combat_result")
	_check(result.get("protocol_version") == "team3-m2.0", "Combat extiende team3-m2.0 sin migración")
	_check(result.get("request_id") == "valid-gateway", "resultado correlaciona request_id")
	_check(not str(result.get("combat_id", "")).is_empty(), "resultado contiene combat_id del servidor")
	_check(resolver.calls == 1, "gateway ejecuta una sola resolución válida")

	gateway.free()
	_finish()


func _attack(request_id: String, target_entity_id: String) -> Dictionary:
	return {
		"type": "attack",
		"protocol_version": "team3-m2.0",
		"request_id": request_id,
		"target_entity_id": target_entity_id,
	}


func _default_target_id(seed: MockWorldSeed) -> String:
	for entry: Dictionary in seed.extra_entities():
		if str(entry.get("kind", "")) == "ship":
			return str(entry.get("entity_id", ""))
	return ""


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("COMBAT_GATEWAY_TEST_FAILED: %s" % message)


func _finish() -> void:
	print("COMBAT_GATEWAY_TEST_OK" if _failures == 0 else "COMBAT_GATEWAY_TEST_FAILED failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)
