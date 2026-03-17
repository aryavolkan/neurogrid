extends Node
## Tests for ActionSystem: movement, eating, all 8 skills.

var _world: GridWorld
var _pheromone: PheromoneLayer
var _action: ActionSystem
var _config: DynamicConfig
var _conn_tracker  # NeatInnovation
var _io_tracker: IoInnovation
var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_test_movement_basic()
	_test_movement_zero()
	_test_movement_boundary_clamp()
	_test_movement_blocked()
	_test_movement_sand_cost()
	_test_eating_food()
	_test_eating_corpse()
	_test_eating_both()
	_test_eating_empty_tile()
	_test_skill_dash()
	_test_skill_bite()
	_test_skill_bite_no_target()
	_test_skill_poison()
	_test_skill_pheromone()
	_test_skill_share_food()
	_test_skill_build_wall()
	_test_skill_heal()
	_test_skill_burrow()
	_test_skill_cooldown_blocks()
	_test_skill_energy_blocks()
	_test_fitness_eating_tracked()
	_test_fitness_damage_tracked()
	_print_results("ActionSystem")


func _setup() -> void:
	_config = DynamicConfig.new()
	_conn_tracker = NeatInnovation.new()
	_io_tracker = IoInnovation.new()
	_world = GridWorld.new()
	_world.setup()
	# Make all tiles grass (passable)
	for pos in _world.tiles:
		_world.tiles[pos].terrain = GameConfig.Terrain.GRASS
	_pheromone = PheromoneLayer.new(_world)
	_action = ActionSystem.new(_world, _pheromone)
	_action.creatures = {}
	_action.fitness_tracker = FitnessTracker.new()


func _make_creature(pos: Vector2i, energy: float = 50.0) -> Creature:
	var genome := DynamicGenome.create(_config, _conn_tracker, _io_tracker)
	var creature := Creature.new()
	var sensor := CreatureSensor.new(_world)
	creature.setup(_get_next_id(), pos, genome, sensor, energy)
	_world.set_creature_position(creature.creature_id, pos)
	_world.tiles[pos].occupant_id = creature.creature_id
	_action.creatures[creature.creature_id] = creature
	_action.fitness_tracker.register(creature.creature_id)
	return creature

var _id_counter: int = 0
func _get_next_id() -> int:
	_id_counter += 1
	return _id_counter


func _make_outputs(move_x: float = 0.0, move_y: float = 0.0, eat: float = 0.0, mate: float = 0.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(GameConfig.CORE_OUTPUT_COUNT)
	out[0] = move_x
	out[1] = move_y
	out[2] = eat
	out[3] = mate
	return out


# --- Movement ---

func _test_movement_basic() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10))
	_action.execute(c, _make_outputs(1.0, 0.0))
	_assert_eq(c.grid_pos, Vector2i(11, 10), "moved right")
	_assert_eq(c.body.facing, Vector2i(1, 0), "facing updated")


func _test_movement_zero() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10))
	_action.execute(c, _make_outputs(0.0, 0.0))
	_assert_eq(c.grid_pos, Vector2i(10, 10), "no movement on zero")


func _test_movement_boundary_clamp() -> void:
	_setup()
	var c := _make_creature(Vector2i(0, 0))
	_action.execute(c, _make_outputs(-1.0, 0.0))
	_assert_eq(c.grid_pos, Vector2i(0, 0), "clamped at left edge")


func _test_movement_blocked() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10))
	_world.tiles[Vector2i(11, 10)].terrain = GameConfig.Terrain.WATER
	_action.execute(c, _make_outputs(1.0, 0.0))
	_assert_eq(c.grid_pos, Vector2i(10, 10), "blocked by water")


func _test_movement_sand_cost() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10))
	_world.tiles[Vector2i(11, 10)].terrain = GameConfig.Terrain.SAND
	var before := c.body.energy
	_action.execute(c, _make_outputs(1.0, 0.0))
	var expected_cost := GameConfig.MOVEMENT_COST * 1.5
	_assert_near(c.body.energy, before - expected_cost, 0.01, "sand costs 1.5x")


# --- Eating ---

func _test_eating_food() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 30.0)
	_world.tiles[Vector2i(10, 10)].food = 10.0
	_action.execute(c, _make_outputs(0.0, 0.0, 1.0))
	_assert_true(c.body.energy > 30.0, "gained energy from food")
	_assert_true(_world.tiles[Vector2i(10, 10)].food < 10.0, "food reduced")


