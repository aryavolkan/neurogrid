extends Node
## Tests for GridWorld, GridTile, FoodManager, PheromoneLayer.

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_test_grid_setup()
	_test_passability()
	_test_creature_tracking()
	_test_food_index()
	_test_spatial_queries()
	_test_pheromone_decay()
	_test_food_manager_total_before_update()
	_print_results("World")


func _test_grid_setup() -> void:
	var world := GridWorld.new()
	world.setup()
	_assert_eq(world.tiles.size(), GameConfig.GRID_WIDTH * GameConfig.GRID_HEIGHT, "tile count")
	var tile: GridTile = world.get_tile(Vector2i(0, 0))
	_assert_true(tile != null, "origin tile exists")
	_assert_true(world.is_valid(Vector2i(0, 0)), "origin is valid")
	_assert_true(not world.is_valid(Vector2i(-1, 0)), "negative pos is invalid")
	_assert_true(not world.is_valid(Vector2i(GameConfig.GRID_WIDTH, 0)), "overflow pos is invalid")


func _test_passability() -> void:
	var world := GridWorld.new()
	world.setup()
	# Default grass is passable
	var tile: GridTile = world.get_tile(Vector2i(5, 5))
	tile.terrain = GameConfig.Terrain.GRASS
	_assert_true(world.is_passable(Vector2i(5, 5)), "grass is passable")

	tile.terrain = GameConfig.Terrain.WATER
	_assert_true(not tile.is_passable(), "water is not passable")

	tile.terrain = GameConfig.Terrain.GRASS
	tile.wall = true
	_assert_true(not tile.is_passable(), "wall blocks passability")


func _test_creature_tracking() -> void:
	var world := GridWorld.new()
	world.setup()
	world.set_creature_position(1, Vector2i(3, 3))
	_assert_eq(world.get_creature_at(Vector2i(3, 3)), 1, "creature at pos")
	_assert_eq(world.get_creature_at(Vector2i(4, 4)), -1, "no creature at empty pos")

	world.move_creature(1, Vector2i(3, 3), Vector2i(4, 3))
	_assert_eq(world.get_creature_at(Vector2i(3, 3)), -1, "old pos cleared after move")
	_assert_eq(world.get_creature_at(Vector2i(4, 3)), 1, "new pos set after move")

	world.clear_creature_position(Vector2i(4, 3))
	_assert_eq(world.get_creature_at(Vector2i(4, 3)), -1, "cleared pos")


func _test_food_index() -> void:
	var world := GridWorld.new()
	world.setup()
	var tile: GridTile = world.get_tile(Vector2i(10, 10))
	tile.food = 5.0
	world.mark_food_dirty()
	world.rebuild_food_index_if_dirty()
	var nearest := world.find_nearest_food(Vector2i(10, 10), 3)
	_assert_eq(nearest, Vector2i(10, 10), "find food at same tile")

	var far := world.find_nearest_food(Vector2i(50, 50), 3)
	_assert_eq(far, Vector2i(-1, -1), "no food in range")


func _test_spatial_queries() -> void:
	var world := GridWorld.new()
	world.setup()
	world.set_creature_position(10, Vector2i(5, 5))
	world.set_creature_position(20, Vector2i(6, 5))
	world.set_creature_position(30, Vector2i(50, 50))

	var nearby := world.find_creatures_in_range(Vector2i(5, 5), 3)
	_assert_eq(nearby.size(), 1, "one creature in range 3")
	_assert_eq(nearby[0].id, 20, "found correct creature")

	var nearest := world.find_nearest_creature(Vector2i(5, 5), 3, 10)
	_assert_eq(nearest.id, 20, "nearest creature")

	var empty_adj := world.find_empty_adjacent(Vector2i(5, 5))
	_assert_true(empty_adj != Vector2i(-1, -1), "found empty adjacent")


func _test_pheromone_decay() -> void:
	var world := GridWorld.new()
	world.setup()
	var layer := PheromoneLayer.new(world)
	layer.deposit(Vector2i(10, 10), 1.0)
	var tile: GridTile = world.get_tile(Vector2i(10, 10))
	_assert_true(tile.pheromone > 0.9, "pheromone deposited")
	layer.update(0.0)
	_assert_true(tile.pheromone < 1.0, "pheromone decayed")


func _test_food_manager_total_before_update() -> void:
	## get_total_food() must return correct total even before first update().
	var w := GridWorld.new()
	w.setup()
	# Place food directly on a tile
	var tile: GridTile = w.get_tile(Vector2i(5, 5))
	tile.food = 10.0
	var fm := FoodManager.new(w)
	# Before any update() call, total should still reflect tile data
	_assert_true(fm.get_total_food() >= 10.0, "get_total_food before update includes tile food")


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
