class_name CreatureSpawner
extends RefCounted
## Creates and places creatures on the grid.

var world: GridWorld
var config: DynamicConfig
var conn_tracker  # NeatInnovation
var io_tracker: IoInnovation
var weather_system: WeatherSystem  # Optional — set after init
var _next_creature_id: int = 0


func _init(p_world: GridWorld, p_config: DynamicConfig, p_conn_tracker, p_io_tracker: IoInnovation) -> void:
	world = p_world
	config = p_config
	conn_tracker = p_conn_tracker
	io_tracker = p_io_tracker


func spawn_creature(genome: DynamicGenome, pos: Vector2i = Vector2i(-1, -1), energy: float = GameConfig.OFFSPRING_ENERGY) -> Creature:
	## Spawn a single creature. If pos is (-1,-1), find a random empty tile.
	if pos == Vector2i(-1, -1):
		pos = _find_random_empty_tile()
	if pos == Vector2i(-1, -1):
		return null  # No space

	var creature := Creature.new()
	var sensor := CreatureSensor.new(world, weather_system)
	creature.setup(_next_creature_id, pos, genome, sensor, energy)
	_next_creature_id += 1

	# Register in world
	world.set_creature_position(creature.creature_id, pos)
	var tile: GridTile = world.get_tile(pos)
	if tile:
		tile.occupant_id = creature.creature_id

	return creature


func spawn_random_creature() -> Creature:
	## Create a creature with a fresh random genome.
	var genome := DynamicGenome.create(config, conn_tracker, io_tracker)
	return spawn_creature(genome, Vector2i(-1, -1), GameConfig.STARTING_ENERGY)


func _find_random_empty_tile() -> Vector2i:
	## Find a random passable, unoccupied tile.
	for _attempt in 100:
		var pos := Vector2i(randi() % world.width, randi() % world.height)
		if world.is_passable(pos):
			return pos
	return Vector2i(-1, -1)
