class_name SolarSystemWorld
extends RefCounted

var system_id: String
var map_size: Vector2i
var tick_count: int = 0
var server_time: int = 0

var _config: SssConfig
var entity_registry: EntityRegistry
var spatial_hash: SpatialHash
var aoi_engine: AoiEngine

## ChangeSet del último tick; perdura hasta el siguiente tick. Cada sesión filtra
## su propia vista por AOI sin destruirlo.
var change_set: WorldChangeSet

## Fuente del tiempo inyectable para tests (Callable() -> int, Unix ms).
## Por defecto usa el reloj del sistema; los tests de viaje la reemplazan.
var _now_ms: Callable


func _init(config: SssConfig, seed: MockWorldSeed) -> void:
	_config = config
	system_id = seed.system_id
	map_size = config.map_size
	entity_registry = EntityRegistry.new()
	spatial_hash = SpatialHash.new(config.spatial_cell_size)
	aoi_engine = AoiEngine.new(spatial_hash, config.aoi_radius)
	change_set = WorldChangeSet.new()
	_now_ms = _system_now_ms
	_update_server_time()
	# Sembrar mundo: nave del jugador + entidades extra del MockWorldSeed.
	_register_ship_from_seed(seed)
	for entry: Dictionary in seed.extra_entities():
		var entity_id: String = str(entry.get("entity_id", ""))
		if entity_id == "":
			continue
		var kind: String = str(entry.get("kind", "asteroid"))
		var pos_arr: Array = entry.get("position", [0, 0])
		var pos := Vector2i(
			int(pos_arr[0]) if pos_arr.size() > 0 else 0,
			int(pos_arr[1]) if pos_arr.size() > 1 else 0,
		)
		var payload: Dictionary = entry.get("payload", {})
		_register_mock_entity(entity_id, kind, pos, payload)


func _system_now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## Inyecta una fuente de tiempo para tests (Callable() -> int en Unix ms).
func set_now_provider(provider: Callable) -> void:
	_now_ms = provider


func tick() -> void:
	tick_count += 1
	_update_server_time()
	_process_travel_arrivals()
	_materialize_travel_positions()


## Limpia el ChangeSet del tick anterior. NO drena por sesión.
func acknowledge_changes() -> void:
	change_set.clear()


# ---------------------------------------------------------------------------
# Viaje de la astronave (TEAM3-M2-I)
# ---------------------------------------------------------------------------

## Mensaje de intención `start_travel` acordado: el SSS deriva la nave del
## player_id de la sesión autenticada. Devuelve una Dictionary con "ok" o
## "error_code"+"message".
func start_travel(player_id: String, destination: Vector2i) -> Dictionary:
	var ship: EntityState = _ship_for_player(player_id)
	if ship == null:
		return _travel_error("SHIP_NOT_FOUND", "No ship for player")
	if destination.x < 0 or destination.y < 0 or destination.x >= map_size.x or destination.y >= map_size.y:
		return _travel_error("INVALID_DESTINATION", "Destination out of map")
	if destination == ship.position:
		return _travel_error("INVALID_DESTINATION", "Destination equals origin")
	if not ship.is_traveling() and ship.state != "ANCHORED":
		return _travel_error("SHIP_NOT_ANCHORED", "Ship is not anchored")
	if ship.is_traveling():
		return _travel_error("SHIP_NOT_ANCHORED", "Ship is already traveling")

	var origin: Vector2i = ship.position
	var dist: float = TravelMath.distance(origin, destination)
	var depart_ts: int = _now_ms.call()
	var arrive_ts_value: int = TravelMath.arrive_ts(depart_ts, dist, _config.travel_speed_tiles_per_min)

	var old_pos: Vector2i = ship.position
	ship.state = "TRAVELING"
	ship.travel = {
		"origin": [origin.x, origin.y],
		"destination": [destination.x, destination.y],
		"depart_ts": depart_ts,
		"arrive_ts": arrive_ts_value,
	}
	# La posición lógica NO cambia en el tick 0 (sigue en origin); el ChangeSet
	# propaga el cambio de estado + campos de viaje.
	change_set.update_entity(ship, old_pos)
	return {"ok": true, "arrive_ts": arrive_ts_value}


