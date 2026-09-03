class_name WorldDebugView
extends Control

var _world_state: WorldState


func set_world_state(world_state: WorldState) -> void:
	if _world_state != null and _world_state.changed.is_connected(queue_redraw):
		_world_state.changed.disconnect(queue_redraw)
	_world_state = world_state
	if _world_state != null:
		_world_state.changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("08111f"), true)
	var inset: float = 20.0
	var map_rect := Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0))
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return
	draw_rect(map_rect, Color("28405f"), false, 2.0)
	if _world_state == null or _world_state.map_size.x <= 0 or _world_state.map_size.y <= 0:
		return
	for raw_entity: Variant in _world_state.entities.values():
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		if str(entity.get("kind", "")) != "ship":
			continue
		var raw_position: Array = entity.get("position", [0, 0])
		if raw_position.size() != 2:
			continue
		var normalized := Vector2(
			float(raw_position[0]) / float(_world_state.map_size.x),
			float(raw_position[1]) / float(_world_state.map_size.y)
		)
		var marker_position := map_rect.position + normalized * map_rect.size
		draw_circle(marker_position, 14.0, Color("63d7ff"))
		draw_circle(marker_position, 18.0, Color("d9f7ff"), false, 2.0)
		draw_line(marker_position + Vector2(-8.0, 0.0), marker_position + Vector2(8.0, 0.0), Color("08111f"), 2.0)
		draw_line(marker_position + Vector2(0.0, -8.0), marker_position + Vector2(0.0, 8.0), Color("08111f"), 2.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
