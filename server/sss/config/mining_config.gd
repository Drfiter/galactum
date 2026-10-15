class_name MiningConfig
extends Resource
## Diario efímero: no expulsar claves que permitirían repetir una intención.

@export_range(1, 1000000, 1) var max_intentions_per_player: int = 256
