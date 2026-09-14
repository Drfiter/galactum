class_name TravelMath
extends RefCounted
## Matemática pura del viaje de astronave (TEAM3-M2-I).
## Sin I/O, sin estado: toda función es estática y testeable en aislamiento.
## - El SSS es la fuente del tiempo: los timestamps son Unix ms enteros.
## - La velocidad vive en SssConfig (configurable) y NO aquí.

const MS_PER_MIN := 60_000


## Distancia euclídea en casillas del grid 600×600.
static func distance(origin: Vector2i, destination: Vector2i) -> float:
	return Vector2(origin).distance_to(Vector2(destination))


## Duración del viaje en milisegundos.
static func duration_ms(distance_tiles: float, speed_tiles_per_min: float) -> int:
	if speed_tiles_per_min <= 0.0:
		return 0
	return int(distance_tiles / speed_tiles_per_min * float(MS_PER_MIN))


## arrive_ts = depart_ts + duración.
static func arrive_ts(depart_ts: int, distance_tiles: float, speed_tiles_per_min: float) -> int:
	return depart_ts + duration_ms(distance_tiles, speed_tiles_per_min)


## Posición derivada del tiempo en `now_ms` entre origin y destination.
## - now_ms <= depart_ts -> origin
## - now_ms >= arrive_ts -> destination
## - en el medio: interpolación lineal (spec GAL3-001: derivada, no integrada).
static func position_at(
		origin: Vector2i,
		destination: Vector2i,
		depart_ts: int,
		arrive_ts: int,
		now_ms: int,
) -> Vector2i:
	var span: int = arrive_ts - depart_ts
	if span <= 0:
		return destination
	var t: float = clampf(float(now_ms - depart_ts) / float(span), 0.0, 1.0)
	var p := Vector2(origin).lerp(Vector2(destination), t)
	return Vector2i(roundi(p.x), roundi(p.y))