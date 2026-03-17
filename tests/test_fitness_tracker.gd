extends Node
## Tests for FitnessTracker: registration, recording, fitness computation.

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_test_register_and_defaults()
	_test_record_food()
	_test_record_offspring()
	_test_record_damage()
	_test_compute_fitness_zero()
	_test_compute_fitness_weighted()
	_test_compute_objectives()
	_test_unregister()
	_print_results("FitnessTracker")


func _test_register_and_defaults() -> void:
	var ft := FitnessTracker.new()
	ft.register(1)
	_assert_eq(ft.compute_fitness(1, 0), 0.0, "zero fitness on register")


func _test_record_food() -> void:
	var ft := FitnessTracker.new()
	ft.register(1)
	ft.record_food_eaten(1, 10.0)
	ft.record_food_eaten(1, 5.0)
	# food component = 15.0 / 100.0 * W_FOOD(0.3) = 0.045
	var fitness := ft.compute_fitness(1, 0)
	_assert_true(fitness > 0.0, "food increases fitness")


func _test_record_offspring() -> void:
	var ft := FitnessTracker.new()
	ft.register(1)
	ft.record_offspring(1)
	ft.record_offspring(1)
	# offspring component = 2 * W_OFFSPRING(3.0) = 6.0
	var fitness := ft.compute_fitness(1, 0)
	_assert_near(fitness, 6.0, 0.01, "offspring fitness = 2 * 3.0")


func _test_record_damage() -> void:
	var ft := FitnessTracker.new()
	ft.register(1)
	ft.record_damage_dealt(1, 30.0)
	# damage component = 30.0 / 100.0 * W_DAMAGE(0.2) = 0.06
	var fitness := ft.compute_fitness(1, 0)
	_assert_near(fitness, 0.06, 0.01, "damage fitness")


func _test_compute_fitness_zero() -> void:
	var ft := FitnessTracker.new()
	ft.register(1)
	_assert_eq(ft.compute_fitness(1, 0), 0.0, "zero everything = zero fitness")


func _test_compute_fitness_weighted() -> void:
	var ft := FitnessTracker.new()
	ft.register(1)
	ft.record_food_eaten(1, 100.0)
	ft.record_offspring(1)
	ft.record_damage_dealt(1, 100.0)
	var fitness := ft.compute_fitness(1, GameConfig.MAX_AGE)
	# survival: 1.0 * 1.0 = 1.0
	# energy: 0.0 (energy_gathered still 0)
	# offspring: 1 * 3.0 = 3.0
	# food: 100/100 * 0.3 = 0.3
	# damage: 100/100 * 0.2 = 0.2
	var expected := 1.0 + 3.0 + 0.3 + 0.2
	_assert_near(fitness, expected, 0.01, "weighted fitness sum")


func _test_compute_objectives() -> void:
	var ft := FitnessTracker.new()
	ft.register(1)
	ft.record_food_eaten(1, 50.0)
	ft.record_offspring(1)
	var obj := ft.compute_objectives(1, 1000)
	_assert_near(obj.x, 1000.0 / float(GameConfig.MAX_AGE), 0.01, "survival objective")
	_assert_near(obj.y, 50.0 / 100.0, 0.01, "foraging objective")
	_assert_eq(obj.z, 1.0, "reproduction objective")


func _test_unregister() -> void:
	var ft := FitnessTracker.new()
	ft.register(1)
	ft.record_food_eaten(1, 10.0)
	ft.unregister(1)
	# After unregister, compute should return 0 (defaults)
	var fitness := ft.compute_fitness(1, 0)
	_assert_eq(fitness, 0.0, "fitness zero after unregister")


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
