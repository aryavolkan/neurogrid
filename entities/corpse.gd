class_name Corpse
extends RefCounted
## Represents a dead creature's energy deposited on a tile.

static func create_from_creature(body: CreatureBody, tile: GridTile) -> void:
	## Deposit remaining energy as corpse food on the tile.
	var energy_deposit: float = maxf(body.energy * 0.5, 5.0)
	tile.corpse_energy += energy_deposit
