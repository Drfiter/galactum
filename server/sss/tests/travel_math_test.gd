extends SceneTree
## TEAM3-M2-I: matemática pura del viaje.

var _failures: int = 0


func _initialize() -> void:
	# --- distance ---
	_check(is_equal_approx(TravelMath.distance(Vector2i(0, 0), Vector2i(3, 4)), 5.0),
		"distance (0,0)->(3,4) debe ser 5.0")
	_check(is_equal_approx(TravelMath.distance(Vector2i(300, 300), Vector2i(300, 300)), 0.0),
		"distance a sí mismo debe ser 0.0")
	_check(is_equal_approx(TravelMath.distance(Vector2i(0, 0), Vector2i(600, 0)), 600.0),
		"distance horizontal debe ser 600.0")

	# --- duration_ms ---
	var d100: int = TravelMath.duration_ms(100.0, 10.0)
	_check(d100 == 600_000, "100 tiles @10 tpm debe ser 600000 ms, got %d" % d100)
	var d50: int = TravelMath.duration_ms(50.0, 10.0)
	_check(d50 == 300_000, "50 tiles @10 tpm debe ser 300000 ms, got %d" % d50)
	var d10w: int = TravelMath.duration_ms(10.0, 20.0)
	_check(d10w == 30_000, "10 tiles @20 tpm debe ser 30000 ms, got %d" % d10w)
	_check(TravelMath.duration_ms(100.0, 0.0) == 0, "velocidad 0 debe dar duración 0 (sin división por 0)")

	# --- arrive_ts ---
	var a0: int = TravelMath.arrive_ts(1_000_000, 60.0, 10.0)
	_check(a0 == 1_000_000 + 360_000, "arrive_ts = depart + duración, got %d" % a0)

	# --- position_at ---
	var origin := Vector2i(0, 0)
	var dest := Vector2i(100, 0)
	var dep: int = 1_000_000
	var arr: int = dep + 600_000
	_check(TravelMath.position_at(origin, dest, dep, arr, dep) == Vector2i(0, 0),
		"t=0 debe estar en origin")
	_check(TravelMath.position_at(origin, dest, dep, arr, dep + 300_000) == Vector2i(50, 0),
		"t=0.5 debe estar en (50,0)")
	_check(TravelMath.position_at(origin, dest, dep, arr, arr) == Vector2i(100, 0),
		"t=1.0 debe estar en destination")
	_check(TravelMath.position_at(origin, dest, dep, arr, arr + 5_000) == Vector2i(100, 0),
		"t>1 no debe pasarse del destino")
	_check(TravelMath.position_at(origin, dest, dep, arr, dep - 5_000) == Vector2i(0, 0),
		"t<0 no debe pasarse del origen")

	if _failures == 0:
		print("TRAVEL_MATH_TEST_OK")
		quit(0)
	else:
		print("TRAVEL_MATH_TEST_FAILED failures=%d" % _failures)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("TRAVEL_MATH_TEST_FAILED: %s" % message)


func _exit_tree() -> void:
	if _failures > 0:
		quit(1)