## Nave del jugador autenticado (única con kind == "ship" y player_id == player_id).
func _ship_for_player(player_id: String) -> EntityState:
	for entity: EntityState in entity_registry.all():
		if entity.kind == "ship" and str(entity.payload.get("player_id", "")) == player_id:
			return entity
	return null


## Procesa llegadas: now >= arrive_ts -> position = destination, ANCHORED, travel limpio.
func _process_travel_arrivals() -> void:
	var now: int = _now_ms.call()
	for entity: EntityState in entity_registry.all():
		if not entity.is_traveling():
			continue
		var arrive_ts_value: int = int(entity.travel.get("arrive_ts", 0))
		if now >= arrive_ts_value:
			var destination: Vector2i = _travel_destination(entity)
			var old_pos: Vector2i = entity.position
			entity.position = destination
			entity.state = "ANCHORED"
			entity.travel = {}
			spatial_hash.move(entity.entity_id, old_pos, destination)
			change_set.update_entity(entity, old_pos)


## Materializa la posición derivada de timestamps a 2 Hz (spec GAL3-001).
## Se llama en cada tick: actualiza entity.position, SpatialHash y ChangeSet
## si la posición derivada cambió.
func _materialize_travel_positions() -> void:
	var now: int = _now_ms.call()
	for entity: EntityState in entity_registry.all():
		if not entity.is_traveling():
			continue
		var derived: Vector2i = TravelMath.position_at(
			Vector2i(int(entity.travel.get("origin", [0, 0])[0]), int(entity.travel.get("origin", [0, 0])[1])),
			_travel_destination(entity),
			int(entity.travel.get("depart_ts", 0)),
			int(entity.travel.get("arrive_ts", 0)),
			now,
		)
		if derived == entity.position:
			continue
		var old_pos: Vector2i = entity.position
		entity.position = derived
		spatial_hash.move(entity.entity_id, old_pos, derived)
		change_set.update_entity(entity, old_pos)


func _travel_destination(entity: EntityState) -> Vector2i:
	var dest: Array = entity.travel.get("destination", [0, 0])
	return Vector2i(int(dest[0]), int(dest[1]))


func _travel_error(error_code: String, message: String) -> Dictionary:
	return {"error_code": error_code, "message": message}


# ---------------------------------------------------------------------------
# Snapshots y deltas (sin cambios respecto a M1 salvo state/travel)
# ---------------------------------------------------------------------------

func full_snapshot_for(player_id: String) -> Dictionary:
	var player_pos: Vector2i = _player_position(player_id)
	if player_pos == Vector2i(-1, -1):
		return {
			"system_id": system_id,
			"map_size": [map_size.x, map_size.y],
			"full": true,
			"added": [],
			"updated": [],
			"removed": [],
		}
	var aoi_ids: Array = aoi_engine.entities_for(player_pos)
	var added: Array = []
	for eid: Variant in aoi_ids:
		var entity: EntityState = entity_registry.get_entity(str(eid))
		if entity != null and _is_in_aoi(entity.position, player_pos, _config.aoi_radius):
			added.append(entity.to_add_snapshot())
	return {
		"system_id": system_id,
		"map_size": [map_size.x, map_size.y],
		"full": true,
		"added": added,
		"updated": [],
		"removed": [],
	}


