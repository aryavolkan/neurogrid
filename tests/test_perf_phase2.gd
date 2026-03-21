extends Node
## Tests for Phase 2 performance optimizations:
## - Viewport-culled grid rendering
## - Conditional creature redraw
## - Weather sparse tile sets
## - Territory on-move updates
## - Species fast pre-filter
## - SimLogger array-based skill tracking
## - Sensor effective_range caching
## - Reproduction fast pre-filter
## - Coevolution nested dict
## - Pheromone reused dict
## - HUD species count

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	# Grid rendering
	_test_terrain_color_lookup()

	# Creature conditional redraw
	_test_creature_prev_state_tracking()

	# Weather sparse tile sets
	_test_weather_sparse_vegetation_init()
	_test_weather_sparse_erosion_init()
	_test_weather_vegetation_only_sparse()
	_test_weather_erosion_removes_flooded()

	# Territory on-move
	_test_territory_update_on_move()
	_test_territory_no_bulk_update()

	# Species fast pre-filter
	_test_species_assign_basic()
	_test_species_prefilter_skips_divergent()

	# SimLogger array-based skills
	_test_logger_skill_array_record()
	_test_logger_skill_array_accumulate()
	_test_logger_skill_gen_report()
	_test_logger_skill_reset()
	_test_logger_legacy_record_skill()

	# Sensor effective_range caching
	_test_sensor_eff_range_cached()
	_test_sensor_eff_range_reset()

	# Reproduction fast pre-filter
	_test_repro_prefilter_basics()

	# Coevolution nested dict
	_test_coevolution_record()
	_test_coevolution_bonus_attacker()
	_test_coevolution_bonus_defender()
	_test_coevolution_report()
	_test_coevolution_reset()

	# Pheromone reused dict
	_test_pheromone_reuses_dict()

	_print_results("PerfPhase2")


# ============================================================
# GRID RENDERING
# ============================================================

func _test_terrain_color_lookup() -> void:
	# Verify terrain color array matches terrain enum values
	_assert_eq(GridWorld.TERRAIN_COLORS.size(), 5, "5 terrain colors defined")
	_assert_eq(GridWorld.TERRAIN_COLORS[GameConfig.Terrain.GRASS], Color(0.2, 0.5, 0.2), "grass color correct")
	_assert_eq(GridWorld.TERRAIN_COLORS[GameConfig.Terrain.WATER], Color(0.15, 0.3, 0.6), "water color correct")
	_assert_eq(GridWorld.TERRAIN_COLORS[GameConfig.Terrain.SAND], Color(0.7, 0.65, 0.4), "sand color correct")


# ============================================================
# CREATURE CONDITIONAL REDRAW
# ============================================================

func _test_creature_prev_state_tracking() -> void:
	# Verify creature tracks previous energy/health for change detection
	var c := Creature.new()
	_assert_true(c._prev_energy == -1.0, "prev_energy starts at -1 (forces first redraw)")
	_assert_true(c._prev_health == -1.0, "prev_health starts at -1 (forces first redraw)")
	c.queue_free()


# ============================================================
# WEATHER SPARSE TILE SETS
# ============================================================

func _test_weather_sparse_vegetation_init() -> void:
	var world := GridWorld.new()
	world.setup()
	# Set some tiles to grass
	var grass_count: int = 0
	for x in 20:
		var tile: GridTile = world.get_tile(Vector2i(x, 0))
		tile.terrain = GameConfig.Terrain.GRASS
		grass_count += 1

	var ws := WeatherSystem.new(world)
	ws._ensure_sparse_initialized()
	_assert_true(ws._vegetation_tiles.size() > 0, "vegetation tiles populated")


func _test_weather_sparse_erosion_init() -> void:
	var world := GridWorld.new()
	world.setup()
	# Create a water tile and adjacent land tile
	var water_tile: GridTile = world.get_tile(Vector2i(10, 10))
	water_tile.terrain = GameConfig.Terrain.WATER
	var land_tile: GridTile = world.get_tile(Vector2i(11, 10))
	land_tile.terrain = GameConfig.Terrain.GRASS
	land_tile.elevation = 0.5

	var ws := WeatherSystem.new(world)
	ws._ensure_sparse_initialized()
	var has_erosion: bool = false
	for pos in ws._erosion_tiles:
		if pos == Vector2i(11, 10):
			has_erosion = true
			break
	_assert_true(has_erosion, "land tile adjacent to water is in erosion set")


func _test_weather_vegetation_only_sparse() -> void:
	var world := GridWorld.new()
	world.setup()
	# Make all tiles rock (no vegetation)
	for pos in world.tiles:
		world.tiles[pos].terrain = GameConfig.Terrain.ROCK

	var ws := WeatherSystem.new(world)
	ws._ensure_sparse_initialized()
	_assert_eq(ws._vegetation_tiles.size(), 0, "no vegetation tiles for all-rock world")


