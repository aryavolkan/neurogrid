extends SceneTree
## Headless test runner. Usage: godot --path . --headless -s tests/test_runner.gd
## Exit code 0 on success, 1 on failure (parsed from output by CI).

var _test_scenes: Array = [
	"res://tests/test_dynamic_genome.gd",
	"res://tests/test_dynamic_network.gd",
	"res://tests/test_world.gd",
	"res://tests/test_creature_body.gd",
	"res://tests/test_fitness_tracker.gd",
	"res://tests/test_species_manager.gd",
	"res://tests/test_action_system.gd",
	"res://tests/test_integration.gd",
	"res://tests/test_phase14.gd",
	"res://tests/test_perf_optimizations.gd",
]
var _current: int = 0
var _loaded: Array = []


func _init() -> void:
	print("\n=== NeuroGrid Test Suite ===\n")


func _process(_delta: float) -> bool:
	# Clean up previous test node
	if _current > 0 and _current <= _loaded.size():
		var prev = _loaded[_current - 1]
		if is_instance_valid(prev):
			prev.queue_free()

	if _current >= _test_scenes.size():
		print("\n=== Tests Complete ===")
		quit()
		return true

	var script: GDScript = load(_test_scenes[_current])
	var node := Node.new()
	node.set_script(script)
	_loaded.append(node)
	root.add_child(node)
	_current += 1
	return false
