extends RefCounted
## Índice espacial por celdas (spec Equipo 3 §3: spatial hash para queries de
## vecindad). Evita recorrer las miles de entidades del sistema en cada consulta AOI.

var _cell_size: int
var _cells: Dictionary = {}      # Vector2i(celda) -> Array[String]
var _positions: Dictionary = {}  # entity_id -> Vector2i


func _init(cell_size: int = 16) -> void:
	_cell_size = maxi(1, cell_size)


func _cell_of(pos: Vector2i) -> Vector2i:
	return Vector2i(floori(pos.x / float(_cell_size)), floori(pos.y / float(_cell_size)))


func insert(entity_id: String, pos: Vector2i) -> void:
	if _positions.has(entity_id):
		remove(entity_id)
	var cell: Vector2i = _cell_of(pos)
	if not _cells.has(cell):
		_cells[cell] = []
	(_cells[cell] as Array).append(entity_id)
	_positions[entity_id] = pos


func remove(entity_id: String) -> void:
	if not _positions.has(entity_id):
		return
	var cell: Vector2i = _cell_of(_positions[entity_id])
	if _cells.has(cell):
		var bucket: Array = _cells[cell]
		bucket.erase(entity_id)
		if bucket.is_empty():
			_cells.erase(cell)
	_positions.erase(entity_id)


func move(entity_id: String, pos: Vector2i) -> void:
	insert(entity_id, pos)


func has(entity_id: String) -> bool:
	return _positions.has(entity_id)


func clear() -> void:
	_cells.clear()
	_positions.clear()


func query_rect(min_pos: Vector2i, max_pos: Vector2i) -> Array:
	var out: Array = []
	var a: Vector2i = _cell_of(min_pos)
	var b: Vector2i = _cell_of(max_pos)
	for cy: int in range(a.y, b.y + 1):
		for cx: int in range(a.x, b.x + 1):
			var cell := Vector2i(cx, cy)
			if not _cells.has(cell):
				continue
			for id: String in _cells[cell]:
				var p: Vector2i = _positions[id]
				if p.x >= min_pos.x and p.x <= max_pos.x and p.y >= min_pos.y and p.y <= max_pos.y:
					out.append(id)
	return out


func query_radius(center: Vector2, radius: float) -> Array:
	var r: int = ceili(radius)
	var c := Vector2i(roundi(center.x), roundi(center.y))
	var out: Array = []
	for id: String in query_rect(c - Vector2i(r, r), c + Vector2i(r, r)):
		if Vector2(_positions[id]).distance_to(center) <= radius:
			out.append(id)
	return out


func any_within(center: Vector2, radius: float) -> bool:
	return not query_radius(center, radius).is_empty()
