class_name ClientConnectionConfig
extends Resource

@export var host: String = "127.0.0.1"
@export_range(1, 65535, 1) var port: int = 9100
@export var mock_token: String = "team3-m0-local-player"
@export var auto_connect: bool = true
@export var auto_reconnect: bool = true
@export_range(0.25, 30.0, 0.25) var reconnect_delay_seconds: float = 2.0
@export_range(1.0, 60.0, 0.5) var ping_interval_seconds: float = 5.0


func websocket_url() -> String:
	return "ws://%s:%d" % [host, port]