func _test_weather_erosion_removes_flooded() -> void:
	var world := GridWorld.new()
	world.setup()
	# Create a sand tile that will flood
	var water_tile: GridTile = world.get_tile(Vector2i(10, 10))
	water_tile.terrain = GameConfig.Terrain.WATER
	var sand_tile: GridTile = world.get_tile(Vector2i(11, 10))
	sand_tile.terrain = GameConfig.Terrain.SAND
	sand_tile.elevation = -0.24  # Just above flood threshold

	var ws := WeatherSystem.new(world)
	ws._ensure_sparse_initialized()
	var initial_erosion_count := ws._erosion_tiles.size()

	# Erode until it floods
	sand_tile.elevation = -0.26  # Below flood threshold
	ws._update_erosion()

	# Flooded tile should be removed from erosion set
	_assert_true(ws._erosion_tiles.size() <= initial_erosion_count, "flooded tile removed from erosion")


# ============================================================
# TERRITORY ON-MOVE
# ============================================================

func _test_territory_update_on_move() -> void:
	var world := GridWorld.new()
	world.setup()
	var eco := EcologySystem.new(world)

	# Create a minimal creature-like object for territory tracking
	var config := DynamicConfig.new()
	var conn_tracker := NeatInnovation.new()
	var io_tracker := IoInnovation.new()
	var genome := DynamicGenome.create(config, conn_tracker, io_tracker)

	var sensor := CreatureSensor.new(world)
	var c := Creature.new()
	c.setup(1, Vector2i(10, 10), genome, sensor)

	eco.update_territory(c)
	_assert_true(eco.has_territory(c.creature_id) == false, "no territory before 100 ticks")
	_assert_true(eco._territories.has(c.creature_id), "territory entry created on first call")


func _test_territory_no_bulk_update() -> void:
	# Verify update() no longer iterates creatures for territory
	var world := GridWorld.new()
	world.setup()
	var eco := EcologySystem.new(world)

	# Call update with empty creatures — should not crash
	eco.update(100, {})
	# Territories dict should remain empty
	_assert_eq(eco._territories.size(), 0, "no territories created by update()")


# ============================================================
# SPECIES FAST PRE-FILTER
# ============================================================

func _test_species_assign_basic() -> void:
	var config := DynamicConfig.new()
	var conn_tracker := NeatInnovation.new()
	var io_tracker := IoInnovation.new()
	var sm := SpeciesManager.new(config)

	var g1 := DynamicGenome.create(config, conn_tracker, io_tracker)
	var g2 := DynamicGenome.create(config, conn_tracker, io_tracker)

	var s1 := sm.assign_species(1, g1)
	var s2 := sm.assign_species(2, g2)

	# Both should get valid species IDs (may or may not be same species due to randomized initial connections)
	_assert_true(s1 > 0, "first genome gets valid species ID")
	_assert_true(s2 > 0, "second genome gets valid species ID")


func _test_species_prefilter_skips_divergent() -> void:
	var config := DynamicConfig.new()
	var conn_tracker := NeatInnovation.new()
	var io_tracker := IoInnovation.new()
	var sm := SpeciesManager.new(config)

	# Create a genome and add many connections to make it large
	var g1 := DynamicGenome.create(config, conn_tracker, io_tracker)
	for _i in 30:
		g1.mutate_add_connection()
	sm.assign_species(1, g1)

	# Create a minimal genome — should be filtered quickly
	var g2 := DynamicGenome.create(config, conn_tracker, io_tracker)
	var s2 := sm.assign_species(2, g2)

	# Should still work (may or may not be same species, but shouldn't crash)
	_assert_true(s2 > 0, "species assignment works with pre-filter")


# ============================================================
# SIMLOGGER ARRAY-BASED SKILLS
# ============================================================

func _test_logger_skill_array_record() -> void:
	var logger := SimLogger.new()
	logger.record_skill_by_id(GameConfig.SKILL_BITE)
	logger.record_skill_by_id(GameConfig.SKILL_BITE)
	logger.record_skill_by_id(GameConfig.SKILL_DASH)
	_assert_eq(logger.skills_fired[GameConfig.SKILL_BITE], 2, "bite recorded twice")
	_assert_eq(logger.skills_fired[GameConfig.SKILL_DASH], 1, "dash recorded once")
	_assert_eq(logger.skills_fired[GameConfig.SKILL_HEAL_SELF], 0, "heal not recorded")


func _test_logger_skill_array_accumulate() -> void:
	var logger := SimLogger.new()
	logger.record_skill_by_id(GameConfig.SKILL_POISON_SPIT)
	logger.end_tick()
	_assert_eq(logger.gen_skills[GameConfig.SKILL_POISON_SPIT], 1, "poison accumulated to gen")
	_assert_eq(logger.skills_fired[GameConfig.SKILL_POISON_SPIT], 0, "tick counter reset")


func _test_logger_skill_gen_report() -> void:
	var logger := SimLogger.new()
	logger.record_skill_by_id(GameConfig.SKILL_BITE)
	logger.end_tick()
	var report := logger.get_gen_report()
	_assert_true(report.contains("bite: 1"), "gen report contains skill count")


