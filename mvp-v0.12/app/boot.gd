extends Node
## Punto de entrada. Con `--server` arranca el SSS dedicado (headless, WebSocket);
## sin argumentos abre el juego (título -> partida local embebida o remota).

const GameServerScript = preload("res://server/game_server.gd")
const Gateway = preload("res://server/net/ws_gateway.gd")


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--server") or OS.has_feature("dedicated_server"):
		_start_dedicated(args)
	else:
		get_tree().change_scene_to_file.call_deferred("res://ui/title.tscn")


func _start_dedicated(args: PackedStringArray) -> void:
	var port: int = 9100
	var fresh: bool = args.has("--fresh")
	for a: String in args:
		if a.begins_with("--port="):
			port = clampi(int(a.trim_prefix("--port=")), 1, 65535)
	var env_port: String = OS.get_environment("SSS_PORT")
	if env_port.is_valid_int():
		port = int(env_port)
	var server: Node = GameServerScript.new()
	server.name = "GameServer"
	add_child(server)
	server.start({"save_path": "user://galactum_server_save.json", "fresh": fresh})
	var gw: Node = Gateway.new()
	gw.name = "Gateway"
	add_child(gw)
	if gw.start(server, port) != OK:
		push_error("No se pudo abrir el puerto %d" % port)
		get_tree().quit(1)
