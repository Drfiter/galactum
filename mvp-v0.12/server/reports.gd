extends RefCounted
## battle_reports (spec Equipo 3 §7): todo combate genera un informe para cada bando,
## con el desglose por rondas, versión del resolver y seed para replays.

const U = preload("res://shared/util.gd")
const KEEP: int = 60

var srv: Node


func _init(server: Node) -> void:
	srv = server


func list_for(pid: String) -> Array:
	return srv.state["reports"].get(pid, [])


func add(pid: String, report: Dictionary) -> void:
	var p: Dictionary = srv.player(pid)
	if p.is_empty() or p.get("is_bot", false):
		return
	report["id"] = "rep_%s" % U.new_id()
	report["ts"] = U.now_ms()
	report["read"] = false
	var list: Array = srv.state["reports"].get(pid, [])
	list.push_front(report)
	while list.size() > KEEP:
		list.pop_back()
	srv.state["reports"][pid] = list
	srv.send_to_player(pid, {"type": "report", "report": report})
	srv.mark_player_dirty(pid)


func unread(pid: String) -> int:
	var n: int = 0
	for r: Dictionary in list_for(pid):
		if not bool(r.get("read", false)):
			n += 1
	return n


func mark_read(pid: String, report_id: String) -> void:
	for r: Dictionary in list_for(pid):
		if report_id.is_empty() or r["id"] == report_id:
			r["read"] = true
	srv.mark_player_dirty(pid)