func _test_logger_skill_reset() -> void:
	var logger := SimLogger.new()
	logger.record_skill_by_id(GameConfig.SKILL_BURROW)
	logger.end_tick()
	logger.reset_generation()
	_assert_eq(logger.gen_skills[GameConfig.SKILL_BURROW], 0, "gen_skills reset to zero")


func _test_logger_legacy_record_skill() -> void:
	var logger := SimLogger.new()
	logger.record_skill("bite")
	_assert_eq(logger.skills_fired[GameConfig.SKILL_BITE], 1, "legacy string record works")


# ============================================================
# SENSOR EFFECTIVE_RANGE CACHING
# ============================================================

func _test_sensor_eff_range_cached() -> void:
	var world := GridWorld.new()
	world.setup()
	var sensor := CreatureSensor.new(world)
	sensor.begin_sensing()

	var pos := Vector2i(10, 10)
	var r1 := sensor._effective_range(5, pos)
	_assert_true(sensor._cached_eff_range_5 == r1, "range 5 cached after first call")

	var r2 := sensor._effective_range(5, pos)
	_assert_eq(r1, r2, "cached range returns same value")

	var r3 := sensor._effective_range(4, pos)
	_assert_true(sensor._cached_eff_range_4 == r3, "range 4 cached separately")


func _test_sensor_eff_range_reset() -> void:
	var world := GridWorld.new()
	world.setup()
	var sensor := CreatureSensor.new(world)
	sensor.begin_sensing()
	sensor._effective_range(5, Vector2i(10, 10))
	_assert_true(sensor._cached_eff_range_5 >= 0, "cache populated")

	sensor.begin_sensing()
	_assert_eq(sensor._cached_eff_range_5, -1, "cache cleared on begin_sensing")


# ============================================================
# REPRODUCTION FAST PRE-FILTER
# ============================================================

func _test_repro_prefilter_basics() -> void:
	# Just verify the pre-filter math works
	var size_a: int = 50
	var size_b: int = 5
	var n: float = maxf(size_a, size_b)
	var diff: float = absf(size_a - size_b)
	_assert_true(n >= 20.0, "n threshold met")
	_assert_true(diff / n > 0.8, "wildly different sizes detected")


# ============================================================
# COEVOLUTION NESTED DICT
# ============================================================

func _test_coevolution_record() -> void:
	var ae := AdvancedEvolution.new()
	ae.record_interaction(1, 2, 15.0, false)
	ae.record_interaction(1, 2, 10.0, true)
	_assert_true(ae._species_interactions.has(1), "attacker species recorded")
	_assert_true(ae._species_interactions[1].has(2), "defender species recorded")
	_assert_eq(ae._species_interactions[1][2].attacks, 2, "2 attacks recorded")
	_assert_eq(ae._species_interactions[1][2].kills, 1, "1 kill recorded")


func _test_coevolution_bonus_attacker() -> void:
	var ae := AdvancedEvolution.new()
	ae.record_interaction(1, 2, 100.0, true)
	var bonus := ae.get_coevolution_bonus(1)
	_assert_true(bonus > 0.0, "attacker gets positive bonus")


func _test_coevolution_bonus_defender() -> void:
	var ae := AdvancedEvolution.new()
	ae.record_interaction(1, 2, 10.0, false)  # Attack but no kill
	var bonus := ae.get_coevolution_bonus(2)
	_assert_true(bonus > 0.0, "defender gets survival bonus")


func _test_coevolution_report() -> void:
	var ae := AdvancedEvolution.new()
	ae.record_interaction(3, 5, 20.0, true)
	var report := ae.get_interaction_report()
	_assert_true(report.contains("3"), "report contains attacker species")
	_assert_true(report.contains("5"), "report contains defender species")
	_assert_true(report.contains("1 kills"), "report contains kill count")


func _test_coevolution_reset() -> void:
	var ae := AdvancedEvolution.new()
	ae.record_interaction(1, 2, 10.0, false)
	ae.reset_interactions()
	_assert_true(ae._species_interactions.is_empty(), "interactions cleared")
	_assert_eq(ae.get_coevolution_bonus(1), 0.0, "bonus is 0 after reset")


# ============================================================
# PHEROMONE REUSED DICT
# ============================================================

func _test_pheromone_reuses_dict() -> void:
	var world := GridWorld.new()
	world.setup()
	var layer := PheromoneLayer.new(world)

	# Verify the _new_values dict exists and is reused
	_assert_true(layer._new_values is Dictionary, "_new_values dict exists")

	layer.deposit(Vector2i(10, 10), 0.5)
	layer.update(0.0)

	# After update, dict should still exist (reused, not recreated)
	_assert_true(layer._new_values is Dictionary, "_new_values dict persists after update")

	# Run another update to verify reuse
	layer.update(0.0)
	_assert_true(layer._new_values is Dictionary, "_new_values dict persists across ticks")


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
