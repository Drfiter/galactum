extends Node
## Suite canónica (spec Equipo 3 §10): determinismo, conservación de tropas,
## ventaja de triángulo, rol de Escudos/Cañoneros, PvE y reglas de economía.
## Ejecutar:  godot --headless --path . res://tests/run_tests.tscn

const Resolver = preload("res://server/combat/combat_resolver.gd")
const Eco = preload("res://server/sgm/economy.gd")
const U = preload("res://shared/util.gd")

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("== Galactum: suite de pruebas ==")
	test_determinism()
	test_conservation()
	test_triangle()
	test_shields_absorb()
	test_gunners_siege()
	test_hunt()
	test_economy_apply()
	test_casualties_split()
	test_production_lazy()
	test_number_format()
	print("== %d OK, %d FALLIDAS ==" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  [OK]   ", name)
	else:
		failed += 1
		print("  [FAIL] ", name)


func side(stacks: Dictionary, perimeter: int = 0) -> Dictionary:
	return {"stacks": stacks, "mods": {}, "perimeter_hp": perimeter}


func test_determinism() -> void:
	var a: Dictionary = side({"infantry_1": 80, "drones_1": 40, "gunners_1": 20})
	var d: Dictionary = side({"pilots_1": 60, "shields_1": 30}, 900)
	var r1: String = JSON.stringify(Resolver.resolve(a, d, 12345))
	var r2: String = JSON.stringify(Resolver.resolve(a, d, 12345))
	var r3: String = JSON.stringify(Resolver.resolve(a, d, 999))
	check(r1 == r2, "determinismo: mismo input + seed => mismo resultado")
	check(r1 != r3, "seed distinto produce variación controlada")


func test_conservation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ok: bool = true
	var keys: PackedStringArray = Catalog.all_troop_keys()
	for i: int in range(300):
		var sa: Dictionary = {}
		var sd: Dictionary = {}
		for k: String in keys:
			if rng.randf() < 0.5:
				sa[k] = rng.randi_range(1, 120)
			if rng.randf() < 0.5:
				sd[k] = rng.randi_range(1, 120)
		var res: Dictionary = Resolver.resolve(side(sa), side(sd, rng.randi_range(0, 2000)), rng.randi())
		for pair: Array in [[sa, res["attacker"]], [sd, res["defender"]]]:
			var init: Dictionary = pair[0]
			var out: Dictionary = pair[1]
			for k: String in init:
				var surv: int = int(out["survivors"].get(k, 0))
				var lost: int = int(out["losses"].get(k, 0))
				if surv + lost != int(init[k]) or surv > int(init[k]) or surv < 0:
					ok = false
	check(ok, "propiedad: el total de tropas nunca crece (300 combates aleatorios)")


func _winrate(a_key: String, d_key: String, n: int) -> float:
	var wins: int = 0
	for i: int in range(n):
		var res: Dictionary = Resolver.resolve(side({a_key: 100}), side({d_key: 100}), 1000 + i)
		if Resolver.power_of(res["attacker"]["survivors"]) > Resolver.power_of(res["defender"]["survivors"]):
			wins += 1
	return float(wins) / n


func test_triangle() -> void:
	check(_winrate("infantry_1", "drones_1", 200) > 0.6, "Infantería > Drones (+30%)")
	check(_winrate("drones_1", "pilots_1", 200) > 0.6, "Drones > Pilotos (+30%)")
	check(_winrate("pilots_1", "infantry_1", 200) > 0.6, "Pilotos > Infantería (+30%)")


func test_shields_absorb() -> void:
	var with_s: Dictionary = Resolver.resolve(side({"infantry_1": 100}), side({"pilots_1": 60, "shields_1": 40}), 5)
	var without: Dictionary = Resolver.resolve(side({"infantry_1": 100}), side({"pilots_1": 60}), 5)
	var lost_with: int = int(with_s["defender"]["losses"].get("pilots_1", 0))
	var lost_without: int = int(without["defender"]["losses"].get("pilots_1", 0))
	check(lost_with < lost_without, "Escudos absorben el primer daño (pilotos perdidos %d < %d)" % [lost_with, lost_without])


func test_gunners_siege() -> void:
	var g: Dictionary = Resolver.resolve(side({"gunners_1": 60}), side({"infantry_1": 10}, 3000), 3)
	var i: Dictionary = Resolver.resolve(side({"infantry_1": 60}), side({"infantry_1": 10}, 3000), 3)
	var g_left: int = int(g["rounds"][0]["perimeter_left"])
	var i_left: int = int(i["rounds"][0]["perimeter_left"])
	check(g_left < i_left, "Cañoneros destruyen el Escudo Perimetral más rápido (tras R1: %d < %d)" % [g_left, i_left])


func test_hunt() -> void:
	var res: Dictionary = Resolver.resolve_hunt({"infantry_1": 100}, {}, "fisica", 1, 1500, 42)
	check(bool(res["killed"]), "100 de Infantería abaten una xenoforma N1 débil a lo físico")
	var res2: Dictionary = Resolver.resolve_hunt({"drones_1": 20}, {}, "fisica", 5, 32000, 42)
	check(not bool(res2["killed"]) and int(res2["xeno_hp_left"]) < 32000, "una flota pequeña solo daña a una N5 (HP persistente)")
	var phys: int = int(Resolver.resolve_hunt({"infantry_1": 50}, {}, "fisica", 3, 9000, 1)["damage"])
	var energ: int = int(Resolver.resolve_hunt({"infantry_1": 50}, {}, "energetica", 3, 9000, 1)["damage"])
	check(phys > energ, "la debilidad de la especie aumenta el daño (+50%)")


func _player() -> Dictionary:
	var p: Dictionary = {
		"id": "t", "resources": {"ore": 100, "credits": 50}, "items": {}, "rooms": {},
		"troops": {}, "wounded": {}, "cryo": {}, "idem": {}, "ledger": [],
	}
	for r: String in Catalog.room_order:
		p["rooms"][r] = {"level": 1, "pending": {}, "last_ts": 0}
	return p


func test_economy_apply() -> void:
	var p: Dictionary = _player()
	check(not Eco.apply(p, {"ore": -150, "credits": -10}, "test"), "apply rechaza saldos negativos")
	check(int(p["resources"]["credits"]) == 50, "rollback: ningún saldo cambia si la operación falla")
	Eco.apply(p, {"ore": 30}, "fleet", "fleet:abc:deliver")
	Eco.apply(p, {"ore": 30}, "fleet", "fleet:abc:deliver")
	check(int(p["resources"]["ore"]) == 130, "idempotencia: la misma clave no abona dos veces")


func test_casualties_split() -> void:
	var p: Dictionary = _player()
	p["rooms"]["medbay"]["level"] = 1  # capacidad 150
	var res: Dictionary = Eco.absorb_casualties(p, {"infantry_1": 250}, 1.0)
	check(int(res["wounded"].get("infantry_1", 0)) == 150, "heridos hasta la capacidad de la Bahía Médica")
	check(int(res["cryo"].get("infantry_1", 0)) == 80 and int(res["lost"].get("infantry_1", 0)) == 20, "bajas mortales: 80% Criosantuario / 20% perdidas")


func test_production_lazy() -> void:
	var p: Dictionary = _player()
	p["rooms"]["factory"]["last_ts"] = 0
	p["energy_ts"] = 0
	Eco.settle(p, 60000, true)
	var pend: float = float(p["rooms"]["factory"]["pending"].get("ore", 0.0))
	check(absf(pend - 40.0) < 0.01, "producción lazy: 1 minuto de Fábrica Nv1 = 40 Mineral")
	Eco.settle(p, 60000 * 500, true)
	check(float(p["rooms"]["factory"]["pending"]["ore"]) <= 40.0 * 20.0 + 0.01, "la producción se limita a su almacenamiento")


func test_number_format() -> void:
	var prev: String = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	check(U.fmt_int(1500) == "1,500", "formato en inglés: 1500 => 1,500")
	check(U.fmt_int(-250000) == "-250,000", "formato en inglés: negativos con coma de miles")
	check(U.fmt_num(1500) == "1.5K", "formato en inglés: 1500 => 1.5K")
	TranslationServer.set_locale("es")
	check(U.fmt_int(1500) == "1.500", "formato en español: 1500 => 1.500")
	check(U.fmt_num(1500) == "1,5K", "formato en español: 1500 => 1,5K")
	check(U.fmt_num(2_500_000) == "2,5M", "formato en español: millones con coma decimal")
	TranslationServer.set_locale(prev)
