class_name WorldGenerator
extends RefCounted
## Procedural terrain, elevation, resources, and nesting site placement.


static func generate(world: GridWorld) -> void:
	_generate_terrain(world)
	_place_initial_food(world)
	_place_resources(world)
	_place_nesting_sites(world)


static func _generate_terrain(world: GridWorld) -> void:
	## Generate terrain and elevation using noise-based biomes.
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.06

	var moisture_noise := FastNoiseLite.new()
	moisture_noise.seed = randi()
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.frequency = 0.04

	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		var elevation: float = noise.get_noise_2d(pos.x, pos.y)
		var moisture: float = moisture_noise.get_noise_2d(pos.x, pos.y)

		# Store raw elevation on tile
		tile.elevation = elevation

		if elevation < -0.3:
			tile.terrain = GameConfig.Terrain.WATER
		elif elevation > 0.4:
			tile.terrain = GameConfig.Terrain.ROCK
		elif elevation > 0.25:
			tile.terrain = GameConfig.Terrain.SAND
		elif moisture > 0.1:
			tile.terrain = GameConfig.Terrain.FOREST
		else:
			tile.terrain = GameConfig.Terrain.GRASS


static func _place_initial_food(world: GridWorld) -> void:
	## Place food on a fraction of grass and forest tiles.
	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		if tile.terrain == GameConfig.Terrain.GRASS or tile.terrain == GameConfig.Terrain.FOREST:
			if randf() < GameConfig.FOOD_SPAWN_DENSITY:
				tile.food = randf_range(5.0, GameConfig.MAX_FOOD_PER_TILE)
	world.mark_food_dirty()


static func _place_resources(world: GridWorld) -> void:
	## Place minerals near rock and medicinal plants in forests.
	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		# Minerals near rock formations
		if tile.terrain == GameConfig.Terrain.SAND or tile.terrain == GameConfig.Terrain.ROCK:
			if randf() < 0.1:
				tile.minerals = randf_range(3.0, 10.0)
		# Medicinal plants in forests
		if tile.terrain == GameConfig.Terrain.FOREST:
			if randf() < 0.08:
				tile.medicinal = randf_range(2.0, 8.0)


static func _place_nesting_sites(world: GridWorld) -> void:
	## Scatter nesting sites on passable tiles with high elevation (sheltered spots).
	var nest_count: int = 0
	var max_nests: int = 10
	# Collect candidate tiles — prefer elevated forest/grass
	var candidates: Array = []
	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		if tile.is_passable() and tile.elevation > 0.1:
			candidates.append(tile)

	candidates.shuffle()
	for tile in candidates:
		if nest_count >= max_nests:
			break
		tile.is_nest = true
		nest_count += 1
