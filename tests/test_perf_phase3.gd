extends Node
## Tests for Phase 3 performance optimizations:
## - Network forward pass with array-indexed activations
## - SimulationManager tick decomposition
## - DynamicGenome cached counts
## - CreatureBody array-based skill cooldowns
## - Headless check caching

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	# Network array-indexed forward pass
	_test_network_forward_basic()
	_test_network_forward_with_hidden()
	_test_network_forward_with_receptors()
	_test_network_get_activation()
	_test_network_output_count()

	# Genome cached counts
	_test_genome_cached_receptor_count()
	_test_genome_cached_skill_count()
	_test_genome_cached_skill_ids()
	_test_genome_cache_invalidated_by_mutate()
	_test_genome_cache_valid_across_reads()

	# CreatureBody array cooldowns
	_test_body_skill_cooldown_array()
	_test_body_skill_cooldown_decrement()
	_test_body_skill_ready_check()
	_test_body_cooldown_bounds_check()

	# Tick decomposition (verify sub-methods exist)
	_test_sim_manager_has_sub_methods()

	_print_results("PerfPhase3")


# ============================================================
# NETWORK ARRAY-INDEXED FORWARD PASS
# ============================================================

func _test_network_forward_basic() -> void:
	var config := DynamicConfig.new()
	var conn := NeatInnovation.new()
	var io := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn, io)

	var net := DynamicNetwork.from_genome(genome)
	var inputs := PackedFloat32Array()
	inputs.resize(net.get_input_count())
	for i in inputs.size():
		inputs[i] = 0.5

	var outputs := net.forward(inputs)
	_assert_true(outputs.size() == net.get_output_count(),
		"output size matches output count")
	_assert_true(outputs.size() >= 4, "at least 4 core outputs")


func _test_network_forward_with_hidden() -> void:
	var config := DynamicConfig.new()
	var conn := NeatInnovation.new()
	var io := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn, io)

	# Add a hidden node
	genome.mutate_add_node()
	var net := DynamicNetwork.from_genome(genome)

	var inputs := PackedFloat32Array()
	inputs.resize(net.get_input_count())
	for i in inputs.size():
		inputs[i] = 1.0

	var outputs := net.forward(inputs)
	_assert_true(outputs.size() > 0, "forward works with hidden node")


func _test_network_forward_with_receptors() -> void:
	var config := DynamicConfig.new()
	var conn := NeatInnovation.new()
	var io := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn, io)

	# Add a receptor
	genome.mutate_add_receptor()
	var net := DynamicNetwork.from_genome(genome)

	_assert_true(net.get_input_count() > GameConfig.CORE_INPUT_COUNT,
		"receptor added extra input")
	_assert_true(net.get_receptor_order().size() > 0,
		"receptor order populated")

	var inputs := PackedFloat32Array()
	inputs.resize(net.get_input_count())
	var outputs := net.forward(inputs)
	_assert_true(outputs.size() > 0, "forward works with receptor")


func _test_network_get_activation() -> void:
	var config := DynamicConfig.new()
	var conn := NeatInnovation.new()
	var io := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn, io)
	var net := DynamicNetwork.from_genome(genome)

	var inputs := PackedFloat32Array()
	inputs.resize(net.get_input_count())
	inputs[0] = 0.8
	net.forward(inputs)

	# Input node 0 should have activation 0.8
	var act := net.get_activation(0)
	_assert_true(abs(act - 0.8) < 0.001,
		"get_activation returns correct input value")

	# Non-existent node should return 0
	var missing := net.get_activation(9999)
	_assert_true(missing == 0.0,
		"get_activation returns 0 for unknown node")


func _test_network_output_count() -> void:
	var config := DynamicConfig.new()
	var conn := NeatInnovation.new()
	var io := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn, io)
	genome.mutate_add_skill()

	var net := DynamicNetwork.from_genome(genome)
	_assert_true(net.get_output_count() > GameConfig.CORE_OUTPUT_COUNT,
		"skill added extra output")
	_assert_true(net.get_skill_order().size() > 0,
		"skill order populated")


# ============================================================
# GENOME CACHED COUNTS
# ============================================================

func _test_genome_cached_receptor_count() -> void:
	var config := DynamicConfig.new()
	var conn := NeatInnovation.new()
	var io := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn, io)

	_assert_eq(genome.get_receptor_count(), 0, "no receptors initially")
	# Second call should use cache
	_assert_eq(genome.get_receptor_count(), 0, "cached receptor count")
	_assert_true(genome._cached_receptor_count == 0,
		"cache populated")


