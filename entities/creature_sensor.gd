class_name CreatureSensor
extends RefCounted
## Reads sensory data from the world for a creature's active receptor set.

var world: GridWorld
var weather_system: WeatherSystem  # Optional — null in tests


func _init(p_world: GridWorld, p_weather: WeatherSystem = null) -> void:
	world = p_world
	weather_system = p_weather


func get_core_inputs(pos: Vector2i, body: CreatureBody) -> PackedFloat32Array:
	## Returns the 8 core inputs: energy, health, age, pos_x, pos_y, vel_x, vel_y, food_here
	var inputs := PackedFloat32Array()
	inputs.resize(GameConfig.CORE_INPUT_COUNT)

	inputs[0] = body.energy / GameConfig.MAX_ENERGY
	inputs[1] = body.health / GameConfig.MAX_HEALTH
	inputs[2] = float(body.age) / float(GameConfig.MAX_AGE)
	inputs[3] = float(pos.x) / float(GameConfig.GRID_WIDTH)
	inputs[4] = float(pos.y) / float(GameConfig.GRID_HEIGHT)
	inputs[5] = float(body.facing.x)  # Velocity proxy (last move dir)
	inputs[6] = float(body.facing.y)
	var tile: GridTile = world.get_tile(pos)
	inputs[7] = tile.food / GameConfig.MAX_FOOD_PER_TILE if tile else 0.0

	return inputs


## Per-tick sensor cache (reset each tick via begin_sensing)
var _cached_food_pos: Vector2i = Vector2i(-2, -2)  # -2 = not cached
var _cached_food_range: int = -1
var _cached_enemy: Dictionary = {}
var _cached_enemy_valid: bool = false
var _cached_enemy_range: int = -1


func begin_sensing() -> void:
	## Call once per tick per creature before querying receptors.
	_cached_food_pos = Vector2i(-2, -2)
	_cached_food_range = -1
	_cached_enemy_valid = false
	_cached_enemy_range = -1


func get_receptor_value(registry_id: int, pos: Vector2i, body: CreatureBody, creature_id: int) -> float:
	## Query the world for a specific receptor value.
	match registry_id:
		0:  # smell_food_dist
			var max_range := _effective_range(5, pos)
			var food_pos := _get_cached_food(pos, max_range)
			if food_pos.x < 0:
				return 0.0
			var dist: float = abs(food_pos.x - pos.x) + abs(food_pos.y - pos.y)
			return 1.0 - (dist / float(max_range))
		1:  # smell_food_dx
			var max_range := _effective_range(5, pos)
			var food_pos := _get_cached_food(pos, max_range)
			if food_pos.x < 0:
				return 0.0
			return clampf(float(food_pos.x - pos.x) / float(max_range), -1.0, 1.0)
		2:  # smell_food_dy
			var max_range := _effective_range(5, pos)
			var food_pos := _get_cached_food(pos, max_range)
			if food_pos.x < 0:
				return 0.0
			return clampf(float(food_pos.y - pos.y) / float(max_range), -1.0, 1.0)
		3:  # sense_enemy_dist
			var max_range := _effective_range(4, pos)
			var nearest := _get_cached_enemy(pos, max_range, creature_id)
			if nearest.is_empty():
				return 0.0
			return 1.0 - (float(nearest.dist) / float(max_range))
		4:  # sense_enemy_dx
			var max_range := _effective_range(4, pos)
			var nearest := _get_cached_enemy(pos, max_range, creature_id)
			if nearest.is_empty():
				return 0.0
			return clampf(float(nearest.pos.x - pos.x) / float(max_range), -1.0, 1.0)
		5:  # sense_ally_count
			return _query_ally_count(pos, _effective_range(4, pos), creature_id, body.species_id)
		6:  # detect_pheromone (tile-local, no range)
			return _query_pheromone(pos)
		7:  # sense_terrain (tile-local, no range)
			return _query_terrain(pos)
	return 0.0


func _effective_range(base_range: int, pos: Vector2i) -> int:
	## Apply elevation bonus and weather fog penalty to sensor range.
	var effective: int = base_range
	var tile: GridTile = world.get_tile(pos)
	if tile:
		effective += tile.sensor_bonus_range
	if weather_system:
		effective = int(float(effective) * weather_system.get_sensor_multiplier())
	return maxi(effective, 1)


func _get_cached_food(pos: Vector2i, max_range: int) -> Vector2i:
	if _cached_food_range == max_range:
		return _cached_food_pos
	_cached_food_pos = world.find_nearest_food(pos, max_range)
	_cached_food_range = max_range
	return _cached_food_pos


func _get_cached_enemy(pos: Vector2i, max_range: int, creature_id: int) -> Dictionary:
	if _cached_enemy_valid and _cached_enemy_range == max_range:
		return _cached_enemy
	_cached_enemy = world.find_nearest_creature(pos, max_range, creature_id)
	_cached_enemy_range = max_range
	_cached_enemy_valid = true
	return _cached_enemy


func _query_ally_count(pos: Vector2i, max_range: int, creature_id: int, species_id: int) -> float:
	var creatures := world.find_creatures_in_range(pos, max_range)
	# Count same species (placeholder: count all for MVP)
	return clampf(float(creatures.size()) / 10.0, 0.0, 1.0)


func _query_pheromone(pos: Vector2i) -> float:
	var tile: GridTile = world.get_tile(pos)
	return tile.pheromone if tile else 0.0


func _query_terrain(pos: Vector2i) -> float:
	var tile: GridTile = world.get_tile(pos)
	if not tile:
		return 0.0
	return float(tile.terrain) / 4.0  # Normalize to 0-1 (5 terrain types: 0-4)
