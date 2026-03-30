extends Node
## Tests for CreatureBody: alive checks, energy, health, cooldowns, poison, burrow.

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_test_initial_state()
	_test_is_alive_energy_zero()
	_test_is_alive_health_zero()
	_test_is_alive_max_age()
	_test_can_reproduce()
	_test_take_damage()
	_test_take_damage_burrowed()
	_test_eat_food()
	_test_eat_food_capped()
	_test_apply_metabolism()
	_test_apply_movement_cost()
	_test_skill_cooldowns()
	_test_update_cooldowns_poison()
	_test_update_cooldowns_burrow()
	_test_reproduction_cooldown()
	_print_results("CreatureBody")


func _test_initial_state() -> void:
	var body := CreatureBody.new()
	_assert_eq(body.energy, GameConfig.STARTING_ENERGY, "initial energy")
	_assert_eq(body.health, GameConfig.MAX_HEALTH, "initial health")
	_assert_eq(body.age, 0, "initial age")
	_assert_true(body.is_alive(), "initially alive")


func _test_is_alive_energy_zero() -> void:
	var body := CreatureBody.new()
	body.energy = 0.0
	_assert_true(not body.is_alive(), "dead at zero energy")


func _test_is_alive_health_zero() -> void:
	var body := CreatureBody.new()
	body.health = 0.0
	_assert_true(not body.is_alive(), "dead at zero health")


func _test_is_alive_max_age() -> void:
	var body := CreatureBody.new()
	body.age = GameConfig.MAX_AGE
	_assert_true(not body.is_alive(), "dead at max age")


func _test_can_reproduce() -> void:
	var body := CreatureBody.new()
	body.energy = GameConfig.REPRODUCTION_ENERGY_THRESHOLD + 1.0
	body.reproduction_cooldown = 0.0
	_assert_true(body.can_reproduce(), "can reproduce with enough energy")

	body.energy = GameConfig.REPRODUCTION_ENERGY_THRESHOLD - 1.0
	_assert_true(not body.can_reproduce(), "cannot reproduce low energy")

	body.energy = GameConfig.REPRODUCTION_ENERGY_THRESHOLD + 1.0
	body.reproduction_cooldown = 5.0
	_assert_true(not body.can_reproduce(), "cannot reproduce on cooldown")


func _test_take_damage() -> void:
	var body := CreatureBody.new()
	body.take_damage(10.0)
	_assert_eq(body.health, GameConfig.MAX_HEALTH - 10.0, "damage applied")

	body.take_damage(999.0)
	_assert_eq(body.health, 0.0, "health clamped to zero")


func _test_take_damage_burrowed() -> void:
	var body := CreatureBody.new()
	body.burrowed = true
	body.take_damage(10.0)
	_assert_eq(body.health, GameConfig.MAX_HEALTH, "no damage when burrowed")


func _test_eat_food() -> void:
	var body := CreatureBody.new()
	body.energy = 30.0
	var consumed := body.eat_food(10.0)
	_assert_eq(consumed, 10.0, "ate full amount")
	_assert_eq(body.energy, 40.0, "energy increased")


func _test_eat_food_capped() -> void:
	var body := CreatureBody.new()
	body.energy = GameConfig.MAX_ENERGY - 3.0
	var consumed := body.eat_food(10.0)
	_assert_eq(consumed, 3.0, "ate only what fits")
	_assert_eq(body.energy, GameConfig.MAX_ENERGY, "energy at max")


func _test_apply_metabolism() -> void:
	var body := CreatureBody.new()
	var initial := body.energy
	body.apply_metabolism(0.1)
	_assert_eq(body.energy, initial - GameConfig.BASE_METABOLISM - 0.1, "metabolism applied")


func _test_apply_movement_cost() -> void:
	var body := CreatureBody.new()
	var initial := body.energy
	body.apply_movement_cost()
	_assert_eq(body.energy, initial - GameConfig.MOVEMENT_COST, "movement cost applied")


func _test_skill_cooldowns() -> void:
	var body := CreatureBody.new()
	_assert_true(body.is_skill_ready(0), "skill ready initially")
	body.set_skill_cooldown(0, 3)
	_assert_true(not body.is_skill_ready(0), "skill on cooldown")
	body.update_cooldowns(0.0)
	body.update_cooldowns(0.0)
	body.update_cooldowns(0.0)
	_assert_true(body.is_skill_ready(0), "skill ready after 3 ticks")


func _test_update_cooldowns_poison() -> void:
	var body := CreatureBody.new()
	body.poisoned_ticks = 2
	body.update_cooldowns(0.0)
	_assert_eq(body.poisoned_ticks, 1, "poison ticks decrement")
	_assert_eq(body.health, GameConfig.MAX_HEALTH - 5.0, "poison damage applied")
	body.update_cooldowns(0.0)
	_assert_eq(body.poisoned_ticks, 0, "poison expired")


func _test_update_cooldowns_burrow() -> void:
	var body := CreatureBody.new()
	body.burrowed = true
	body.burrow_ticks = 1
	body.update_cooldowns(0.0)
	_assert_true(not body.burrowed, "emerged from burrow")
	_assert_eq(body.burrow_ticks, 0, "burrow ticks zeroed")


func _test_reproduction_cooldown() -> void:
	var body := CreatureBody.new()
	body.reproduction_cooldown = 2.0
	body.update_cooldowns(0.0)
	_assert_eq(body.reproduction_cooldown, 1.0, "repro cooldown decrements")
	body.update_cooldowns(0.0)
	_assert_eq(body.reproduction_cooldown, 0.0, "repro cooldown zero")


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
