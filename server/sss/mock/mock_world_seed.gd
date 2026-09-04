class_name MockWorldSeed
extends Resource

@export var accepted_token: String = "team3-m0-local-player"
@export var system_id: String = "018f0000-0000-7000-8000-000000000003"
@export var player_id: String = "018f0000-0000-7000-8000-000000000001"
@export var ship_id: String = "018f0000-0000-7000-8000-000000000002"
@export var entity_id: String = "018f0000-0000-7000-8000-000000000004"
@export var ship_name: String = "M0 Dummy"
@export var ship_position: Vector2i = Vector2i(300, 300)

## Entidades adicionales de prueba (además de la nave del jugador en (300,300)).
## AOI por defecto: radio 50 → box [250,350]×[250,350]. Se usa para comprobar
## dentro/fuera, agregado/actualizado/eliminado.
## Cada entrada: { "entity_id": "...", "kind": "...", "position": [x,y], "payload": {...} }
func extra_entities() -> Array[Dictionary]:
	return [
		{
			"entity_id": "018f0000-0000-7000-8000-000000000005",
			"kind": "ship",
			"position": [340, 300],
			"payload": {"display_name": "Other Ship", "ship_id": "018f0000-0000-7000-8000-000000000006"},
		},
		{
			"entity_id": "018f0000-0000-7000-8000-000000000007",
			"kind": "asteroid",
			"position": [310, 290],
			"payload": {},
		},
		{
			"entity_id": "018f0000-0000-7000-8000-000000000008",
			"kind": "asteroid",
			"position": [550, 500],
			"payload": {},
		},
		{
			"entity_id": "018f0000-0000-7000-8000-000000000009",
			"kind": "xenoform",
			"position": [310, 315],
			"payload": {"display_name": "Xenoform Dummy"},
		},
	]
