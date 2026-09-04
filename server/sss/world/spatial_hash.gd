class_name SpatialHash
extends RefCounted

## Índice espacial por celdas cuadradas. Permite consultar entidades cercanas
## sin recorrer todo el registro del mundo.

var _cell_size: int
## cell_key "x,y" -> Array[String] de entity_id
var _cells: Dictionary = {}
## entity_id -> posición actual (para poder mover/eliminar de su celda previa)
var _positions: Dictionary = {}


func _init(p_cell_size: int) -> void:
	_cell_size = maxi(1, p_cell_size)


func cell_size() -> int:
	return _cell_size


func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


func _cell_of(position: Vector2i) -> Vector2i:
	return Vector2i(floori(position.x / float(_cell_size)), floori(position.y / float(_cell_size)))


func insert(entity_id: String, position: Vector2i) -> void:
	var cell: Vector2i = _cell_of(position)
	var key: String = _cell_key(cell)
	if not _cells.has(key):
		_cells[key] = []
	var bucket: Array = _cells[key]
	if not bucket.has(entity_id):
		bucket.append(entity_id)
	_positions[entity_id] = position


func move(entity_id: String, from: Vector2i, to: Vector2i) -> void:
	remove(entity_id, from)
	insert(entity_id, to)


func remove(entity_id: String, position: Vector2i) -> void:
	var key: String = _cell_key(_cell_of(position))
	if _cells.has(key):
		var bucket: Array = _cells[key]
		bucket.erase(entity_id)
		if bucket.is_empty():
			_cells.erase(key)
	_positions.erase(entity_id)


func query_rect(from: Vector2i, extent: Vector2i, result: Array) -> void:
	result.clear()
	var min_cell: Vector2i = _cell_of(from)
	var max_cell: Vector2i = _cell_of(from + extent)
	for cy in range(min_cell.y, max_cell.y + 1):
		for cx in range(min_cell.x, max_cell.x + 1):
			var key: String = _cell_key(Vector2i(cx, cy))
			if _cells.has(key):
				for entity_id: String in _cells[key]:
					result.append(entity_id)


func has(entity_id: String) -> bool:
	return _positions.has(entity_id)
