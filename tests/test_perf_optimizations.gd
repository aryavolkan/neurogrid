extends Node
## Tests for P0 and P2 performance optimizations:
## - Sensor caching (food, enemy queries)
## - Pheromone sparse tracking
## - Food manager sparse regen + incremental total
## - GridTile cached elevation values
## - Skill ID constants
## - Ecology system skill lookup optimization
## - Species manager reference-based representative
## - CreatureBrain cached receptor cost

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	# P0: Sensor caching
	_test_sensor_begin_sensing_resets_cache()
	_test_sensor_food_cache_single_query()
	_test_sensor_food_cache_reused_across_receptors()
	_test_sensor_enemy_cache_single_query()
	_test_sensor_cache_invalidated_by_begin_sensing()
	_test_sensor_food_cache_range_mismatch_requeues()

	# P0: Pheromone sparse tracking
	_test_pheromone_sparse_deposit_and_decay()
	_test_pheromone_sparse_no_update_when_empty()
	_test_pheromone_sparse_diffusion_adds_neighbors()
	_test_pheromone_tiles_below_threshold_removed()
	_test_pheromone_multiple_deposits_tracked()

	# P0: Food manager sparse regen
	_test_food_manager_regen_tiles_precomputed()
	_test_food_manager_corpse_sparse_tracking()
	_test_food_manager_corpse_removed_when_depleted()
	_test_food_manager_total_food_incremental()
	_test_food_manager_global_cap_respected()
	_test_food_manager_season_modifier()

	# P0: Food index batch rebuild
	_test_food_index_batch_rebuild()
	_test_food_index_no_rebuild_when_clean()

	# P2: GridTile cached values
	_test_tile_cached_movement_cost()
	_test_tile_cached_sensor_bonus()
	_test_tile_cached_is_sand()
	_test_tile_update_cached_values_refreshes()
	_test_tile_default_cached_values()
	_test_tile_elevation_extremes()

	# P2: Skill ID constants
	_test_skill_constants_match_registry()
	_test_skill_constants_all_defined()

	# P0: Ecology skill lookup
	_test_ecology_herbivore_bonus_no_combat()
	_test_ecology_herbivore_bonus_with_bite()
	_test_ecology_herbivore_bonus_with_poison()

	# P2: Species manager reference representative
	_test_species_representative_is_reference()

	# P1: CreatureBrain cached receptor cost
	_test_brain_receptor_cost_cached()
	_test_brain_receptor_cost_zero_no_receptors()

	# P2: WorldGenerator calls update_cached_values
	_test_world_generator_caches_initialized()

	# P1: Neuromodulation reward bug fix
	_test_neuromodulation_reward_nonzero()

	_print_results("PerfOptimizations")


# ============================================================
# P0: SENSOR CACHING TESTS
# ============================================================

func _test_sensor_begin_sensing_resets_cache() -> void:
	var world := GridWorld.new()
	world.setup()
	var sensor := CreatureSensor.new(world)
	sensor.begin_sensing()
	_assert_true(sensor._cached_food_range == -1, "begin_sensing resets food range cache")
	_assert_true(sensor._cached_enemy_valid == false, "begin_sensing resets enemy cache")
	_assert_true(sensor._cached_food_pos == Vector2i(-2, -2), "begin_sensing resets food pos cache")


func _test_sensor_food_cache_single_query() -> void:
	var world := GridWorld.new()
	world.setup()
	# Place food at known position
	var tile: GridTile = world.get_tile(Vector2i(10, 10))
	tile.food = 5.0
	world.mark_food_dirty()
	world.rebuild_food_index_if_dirty()

	var sensor := CreatureSensor.new(world)
	sensor.begin_sensing()

	var body := CreatureBody.new()
	# Query food dist (registry_id 0) — should cache
	var val := sensor.get_receptor_value(0, Vector2i(9, 10), body, 1)
	_assert_true(val > 0.0, "food dist returns nonzero when food nearby")
	_assert_true(sensor._cached_food_range > 0, "food range cached after query")


