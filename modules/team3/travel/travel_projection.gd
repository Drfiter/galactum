class_name TravelProjection
extends RefCounted
## Proyección visual de un viaje autoritativo recibido desde el SSS.
## Nunca modifica la entidad ni WorldState.


static func has_valid_travel(entity: Dictionary) -> bool:
	if str(entity.get("state", "")) != "TRAVELING":
		return false
	var raw_travel: Variant = entity.get("travel")
	if not raw_travel is Dictionary:
		return false
	var travel: Dictionary = raw_travel
	var origin: Variant = travel.get("origin")
	var destination: Variant = travel.get("destination")
	if not origin is Array or not destination is Array:
		return false
	if origin.size() != 2 or destination.size() != 2:
		return false
	var depart_ts: int = int(travel.get("depart_ts", 0))
	var arrive_ts: int = int(travel.get("arrive_ts", 0))
	return depart_ts > 0 and arrive_ts > depart_ts


static func display_position(entity: Dictionary, server_now_ms: int) -> Vector2:
	var fallback := _position_from(entity.get("position", [0, 0]))
	if not has_valid_travel(entity):
		return fallback
	var travel: Dictionary = entity["travel"]
	var origin := _position_from(travel["origin"])
	var destination := _position_from(travel["destination"])
	var depart_ts: int = int(travel["depart_ts"])
	var arrive_ts: int = int(travel["arrive_ts"])
	var progress: float = clampf(
		float(server_now_ms - depart_ts) / float(arrive_ts - depart_ts),
		0.0,
		1.0,
	)
	return origin.lerp(destination, progress)


static func remaining_milliseconds(entity: Dictionary, server_now_ms: int) -> int:
	if not has_valid_travel(entity):
		return 0
	var travel: Dictionary = entity["travel"]
	return maxi(0, int(travel["arrive_ts"]) - server_now_ms)


static func destination(entity: Dictionary) -> Vector2:
	if not has_valid_travel(entity):
		return display_position(entity, 0)
	var travel: Dictionary = entity["travel"]
	return _position_from(travel["destination"])


static func origin(entity: Dictionary) -> Vector2:
	if not has_valid_travel(entity):
		return display_position(entity, 0)
	var travel: Dictionary = entity["travel"]
	return _position_from(travel["origin"])


static func _position_from(value: Variant) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
