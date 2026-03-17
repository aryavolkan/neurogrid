class_name CreatureSensor
extends RefCounted
## Reads sensory data from the world for a creature's active receptor set.

var world: GridWorld


func _init(p_world: GridWorld) -> void:
	world = p_world


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


func get_receptor_value(registry_id: int, pos: Vector2i, body: CreatureBody, creature_id: int) -> float:
	## Query the world for a specific receptor value.
	match registry_id:
		0:  # smell_food_dist
			return _query_food_dist(pos, 5)
		1:  # smell_food_dx
			return _query_food_dx(pos, 5)
		2:  # smell_food_dy
			return _query_food_dy(pos, 5)
		3:  # sense_enemy_dist
			return _query_enemy_dist(pos, 4, creature_id, body.species_id)
		4:  # sense_enemy_dx
			return _query_enemy_dx(pos, 4, creature_id, body.species_id)
		5:  # sense_ally_count
			return _query_ally_count(pos, 4, creature_id, body.species_id)
		6:  # detect_pheromone
			return _query_pheromone(pos)
		7:  # sense_terrain
			return _query_terrain(pos)
	return 0.0


func _query_food_dist(pos: Vector2i, max_range: int) -> float:
	var food_pos := world.find_nearest_food(pos, max_range)
	if food_pos.x < 0:
		return 0.0
	var dist: float = abs(food_pos.x - pos.x) + abs(food_pos.y - pos.y)
	return 1.0 - (dist / float(max_range))  # Closer = higher


func _query_food_dx(pos: Vector2i, max_range: int) -> float:
	var food_pos := world.find_nearest_food(pos, max_range)
	if food_pos.x < 0:
		return 0.0
	return clampf(float(food_pos.x - pos.x) / float(max_range), -1.0, 1.0)


func _query_food_dy(pos: Vector2i, max_range: int) -> float:
	var food_pos := world.find_nearest_food(pos, max_range)
	if food_pos.x < 0:
		return 0.0
	return clampf(float(food_pos.y - pos.y) / float(max_range), -1.0, 1.0)


func _query_enemy_dist(pos: Vector2i, max_range: int, creature_id: int, species_id: int) -> float:
	# For now, treat all other creatures as potential enemies (different species)
	var nearest := world.find_nearest_creature(pos, max_range, creature_id)
	if nearest.is_empty():
		return 0.0
	return 1.0 - (float(nearest.dist) / float(max_range))


func _query_enemy_dx(pos: Vector2i, max_range: int, creature_id: int, species_id: int) -> float:
	var nearest := world.find_nearest_creature(pos, max_range, creature_id)
	if nearest.is_empty():
		return 0.0
	return clampf(float(nearest.pos.x - pos.x) / float(max_range), -1.0, 1.0)


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