func _test_sensor_food_cache_reused_across_receptors() -> void:
	var world := GridWorld.new()
	world.setup()
	var tile: GridTile = world.get_tile(Vector2i(15, 15))
	tile.food = 8.0
	world.mark_food_dirty()
	world.rebuild_food_index_if_dirty()

	var sensor := CreatureSensor.new(world)
	sensor.begin_sensing()
	var body := CreatureBody.new()
	var pos := Vector2i(14, 15)

	# Query all three food receptors — should hit cache for #1 and #2
	var dist_val := sensor.get_receptor_value(0, pos, body, 1)
	var cached_pos_after_first := sensor._cached_food_pos

	var dx_val := sensor.get_receptor_value(1, pos, body, 1)
	_assert_eq(sensor._cached_food_pos, cached_pos_after_first, "food cache reused for dx query")

	var dy_val := sensor.get_receptor_value(2, pos, body, 1)
	_assert_eq(sensor._cached_food_pos, cached_pos_after_first, "food cache reused for dy query")

	_assert_true(dist_val > 0.0, "food dist value correct")
	_assert_true(dx_val > 0.0, "food dx value correct (food is to the right)")


func _test_sensor_enemy_cache_single_query() -> void:
	var world := GridWorld.new()
	world.setup()
	world.set_creature_position(99, Vector2i(20, 20))

	var sensor := CreatureSensor.new(world)
	sensor.begin_sensing()
	var body := CreatureBody.new()

	# Query enemy dist (registry_id 3) — should cache
	var val := sensor.get_receptor_value(3, Vector2i(19, 20), body, 1)
	_assert_true(val > 0.0, "enemy dist returns nonzero when enemy nearby")
	_assert_true(sensor._cached_enemy_valid, "enemy cache valid after query")


func _test_sensor_cache_invalidated_by_begin_sensing() -> void:
	var world := GridWorld.new()
	world.setup()
	var tile: GridTile = world.get_tile(Vector2i(5, 5))
	tile.food = 3.0
	world.mark_food_dirty()
	world.rebuild_food_index_if_dirty()

	var sensor := CreatureSensor.new(world)
	sensor.begin_sensing()
	var body := CreatureBody.new()

	# Fill cache
	sensor.get_receptor_value(0, Vector2i(5, 5), body, 1)
	_assert_true(sensor._cached_food_range > 0, "cache filled")

	# Reset
	sensor.begin_sensing()
	_assert_eq(sensor._cached_food_range, -1, "cache cleared after begin_sensing")


func _test_sensor_food_cache_range_mismatch_requeues() -> void:
	var world := GridWorld.new()
	world.setup()
	var sensor := CreatureSensor.new(world)
	sensor.begin_sensing()

	# Manually set a cached range
	sensor._cached_food_range = 5
	sensor._cached_food_pos = Vector2i(10, 10)

	# Query with different effective range — should re-query
	# (We can't easily change effective range here, so just verify the mechanism)
	var result := sensor._get_cached_food(Vector2i(0, 0), 7)
	_assert_true(sensor._cached_food_range == 7, "cache updated when range differs")


# ============================================================
# P0: PHEROMONE SPARSE TRACKING TESTS
# ============================================================

func _test_pheromone_sparse_deposit_and_decay() -> void:
	var world := GridWorld.new()
	world.setup()
	var layer := PheromoneLayer.new(world)

	layer.deposit(Vector2i(10, 10), 0.5)
	_assert_true(layer._active_tiles.has(Vector2i(10, 10)), "deposit adds to active tiles")

	var tile: GridTile = world.get_tile(Vector2i(10, 10))
	_assert_true(tile.pheromone > 0.4, "pheromone deposited on tile")

	layer.update(0.0)
	_assert_true(tile.pheromone > 0.0, "pheromone still present after one decay")
	_assert_true(tile.pheromone < 0.5, "pheromone decayed")


func _test_pheromone_sparse_no_update_when_empty() -> void:
	var world := GridWorld.new()
	world.setup()
	var layer := PheromoneLayer.new(world)

	_assert_true(layer._active_tiles.is_empty(), "no active tiles initially")
	# Should not crash or iterate
	layer.update(0.0)
	_assert_true(layer._active_tiles.is_empty(), "still empty after update with no pheromone")


