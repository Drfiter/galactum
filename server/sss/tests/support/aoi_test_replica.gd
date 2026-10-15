extends RefCounted
## Baseline de una conexión en pruebas; aplica únicamente added/removed del contrato.

var known_ids: Array[String] = []


func _init(snapshot: Dictionary) -> void:
	for entity: Dictionary in snapshot.get("added", []):
		known_ids.append(str(entity["entity_id"]))


func apply(delta: Dictionary) -> void:
	for entity_id: String in delta.get("removed", []):
		known_ids.erase(entity_id)
	for entity: Dictionary in delta.get("added", []):
		var entity_id: String = str(entity["entity_id"])
		if not known_ids.has(entity_id):
			known_ids.append(entity_id)