func _test_eating_corpse() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 30.0)
	_world.tiles[Vector2i(10, 10)].corpse_energy = 10.0
	_action.execute(c, _make_outputs(0.0, 0.0, 1.0))
	_assert_true(c.body.energy > 30.0, "gained energy from corpse")


func _test_eating_both() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 30.0)
	_world.tiles[Vector2i(10, 10)].food = 5.0
	_world.tiles[Vector2i(10, 10)].corpse_energy = 5.0
	_action.execute(c, _make_outputs(0.0, 0.0, 1.0))
	_assert_true(c.body.energy > 30.0, "ate both food and corpse")


func _test_eating_empty_tile() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 30.0)
	_action.execute(c, _make_outputs(0.0, 0.0, 1.0))
	_assert_eq(c.body.energy, 30.0, "no food = no change")


# --- Skills ---

func _test_skill_dash() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	c.body.facing = Vector2i(1, 0)
	_action._execute_skill(c, 0)  # dash
	_assert_eq(c.grid_pos, Vector2i(13, 10), "dashed 3 tiles right")


func _test_skill_bite() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	c.body.facing = Vector2i(1, 0)
	var target := _make_creature(Vector2i(11, 10), 50.0)
	_action._execute_skill(c, 1)  # bite
	_assert_eq(target.body.health, GameConfig.MAX_HEALTH - 15.0, "bite dealt 15 damage")


func _test_skill_bite_no_target() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	c.body.facing = Vector2i(1, 0)
	var health_before := c.body.health
	_action._execute_skill(c, 1)  # bite at nothing
	_assert_eq(c.body.health, health_before, "no self-damage")


func _test_skill_poison() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	var target := _make_creature(Vector2i(11, 10), 50.0)
	_action._execute_skill(c, 2)  # poison_spit
	_assert_eq(target.body.poisoned_ticks, 5, "poison applied")


func _test_skill_pheromone() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	_action._execute_skill(c, 3)  # emit_pheromone
	_assert_true(_world.tiles[Vector2i(10, 10)].pheromone > 0.0, "pheromone deposited")


func _test_skill_share_food() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	var ally := _make_creature(Vector2i(11, 10), 30.0)
	c.body.species_id = 1
	ally.body.species_id = 1
	_action._execute_skill(c, 4)  # share_food
	_assert_true(ally.body.energy > 30.0, "ally received energy")


func _test_skill_build_wall() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	c.body.facing = Vector2i(0, 1)
	_action._execute_skill(c, 5)  # build_wall
	_assert_true(_world.tiles[Vector2i(10, 11)].wall, "wall placed")


func _test_skill_heal() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	c.body.health = 10.0
	_action._execute_skill(c, 6)  # heal_self
	_assert_eq(c.body.health, 20.0, "healed 10 hp")


func _test_skill_burrow() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	_action._execute_skill(c, 7)  # burrow
	_assert_true(c.body.burrowed, "burrowed state set")
	_assert_eq(c.body.burrow_ticks, 5, "burrow ticks set")


func _test_skill_cooldown_blocks() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	c.body.set_skill_cooldown(6, 10)
	var health_before := c.body.health
	c.body.health = 10.0
	_action._execute_skill(c, 6)  # heal on cooldown
	_assert_eq(c.body.health, 10.0, "skill blocked by cooldown")


func _test_skill_energy_blocks() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 0.5)
	c.body.health = 10.0
	_action._execute_skill(c, 6)  # heal but no energy
	_assert_eq(c.body.health, 10.0, "skill blocked by low energy")


# --- Fitness integration ---

func _test_fitness_eating_tracked() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 30.0)
	_world.tiles[Vector2i(10, 10)].food = 10.0
	_action.execute(c, _make_outputs(0.0, 0.0, 1.0))
	var fitness := _action.fitness_tracker.compute_fitness(c.creature_id, 0)
	_assert_true(fitness > 0.0, "eating tracked in fitness")


func _test_fitness_damage_tracked() -> void:
	_setup()
	var c := _make_creature(Vector2i(10, 10), 50.0)
	c.body.facing = Vector2i(1, 0)
	var _target := _make_creature(Vector2i(11, 10), 50.0)
	_action._execute_skill(c, 1)
	var fitness := _action.fitness_tracker.compute_fitness(c.creature_id, 0)
	_assert_true(fitness > 0.0, "damage tracked in fitness")


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
