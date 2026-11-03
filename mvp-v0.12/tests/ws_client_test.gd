extends Node
## Cliente de prueba contra el SSS dedicado (WebSocket).
## godot --headless --path . res://tests/ws_client_test.tscn -- --name=Lucas

func _ready() -> void:
	var name: String = "Tester"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			name = a.trim_prefix("--name=")
	GameClient.start_remote("127.0.0.1", 9100, name, "p03")
	var t: float = 0.0
	while not GameClient.connected and t < 10.0:
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	print("[%s] connected=%s player_id=%s" % [name, GameClient.connected, GameClient.player_id])
	await get_tree().create_timer(2.0).timeout
	var bases: Array = []
	for id: String in GameClient.entities:
		var e: Dictionary = GameClient.entities[id]
		if e.get("kind") == "base" and not bool(e.get("is_bot", true)):
			bases.append(str(e.get("name", "")))
	print("[%s] entities=%d humans_visible=%s power=%s" % [name, GameClient.entities.size(), str(bases), str(GameClient.me.get("power", "?"))])
	var done: Array = [false]
	var target: String = ""
	for id: String in GameClient.entities:
		if GameClient.entities[id].get("kind") == "asteroid" and str(GameClient.entities[id].get("occupant_owner", "")).is_empty():
			target = id
			break
	GameClient.intent("march", {"mission": "gather", "target_id": target, "troops": {"infantry_1": 20}}, func(ok: bool, p: Dictionary) -> void:
		print("[%s] march ok=%s %s" % [name, ok, p.get("message", "")])
		done[0] = true)
	while not done[0]:
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(1.5).timeout
	print("[%s] fleets=%d" % [name, (GameClient.me.get("fleets", []) as Array).size()])
	get_tree().quit()
