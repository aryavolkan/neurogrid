extends Node
## Integration tests: full lifecycle, reproduction, death, population maintenance.

var _config: DynamicConfig
var _conn_tracker  # NeatInnovation
var _io_tracker: IoInnovation
var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_setup()
	_test_creature_spawn_and_register()
	_test_creature_death_deposits_corpse()
	_test_creature_death_cleans_spatial_index()
	_test_reproduction_produces_valid_offspring()
	_test_food_manager_regrows_food()
	_test_genome_serialize_roundtrip()
	_test_io_innovation_consistency()
	_test_corpse_energy_minimum()
	_test_sensor_core_inputs_bounded()
	_print_results("Integration")


func _setup() -> void:
	_config = DynamicConfig.new()
	_conn_tracker = NeatInnovation.new()
	_io_tracker = IoInnovation.new()


func _test_creature_spawn_and_register() -> void:
	var world := GridWorld.new()
	world.setup()
	WorldGenerator.generate(world)
	var spawner := CreatureSpawner.new(world, _config, _conn_tracker, _io_tracker)
	var creature := spawner.spawn_random_creature()
	_assert_true(creature != null, "creature spawned")
	_assert_true(creature.creature_id >= 0, "creature has id")
	_assert_true(creature.body.is_alive(), "creature is alive")
	_assert_true(world.get_creature_at(creature.grid_pos) == creature.creature_id, "registered in world")


func _test_creature_death_deposits_corpse() -> void:
	var world := GridWorld.new()
	world.setup()
	for pos in world.tiles:
		world.tiles[pos].terrain = GameConfig.Terrain.GRASS

	var spawner := CreatureSpawner.new(world, _config, _conn_tracker, _io_tracker)
	var creature := spawner.spawn_random_creature()
	creature.body.energy = 20.0
	var tile: GridTile = world.get_tile(creature.grid_pos)
	Corpse.create_from_creature(creature.body, tile)
	_assert_near(tile.corpse_energy, 10.0, 0.01, "corpse = 50% energy")


func _test_creature_death_cleans_spatial_index() -> void:
	var world := GridWorld.new()
	world.setup()
	for pos in world.tiles:
		world.tiles[pos].terrain = GameConfig.Terrain.GRASS

	var spawner := CreatureSpawner.new(world, _config, _conn_tracker, _io_tracker)
	var creature := spawner.spawn_random_creature()
	var pos := creature.grid_pos
	world.clear_creature_position(pos)
	_assert_eq(world.get_creature_at(pos), -1, "spatial index cleared")


func _test_reproduction_produces_valid_offspring() -> void:
	var world := GridWorld.new()
	world.setup()
	for pos in world.tiles:
		world.tiles[pos].terrain = GameConfig.Terrain.GRASS

	var spawner := CreatureSpawner.new(world, _config, _conn_tracker, _io_tracker)
	var parent_a := spawner.spawn_random_creature()
	var parent_b := spawner.spawn_random_creature()

	# Crossover
	var child_genome := DynamicGenome.crossover(parent_a.genome, parent_b.genome)
	child_genome.mutate()

	# Verify child genome is valid
	var inputs := child_genome.get_nodes_by_type([DynamicGenome.TYPE_CORE_INPUT])
	var outputs := child_genome.get_nodes_by_type([DynamicGenome.TYPE_CORE_OUTPUT])
	_assert_eq(inputs.size(), GameConfig.CORE_INPUT_COUNT, "child has core inputs")
	_assert_eq(outputs.size(), GameConfig.CORE_OUTPUT_COUNT, "child has core outputs")

	# Verify child can be built into network
	var net := DynamicNetwork.from_genome(child_genome)
	_assert_true(net.get_input_count() >= GameConfig.CORE_INPUT_COUNT, "child network valid")


