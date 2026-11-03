extends RefCounted
## Mundo del Sistema Solar (SSS, Equipo 3 §3): grid 600×600, terreno estático
## (Portal de Salto y gigantes gaseosos no ocupables), entidades dinámicas
## (astronaves ancladas, asteroides N1-N5 más ricos hacia el centro, xenoformas).

const U = preload("res://shared/util.gd")
const SpatialHash = preload("res://server/sss/spatial_hash.gd")

var srv: Node
var hash := SpatialHash.new(16)
var map_size: int = 600
var center := Vector2(300, 300)


func _init(server: Node) -> void:
	srv = server
	map_size = int(Catalog.cfg("map_size", 600))
	center = Vector2(map_size / 2.0, map_size / 2.0)


func entities() -> Dictionary:
	return srv.cur["entities"]


func get_entity(id: String) -> Dictionary:
	return entities().get(id, {})


func rebuild_index() -> void:
	hash.clear()
	for id: String in entities():
		var e: Dictionary = entities()[id]
		hash.insert(id, Vector2i(U.v2(e["pos"])))


func add_entity(e: Dictionary) -> void:
	e["rev"] = int(e.get("rev", 0)) + 1
	entities()[e["id"]] = e
	hash.insert(e["id"], Vector2i(U.v2(e["pos"])))


func remove_entity(id: String) -> void:
	entities().erase(id)
	hash.remove(id)


func move_entity(id: String, pos: Vector2i) -> void:
	var e: Dictionary = get_entity(id)
	if e.is_empty():
		return
	e["pos"] = [pos.x, pos.y]
	hash.move(id, pos)
	bump(e)


func bump(e: Dictionary) -> void:
	e["rev"] = int(e.get("rev", 0)) + 1


# ---------------------------------------------------------------- terreno

func terrain() -> Array:
	return srv.cur.get("terrain", [])


func is_blocked(pos: Vector2, margin: float = 0.0) -> bool:
	if pos.x < 3 or pos.y < 3 or pos.x > map_size - 4 or pos.y > map_size - 4:
		return true
	for t: Dictionary in terrain():
		if pos.distance_to(U.v2(t["pos"])) <= float(t["radius"]) + margin:
			return true
	return false


func is_free(pos: Vector2, radius: float = 2.0) -> bool:
	if is_blocked(pos, 1.0):
		return false
	return not hash.any_within(pos, radius)


func find_free_near(origin: Vector2, min_r: float, max_r: float, rng: RandomNumberGenerator, spacing: float = 2.5, attempts: int = 60) -> Vector2i:
	for _i: int in range(attempts):
		var ang: float = rng.randf() * TAU
		var r: float = rng.randf_range(min_r, max_r)
		var p: Vector2 = (origin + Vector2(cos(ang), sin(ang)) * r).round()
		if is_free(p, spacing):
			return Vector2i(p)
	return Vector2i(-1, -1)


func level_for_distance(d: float, rng: RandomNumberGenerator) -> int:
	var lo: int = 1
	if d < 95.0:
		lo = 4
	elif d < 155.0:
		lo = 3
	elif d < 215.0:
		lo = 2
	return clampi(lo + (1 if rng.randf() < 0.35 else 0), 1, 5)


# ---------------------------------------------------------------- generación

