class_name WeatherSystem
extends RefCounted
## Phase 13: Weather and dynamic terrain. Rain, storms, fog, erosion, vegetation growth.

var world: GridWorld

# Weather state
enum Weather { CLEAR, RAIN, STORM, FOG }
var current_weather: int = Weather.CLEAR
var _weather_tick: int = 0
var _weather_duration: int = 0  # Ticks remaining for current weather

# Weather cycle parameters
const WEATHER_CHECK_INTERVAL: int = 200  # Check for weather change every N ticks
const RAIN_CHANCE: float = 0.25
const STORM_CHANCE: float = 0.10
const FOG_CHANCE: float = 0.15
const RAIN_DURATION_MIN: int = 150
const RAIN_DURATION_MAX: int = 400
const STORM_DURATION_MIN: int = 50
const STORM_DURATION_MAX: int = 150
const FOG_DURATION_MIN: int = 100
const FOG_DURATION_MAX: int = 300

# Weather effects
const RAIN_FOOD_REGEN_BONUS: float = 0.1   # Extra food regen during rain
const STORM_DAMAGE: float = 2.0             # Damage per tick to exposed creatures
const FOG_SENSOR_MULT: float = 0.4          # Sensor range multiplied during fog

# Dynamic terrain
const VEGETATION_GROWTH_RATE: float = 0.001  # Per tick on grass/forest
const VEGETATION_MAX: float = 1.0
const EROSION_RATE: float = 0.0001           # Elevation change per tick near water


func _init(p_world: GridWorld) -> void:
	world = p_world


func update(tick: int) -> void:
	_weather_tick = tick

	# Weather duration countdown
	if _weather_duration > 0:
		_weather_duration -= 1
		if _weather_duration <= 0:
			current_weather = Weather.CLEAR
	elif tick % WEATHER_CHECK_INTERVAL == 0:
		_roll_weather()

	# Dynamic terrain updates (every 10 ticks to save CPU)
	if tick % 10 == 0:
		_update_vegetation()
		_update_erosion()


func _roll_weather() -> void:
	var roll: float = randf()
	if roll < STORM_CHANCE:
		current_weather = Weather.STORM
		_weather_duration = randi_range(STORM_DURATION_MIN, STORM_DURATION_MAX)
	elif roll < STORM_CHANCE + RAIN_CHANCE:
		current_weather = Weather.RAIN
		_weather_duration = randi_range(RAIN_DURATION_MIN, RAIN_DURATION_MAX)
	elif roll < STORM_CHANCE + RAIN_CHANCE + FOG_CHANCE:
		current_weather = Weather.FOG
		_weather_duration = randi_range(FOG_DURATION_MIN, FOG_DURATION_MAX)


func _update_vegetation() -> void:
	## Vegetation grows on grass/forest, faster during rain.
	var rain_mult: float = 2.0 if current_weather == Weather.RAIN else 1.0
	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		if tile.terrain == GameConfig.Terrain.GRASS or tile.terrain == GameConfig.Terrain.FOREST:
			tile.vegetation = minf(tile.vegetation + VEGETATION_GROWTH_RATE * rain_mult, VEGETATION_MAX)
			# Dense vegetation converts grass to forest over very long time
			if tile.terrain == GameConfig.Terrain.GRASS and tile.vegetation > 0.9:
				tile.terrain = GameConfig.Terrain.FOREST
				tile.vegetation = 0.5


func _update_erosion() -> void:
	## Tiles adjacent to water slowly lose elevation (erosion).
	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		if tile.elevation <= -0.3:
			continue  # Already low
		# Check if adjacent to water
		var near_water: bool = false
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var np: Vector2i = pos + offset
			var neighbor: GridTile = world.tiles.get(np)
			if neighbor and neighbor.terrain == GameConfig.Terrain.WATER:
				near_water = true
				break
		if near_water:
			tile.elevation -= EROSION_RATE
			# Severe erosion can flood sand tiles
			if tile.terrain == GameConfig.Terrain.SAND and tile.elevation < -0.25:
				tile.terrain = GameConfig.Terrain.WATER


# --- Queries ---

func get_weather_name() -> String:
	match current_weather:
		Weather.CLEAR: return "Clear"
		Weather.RAIN: return "Rain"
		Weather.STORM: return "Storm"
		Weather.FOG: return "Fog"
	return "Clear"


func is_raining() -> bool:
	return current_weather == Weather.RAIN


func is_storm() -> bool:
	return current_weather == Weather.STORM


func is_fog() -> bool:
	return current_weather == Weather.FOG


func get_food_regen_bonus() -> float:
	if current_weather == Weather.RAIN:
		return RAIN_FOOD_REGEN_BONUS
	return 0.0


func get_sensor_multiplier() -> float:
	if current_weather == Weather.FOG:
		return FOG_SENSOR_MULT
	return 1.0


func get_storm_damage() -> float:
	if current_weather == Weather.STORM:
		return STORM_DAMAGE
	return 0.0