func _test_food_manager_regrows_food() -> void:
	var world := GridWorld.new()
	world.setup()
	var tile: GridTile = world.get_tile(Vector2i(5, 5))
	tile.terrain = GameConfig.Terrain.GRASS
	tile.food = 0.0

	var fm := FoodManager.new(world)
	fm.update(0.0)
	_assert_true(tile.food > 0.0, "food regrew on grass")


func _test_genome_serialize_roundtrip() -> void:
	var g := DynamicGenome.create(_config, _conn_tracker, _io_tracker)
	g.mutate_add_receptor()
	g.mutate_add_skill()
	g.mutate_add_connection()
	g.fitness = 42.5

	var data := g.serialize()
	var restored := DynamicGenome.deserialize(data, _config, _conn_tracker, _io_tracker)

	_assert_eq(restored.node_genes.size(), g.node_genes.size(), "roundtrip node count")
	_assert_eq(restored.connection_genes.size(), g.connection_genes.size(), "roundtrip conn count")
	_assert_eq(restored.get_receptor_count(), g.get_receptor_count(), "roundtrip receptor count")
	_assert_eq(restored.get_skill_count(), g.get_skill_count(), "roundtrip skill count")
	_assert_near(restored.fitness, 42.5, 0.01, "roundtrip fitness")


func _test_io_innovation_consistency() -> void:
	var io := IoInnovation.new()
	var innov_a := io.get_receptor_innovation(0)
	var innov_b := io.get_receptor_innovation(0)
	_assert_eq(innov_a, innov_b, "same receptor → same innovation")

	var innov_c := io.get_receptor_innovation(1)
	_assert_true(innov_c != innov_a, "different receptor → different innovation")

	var skill_innov := io.get_skill_innovation(0)
	_assert_true(skill_innov != innov_a, "skill innovation differs from receptor")


func _test_corpse_energy_minimum() -> void:
	var world := GridWorld.new()
	world.setup()
	var tile := GridTile.new(Vector2i(0, 0))
	var body := CreatureBody.new()
	body.energy = 2.0  # Less than minimum of 5.0
	Corpse.create_from_creature(body, tile)
	_assert_near(tile.corpse_energy, 5.0, 0.01, "corpse energy minimum 5.0")


func _test_sensor_core_inputs_bounded() -> void:
	var world := GridWorld.new()
	world.setup()
	for pos in world.tiles:
		world.tiles[pos].terrain = GameConfig.Terrain.GRASS
	var sensor := CreatureSensor.new(world)
	var body := CreatureBody.new()
	body.energy = GameConfig.MAX_ENERGY
	body.health = GameConfig.MAX_HEALTH
	body.age = GameConfig.MAX_AGE - 1
	var inputs := sensor.get_core_inputs(Vector2i(0, 0), body)
	_assert_eq(inputs.size(), GameConfig.CORE_INPUT_COUNT, "core input count")
	var all_bounded := true
	for val in inputs:
		if val < -1.1 or val > 1.1:
			all_bounded = false
	_assert_true(all_bounded, "core inputs bounded")


# --- Helpers ---

func _assert_eq(actual, expected, msg: String) -> void:
	if typeof(actual) == TYPE_FLOAT and typeof(expected) == TYPE_FLOAT:
		if absf(actual - expected) < 0.001:
			_pass_count += 1
			return
	if actual == expected:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL: %s — expected %s, got %s" % [msg, str(expected), str(actual)])


func _assert_near(actual: float, expected: float, tolerance: float, msg: String) -> void:
	if absf(actual - expected) <= tolerance:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL: %s — expected ~%.4f, got %.4f" % [msg, expected, actual])


func _assert_true(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL: %s" % msg)


func _print_results(suite: String) -> void:
	var total := _pass_count + _fail_count
	if _fail_count == 0:
		print("[%s] All %d tests passed" % [suite, total])
	else:
		print("[%s] %d/%d passed, %d FAILED" % [suite, _pass_count, total, _fail_count])
