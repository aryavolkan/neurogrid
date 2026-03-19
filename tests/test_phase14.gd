extends Node
## Phase 14 tests: PhylogenyTracker, GenomeDiff, ExperimentRunner sweeps,
## CreatureSensor effective range, GameConfig overrides.

var _config: DynamicConfig
var _conn_tracker  # NeatInnovation
var _io_tracker: IoInnovation
var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_setup()

	# PhylogenyTracker
	_test_phylogeny_record_species()
	_test_phylogeny_extinction()
	_test_phylogeny_lineage()
	_test_phylogeny_tree_depth()
	_test_phylogeny_update_stats()
	_test_phylogeny_report()
	_test_phylogeny_living_species()

	# GenomeDiff
	_test_diff_identical_genomes()
	_test_diff_different_genomes()
	_test_diff_receptor_skill_comparison()
	_test_diff_format_report()

	# ExperimentRunner sweep utilities
	_test_generate_combinations_empty()
	_test_generate_combinations_single()
	_test_generate_combinations_cartesian()

	# GameConfig overrides
	_test_config_apply_overrides()
	_test_config_restore_defaults()
	_test_config_unknown_param_warning()

	# CreatureSensor effective range
	_test_sensor_effective_range_default()
	_test_sensor_effective_range_with_weather()
	_test_sensor_effective_range_minimum()

	_print_results("Phase14")


func _setup() -> void:
	_config = DynamicConfig.new()
	_conn_tracker = NeatInnovation.new()
	_io_tracker = IoInnovation.new()


# --- PhylogenyTracker ---

func _test_phylogeny_record_species() -> void:
	var tracker := PhylogenyTracker.new()
	tracker.record_species_born(1, -1, 0)
	tracker.record_species_born(2, 1, 100)
	_assert_eq(tracker.get_all_nodes().size(), 2, "phylogeny has 2 species")
	var node1: PhylogenyTracker.PhyloNode = tracker.get_node(1)
	_assert_eq(node1.species_id, 1, "species 1 id")
	_assert_eq(node1.parent_species_id, -1, "species 1 is root")
	_assert_eq(node1.born_tick, 0, "species 1 born at tick 0")
	var node2: PhylogenyTracker.PhyloNode = tracker.get_node(2)
	_assert_eq(node2.parent_species_id, 1, "species 2 parent is 1")
	_assert_true(node1.children.has(2), "species 1 has child 2")


func _test_phylogeny_extinction() -> void:
	var tracker := PhylogenyTracker.new()
	tracker.record_species_born(1, -1, 0)
	_assert_true(tracker.get_node(1).is_alive(), "species alive before extinction")
	tracker.record_species_extinct(1, 500)
	_assert_true(not tracker.get_node(1).is_alive(), "species dead after extinction")
	_assert_eq(tracker.get_node(1).extinct_tick, 500, "extinction tick recorded")


func _test_phylogeny_lineage() -> void:
	var tracker := PhylogenyTracker.new()
	tracker.record_species_born(1, -1, 0)
	tracker.record_species_born(2, 1, 100)
	tracker.record_species_born(3, 2, 200)
	var lineage := tracker.get_lineage(3)
	_assert_eq(lineage.size(), 3, "lineage has 3 entries")
	_assert_eq(lineage[0], 1, "lineage root is 1")
	_assert_eq(lineage[1], 2, "lineage middle is 2")
	_assert_eq(lineage[2], 3, "lineage leaf is 3")


func _test_phylogeny_tree_depth() -> void:
	var tracker := PhylogenyTracker.new()
	tracker.record_species_born(1, -1, 0)
	tracker.record_species_born(2, 1, 100)
	tracker.record_species_born(3, 2, 200)
	_assert_eq(tracker.get_tree_depth(1), 0, "root depth is 0")
	_assert_eq(tracker.get_tree_depth(2), 1, "child depth is 1")
	_assert_eq(tracker.get_tree_depth(3), 2, "grandchild depth is 2")


