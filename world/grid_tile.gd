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

# Phase 13: World Complexity
var elevation: float = 0.0      # -1.0 (valley) to 1.0 (peak), affects movement cost + sensor range
var minerals: float = 0.0       # Resource for wall building (reduces build_wall energy cost)
var medicinal: float = 0.0      # Resource for healing (boosts heal_self effectiveness)
var is_nest: bool = false        # Nesting site — offspring get bonus energy here
var vegetation: float = 0.0      # Dynamic vegetation level, grows over time on grass/forest

# Pre-computed values (call update_cached_values() after changing elevation or terrain)
var movement_cost_mult: float = 1.0  # Cached elevation movement cost multiplier
var sensor_bonus_range: int = 0       # Cached elevation sensor bonus
var is_sand: bool = false             # Cached terrain check


func _init(pos: Vector2i, p_terrain: int = GameConfig.Terrain.GRASS) -> void:
	position = pos
	terrain = p_terrain
	is_sand = (terrain == GameConfig.Terrain.SAND)


func update_cached_values() -> void:
	## Call after changing elevation or terrain to refresh cached multipliers.
	movement_cost_mult = 1.0 + clampf(elevation, -0.5, 1.0)
	sensor_bonus_range = int(elevation * 3.0) if elevation > 0.3 else 0
	is_sand = (terrain == GameConfig.Terrain.SAND)


func is_passable() -> bool:
	return not wall and terrain != GameConfig.Terrain.ROCK and terrain != GameConfig.Terrain.WATER


func is_occupied() -> bool:
	return occupant_id >= 0


func has_food() -> bool:
	return food > 0.0 or corpse_energy > 0.0


func get_elevation_movement_cost() -> float:
	## Uphill costs more, downhill costs less. Returns multiplier 0.5–2.0.
	return movement_cost_mult


func get_elevation_sensor_bonus() -> int:
	## High ground extends sensor range. Returns 0–3 extra tiles.
	return sensor_bonus_range
