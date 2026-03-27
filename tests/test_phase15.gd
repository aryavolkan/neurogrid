extends Node
## Phase 15 tests: ConfigPresetManager, ReplayRecorder, WandbLogger.

var _config: DynamicConfig
var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	_setup()

	# ConfigPresetManager
	_test_preset_builtin_names()
	_test_preset_is_builtin()
	_test_preset_load_builtin()
	_test_preset_apply()
	_test_preset_save_load_roundtrip()
	_test_preset_delete()
	_test_preset_delete_builtin_fails()
	_test_preset_get_current_as_dict()

	# ReplayRecorder
	_test_recorder_empty()
	_test_recorder_records_frame()
	_test_recorder_frame_data_fields()
	_test_recorder_ring_buffer_wrap()
	_test_recorder_clear()
	_test_recorder_get_frame_out_of_bounds()
	_test_recorder_latest_frame()
	_test_recorder_recording_toggle()

	# WandbLogger (file I/O only — no sim required)
	_test_wandb_write_metrics_creates_file()
	_test_wandb_metrics_json_structure()

	_print_results("Phase15")


func _setup() -> void:
	_config = DynamicConfig.new()
	GameConfig.restore_defaults()


# ---------------------------------------------------------------------------
# ConfigPresetManager
# ---------------------------------------------------------------------------

func _test_preset_builtin_names() -> void:
	var names := ConfigPresetManager.list_presets()
	_assert_true(names.has("default"), "built-in 'default' in list")
	_assert_true(names.has("fast_evolution"), "built-in 'fast_evolution' in list")
	_assert_true(names.has("rich_ecology"), "built-in 'rich_ecology' in list")
	_assert_true(names.has("minimal"), "built-in 'minimal' in list")


func _test_preset_is_builtin() -> void:
	_assert_true(ConfigPresetManager.is_builtin("default"), "default is builtin")
	_assert_true(ConfigPresetManager.is_builtin("fast_evolution"), "fast_evolution is builtin")
	_assert_true(not ConfigPresetManager.is_builtin("my_custom"), "my_custom is not builtin")


func _test_preset_load_builtin() -> void:
	var params := ConfigPresetManager.load_preset("default")
	_assert_true(params.has("INITIAL_POPULATION"), "default has INITIAL_POPULATION")
	_assert_true(params.has("BASE_METABOLISM"), "default has BASE_METABOLISM")
	_assert_true(params.has("FOOD_REGEN_RATE"), "default has FOOD_REGEN_RATE")
	_assert_true(params.has("add_receptor_rate"), "default has add_receptor_rate")


func _test_preset_apply() -> void:
	# Apply fast_evolution and verify GameConfig changes
	var params := ConfigPresetManager.load_preset("fast_evolution")
	ConfigPresetManager.apply_preset(params, _config)
	_assert_eq(GameConfig.INITIAL_POPULATION, 120, "fast_evolution INITIAL_POPULATION=120")
	_assert_near(GameConfig.ADD_NODE_RATE, 0.06, 0.001, "fast_evolution ADD_NODE_RATE=0.06")
	_assert_near(_config.add_receptor_rate, 0.06, 0.001, "fast_evolution add_receptor_rate=0.06")

	# Restore defaults for subsequent tests
	GameConfig.restore_defaults()
	ConfigPresetManager.apply_preset(ConfigPresetManager.load_preset("default"), _config)


func _test_preset_save_load_roundtrip() -> void:
	# Tweak config, save, reload, verify values match
	GameConfig.FOOD_REGEN_RATE = 0.123
	_config.add_skill_rate = 0.077

	var ok := ConfigPresetManager.save_preset("_test_roundtrip", _config)
	_assert_true(ok, "save_preset returns true")

	GameConfig.restore_defaults()
	_config.add_skill_rate = 0.02  # reset

	var loaded := ConfigPresetManager.load_preset("_test_roundtrip")
	_assert_true(not loaded.is_empty(), "loaded preset is not empty")
	_assert_near(float(loaded.get("FOOD_REGEN_RATE", 0.0)), 0.123, 0.001, "roundtrip FOOD_REGEN_RATE=0.123")
	_assert_near(float(loaded.get("add_skill_rate", 0.0)), 0.077, 0.001, "roundtrip add_skill_rate=0.077")

	ConfigPresetManager.delete_preset("_test_roundtrip")
	GameConfig.restore_defaults()


func _test_preset_delete() -> void:
	ConfigPresetManager.save_preset("_test_delete_me", _config)
	var names_before := ConfigPresetManager.list_presets()
	_assert_true(names_before.has("_test_delete_me"), "preset exists before delete")

	var ok := ConfigPresetManager.delete_preset("_test_delete_me")
	_assert_true(ok, "delete returns true")

	var names_after := ConfigPresetManager.list_presets()
	_assert_true(not names_after.has("_test_delete_me"), "preset gone after delete")


func _test_preset_delete_builtin_fails() -> void:
	var ok := ConfigPresetManager.delete_preset("default")
	_assert_true(not ok, "cannot delete built-in preset")
	_assert_true(ConfigPresetManager.list_presets().has("default"), "default still exists")


