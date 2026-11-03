extends RefCounted
## Enlace en memoria con un GameServer embebido (modo local / Android sin red).
## Copia profunda en ambos sentidos y entrega diferida: el cliente se comporta
## exactamente igual que con WebSocket (no comparte referencias con el servidor).

signal message_received(msg: Dictionary)
signal opened
signal closed(reason: String)

var _server: Node
var _sid: int = -1


func open(server: Node) -> void:
	_server = server
	_sid = server.open_session(_deliver)
	opened.emit.call_deferred()


func _deliver(msg: Dictionary) -> void:
	message_received.emit.call_deferred(msg.duplicate(true))


func send(msg: Dictionary) -> void:
	if _server == null or _sid < 0:
		return
	_server.handle_message.call_deferred(_sid, msg.duplicate(true))


func poll() -> void:
	pass


func close() -> void:
	if _server != null and _sid >= 0 and is_instance_valid(_server):
		_server.close_session(_sid)
	_sid = -1


func is_open() -> bool:
	return _sid >= 0
