class_name PheromoneLayer
extends RefCounted
## Pheromone grid with diffusion and decay. Uses sparse tracking for performance.

const DECAY_RATE: float = 0.02
const DIFFUSION_RATE: float = 0.01
const MIN_PHEROMONE: float = 0.001

var world: GridWorld
var _active_tiles: Dictionary = {}  # Vector2i -> true (tiles with non-zero pheromone)


func _init(p_world: GridWorld) -> void:
	world = p_world


func deposit(pos: Vector2i, amount: float) -> void:
	var tile: GridTile = world.get_tile(pos)
	if tile:
		tile.pheromone = clampf(tile.pheromone + amount, 0.0, 1.0)
		_active_tiles[pos] = true


func update(_delta: float) -> void:
	## Decay and diffuse pheromones each tick. Only processes active tiles.
	if _active_tiles.is_empty():
		return

	var new_values: Dictionary = {}
	var tiles_to_process: Array = _active_tiles.keys()

	for pos in tiles_to_process:
		var tile: GridTile = world.tiles[pos]
		if tile.pheromone < MIN_PHEROMONE:
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

	# Clear old active tiles
	for pos in tiles_to_process:
		world.tiles[pos].pheromone = 0.0
	_active_tiles.clear()

	# Apply new values, track new active set
	for pos in new_values:
		var val: float = new_values[pos]
		if val >= MIN_PHEROMONE:
			var tile: GridTile = world.get_tile(pos)
			if tile:
				tile.pheromone = clampf(val, 0.0, 1.0)
				_active_tiles[pos] = true
