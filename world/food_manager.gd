class_name FoodManager
extends RefCounted
## Handles food regeneration with scarcity pressure and seasonal cycles.
## Uses sparse tile lists for performance instead of scanning all 4096 tiles.

var world: GridWorld

# Seasonal cycle: oscillates regen rate between abundance and famine
var _season_tick: int = 0
const SEASON_LENGTH: int = 1000  # Ticks per full cycle (abundance → famine → abundance)

# Global food budget (tracked incrementally)
var _total_food: float = 0.0
const MAX_GLOBAL_FOOD: float = 8000.0  # Cap on total food in world

# Pre-computed tile lists (built once during setup)
var _regen_tiles: Array = []  # Tiles eligible for food regen (grass/forest, no wall)
var _corpse_tiles: Dictionary = {}  # Vector2i -> true (tiles with active corpses)
var _initialized: bool = false


func _init(p_world: GridWorld) -> void:
	world = p_world


func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_total_food = 0.0
	_regen_tiles.clear()
	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		_total_food += tile.food
		if (tile.terrain == GameConfig.Terrain.GRASS or tile.terrain == GameConfig.Terrain.FOREST) and not tile.wall:
			_regen_tiles.append(pos)
		if tile.corpse_energy > 0.0:
			_corpse_tiles[pos] = true


func add_corpse(pos: Vector2i) -> void:
	## Track a new corpse tile for sparse decay.
	_corpse_tiles[pos] = true


func adjust_food_total(delta: float) -> void:
	## Call when food is consumed or added externally to keep total in sync.
	_total_food += delta


func update(_delta: float, ecology: EcologySystem = null, weather: WeatherSystem = null) -> void:
	## Called each tick. Regenerates food with seasonal modifier, global cap, hotspot, and weather.
	_ensure_initialized()
	_season_tick += 1

	# Seasonal modifier: sin wave from 0.3 (famine) to 1.5 (abundance)
	var season_phase: float = float(_season_tick) / float(SEASON_LENGTH) * TAU
	var season_mod: float = 0.9 + 0.6 * sin(season_phase)

	var any_changed := false

	# Regen food on eligible tiles
	if _total_food < MAX_GLOBAL_FOOD:
		for pos in _regen_tiles:
			if _total_food >= MAX_GLOBAL_FOOD:
				break
			var tile: GridTile = world.tiles[pos]
			if tile.food < GameConfig.MAX_FOOD_PER_TILE:
				var regen_rate: float = GameConfig.FOOD_REGEN_RATE * season_mod
				if tile.terrain == GameConfig.Terrain.FOREST:
					regen_rate *= 1.5
				# Migration hotspot bonus
				if ecology:
					regen_rate += ecology.get_hotspot_food_bonus(pos)
				# Weather bonus (rain)
				if weather:
					regen_rate += weather.get_food_regen_bonus()
				var added := minf(regen_rate, MAX_GLOBAL_FOOD - _total_food)
				added = minf(added, GameConfig.MAX_FOOD_PER_TILE - tile.food)
				if added > 0.0:
					tile.food += added
					_total_food += added
					any_changed = true

	# Decay corpse energy (sparse)
	if not _corpse_tiles.is_empty():
		var expired: Array = []
		for pos in _corpse_tiles:
			var tile: GridTile = world.tiles[pos]
			tile.corpse_energy = maxf(tile.corpse_energy - 0.1, 0.0)
			any_changed = true
			if tile.corpse_energy <= 0.0:
				expired.append(pos)
		for pos in expired:
			_corpse_tiles.erase(pos)

	if any_changed:
		world.mark_food_dirty()


func get_season_phase() -> float:
	## Returns 0.0 to 1.0 indicating position in seasonal cycle.
	return fmod(float(_season_tick), float(SEASON_LENGTH)) / float(SEASON_LENGTH)


func get_total_food() -> float:
	_ensure_initialized()
	return _total_food


func is_famine() -> bool:
	## Returns true during the scarce half of the cycle.
	var phase := get_season_phase()
	return phase > 0.25 and phase < 0.75
