class_name WorldState
extends RefCounted
## Réplica local (NO autoritativa) del mundo recibido desde el SSS.
## TEAM3-M1: soporta full_snapshot y map_delta incremental (added/updated/removed).
##
## WorldState NO decide posiciones, NO inventa entidades y NO exige que dos
## map_delta tengan seq consecutivo: la continuidad de seq se valida en
## SssConnection (todos los mensajes del SSS comparten una única secuencia).
## Aquí solo se registra el seq del último estado aplicado.

signal changed

var protocol_version: String = ""
var seq: int = -1
var server_time: int = 0
var system_id: String = ""
var map_size: Vector2i = Vector2i.ZERO
var _server_time_sample_ticks_msec: int = 0

# Réplica visible: entity_id -> Dictionary(entidad)
var entities: Dictionary = {}


## Limpia por completo el estado local y notifica a la presentación para que
## descarte marcadores obsoletos durante reconexión o resume.
func clear() -> void:
	protocol_version = ""
	seq = -1
	server_time = 0
	_server_time_sample_ticks_msec = 0
	system_id = ""
	map_size = Vector2i.ZERO
	entities.clear()
	changed.emit()


## Aplica un snapshot completo (map_delta con full == true).
## Reconstruye la réplica desde cero. Devuelve false si el sobre es inválido.
func apply_full_snapshot(message: Dictionary) -> bool:
	var incoming_seq: int = int(message.get("seq", -1))
	if incoming_seq < 0:
		return false
	var raw_map_size: Array = message.get("map_size", [0, 0])
	if raw_map_size.size() != 2:
		return false
	protocol_version = str(message.get("protocol_version", ""))
	seq = incoming_seq
	synchronize_server_time(int(message.get("server_time", 0)))
	system_id = str(message.get("system_id", ""))
	map_size = Vector2i(int(raw_map_size[0]), int(raw_map_size[1]))
	entities.clear()
	for raw_entity: Variant in message.get("added", []):
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		var entity_id: String = str(entity.get("entity_id", ""))
		if entity_id != "":
			entities[entity_id] = entity.duplicate(true)
	changed.emit()
	return true


## Aplica un delta incremental (map_delta con full == false).
## - added  : entidades completas que se insertan/sustituyen.
## - updated: mínimo entity_id + campos actualizados (merge sobre la existente).
## - removed: solo entity_id -> se elimina de la réplica visible.
## Si el mensaje llega con full == true se delega en apply_full_snapshot.
## Devuelve false si el sobre es inválido o la entidad de `updated` no existe.
func apply_map_delta(message: Dictionary) -> bool:
	if bool(message.get("full", false)):
		return apply_full_snapshot(message)
	var incoming_seq: int = int(message.get("seq", -1))
	if incoming_seq < 0:
		return false
	seq = incoming_seq
	synchronize_server_time(int(message.get("server_time", 0)))
	# system_id/map_size no se exigen en un delta (el SSS ya los publicó en full)

	for raw_entity: Variant in message.get("added", []):
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		var entity_id: String = str(entity.get("entity_id", ""))
		if entity_id != "":
			entities[entity_id] = entity.duplicate(true)

	for raw_entity: Variant in message.get("updated", []):
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		var entity_id: String = str(entity.get("entity_id", ""))
		if entity_id == "" or not entities.has(entity_id):
			# No inventar la entidad: si no la conocemos, quedamos desincronizados.
			return false
		# Merge: los campos presentes en el update sustituyen a los locales,
		# preservando los campos que no vienen.
		var merged: Dictionary = entities[entity_id].duplicate(true)
		for key: Variant in entity.keys():
			merged[key] = entity[key]
		entities[entity_id] = merged

	for raw_id: Variant in message.get("removed", []):
		var entity_id: String = str(raw_id)
		if entity_id != "":
			entities.erase(entity_id)

	changed.emit()
	return true


## Devuelve una copia de la entidad por entity_id, o {} si no existe.
func get_entity(entity_id: String) -> Dictionary:
	if entities.has(entity_id):
		return entities[entity_id].duplicate(true)
	return {}


## Devuelve la nave perteneciente al player_id autenticado, sin asumir que sea
## la primera nave de la réplica AOI.
func ship_for_player(player_id: String) -> Dictionary:
	if player_id == "":
		return {}
	for raw_entity: Variant in entities.values():
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		if (str(entity.get("kind", "")) == "ship"
			and str(entity.get("player_id", "")) == player_id):
			return entity.duplicate(true)
	return {}


func synchronize_server_time(value: int) -> void:
	if value <= 0:
		return
	server_time = value
	_server_time_sample_ticks_msec = Time.get_ticks_msec()


## Reloj visual estimado: muestra del reloj Unix autoritativo del SSS más el
## tiempo monotónico local transcurrido. No usa el reloj Unix del dispositivo.
func estimated_server_time_ms() -> int:
	if server_time <= 0 or _server_time_sample_ticks_msec <= 0:
		return server_time
	return server_time + maxi(0, Time.get_ticks_msec() - _server_time_sample_ticks_msec)


## Obtiene la primera nave (ship) de la réplica. Utilidad de diagnóstico M0/M1.
func first_ship() -> Dictionary:
	for entity: Variant in entities.values():
		if entity is Dictionary and str(entity.get("kind", "")) == "ship":
			return entity
	return {}
