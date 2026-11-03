extends Node

const U = preload("res://shared/util.gd")
## Gateway WebSocket del SSS dedicado. Cada conexión abre una sesión en el
## GameServer; el protocolo JSON es el mismo que usa el enlace local.

var server: Node
var port: int = 9100
var _tcp := TCPServer.new()
var _conns: Dictionary = {}  # sid -> WebSocketPeer
var _pending: Array = []     # WebSocketPeer aún en handshake


func start(game_server: Node, listen_port: int) -> Error:
	server = game_server
	port = listen_port
	var err: Error = _tcp.listen(port)
	if err == OK:
		print("SSS WebSocket escuchando en el puerto %d" % port)
	return err


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var conn: StreamPeerTCP = _tcp.take_connection()
		var peer := WebSocketPeer.new()
		peer.inbound_buffer_size = 1024 * 1024
		peer.outbound_buffer_size = 8 * 1024 * 1024
		if peer.accept_stream(conn) == OK:
			_pending.append(peer)
	for peer: WebSocketPeer in _pending.duplicate():
		peer.poll()
		var st: int = peer.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			_pending.erase(peer)
			var sid: int = server.open_session(func(msg: Dictionary) -> void:
				if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
					peer.send_text(JSON.stringify(msg)))
			_conns[sid] = peer
		elif st == WebSocketPeer.STATE_CLOSED:
			_pending.erase(peer)
	for sid: int in _conns.keys():
		var p: WebSocketPeer = _conns[sid]
		p.poll()
		match p.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while p.get_available_packet_count() > 0:
					var parsed: Variant = JSON.parse_string(p.get_packet().get_string_from_utf8())
					if parsed is Dictionary:
						server.handle_message(sid, parsed)
			WebSocketPeer.STATE_CLOSED:
				_conns.erase(sid)
				server.close_session(sid)


func stop() -> void:
	for sid: int in _conns:
		(_conns[sid] as WebSocketPeer).close(1001, "server stopping")
	_conns.clear()
	_tcp.stop()
