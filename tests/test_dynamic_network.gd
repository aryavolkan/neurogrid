extends Node
## Tests for DynamicNetwork: forward pass dimensions and correctness.

var _config: DynamicConfig
var _conn_tracker  # NeatInnovation
var _io_tracker: IoInnovation
var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_setup()
	_test_output_dimensions_core_only()
	_test_output_dimensions_with_receptors()
	_test_forward_pass_bounded()
	_test_from_genome_topology()
	_print_results("DynamicNetwork")


func _setup() -> void:
	_config = DynamicConfig.new()
	_conn_tracker = NeatInnovation.new()
	_io_tracker = IoInnovation.new()


func _make_genome() -> DynamicGenome:
	return DynamicGenome.create(_config, _conn_tracker, _io_tracker)


func _test_output_dimensions_core_only() -> void:
	var g := _make_genome()
	var net := DynamicNetwork.from_genome(g)
	var inputs := PackedFloat32Array()
	inputs.resize(net.get_input_count())
	var outputs := net.forward(inputs)
	_assert_eq(outputs.size(), GameConfig.CORE_OUTPUT_COUNT, "core-only output size")
	_assert_eq(net.get_core_input_count(), GameConfig.CORE_INPUT_COUNT, "core input count")
	_assert_eq(net.get_core_output_count(), GameConfig.CORE_OUTPUT_COUNT, "core output count")


func _test_output_dimensions_with_receptors() -> void:
	var g := _make_genome()
	g.mutate_add_receptor()
	g.mutate_add_skill()
	var net := DynamicNetwork.from_genome(g)
	_assert_eq(net.get_input_count(), GameConfig.CORE_INPUT_COUNT + 1, "input count with receptor")
	_assert_eq(net.get_output_count(), GameConfig.CORE_OUTPUT_COUNT + 1, "output count with skill")
	_assert_eq(net.get_receptor_order().size(), 1, "receptor order size")
	_assert_eq(net.get_skill_order().size(), 1, "skill order size")


func _test_forward_pass_bounded() -> void:
	var g := _make_genome()
	# Add some connections and hidden nodes
	g.mutate_add_connection()
	g.mutate_add_connection()
	g.mutate_add_node()
	var net := DynamicNetwork.from_genome(g)
	var inputs := PackedFloat32Array()
	inputs.resize(net.get_input_count())
	for i in inputs.size():
		inputs[i] = randf_range(-1.0, 1.0)
	var outputs := net.forward(inputs)
	var all_bounded := true
	for val in outputs:
		if absf(val) > 1.0:
			all_bounded = false
	_assert_true(all_bounded, "all outputs bounded by tanh [-1, 1]")


func _test_from_genome_topology() -> void:
	var g := _make_genome()
	g.mutate_add_receptor()
	g.mutate_add_receptor()
	g.mutate_add_skill()
	var net := DynamicNetwork.from_genome(g)

	# Receptor order should match genome receptor nodes
	var genome_receptors := g.get_receptor_nodes()
	var net_receptors := net.get_receptor_order()
	_assert_eq(net_receptors.size(), genome_receptors.size(), "receptor order matches genome")

	# Skill order should match
	var genome_skills := g.get_skill_nodes()
	var net_skills := net.get_skill_order()
	_assert_eq(net_skills.size(), genome_skills.size(), "skill order matches genome")


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