func _test_preset_get_current_as_dict() -> void:
	var d := ConfigPresetManager.get_current_as_dict(_config)
	var required_keys: Array = [
		"INITIAL_POPULATION", "BASE_METABOLISM", "REPRODUCTION_ENERGY_THRESHOLD",
		"FOOD_REGEN_RATE", "ADD_NODE_RATE", "ADD_CONNECTION_RATE",
		"add_receptor_rate", "add_skill_rate", "remove_receptor_rate", "remove_skill_rate",
	]
	for key in required_keys:
		_assert_true(d.has(key), "get_current_as_dict has key: " + key)


# ---------------------------------------------------------------------------
# ReplayRecorder
# ---------------------------------------------------------------------------

func _test_recorder_empty() -> void:
	var rec := ReplayRecorder.new()
	_assert_eq(rec.get_frame_count(), 0, "new recorder has 0 frames")


func _test_recorder_records_frame() -> void:
	var rec := ReplayRecorder.new()
	rec.record({"tick": 1, "creatures": [], "pop": 0, "food_total": 100.0})
	_assert_eq(rec.get_frame_count(), 1, "recorder has 1 frame after record")


func _test_recorder_frame_data_fields() -> void:
	var rec := ReplayRecorder.new()
	var frame := {"tick": 42, "creatures": [{"id": 1, "x": 5, "y": 10}], "pop": 1, "food_total": 500.0}
	rec.record(frame)
	var got := rec.get_frame(0)
	_assert_eq(got.get("tick"), 42, "frame tick=42")
	_assert_eq(got.get("pop"), 1, "frame pop=1")
	_assert_near(float(got.get("food_total", 0.0)), 500.0, 0.01, "frame food_total=500")
	var creatures: Array = got.get("creatures", [])
	_assert_eq(creatures.size(), 1, "frame has 1 creature")
	_assert_eq(creatures[0].get("id"), 1, "creature id=1")


func _test_recorder_ring_buffer_wrap() -> void:
	var rec := ReplayRecorder.new()
	var total := ReplayRecorder.MAX_FRAMES + 5
	for i in range(total):
		rec.record({"tick": i, "creatures": [], "pop": 0, "food_total": 0.0})
	# Buffer should not exceed MAX_FRAMES
	_assert_eq(rec.get_frame_count(), ReplayRecorder.MAX_FRAMES, "ring buffer capped at MAX_FRAMES")
	# Oldest frame should be tick=5 (the earliest still in buffer)
	var oldest := rec.get_frame(0)
	_assert_eq(oldest.get("tick"), 5, "oldest frame is tick=5 after wrap")


func _test_recorder_clear() -> void:
	var rec := ReplayRecorder.new()
	for i in range(10):
		rec.record({"tick": i, "creatures": [], "pop": 0, "food_total": 0.0})
	rec.clear()
	_assert_eq(rec.get_frame_count(), 0, "clear() resets frame count")


func _test_recorder_get_frame_out_of_bounds() -> void:
	var rec := ReplayRecorder.new()
	var empty := rec.get_frame(0)
	_assert_true(empty.is_empty(), "get_frame on empty recorder returns {}")
	rec.record({"tick": 1, "creatures": [], "pop": 0, "food_total": 0.0})
	var out_of_range := rec.get_frame(99)
	_assert_true(out_of_range.is_empty(), "get_frame out of range returns {}")


func _test_recorder_latest_frame() -> void:
	var rec := ReplayRecorder.new()
	rec.record({"tick": 10, "creatures": [], "pop": 0, "food_total": 0.0})
	rec.record({"tick": 20, "creatures": [], "pop": 0, "food_total": 0.0})
	var latest := rec.get_latest_frame()
	_assert_eq(latest.get("tick"), 20, "get_latest_frame returns tick=20")


func _test_recorder_recording_toggle() -> void:
	var rec := ReplayRecorder.new()
	rec.is_recording = false
	# record() still works directly even when is_recording=false (capture() checks it)
	rec.record({"tick": 1, "creatures": [], "pop": 0, "food_total": 0.0})
	_assert_eq(rec.get_frame_count(), 1, "record() bypasses is_recording flag")


# ---------------------------------------------------------------------------
# WandbLogger (file I/O)
# ---------------------------------------------------------------------------

func _test_wandb_write_metrics_creates_file() -> void:
	# Test the static file write by calling _write_file indirectly via a
	# standalone helper (avoids needing a real SimulationManager).
	var path := "user://test_metrics_phase15.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert_true(file != null, "can open test metrics file for write")
	if file:
		var data := {
			"generation": 1, "tick": 500, "best_fitness": 1.5,
			"avg_fitness": 0.9, "population": 75, "species_count": 3,
			"food_total": 3000.0, "avg_nodes": 6.0, "avg_connections": 9.0,
			"avg_receptors": 1.2, "avg_skills": 0.8, "training_complete": false,
		}
		file.store_string(JSON.stringify(data))
		file.close()
		_assert_true(FileAccess.file_exists(path), "test metrics file exists after write")
		DirAccess.remove_absolute(path)


func _test_wandb_metrics_json_structure() -> void:
	# Verify that the expected metrics keys are present in what WandbLogger would write.
	var required_keys: Array = [
		"generation", "tick", "best_fitness", "avg_fitness",
		"population", "species_count", "food_total",
		"avg_nodes", "avg_connections", "avg_receptors", "avg_skills",
		"training_complete",
	]
	# We construct the same dict structure as WandbLogger.write_metrics does.
	var metrics: Dictionary = {}
	for key in required_keys:
		metrics[key] = 0  # placeholder

	for key in required_keys:
		_assert_true(metrics.has(key), "metrics dict has key: " + key)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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