func _test_genome_cached_skill_count() -> void:
	var config := DynamicConfig.new()
	var conn := NeatInnovation.new()
	var io := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn, io)

	_assert_eq(genome.get_skill_count(), 0, "no skills initially")
	_assert_true(genome._cached_skill_count == 0, "cache populated")


func _test_genome_cached_skill_ids() -> void:
	var config := DynamicConfig.new()
	var conn := NeatInnovation.new()
	var io := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn, io)
	genome.mutate_add_skill()

	var ids := genome.get_skill_registry_ids()
	_assert_true(ids.size() > 0, "skill IDs returned")
	_assert_true(genome._cached_skill_ids_valid, "cache valid")

	# Second call should return cached
	var ids2 := genome.get_skill_registry_ids()
	_assert_eq(ids.size(), ids2.size(), "cached IDs same size")


func _test_genome_cache_invalidated_by_mutate() -> void:
	var config := DynamicConfig.new()
	var conn := NeatInnovation.new()
	var io := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn, io)

	# Populate cache
	genome.get_receptor_count()
	genome.get_skill_count()
	genome.get_skill_registry_ids()
	_assert_true(genome._cached_receptor_count >= 0, "cache set")

	# Mutate should invalidate
	genome.mutate()
	_assert_eq(genome._cached_receptor_count, -1,
		"receptor cache invalidated after mutate")
	_assert_eq(genome._cached_skill_count, -1,
		"skill cache invalidated after mutate")
	_assert_true(not genome._cached_skill_ids_valid,
		"skill IDs cache invalidated after mutate")


func _test_genome_cache_valid_across_reads() -> void:
	var config := DynamicConfig.new()
	var conn := NeatInnovation.new()
	var io := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn, io)

	# Multiple reads should all hit cache
	var c1 := genome.get_receptor_count()
	var c2 := genome.get_receptor_count()
	var c3 := genome.get_receptor_count()
	_assert_eq(c1, c2, "consistent receptor count")
	_assert_eq(c2, c3, "cache stable across reads")


# ============================================================
# CREATURE BODY ARRAY COOLDOWNS
# ============================================================

func _test_body_skill_cooldown_array() -> void:
	var body := CreatureBody.new()
	_assert_eq(body.skill_cooldowns.size(), 8, "8 cooldown slots")
	_assert_eq(body.skill_cooldowns[0], 0, "all cooldowns start at 0")


func _test_body_skill_cooldown_decrement() -> void:
	var body := CreatureBody.new()
	body.set_skill_cooldown(GameConfig.SKILL_BITE, 5)
	_assert_eq(body.skill_cooldowns[GameConfig.SKILL_BITE], 5,
		"cooldown set to 5")

	body.update_cooldowns(0.0)
	_assert_eq(body.skill_cooldowns[GameConfig.SKILL_BITE], 4,
		"cooldown decremented to 4")


func _test_body_skill_ready_check() -> void:
	var body := CreatureBody.new()
	_assert_true(body.is_skill_ready(GameConfig.SKILL_DASH),
		"skill ready when cooldown is 0")

	body.set_skill_cooldown(GameConfig.SKILL_DASH, 3)
	_assert_true(not body.is_skill_ready(GameConfig.SKILL_DASH),
		"skill not ready during cooldown")

	# Tick down to 0
	for _i in 3:
		body.update_cooldowns(0.0)
	_assert_true(body.is_skill_ready(GameConfig.SKILL_DASH),
		"skill ready after cooldown expires")


func _test_body_cooldown_bounds_check() -> void:
	var body := CreatureBody.new()
	# Out of bounds should not crash
	body.set_skill_cooldown(-1, 5)
	body.set_skill_cooldown(99, 5)
	_assert_true(not body.is_skill_ready(-1),
		"invalid skill ID returns not ready")
	_assert_true(not body.is_skill_ready(99),
		"out of range skill ID returns not ready")


# ============================================================
# SIMULATION TICK DECOMPOSITION
# ============================================================

func _test_sim_manager_has_sub_methods() -> void:
	# Verify the decomposed methods exist on SimulationManager
	var sim := SimulationManager.new()
	_assert_true(sim.has_method("_update_metabolism"),
		"_update_metabolism method exists")
	_assert_true(sim.has_method("_sense_think_act"),
		"_sense_think_act method exists")
	_assert_true(sim.has_method("_handle_deaths"),
		"_handle_deaths method exists")
	_assert_true(sim.has_method("_update_world"),
		"_update_world method exists")
	sim.queue_free()


# ============================================================
# ASSERT HELPERS
# ============================================================

func _assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL: %s — expected %s, got %s" % [
			msg, str(expected), str(actual)])


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
		print("[%s] %d/%d passed, %d FAILED" % [
			suite, _pass_count, total, _fail_count])
