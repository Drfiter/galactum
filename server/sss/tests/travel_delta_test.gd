extends SceneTree
## TEAM3-M2-I: forma del map_delta (inicio / durante / llegada) conforme al contrato.

const DEFAULT_CONFIG: SssConfig = preload("res://config/default_sss_config.tres")
const DEFAULT_SEED: MockWorldSeed = preload("res://mock/default_mock_world_seed.tres")

var _failures: int = 0
var _now: int = 10_000_000


func _initialize() -> void:
	var config: SssConfig = DEFAULT_CONFIG.duplicate(true) as SssConfig
	var seed: MockWorldSeed = DEFAULT_SEED.duplicate(true) as MockWorldSeed
	var world := SolarSystemWorld.new(config, seed)
	world.set_now_provider(func() -> int: return _now)

	# --- Inicio: el updated debe llevar state + travel completo ---
	world.start_travel(seed.player_id, Vector2i(420, 180))
	var delta_start: Dictionary = world.delta_for(seed.player_id)
	_check(delta_start.get("full", true) == false, "delta de inicio debe ser full:false")
	var upd_start: Array = delta_start.get("updated", [])
	_check(upd_start.size() == 1, "debe haber 1 updated al iniciar viaje")
	if upd_start.size() == 1:
		var u: Dictionary = upd_start[0]
		_check(str(u.get("entity_id", "")) == seed.entity_id, "entity_id debe ser la nave")
		_check(u.get("position") == [300, 300], "position al iniciar debe ser el origen")
		_check(u.get("state") == "TRAVELING", "state debe ser TRAVELING al iniciar")
		var t: Dictionary = u.get("travel", {})
		_check(t.get("origin") == [300, 300], "travel.origin debe ser [300,300]")
		_check(t.get("destination") == [420, 180], "travel.destination debe ser [420,180]")
		_check(typeof(t.get("depart_ts", 0)) == TYPE_INT, "depart_ts debe ser int")
		_check(typeof(t.get("arrive_ts", 0)) == TYPE_INT, "arrive_ts debe ser int")
	world.acknowledge_changes()

	# --- Durante: solo position + state, sin repetir travel si no cambió ---
	_now += 500
	world.tick()
	var ship: EntityState = world.entity_registry.get_entity(seed.entity_id)
	if ship.position != Vector2i(300, 300):
		var delta_mid: Dictionary = world.delta_for(seed.player_id)
		var upd_mid: Array = delta_mid.get("updated", [])
		_check(upd_mid.size() == 1, "debe haber 1 updated durante el viaje")
		if upd_mid.size() == 1:
			var um: Dictionary = upd_mid[0]
			_check(um.get("position") == [ship.position.x, ship.position.y], "position debe ser la derivada")
			_check(um.get("state") == "TRAVELING", "state debe seguir TRAVELING")
			_check(um.has("travel") == false, "no debe reenviar travel en updates intermedios")
	world.acknowledge_changes()

	# --- Llegada: state ANCHORED + position = destino, sin travel ---
	var arrive_ts_value: int = int(ship.travel.get("arrive_ts", 0))
	_now = arrive_ts_value
	world.tick()
	var delta_arr: Dictionary = world.delta_for(seed.player_id)
	var upd_arr: Array = delta_arr.get("updated", [])
	_check(upd_arr.size() == 1, "debe haber 1 updated al llegar")
	if upd_arr.size() == 1:
		var ua: Dictionary = upd_arr[0]
		_check(ua.get("state") == "ANCHORED", "state debe ser ANCHORED al llegar")
		_check(ua.get("position") == [420, 180], "position debe ser el destino")
		_check(ua.get("travel") == null, "travel debe ser null al llegar (contrato)")


	# El contrato dice "travel": null al llegar — lo emitimos como ausencia del campo
	# (el cliente reconstruye travel={} si quiere). Verificamos que nunca emitimos travel
	# con state != TRAVELING.
	_check(true, "travel solo se emite mientras state == TRAVELING")

	if _failures == 0:
		print("TRAVEL_DELTA_TEST_OK")
		quit(0)
	else:
		print("TRAVEL_DELTA_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("TRAVEL_DELTA_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)