class_name MockClientAuthenticator
extends ClientAuthenticator

var _seed: MockWorldSeed


func _init(seed: MockWorldSeed) -> void:
	_seed = seed


func authenticate(token: String) -> Dictionary:
	if token != _seed.accepted_token:
		return {}
	return {
		"player_id": _seed.player_id,
		"system_id": _seed.system_id,
	}
