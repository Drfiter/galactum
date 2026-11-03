extends Node
## Harness de balance (spec Equipo 3 §10): simula N combates por matchup con
## composiciones muestreadas y emite winrates. Criterio de la spec: ningún
## matchup "espejo + ventaja" por debajo de 60% ni por encima de 75%.
## Ejecutar:  godot --headless --path . res://tools/balance_harness.tscn -- --n=10000
## Salida CSV: user://balance_report.csv (ruta absoluta impresa al final).

const Resolver = preload("res://server/combat/combat_resolver.gd")
## Fracción del ejército que el bando favorecido cambia por la fuerza con ventaja.
const SHARE_MIN: float = 0.10
const SHARE_MAX: float = 0.30


func _ready() -> void:
	var n: int = 10000
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = maxi(100, int(a.trim_prefix("--n=")))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var matchups: Array = [["infantry", "drones"], ["drones", "pilots"], ["pilots", "infantry"]]
	var lines: Array = ["matchup,ventaja,combates,victorias_favorecido,winrate,dentro_60_75"]
	var all_ok: bool = true
	print("== Harness de balance: %d combates por matchup ==" % n)
	for m: Array in matchups:
		var fav: String = m[0]
		var other: String = m[1]
		var wins: int = 0
		for i: int in range(n):
			# Espejo + ventaja: misma base de ejército mixto; el favorecido cambia
			# una parte de su composición por la fuerza que tiene ventaja.
			var size: int = rng.randi_range(60, 220)
			var share: float = rng.randf_range(SHARE_MIN, SHARE_MAX)
			var base: Dictionary = _mixed(rng, int(size * (1.0 - share)))
			var a: Dictionary = base.duplicate()
			var d: Dictionary = base.duplicate()
			var k: int = int(size * share)
			a[fav + "_1"] = int(a.get(fav + "_1", 0)) + k
			d[other + "_1"] = int(d.get(other + "_1", 0)) + k
			var res: Dictionary = Resolver.resolve({"stacks": a, "mods": {}}, {"stacks": d, "mods": {}}, rng.randi())
			if Resolver.power_of(res["attacker"]["survivors"]) > Resolver.power_of(res["defender"]["survivors"]):
				wins += 1
		var wr: float = float(wins) / n
		var ok: bool = wr >= 0.60 and wr <= 0.75
		all_ok = all_ok and ok
		lines.append("%s_vs_%s,triangulo,%d,%d,%.4f,%s" % [fav, other, n, wins, wr, "si" if ok else "no"])
		print("  %-9s > %-9s  winrate %.1f%%  %s" % [fav, other, wr * 100.0, "OK" if ok else "FUERA DE RANGO"])
	# Matchups de rol: Cañoneros contra Escudos y contra el triángulo.
	for m2: Array in [["gunners", "shields"], ["infantry", "gunners"]]:
		var w2: int = 0
		for i: int in range(n):
			var s: int = rng.randi_range(60, 200)
			var res2: Dictionary = Resolver.resolve({"stacks": {m2[0] + "_1": s}, "mods": {}}, {"stacks": {m2[1] + "_1": s}, "mods": {}}, rng.randi())
			if Resolver.power_of(res2["attacker"]["survivors"]) > Resolver.power_of(res2["defender"]["survivors"]):
				w2 += 1
		var wr2: float = float(w2) / n
		lines.append("%s_vs_%s,rol,%d,%d,%.4f,-" % [m2[0], m2[1], n, w2, wr2])
		print("  %-9s vs %-9s winrate %.1f%%  (informativo)" % [m2[0], m2[1], wr2 * 100.0])
	var f: FileAccess = FileAccess.open("user://balance_report.csv", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("CSV: ", ProjectSettings.globalize_path("user://balance_report.csv"))
	print("RESULTADO: ", "BALANCE OK" if all_ok else "REVISAR CATÁLOGO")
	get_tree().quit(0 if all_ok else 2)


func _mixed(rng: RandomNumberGenerator, total: int) -> Dictionary:
	var out: Dictionary = {}
	var types: Array = ["infantry", "drones", "pilots", "shields", "gunners"]
	var w: Array = []
	var ws: float = 0.0
	for t: String in types:
		var x: float = rng.randf_range(0.2, 1.0)
		w.append(x)
		ws += x
	for i: int in range(types.size()):
		var q: int = int(total * w[i] / ws)
		if q > 0:
			out[types[i] + "_1"] = q
	return out
