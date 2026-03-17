class_name GridTile
extends RefCounted
## Data for a single grid tile.

var position: Vector2i
var terrain: int = GameConfig.Terrain.GRASS
var food: float = 0.0
var pheromone: float = 0.0
var wall: bool = false
var occupant_id: int = -1  # Creature ID or -1
var corpse_energy: float = 0.0


func _init(pos: Vector2i, p_terrain: int = GameConfig.Terrain.GRASS) -> void:
	position = pos
	terrain = p_terrain


func is_passable() -> bool:
	return not wall and terrain != GameConfig.Terrain.ROCK and terrain != GameConfig.Terrain.WATER


func is_occupied() -> bool:
	return occupant_id >= 0


func has_food() -> bool:
	return food > 0.0 or corpse_energy > 0.0