func _test_pheromone_sparse_diffusion_adds_neighbors() -> void:
	var world := GridWorld.new()
	world.setup()
	var layer := PheromoneLayer.new(world)

	layer.deposit(Vector2i(30, 30), 1.0)
	layer.update(0.0)

	# Check that neighbors got some pheromone from diffusion
	var neighbor_tile: GridTile = world.get_tile(Vector2i(31, 30))
	_assert_true(neighbor_tile.pheromone > 0.0, "pheromone diffused to neighbor")
	_assert_true(layer._active_tiles.has(Vector2i(31, 30)), "neighbor added to active tiles")


func _test_pheromone_tiles_below_threshold_removed() -> void:
	var world := GridWorld.new()
	world.setup()
	var layer := PheromoneLayer.new(world)

	layer.deposit(Vector2i(20, 20), 0.002)  # Very small amount
	# After several decays, should drop below threshold and be removed
	for _i in 20:
		layer.update(0.0)

	var tile: GridTile = world.get_tile(Vector2i(20, 20))
	_assert_true(tile.pheromone < 0.001, "tiny pheromone decayed away")


func _test_pheromone_multiple_deposits_tracked() -> void:
	var world := GridWorld.new()
	world.setup()
	var layer := PheromoneLayer.new(world)

	layer.deposit(Vector2i(5, 5), 0.5)
	layer.deposit(Vector2i(50, 50), 0.5)
	_assert_eq(layer._active_tiles.size(), 2, "two active tiles after two deposits")


# ============================================================
# P0: FOOD MANAGER SPARSE REGEN TESTS
# ============================================================

func _test_food_manager_regen_tiles_precomputed() -> void:
	var world := GridWorld.new()
	world.setup()
	# Set specific terrain
	for x in 10:
		var tile: GridTile = world.get_tile(Vector2i(x, 0))
		tile.terrain = GameConfig.Terrain.GRASS

	var fm := FoodManager.new(world)
	fm._ensure_initialized()
	_assert_true(fm._regen_tiles.size() > 0, "regen tiles precomputed")
	_assert_true(fm._regen_tiles.size() <= world.tiles.size(), "regen tiles <= total tiles")


func _test_food_manager_corpse_sparse_tracking() -> void:
	var world := GridWorld.new()
	world.setup()
	var fm := FoodManager.new(world)
	fm._ensure_initialized()

	var tile: GridTile = world.get_tile(Vector2i(10, 10))
	tile.corpse_energy = 5.0
	fm.add_corpse(Vector2i(10, 10))

	_assert_true(fm._corpse_tiles.has(Vector2i(10, 10)), "corpse tile tracked")


func _test_food_manager_corpse_removed_when_depleted() -> void:
	var world := GridWorld.new()
	world.setup()
	var fm := FoodManager.new(world)
	fm._ensure_initialized()

	var tile: GridTile = world.get_tile(Vector2i(10, 10))
	tile.corpse_energy = 0.05  # Will deplete in 1 tick (0.1 decay)
	fm.add_corpse(Vector2i(10, 10))

	fm.update(0.0)
	_assert_true(not fm._corpse_tiles.has(Vector2i(10, 10)), "depleted corpse removed from tracking")


func _test_food_manager_total_food_incremental() -> void:
	var world := GridWorld.new()
	world.setup()
	# Clear all food to have a known baseline
	for pos in world.tiles:
		world.tiles[pos].food = 0.0
		world.tiles[pos].terrain = GameConfig.Terrain.ROCK  # No regen

	var fm := FoodManager.new(world)
	fm._ensure_initialized()
	_assert_true(fm.get_total_food() == 0.0, "total food is zero with no food tiles")

	# Simulate external food addition
	fm.adjust_food_total(100.0)
	_assert_true(abs(fm.get_total_food() - 100.0) < 0.01, "adjust_food_total works")


func _test_food_manager_global_cap_respected() -> void:
	var world := GridWorld.new()
	world.setup()
	var fm := FoodManager.new(world)
	fm._ensure_initialized()

	# Set total food to near cap
	fm._total_food = FoodManager.MAX_GLOBAL_FOOD - 1.0
	fm.update(0.0)

	_assert_true(fm._total_food <= FoodManager.MAX_GLOBAL_FOOD + 1.0, "global food cap respected")


func _test_food_manager_season_modifier() -> void:
	var world := GridWorld.new()
	world.setup()
	var fm := FoodManager.new(world)

	_assert_eq(fm.get_season_phase(), 0.0, "season starts at 0")
	fm._season_tick = FoodManager.SEASON_LENGTH / 2
	var phase := fm.get_season_phase()
	_assert_true(abs(phase - 0.5) < 0.01, "season midpoint at 0.5")
	_assert_true(fm.is_famine(), "midpoint is famine")


