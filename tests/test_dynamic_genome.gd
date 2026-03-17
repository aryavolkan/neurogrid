extends Node
## Tests for DynamicGenome: mutation, crossover, compatibility.
## Run with: godot --path . --headless -s tests/test_runner.gd

var _config: DynamicConfig
var _conn_tracker  # NeatInnovation
var _io_tracker: IoInnovation
var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_setup()
	_test_create_genome()
	_test_mutate_add_receptor()
	_test_mutate_add_skill()
	_test_mutate_remove_receptor()
	_test_crossover_preserves_io_innovation()
	_test_compatibility_symmetric()
	_test_compatibility_io_diff()
	_test_copy()
	_test_serialize_deserialize()
	_print_results("DynamicGenome")


func _setup() -> void:
	_config = DynamicConfig.new()
	_conn_tracker = NeatInnovation.new()
	_io_tracker = IoInnovation.new()


func _make_genome() -> DynamicGenome:
	return DynamicGenome.create(_config, _conn_tracker, _io_tracker)


func _test_create_genome() -> void:
	var g := _make_genome()
	var inputs := g.get_nodes_by_type([DynamicGenome.TYPE_CORE_INPUT])
	var outputs := g.get_nodes_by_type([DynamicGenome.TYPE_CORE_OUTPUT])
	_assert_eq(inputs.size(), GameConfig.CORE_INPUT_COUNT, "core input count")
	_assert_eq(outputs.size(), GameConfig.CORE_OUTPUT_COUNT, "core output count")
	_assert_eq(g.get_receptor_count(), 0, "initial receptor count")
	_assert_eq(g.get_skill_count(), 0, "initial skill count")


func _test_mutate_add_receptor() -> void:
	var g := _make_genome()
	g.mutate_add_receptor()
	_assert_eq(g.get_receptor_count(), 1, "receptor count after add")
	var receptors := g.get_receptor_nodes()
	_assert_true(receptors[0].registry_id >= 0, "receptor has registry_id")
	_assert_true(receptors[0].io_innovation >= 0, "receptor has io_innovation")


func _test_mutate_add_skill() -> void:
	var g := _make_genome()
	g.mutate_add_skill()
	_assert_eq(g.get_skill_count(), 1, "skill count after add")
	var skills := g.get_skill_nodes()
	_assert_true(skills[0].registry_id >= 0, "skill has registry_id")


func _test_mutate_remove_receptor() -> void:
	var g := _make_genome()
	g.mutate_add_receptor()
	g.mutate_add_receptor()
	var count_before := g.get_receptor_count()
	g.mutate_remove_receptor()
	_assert_eq(g.get_receptor_count(), count_before - 1, "receptor removed")


func _test_crossover_preserves_io_innovation() -> void:
	var a := _make_genome()
	var b := _make_genome()
	# Give both the same receptor (same registry_id → same io_innovation)
	a.mutate_add_receptor()
	var a_receptors := a.get_receptor_nodes()
	# Force b to have same receptor registry_id
	var reg_id: int = a_receptors[0].registry_id
	var io_innov: int = _io_tracker.get_receptor_innovation(reg_id)
	var node_id: int = _conn_tracker.allocate_node_id()
	b.node_genes.append(DynamicGenome.DynamicNodeGene.new(node_id, DynamicGenome.TYPE_RECEPTOR, reg_id, io_innov))

	a.fitness = 1.0
	b.fitness = 1.0
	var child := DynamicGenome.crossover(a, b)
	# Child should have the receptor (present in both parents)
	_assert_true(child.get_receptor_count() >= 1, "crossover preserves shared receptor")


func _test_compatibility_symmetric() -> void:
	var a := _make_genome()
	var b := _make_genome()
	var dist_ab := a.compatibility(b)
	var dist_ba := b.compatibility(a)
	_assert_true(absf(dist_ab - dist_ba) < 0.001, "compatibility is symmetric")


func _test_compatibility_io_diff() -> void:
	var a := _make_genome()
	var b := _make_genome()
	var dist_same := a.compatibility(b)
	a.mutate_add_receptor()
	a.mutate_add_skill()
	var dist_diff := a.compatibility(b)
	_assert_true(dist_diff > dist_same, "I/O differences increase compatibility distance")


func _test_copy() -> void:
	var g := _make_genome()
	g.mutate_add_receptor()
	g.fitness = 42.0
	var copy := g.copy()
	_assert_eq(copy.node_genes.size(), g.node_genes.size(), "copy node count")
	_assert_eq(copy.connection_genes.size(), g.connection_genes.size(), "copy connection count")
	_assert_eq(copy.fitness, 42.0, "copy fitness")
	_assert_eq(copy.get_receptor_count(), g.get_receptor_count(), "copy receptor count")


func _test_serialize_deserialize() -> void:
	var g := _make_genome()
	g.mutate_add_receptor()
	g.mutate_add_skill()
	g.fitness = 7.5
	var data := g.serialize()
	var restored := DynamicGenome.deserialize(data, _config, _conn_tracker, _io_tracker)
	_assert_eq(restored.node_genes.size(), g.node_genes.size(), "serialized node count")
	_assert_eq(restored.connection_genes.size(), g.connection_genes.size(), "serialized connection count")
	_assert_eq(restored.fitness, 7.5, "serialized fitness")


# --- Assert helpers ---

func _assert_eq(actual, expected, msg: String) -> void:
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
