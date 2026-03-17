class_name PheromoneLayer
extends RefCounted
## Pheromone grid with diffusion and decay.

const DECAY_RATE: float = 0.02
const DIFFUSION_RATE: float = 0.01

var world: GridWorld


func _init(p_world: GridWorld) -> void:
	world = p_world


func deposit(pos: Vector2i, amount: float) -> void:
	var tile: GridTile = world.get_tile(pos)
	if tile:
		tile.pheromone = clampf(tile.pheromone + amount, 0.0, 1.0)


func update(_delta: float) -> void:
	## Decay and diffuse pheromones each tick.
	# Collect current values
	var new_values: Dictionary = {}

	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		if tile.pheromone < 0.001:
			continue

		# Decay
		var val: float = tile.pheromone * (1.0 - DECAY_RATE)

		# Diffuse to neighbors
		var neighbors := world.get_adjacent_positions(pos)
		var diffuse_amount: float = val * DIFFUSION_RATE
		val -= diffuse_amount * neighbors.size()

		for npos in neighbors:
			new_values[npos] = new_values.get(npos, 0.0) + diffuse_amount

		new_values[pos] = new_values.get(pos, 0.0) + maxf(val, 0.0)

	# Apply new values
	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		tile.pheromone = clampf(new_values.get(pos, 0.0), 0.0, 1.0)