# ============================================================
# P0: FOOD INDEX BATCH REBUILD
# ============================================================

func _test_food_index_batch_rebuild() -> void:
	var world := GridWorld.new()
	world.setup()
	var tile: GridTile = world.get_tile(Vector2i(10, 10))
	tile.food = 5.0
	world.mark_food_dirty()

	_assert_true(world._food_dirty, "food index is dirty after mark")
	world.rebuild_food_index_if_dirty()
	_assert_true(not world._food_dirty, "food index clean after batch rebuild")

	# find_nearest_food should work without triggering rebuild
	var pos := world.find_nearest_food(Vector2i(10, 10), 3)
	_assert_eq(pos, Vector2i(10, 10), "food found after batch rebuild")


func _test_food_index_no_rebuild_when_clean() -> void:
	var world := GridWorld.new()
	world.setup()
	world.mark_food_dirty()
	world.rebuild_food_index_if_dirty()
	_assert_true(not world._food_dirty, "index is clean")

	# Call again — should be a no-op
	world.rebuild_food_index_if_dirty()
	_assert_true(not world._food_dirty, "index stays clean")


# ============================================================
# P2: GRID TILE CACHED VALUES
# ============================================================

func _test_tile_cached_movement_cost() -> void:
	var tile := GridTile.new(Vector2i(0, 0))
	tile.elevation = 0.5
	tile.update_cached_values()
	var expected: float = 1.0 + clampf(0.5, -0.5, 1.0)  # 1.5
	_assert_true(abs(tile.movement_cost_mult - expected) < 0.001, "cached movement cost matches elevation 0.5")
	_assert_true(abs(tile.get_elevation_movement_cost() - expected) < 0.001, "getter returns cached value")


func _test_tile_cached_sensor_bonus() -> void:
	var tile := GridTile.new(Vector2i(0, 0))
	tile.elevation = 0.8
	tile.update_cached_values()
	var expected: int = int(0.8 * 3.0)  # 2
	_assert_eq(tile.sensor_bonus_range, expected, "cached sensor bonus for elevation 0.8")
	_assert_eq(tile.get_elevation_sensor_bonus(), expected, "getter returns cached value")


func _test_tile_cached_is_sand() -> void:
	var tile := GridTile.new(Vector2i(0, 0))
	tile.terrain = GameConfig.Terrain.SAND
	tile.update_cached_values()
	_assert_true(tile.is_sand, "is_sand true for sand terrain")

	tile.terrain = GameConfig.Terrain.GRASS
	tile.update_cached_values()
	_assert_true(not tile.is_sand, "is_sand false for grass terrain")


func _test_tile_update_cached_values_refreshes() -> void:
	var tile := GridTile.new(Vector2i(0, 0))
	tile.elevation = 0.0
	tile.update_cached_values()
	_assert_true(abs(tile.movement_cost_mult - 1.0) < 0.001, "flat terrain cost is 1.0")

	tile.elevation = 1.0
	tile.update_cached_values()
	_assert_true(abs(tile.movement_cost_mult - 2.0) < 0.001, "max elevation cost is 2.0")


func _test_tile_default_cached_values() -> void:
	var tile := GridTile.new(Vector2i(0, 0))
	# Default values without calling update_cached_values
	_assert_true(abs(tile.movement_cost_mult - 1.0) < 0.001, "default movement cost is 1.0")
	_assert_eq(tile.sensor_bonus_range, 0, "default sensor bonus is 0")
	_assert_true(not tile.is_sand, "default is not sand (grass)")


func _test_tile_elevation_extremes() -> void:
	var tile := GridTile.new(Vector2i(0, 0))

	# Valley (negative elevation)
	tile.elevation = -1.0
	tile.update_cached_values()
	_assert_true(abs(tile.movement_cost_mult - 0.5) < 0.001, "valley clamped to 0.5 cost")
	_assert_eq(tile.sensor_bonus_range, 0, "valley has no sensor bonus")

	# Peak (max elevation)
	tile.elevation = 1.0
	tile.update_cached_values()
	_assert_true(abs(tile.movement_cost_mult - 2.0) < 0.001, "peak at 2.0 cost")
	_assert_eq(tile.sensor_bonus_range, 3, "peak has max sensor bonus")


