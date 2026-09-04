class_name WorldCamera2D
extends RefCounted
## Cámara 2D diagnóstica (TEAM3-M1) para la vista del mundo 600×600.
## Herramienta de diagnóstico, NO una decisión irreversible sobre la
## presentación final de Galactum.
##
## Responsabilidades:
## - convertir entre coordenadas de pantalla (del Control) y coordenadas del
##   mundo lógico (grid 600×600);
## - paneo (arrastre) y zoom (rueda / pellizco).
## No contiene estado de gameplay: solo transforma coordenadas.

var _screen_size: Vector2 = Vector2.ZERO

# Centro de la vista en coordenadas de mundo.
var _center: Vector2 = Vector2.ZERO

# Escala: píxeles por celda de mundo.
var _pixels_per_cell: float = 1.0

const MIN_PPC: float = 0.1
const MAX_PPC: float = 50.0


## Debe llamarse cuando el Control de la vista cambie de tamaño.
func set_screen_size(screen_size: Vector2) -> void:
	_screen_size = screen_size
	if _screen_size.x <= 0.0 or _screen_size.y <= 0.0:
		return
	# Inicializa el centro en el medio del mapa si no se ha fijado aún.
	if _center == Vector2.ZERO and _screen_size != Vector2.ZERO:
		_center = Vector2(300.0, 300.0)


func get_center() -> Vector2:
	return _center


func set_center(value: Vector2) -> void:
	_center = value


func get_pixels_per_cell() -> float:
	return _pixels_per_cell


## Conversión: coordenada de pantalla (local del Control) -> coordenada de mundo.
func screen_to_world(screen_pos: Vector2) -> Vector2:
	return _center + (screen_pos - _screen_size * 0.5) / _pixels_per_cell


## Conversión: coordenada de mundo -> coordenada de pantalla (local del Control).
func world_to_screen(world_pos: Vector2) -> Vector2:
	return (world_pos - _center) * _pixels_per_cell + _screen_size * 0.5


## Panea la cámara por un desplazamiento de pantalla (en píxeles).
func pan_by_pixels(screen_delta: Vector2) -> void:
	_center -= screen_delta / _pixels_per_cell


## Ajusta el zoom (factor multiplicativo) anclando en el punto de mundo que
## queda bajo el cursor/punto táctil screen_pos (rueda de mouse / pellizco).
func zoom_at_screen(screen_pos: Vector2, factor: float) -> void:
	var anchor_world: Vector2 = screen_to_world(screen_pos)
	_pixels_per_cell = clampf(_pixels_per_cell * factor, MIN_PPC, MAX_PPC)
	# Re-posiciona para que anchor_world vuelva a quedar bajo screen_pos.
	_center = anchor_world - (screen_pos - _screen_size * 0.5) / _pixels_per_cell


## Devuelve true si la vista muestra únicamente una región (AOI futura) o todo.
func is_fitted() -> bool:
	return _pixels_per_cell <= MIN_PPC * 1.001