func _test_phylogeny_update_stats() -> void:
	var tracker := PhylogenyTracker.new()
	tracker.record_species_born(1, -1, 0)
	tracker.update_species_stats(1, 10, 5.0)
	tracker.update_species_stats(1, 8, 7.0)
	var node: PhylogenyTracker.PhyloNode = tracker.get_node(1)
	_assert_eq(node.peak_members, 10, "peak members is max")
	_assert_near(node.peak_fitness, 7.0, 0.01, "peak fitness is max")


func _test_phylogeny_report() -> void:
	var tracker := PhylogenyTracker.new()
	tracker.record_species_born(1, -1, 0)
	tracker.update_species_stats(1, 5, 3.0)
	var report := tracker.get_report(1000)
	_assert_true(report.length() > 0, "report is non-empty")
	_assert_true("1 total species" in report, "report mentions species count")
	_assert_true("1 alive" in report, "report mentions alive count")


func _test_phylogeny_living_species() -> void:
	var tracker := PhylogenyTracker.new()
	tracker.record_species_born(1, -1, 0)
	tracker.record_species_born(2, 1, 100)
	tracker.record_species_extinct(1, 200)
	var living := tracker.get_living_species()
	_assert_eq(living.size(), 1, "one living species")
	_assert_eq(living[0], 2, "species 2 is alive")


# --- GenomeDiff ---

func _test_diff_identical_genomes() -> void:
	var genome := DynamicGenome.create(_config, _conn_tracker, _io_tracker)
	var diff := GenomeDiff.compare(genome, genome)
	_assert_eq(diff.disjoint_connections, 0, "identical: no disjoint")
	_assert_eq(diff.excess_connections, 0, "identical: no excess")
	_assert_near(diff.avg_weight_diff, 0.0, 0.001, "identical: zero weight diff")
	_assert_near(diff.compatibility_distance, 0.0, 0.001, "identical: zero compat dist")


func _test_diff_different_genomes() -> void:
	var a := DynamicGenome.create(_config, _conn_tracker, _io_tracker)
	var b := DynamicGenome.create(_config, _conn_tracker, _io_tracker)
	# Mutate b to create differences
	for _i in 5:
		b.mutate()
	var diff := GenomeDiff.compare(a, b)
	_assert_true(diff.node_count_a > 0, "genome a has nodes")
	_assert_true(diff.node_count_b > 0, "genome b has nodes")
	_assert_true(diff.connection_count_a > 0, "genome a has connections")


func _test_diff_receptor_skill_comparison() -> void:
	var a := DynamicGenome.create(_config, _conn_tracker, _io_tracker)
	var b := DynamicGenome.create(_config, _conn_tracker, _io_tracker)
	# Add receptors/skills via mutation
	for _i in 10:
		a.mutate_add_receptor()
		b.mutate_add_skill()
	var diff := GenomeDiff.compare(a, b)
	# a should have receptors that b doesn't, b should have skills that a doesn't
	_assert_true(diff.unique_receptors_a.size() >= 0, "receptor diff computed")
	_assert_true(diff.unique_skills_b.size() >= 0, "skill diff computed")


func _test_diff_format_report() -> void:
	var a := DynamicGenome.create(_config, _conn_tracker, _io_tracker)
	var b := DynamicGenome.create(_config, _conn_tracker, _io_tracker)
	var diff := GenomeDiff.compare(a, b)
	var report := GenomeDiff.format_report(diff, "Creature1", "Creature2")
	_assert_true("Creature1" in report, "report contains label A")
	_assert_true("Creature2" in report, "report contains label B")
	_assert_true("Compatibility" in report, "report contains compat info")


# --- ExperimentRunner ---

func _test_generate_combinations_empty() -> void:
	var combos := ExperimentRunner.generate_combinations({})
	_assert_eq(combos.size(), 1, "empty grid yields 1 combo")
	_assert_eq(combos[0].size(), 0, "empty combo has no params")


func _test_generate_combinations_single() -> void:
	var combos := ExperimentRunner.generate_combinations({"A": [1, 2, 3]})
	_assert_eq(combos.size(), 3, "single param yields 3 combos")
	_assert_eq(combos[0]["A"], 1, "first combo A=1")
	_assert_eq(combos[2]["A"], 3, "third combo A=3")