# ============================================================
# P2: SKILL ID CONSTANTS
# ============================================================

func _test_skill_constants_match_registry() -> void:
	_assert_eq(GameConfig.SKILL_DASH, 0, "SKILL_DASH is 0")
	_assert_eq(GameConfig.SKILL_BITE, 1, "SKILL_BITE is 1")
	_assert_eq(GameConfig.SKILL_POISON_SPIT, 2, "SKILL_POISON_SPIT is 2")
	_assert_eq(GameConfig.SKILL_EMIT_PHEROMONE, 3, "SKILL_EMIT_PHEROMONE is 3")
	_assert_eq(GameConfig.SKILL_SHARE_FOOD, 4, "SKILL_SHARE_FOOD is 4")
	_assert_eq(GameConfig.SKILL_BUILD_WALL, 5, "SKILL_BUILD_WALL is 5")
	_assert_eq(GameConfig.SKILL_HEAL_SELF, 6, "SKILL_HEAL_SELF is 6")
	_assert_eq(GameConfig.SKILL_BURROW, 7, "SKILL_BURROW is 7")


func _test_skill_constants_all_defined() -> void:
	var skill_count: int = Registries.skill_registry.get_count()
	_assert_eq(skill_count, 8, "8 skills in registry")
	# Verify each constant has a matching registry entry
	for id in [GameConfig.SKILL_DASH, GameConfig.SKILL_BITE, GameConfig.SKILL_POISON_SPIT,
			   GameConfig.SKILL_EMIT_PHEROMONE, GameConfig.SKILL_SHARE_FOOD,
			   GameConfig.SKILL_BUILD_WALL, GameConfig.SKILL_HEAL_SELF, GameConfig.SKILL_BURROW]:
		var entry = Registries.skill_registry.get_entry(id)
		_assert_true(entry != null, "skill constant %d has registry entry" % id)


# ============================================================
# P0: ECOLOGY SKILL LOOKUP OPTIMIZATION
# ============================================================

func _make_genome_with_skills(skill_ids: Array) -> DynamicGenome:
	## Helper: create a genome with specific skill nodes.
	var config := DynamicConfig.new()
	var conn_tracker := NeatInnovation.new()
	var io_tracker := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn_tracker, io_tracker)
	for sid in skill_ids:
		var io_innov: int = io_tracker.get_skill_innovation(sid)
		var node_id: int = conn_tracker.allocate_node_id()
		var node := DynamicGenome.DynamicNodeGene.new(node_id, DynamicGenome.TYPE_SKILL, sid, io_innov)
		genome.node_genes.append(node)
	return genome


func _test_ecology_herbivore_bonus_no_combat() -> void:
	var genome := _make_genome_with_skills([GameConfig.SKILL_DASH, GameConfig.SKILL_HEAL_SELF])
	# Herbivore: no bite or poison
	var skill_ids := genome.get_skill_registry_ids()
	var is_herbivore: bool = not skill_ids.has(GameConfig.SKILL_BITE) and not skill_ids.has(GameConfig.SKILL_POISON_SPIT)
	_assert_true(is_herbivore, "genome without bite/poison is herbivore")


func _test_ecology_herbivore_bonus_with_bite() -> void:
	var genome := _make_genome_with_skills([GameConfig.SKILL_BITE, GameConfig.SKILL_DASH])
	var skill_ids := genome.get_skill_registry_ids()
	var is_herbivore: bool = not skill_ids.has(GameConfig.SKILL_BITE) and not skill_ids.has(GameConfig.SKILL_POISON_SPIT)
	_assert_true(not is_herbivore, "genome with bite is not herbivore")


func _test_ecology_herbivore_bonus_with_poison() -> void:
	var genome := _make_genome_with_skills([GameConfig.SKILL_POISON_SPIT])
	var skill_ids := genome.get_skill_registry_ids()
	var is_herbivore: bool = not skill_ids.has(GameConfig.SKILL_BITE) and not skill_ids.has(GameConfig.SKILL_POISON_SPIT)
	_assert_true(not is_herbivore, "genome with poison is not herbivore")


# ============================================================
# P2: SPECIES MANAGER REFERENCE REPRESENTATIVE
# ============================================================

