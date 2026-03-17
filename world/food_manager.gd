class_name FoodManager
extends RefCounted
## Handles food regeneration with scarcity pressure and seasonal cycles.

var world: GridWorld

# Seasonal cycle: oscillates regen rate between abundance and famine
var _season_tick: int = 0
const SEASON_LENGTH: int = 1000  # Ticks per full cycle (abundance → famine → abundance)

# Global food budget
var _total_food: float = 0.0
const MAX_GLOBAL_FOOD: float = 4000.0  # Cap on total food in world


func _init(p_world: GridWorld) -> void:
	world = p_world


func update(_delta: float) -> void:
	## Called each tick. Regenerates food with seasonal modifier and global cap.
	_season_tick += 1

	# Seasonal modifier: sin wave from 0.3 (famine) to 1.5 (abundance)
	var season_phase: float = float(_season_tick) / float(SEASON_LENGTH) * TAU
	var season_mod: float = 0.9 + 0.6 * sin(season_phase)

	# Recalculate total food
	_total_food = 0.0
	var any_changed := false

	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		_total_food += tile.food

		if tile.terrain == GameConfig.Terrain.GRASS or tile.terrain == GameConfig.Terrain.FOREST:
			if tile.food < GameConfig.MAX_FOOD_PER_TILE and not tile.wall:
				# Only regen if under global budget
				if _total_food < MAX_GLOBAL_FOOD:
					var regen_rate: float = GameConfig.FOOD_REGEN_RATE * season_mod
					if tile.terrain == GameConfig.Terrain.FOREST:
						regen_rate *= 1.5
					var added := minf(regen_rate, MAX_GLOBAL_FOOD - _total_food)
					tile.food = minf(tile.food + added, GameConfig.MAX_FOOD_PER_TILE)
					_total_food += added
					any_changed = true

		# Decay corpse energy
		if tile.corpse_energy > 0.0:
			tile.corpse_energy = maxf(tile.corpse_energy - 0.1, 0.0)
			any_changed = true

	if any_changed:
		world.mark_food_dirty()


func get_season_phase() -> float:
	## Returns 0.0 to 1.0 indicating position in seasonal cycle.
	return fmod(float(_season_tick), float(SEASON_LENGTH)) / float(SEASON_LENGTH)


func get_total_food() -> float:
	return _total_food


func is_famine() -> bool:
	## Returns true during the scarce half of the cycle.
	var phase := get_season_phase()
	return phase > 0.25 and phase < 0.75