func generate(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	srv.cur["entities"] = {}
	hash.clear()
	var terr: Array = []
	terr.append({"id": "portal", "kind": "portal", "name": U.t("Portal de Salto"), "pos": [center.x, center.y], "radius": float(Catalog.cfg("portal_radius", 14))})
	var planet_names: Array = srv.galaxy.planet_names(seed)
	var planet_colors: Array = ["#d98c5f", "#5fa8d9", "#9b7bd9", "#5fd9a1"]
	for i: int in range(4):
		var ang: float = TAU * (i / 4.0) + rng.randf_range(-0.4, 0.4)
		var dist: float = rng.randf_range(120.0, 230.0)
		var pos: Vector2 = center + Vector2(cos(ang), sin(ang)) * dist
		terr.append({"id": "planet_%d" % i, "kind": "planet", "name": planet_names[i], "pos": [roundf(pos.x), roundf(pos.y)], "radius": rng.randf_range(9.0, 15.0), "color": planet_colors[i]})
	srv.cur["terrain"] = terr

	var asteroid_count: int = int(Catalog.cfg("asteroid_count", 2000))
	var xeno_count: int = int(Catalog.cfg("xenoform_count", 1000))
	for i: int in range(asteroid_count):
		var p: Vector2i = _random_free(rng, 3.0)
		if p.x < 0:
			continue
		spawn_asteroid(level_for_distance(Vector2(p).distance_to(center), rng), p, rng)
	for i: int in range(xeno_count):
		var p2: Vector2i = _random_free(rng, 3.0)
		if p2.x < 0:
			continue
		spawn_xenoform(level_for_distance(Vector2(p2).distance_to(center), rng), p2, rng)


func _random_free(rng: RandomNumberGenerator, spacing: float) -> Vector2i:
	for _i: int in range(40):
		# Distribución uniforme en el disco del sistema (las esquinas quedan vacías).
		var ang: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf()) * (map_size / 2.0 - 8.0)
		var p: Vector2 = (center + Vector2(cos(ang), sin(ang)) * r).round()
		if is_free(p, spacing):
			return Vector2i(p)
	return Vector2i(-1, -1)


func spawn_asteroid(level: int, pos: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var lvl: Dictionary = Catalog.asteroid_level(level)
	var element: String = Catalog.mining_element_ids[rng.randi() % Catalog.mining_element_ids.size()]
	var e: Dictionary = {
		"id": "ast_%s" % U.new_id(),
		"kind": "asteroid",
		"pos": [pos.x, pos.y],
		"level": level,
		"element": element,
		"quantity": int(lvl.get("quantity", 500)),
		"remaining": int(lvl.get("quantity", 500)),
		"occupant": "",
		"variant": rng.randi() % 4,
	}
	add_entity(e)
	return e


func spawn_xenoform(level: int, pos: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var species: Array = Catalog.xeno.get("species", [])
	var sp: Dictionary = species[rng.randi() % species.size()]
	var hp: int = int(Catalog.xeno_level(level).get("hp", 1000))
	var e: Dictionary = {
		"id": "xen_%s" % U.new_id(),
		"kind": "xenoform",
		"pos": [pos.x, pos.y],
		"level": level,
		"species": sp["id"],
		"hp": hp,
		"max_hp": hp,
	}
	add_entity(e)
	return e


## Al agotarse/morir, la entidad reaparece cerca (mantiene la densidad local).
func schedule_respawn(e: Dictionary, delay_sec: float) -> void:
	var list: Array = srv.cur.get("respawns", [])
	list.append({
		"kind": e["kind"], "level": int(e.get("level", 1)), "near": e["pos"],
		"at": U.now_ms() + int(delay_sec * 1000.0),
	})
	srv.cur["respawns"] = list


func process_respawns(now: int) -> void:
	var list: Array = srv.cur.get("respawns", [])
	if list.is_empty():
		return
	var keep: Array = []
	var rng: RandomNumberGenerator = srv.rng
	for r: Dictionary in list:
		if int(r["at"]) > now:
			keep.append(r)
			continue
		var p: Vector2i = find_free_near(U.v2(r["near"]), 4.0, 30.0, rng, 3.0)
		if p.x < 0:
			continue
		if r["kind"] == "asteroid":
			spawn_asteroid(int(r["level"]), p, rng)
		elif r["kind"] == "xenoform":
			spawn_xenoform(int(r["level"]), p, rng)
	srv.cur["respawns"] = keep


func query_view(view_center: Vector2, radius: float) -> Array:
	var r: int = ceili(radius)
	var c := Vector2i(view_center.round())
	return hash.query_rect(c - Vector2i(r, r), c + Vector2i(r, r))


## Busca entidades de un tipo cerca de un punto, ordenadas por distancia.
func nearest_of_kind(origin: Vector2, kind: String, max_r: float, filter: Callable = Callable()) -> Array:
	var out: Array = []
	for id: String in hash.query_radius(origin, max_r):
		var e: Dictionary = get_entity(id)
		if e.is_empty() or e["kind"] != kind:
			continue
		if filter.is_valid() and not bool(filter.call(e)):
			continue
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return U.v2(a["pos"]).distance_squared_to(origin) < U.v2(b["pos"]).distance_squared_to(origin))
	return out