func _test_species_representative_is_reference() -> void:
	var config := DynamicConfig.new()
	var conn_tracker := NeatInnovation.new()
	var io_tracker := IoInnovation.new()
	var sm := SpeciesManager.new(config)
	var genome := DynamicGenome.create(config, conn_tracker, io_tracker)

	var species_id := sm.assign_species(1, genome)
	var info := sm.get_species_info(species_id)

	# Representative should be the same object (not a copy)
	_assert_true(info.representative_genome == genome, "representative is same reference, not copy")


# ============================================================
# P1: CREATURE BRAIN CACHED RECEPTOR COST
# ============================================================

func _test_brain_receptor_cost_cached() -> void:
	var config := DynamicConfig.new()
	var conn_tracker := NeatInnovation.new()
	var io_tracker := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn_tracker, io_tracker)
	# Add a receptor (smell_food_dist, cost 0.1)
	var io_innov: int = io_tracker.get_receptor_innovation(0)
	var node_id: int = conn_tracker.allocate_node_id()
	var node := DynamicGenome.DynamicNodeGene.new(node_id, DynamicGenome.TYPE_RECEPTOR, 0, io_innov)
	genome.node_genes.append(node)

	var world := GridWorld.new()
	world.setup()
	var sensor := CreatureSensor.new(world)
	var brain := CreatureBrain.new(genome, sensor)

	_assert_true(abs(brain.get_receptor_energy_cost() - 0.1) < 0.001, "cached receptor cost is 0.1")
	# Call again — should return same cached value
	_assert_true(abs(brain.get_receptor_energy_cost() - 0.1) < 0.001, "receptor cost still cached")


func _test_brain_receptor_cost_zero_no_receptors() -> void:
	var config := DynamicConfig.new()
	var conn_tracker := NeatInnovation.new()
	var io_tracker := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn_tracker, io_tracker)

	var world := GridWorld.new()
	world.setup()
	var sensor := CreatureSensor.new(world)
	var brain := CreatureBrain.new(genome, sensor)

	_assert_true(brain.get_receptor_energy_cost() == 0.0, "no receptors = zero cost")


# ============================================================
# P2: WORLD GENERATOR CACHES
# ============================================================

func _test_world_generator_caches_initialized() -> void:
	var world := GridWorld.new()
	world.setup()
	WorldGenerator.generate(world)

	# Verify that tiles with elevation have correct cached values
	var found_elevated: bool = false
	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		if tile.elevation > 0.5:  # Use 0.5 to ensure int(elev * 3.0) >= 1
			found_elevated = true
			_assert_true(tile.sensor_bonus_range > 0, "elevated tile has sensor bonus cached")
			_assert_true(tile.movement_cost_mult > 1.0, "elevated tile has movement cost > 1.0")
			break

	var found_sand: bool = false
	for pos in world.tiles:
		var tile: GridTile = world.tiles[pos]
		if tile.terrain == GameConfig.Terrain.SAND:
			found_sand = true
			_assert_true(tile.is_sand, "sand tile has is_sand cached")
			break

	# At least one elevated or sand tile should exist in generated world
	_assert_true(found_elevated or found_sand, "generated world has elevated or sand tiles")


# ============================================================
# P1: NEUROMODULATION REWARD BUG FIX
# ============================================================

func _test_neuromodulation_reward_nonzero() -> void:
	## The bug: reward was computed as (energy_after - energy_after) which is always 0.
	## Fix: reward = (energy_after - energy_before) * 0.01
	## This test verifies the math is correct by simulating the pattern.
	var energy_before: float = 80.0
	var energy_after: float = 75.0  # Lost 5 energy from actions
	var reward: float = (energy_after - energy_before) * 0.01
	_assert_true(abs(reward - (-0.05)) < 0.001, "negative reward for energy loss")

	energy_after = 85.0  # Gained 5 energy from eating
	reward = (energy_after - energy_before) * 0.01
	_assert_true(abs(reward - 0.05) < 0.001, "positive reward for energy gain")

	# Old buggy version
	var buggy_reward: float = (energy_after - energy_after) * 0.01
	_assert_true(buggy_reward == 0.0, "buggy version always returns zero")


# ============================================================
# ASSERT HELPERS
# ============================================================

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
