extends RefCounted

const U = preload("res://shared/util.gd")
## Enlace WebSocket con un SSS dedicado (JSON). Compatible con export web/Android.

signal message_received(msg: Dictionary)
signal opened
signal closed(reason: String)

var _peer := WebSocketPeer.new()
var _was_open: bool = false
var _url: String = ""


func open_url(url: String) -> Error:
	_url = url
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = 4 * 1024 * 1024
	_peer.outbound_buffer_size = 1024 * 1024
	return _peer.connect_to_url(url)


func poll() -> void:
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				opened.emit()
			while _peer.get_available_packet_count() > 0:
				var text: String = _peer.get_packet().get_string_from_utf8()
				var parsed: Variant = JSON.parse_string(text)
				if parsed is Dictionary:
					message_received.emit(parsed)
		WebSocketPeer.STATE_CLOSED:
			if _was_open:
				_was_open = false
				closed.emit(U.t("Conexión cerrada (%d)") % _peer.get_close_code())
			elif not _url.is_empty():
				_url = ""
				closed.emit(U.t("No se pudo conectar al servidor"))


func send(msg: Dictionary) -> void:
	if _peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_peer.send_text(JSON.stringify(msg))


func close() -> void:
	_peer.close()


func is_open() -> bool:
	return _peer.get_ready_state() == WebSocketPeer.STATE_OPEN
