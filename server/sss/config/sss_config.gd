class_name SssConfig
extends Resource

@export var protocol_version: String = "team3-m1.0"
@export_range(1, 65535, 1) var port: int = 9100
@export_range(0.5, 10.0, 0.5) var tick_hz: float = 2.0
@export var map_size: Vector2i = Vector2i(600, 600)
## Tamaño de celda del SpatialHash (independiente del radio de AOI).
@export_range(8, 256, 1) var spatial_cell_size: int = 50
## Radio del Area of Interest en unidades de mundo (independiente del cell size).
## Es una configuración interna del SSS; NO viaja al cliente en M1.
@export_range(1, 2000, 1) var aoi_radius: int = 50