## Delta incremental para una sesión, filtrado por AOI. No drena el changeset.
## Resuelve las 4 transiciones de visibilidad por sesión:
## 1. previous outside + current inside -> added
## 2. previous inside  + current inside -> updated
## 3. previous inside  + current outside -> removed
## 4. previous outside + current outside -> nada
func delta_for(player_id: String) -> Dictionary:
	if not change_set.has_changes():
		return {}
	var player_pos: Vector2i = _player_position(player_id)
	if player_pos == Vector2i(-1, -1):
		return {}
	var player_entity: EntityState = _ship_for_player(player_id)
	var own_ship_id: String = "" if player_entity == null else player_entity.entity_id
	var radius: int = _config.aoi_radius
	var added_out: Array = []
	var updated_out: Array = []
	var removed_out: Array = []

	# 1. Entidades agregadas en el mundo (creación de entidad)
	for entity: EntityState in change_set.added():
		if _is_in_aoi(entity.position, player_pos, radius):
			added_out.append(entity.to_add_snapshot())

	# 2. Entidades modificadas / movidas en el mundo
	for item: Dictionary in change_set.updated():
		var entity: EntityState = item.get("entity")
		if entity == null:
			continue
		# La nave del jugador ES el centro del AOI: el cliente siempre la tiene,
		# así que cualquier cambio sobre ella es un `updated` (nunca added/removed).
		# Sin esto, un salto grande (llegada) clasificaría outside->inside (added)
		# porque el centro se recentra con la nave en el mismo tick.
		if entity.entity_id == own_ship_id:
			updated_out.append(entity.to_updated_snapshot())
			continue
		var prev_pos: Vector2i = item.get("previous_position", entity.position)
		var curr_pos: Vector2i = entity.position
		var prev_in: bool = _is_in_aoi(prev_pos, player_pos, radius)
		var curr_in: bool = _is_in_aoi(curr_pos, player_pos, radius)

		if not prev_in and curr_in:
			# Caso 1: outside -> inside => added (entidad completa)
			added_out.append(entity.to_add_snapshot())
		elif prev_in and curr_in:
			# Caso 2: inside -> inside => updated (entity_id + campos modificados)
			updated_out.append(entity.to_updated_snapshot())
		elif prev_in and not curr_in:
			# Caso 3: inside -> outside => removed (solo entity_id)
			if not removed_out.has(entity.entity_id):
				removed_out.append(entity.entity_id)
		else:
			# Caso 4: outside -> outside => nada
			pass

	# 3. Entidades eliminadas del mundo (destrucción de entidad)
	for entry: Dictionary in change_set.removed():
		var eid: String = str(entry.get("entity_id", ""))
		var pos: Vector2i = entry.get("position", Vector2i(-1, -1))
		if pos == Vector2i(-1, -1):
			continue
		if _is_in_aoi(pos, player_pos, radius):
			if not removed_out.has(eid):
				removed_out.append(eid)

	if added_out.is_empty() and updated_out.is_empty() and removed_out.is_empty():
		return {}
	return {
		"system_id": system_id,
		"full": false,
		"added": added_out,
		"updated": updated_out,
		"removed": removed_out,
	}


func _is_in_aoi(pos: Vector2i, aoc: Vector2i, radius: int) -> bool:
	return abs(pos.x - aoc.x) <= radius and abs(pos.y - aoc.y) <= radius


# ---------------------------------------------------------------------------
# API de prueba / mock (M1 intacta)
# ---------------------------------------------------------------------------

func add_mock_entity(entity_id: String, kind: String, position: Vector2i, payload: Dictionary = {}) -> void:
	_register_mock_entity(entity_id, kind, position, payload)
	var entity: EntityState = entity_registry.get_entity(entity_id)
	if entity != null:
		change_set.add_entity(entity)


func set_entity_position(entity_id: String, position: Vector2i) -> void:
	var entity: EntityState = entity_registry.get_entity(entity_id)
	if entity == null:
		return
	var old: Vector2i = entity.position
	if old == position:
		return
	entity.position = position
	spatial_hash.move(entity_id, old, position)
	change_set.update_entity(entity, old)


func remove_mock_entity(entity_id: String) -> void:
	var entity: EntityState = entity_registry.get_entity(entity_id)
	if entity == null:
		return
	var pos: Vector2i = entity.position
	spatial_hash.remove(entity_id, pos)
	entity_registry.erase(entity_id)
	change_set.remove_entity(entity_id, pos)


func _register_ship_from_seed(seed: MockWorldSeed) -> void:
	var entity := EntityState.new(seed.entity_id, "ship", seed.ship_position)
	entity.payload = {
		"ship_id": seed.ship_id,
		"player_id": seed.player_id,
		"system_id": seed.system_id,
		"display_name": seed.ship_name,
	}
	entity.state = "ANCHORED"
	_register_entity(entity)


func _register_mock_entity(entity_id: String, kind: String, position: Vector2i, payload: Dictionary) -> void:
	var entity := EntityState.new(entity_id, kind, position)
	entity.payload = payload.duplicate(true) if payload != null else {}
	_register_entity(entity)


func _register_entity(entity: EntityState) -> void:
	entity_registry.add(entity)
	spatial_hash.insert(entity.entity_id, entity.position)


func _player_position(player_id: String) -> Vector2i:
	var ship: EntityState = _ship_for_player(player_id)
	if ship == null:
		return Vector2i(-1, -1)
	return ship.position


func _update_server_time() -> void:
	server_time = _now_ms.call()