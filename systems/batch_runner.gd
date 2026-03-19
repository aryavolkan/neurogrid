class_name BatchRunner
extends Node
## Runs batch parameter sweep experiments. Creates temporary SimulationManager
## instances, runs them for a configured number of ticks, and exports results.

signal run_complete(run_id: int, combo_idx: int)
signal batch_complete(results: Array)

var _sweep: ExperimentRunner.SweepConfig
var _combos: Array = []
var _combo_idx: int = 0
var _run_idx: int = 0
var _sim: SimulationManager = null
var _results: Array = []
var _running: bool = false
var _ticks_done: int = 0
var _gen_history: Array = []  # Per-generation snapshots for current run

const TICKS_PER_FRAME: int = 50  # Batch multiple ticks per frame


func start_sweep(config: ExperimentRunner.SweepConfig) -> void:
	_sweep = config
	_combos = ExperimentRunner.generate_combinations(config.param_grid)
	_combo_idx = 0
	_run_idx = 0
	_results = []
	print("Starting sweep '%s': %d combos x %d runs = %d total runs, %d ticks each" % [
		config.name, _combos.size(), config.runs_per_combo,
		_combos.size() * config.runs_per_combo, config.ticks,
	])
	_start_next_run()


func _process(_delta: float) -> void:
	if not _running or not _sim:
		return

	for _i in TICKS_PER_FRAME:
		if _ticks_done >= _sweep.ticks:
			break
		_sim._simulate_tick(1.0 / GameConfig.TICKS_PER_SECOND)
		_ticks_done += 1

		# Record generation boundaries
		if _ticks_done % SimulationManager.GENERATION_INTERVAL == 0:
			_gen_history.append({
				"tick": _ticks_done,
				"population": _sim.get_creature_count(),
				"species": _sim.get_species_counts().size(),
				"best_fitness": _sim._gen_best_fitness,
			})

	if _ticks_done >= _sweep.ticks:
		_finish_current_run()


func _start_next_run() -> void:
	if _combo_idx >= _combos.size():
		_finish_sweep()
		return

	var combo: Dictionary = _combos[_combo_idx]

	# Apply parameter overrides
	GameConfig.apply_overrides(combo)

	# Create fresh simulation
	_destroy_sim()
	_sim = SimulationManager.new()
	add_child(_sim)
	# Let _ready run, then disable visual processing
	_sim.set_process(false)  # We drive ticks manually

	_ticks_done = 0
	_gen_history = []
	_running = true

	var run_total: int = _combo_idx * _sweep.runs_per_combo + _run_idx + 1
	var total_runs: int = _combos.size() * _sweep.runs_per_combo
	print("  Run %d/%d (combo %d/%d, rep %d/%d): %s" % [
		run_total, total_runs,
		_combo_idx + 1, _combos.size(),
		_run_idx + 1, _sweep.runs_per_combo,
		str(combo),
	])


func _finish_current_run() -> void:
	_running = false

	# Collect result
	var result := ExperimentRunner.collect_run_result(
		_sim, _combos[_combo_idx],
		_combo_idx * _sweep.runs_per_combo + _run_idx
	)
	_results.append(result)

	var run_id: int = _combo_idx * _sweep.runs_per_combo + _run_idx
	run_complete.emit(run_id, _combo_idx)

	# Next run or next combo
	_run_idx += 1
	if _run_idx >= _sweep.runs_per_combo:
		_run_idx = 0
		_combo_idx += 1

	# Restore defaults before next run
	GameConfig.restore_defaults()

	_start_next_run()


func _finish_sweep() -> void:
	_destroy_sim()
	GameConfig.restore_defaults()

	# Export results
	var param_names: Array = _sweep.param_grid.keys()
	ExperimentRunner.export_sweep_csv(_results, param_names, _sweep.name)
	print("Sweep '%s' complete: %d results exported" % [_sweep.name, _results.size()])

	batch_complete.emit(_results)


func _destroy_sim() -> void:
	if _sim:
		_sim.queue_free()
		_sim = null
