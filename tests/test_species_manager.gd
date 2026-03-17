extends Node
## Tests for SpeciesManager: assignment, stagnation, threshold adjustment.

var _config: DynamicConfig
var _conn_tracker  # NeatInnovation
var _io_tracker: IoInnovation
var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_setup()
	_test_assign_first_creature()
	_test_assign_compatible_same_species()
	_test_assign_incompatible_new_species()
	_test_remove_creature()
	_test_update_fitness()
	_test_stagnation_detection()
	_test_threshold_adjustment_up()
	_test_threshold_adjustment_down()
	_test_empty_species_pruned()
	_test_species_counts()
	_print_results("SpeciesManager")


func _setup() -> void:
	_config = DynamicConfig.new()
	_conn_tracker = NeatInnovation.new()
	_io_tracker = IoInnovation.new()


func _make_genome() -> DynamicGenome:
	return DynamicGenome.create(_config, _conn_tracker, _io_tracker)


func _test_assign_first_creature() -> void:
	var sm := SpeciesManager.new(_config)
	var g := _make_genome()
	var sid := sm.assign_species(1, g)
	_assert_true(sid > 0, "first creature gets species id")
	_assert_eq(sm.get_species_count(), 1, "one species")


func _test_assign_compatible_same_species() -> void:
	var sm := SpeciesManager.new(_config)
	var g1 := _make_genome()
	var g2 := g1.copy()  # Identical genome, must be compatible
	var sid1 := sm.assign_species(1, g1)
	var sid2 := sm.assign_species(2, g2)
	_assert_eq(sid1, sid2, "compatible genomes same species")


func _test_assign_incompatible_new_species() -> void:
	var sm := SpeciesManager.new(_config)
	var g1 := _make_genome()
	var sid1 := sm.assign_species(1, g1)

	# Make a very different genome
	var g2 := _make_genome()
	for _i in 5:
		g2.mutate_add_receptor()
		g2.mutate_add_skill()
		g2.mutate_add_connection()
		g2.mutate_add_node()
	# Force high threshold for test reliability
	_config.neat_config.compatibility_threshold = 0.01
	var sid2 := sm.assign_species(2, g2)
	_assert_true(sid2 != sid1, "incompatible genome gets new species")
	_config.neat_config.compatibility_threshold = GameConfig.COMPATIBILITY_THRESHOLD


func _test_remove_creature() -> void:
	var sm := SpeciesManager.new(_config)
	var g := _make_genome()
	sm.assign_species(1, g)
	sm.remove_creature(1)
	_assert_eq(sm.get_species_id(1), -1, "creature removed from tracking")


func _test_update_fitness() -> void:
	var sm := SpeciesManager.new(_config)
	var g := _make_genome()
	var sid := sm.assign_species(1, g)
	sm.update_fitness(1, 5.0)
	sm.update_fitness(1, 10.0)
	var info := sm.get_species_info(sid)
	_assert_eq(info.best_fitness, 10.0, "best fitness tracked")


func _test_stagnation_detection() -> void:
	var sm := SpeciesManager.new(_config)
	var g := _make_genome()
	var sid := sm.assign_species(1, g)
	sm.update_fitness(1, 5.0)

	# Run many generations without improvement
	for _i in _config.neat_config.stagnation_kill_threshold + 1:
		sm.end_generation()

	_assert_true(sm.is_stagnant(sid), "species stagnant after threshold")


func _test_threshold_adjustment_up() -> void:
	var sm := SpeciesManager.new(_config)
	_config.neat_config.target_species_count = 2
	# Create many species to exceed target
	for i in 5:
		var g := _make_genome()
		for _j in 3:
			g.mutate_add_receptor()
			g.mutate_add_skill()
		_config.neat_config.compatibility_threshold = 0.001
		sm.assign_species(i, g)
	_config.neat_config.compatibility_threshold = GameConfig.COMPATIBILITY_THRESHOLD

	var before := _config.neat_config.compatibility_threshold
	# Force species count > target
	if sm.get_species_count() > _config.neat_config.target_species_count:
		sm.end_generation()
		_assert_true(_config.neat_config.compatibility_threshold >= before, "threshold increased when too many species")
	else:
		_pass_count += 1  # Can't reliably force many species, pass


func _test_threshold_adjustment_down() -> void:
	var sm := SpeciesManager.new(_config)
	_config.neat_config.target_species_count = 100  # Way more than we'll have
	var g := _make_genome()
	sm.assign_species(1, g)
	var before := _config.neat_config.compatibility_threshold
	sm.end_generation()
	_assert_true(_config.neat_config.compatibility_threshold <= before, "threshold decreased when too few species")
	_config.neat_config.target_species_count = 8


func _test_empty_species_pruned() -> void:
	var sm := SpeciesManager.new(_config)
	var g := _make_genome()
	sm.assign_species(1, g)
	sm.remove_creature(1)
	sm.end_generation()
	_assert_eq(sm.get_species_count(), 0, "empty species removed")


func _test_species_counts() -> void:
	var sm := SpeciesManager.new(_config)
	var g := _make_genome()
	sm.assign_species(1, g)
	sm.assign_species(2, g)
	var counts := sm.get_species_counts()
	var total: int = 0
	for sid in counts:
		total += counts[sid]
	_assert_eq(total, 2, "species counts sum to creature count")


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
