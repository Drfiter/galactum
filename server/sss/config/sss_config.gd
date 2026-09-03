class_name SssConfig
extends Resource

@export var protocol_version: String = "team3-m0.1"
@export_range(1, 65535, 1) var port: int = 9100
@export_range(0.5, 10.0, 0.5) var tick_hz: float = 2.0
@export var map_size: Vector2i = Vector2i(600, 600)
