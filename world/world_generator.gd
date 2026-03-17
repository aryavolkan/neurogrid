class_name WorldGenerator
extends RefCounted
## Procedural terrain and food placement for the grid world.


static func generate(world: GridWorld) -> void:
	_generate_terrain(world)
	_place_initial_food(world)


static func _generate_terrain(world: GridWorld) -> void:
	## Generate terrain using simple noise-based biomes.
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
