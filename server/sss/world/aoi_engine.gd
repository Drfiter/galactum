class_name AoiEngine
extends RefCounted

## Calcula qué entidades son relevantes para una posición de interés, usando
## el SpatialHash. En M1 el AOI es una región cuadrada de lado (radius*2+1)
## centrada en la posición, suficiente para la validación; la forma exacta es
## una decisión de gameplay abierta a M2.

var _spatial: SpatialHash
var _radius: int


func _init(spatial: SpatialHash, radius: int) -> void:
	_spatial = spatial
	_radius = maxi(0, radius)


func radius() -> int:
	return _radius


## Devuelve los entity_id dentro del AOI de una posición.
func entities_for(position: Vector2i) -> Array:
	var extent := Vector2i(_radius * 2, _radius * 2)
	var result: Array = []
	var from := position - Vector2i(_radius, _radius)
	_spatial.query_rect(from, extent, result)
	return result