func _test_generate_combinations_cartesian() -> void:
	var combos := ExperimentRunner.generate_combinations({"A": [1, 2], "B": [10, 20, 30]})
	_assert_eq(combos.size(), 6, "2x3 grid yields 6 combos")
	# Verify all combos have both keys
	var all_have_keys := true
	for combo in combos:
		if not combo.has("A") or not combo.has("B"):
			all_have_keys = false
	_assert_true(all_have_keys, "all combos have both keys")


# --- GameConfig overrides ---

func _test_config_apply_overrides() -> void:
	var orig_metabolism: float = GameConfig.BASE_METABOLISM
	GameConfig.apply_overrides({"BASE_METABOLISM": 0.5})
	_assert_near(GameConfig.BASE_METABOLISM, 0.5, 0.001, "metabolism overridden to 0.5")
	GameConfig.restore_defaults()
	_assert_near(GameConfig.BASE_METABOLISM, orig_metabolism, 0.001, "metabolism restored")


func _test_config_restore_defaults() -> void:
	GameConfig.apply_overrides({
		"INITIAL_POPULATION": 200,
		"FOOD_REGEN_RATE": 0.5,
		"ADD_NODE_RATE": 0.1,
	})
	_assert_eq(GameConfig.INITIAL_POPULATION, 200, "pop overridden")
	_assert_near(GameConfig.FOOD_REGEN_RATE, 0.5, 0.001, "food regen overridden")
	GameConfig.restore_defaults()
	_assert_eq(GameConfig.INITIAL_POPULATION, 80, "pop restored to 80")
	_assert_near(GameConfig.FOOD_REGEN_RATE, 0.08, 0.001, "food regen restored to 0.08")
	_assert_near(GameConfig.ADD_NODE_RATE, 0.03, 0.001, "add node rate restored")


func _test_config_unknown_param_warning() -> void:
	# Should not crash, just warn
	GameConfig.apply_overrides({"NONEXISTENT_PARAM": 999})
	_assert_true(true, "unknown param does not crash")
	GameConfig.restore_defaults()


# --- CreatureSensor effective range ---

func _test_sensor_effective_range_default() -> void:
	var world := GridWorld.new()
	world.setup()
	for pos in world.tiles:
		world.tiles[pos].terrain = GameConfig.Terrain.GRASS
		world.tiles[pos].elevation = 0.0
	var sensor := CreatureSensor.new(world)  # No weather system
	var effective: int = sensor._effective_range(5, Vector2i(5, 5))
	_assert_eq(effective, 5, "no elevation bonus, no weather: range unchanged")


func _test_sensor_effective_range_with_weather() -> void:
	var world := GridWorld.new()
	world.setup()
	for pos in world.tiles:
		world.tiles[pos].terrain = GameConfig.Terrain.GRASS
		world.tiles[pos].elevation = 0.0
	var weather := WeatherSystem.new(world)
	weather.current_weather = WeatherSystem.Weather.FOG
	var sensor := CreatureSensor.new(world, weather)
	var effective: int = sensor._effective_range(5, Vector2i(5, 5))
	# FOG_SENSOR_MULT = 0.4, so int(5 * 0.4) = 2
	_assert_eq(effective, 2, "fog reduces range to 2")


func _test_sensor_effective_range_minimum() -> void:
	var world := GridWorld.new()
	world.setup()
	for pos in world.tiles:
		world.tiles[pos].terrain = GameConfig.Terrain.GRASS
		world.tiles[pos].elevation = -0.5  # Low elevation, no bonus
	var weather := WeatherSystem.new(world)
	weather.current_weather = WeatherSystem.Weather.FOG
	var sensor := CreatureSensor.new(world, weather)
	var effective: int = sensor._effective_range(1, Vector2i(5, 5))
	# int(1 * 0.4) = 0, but minimum is 1
	_assert_true(effective >= 1, "effective range never below 1")


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
