class_name WandbLogger
extends RefCounted
## Writes per-generation metrics to user://metrics.json so the Python
## training script (scripts/neurogrid_train.py) can poll and log to W&B.
##
## Usage in headless mode:
##   var wb := WandbLogger.new()
##   wb.setup(sim)
##   # Logs automatically on each generation_complete signal.
##   # Call wb.mark_complete() when simulation finishes.

const METRICS_FILE: String = "user://metrics.json"

var _sim: SimulationManager
var _enabled: bool = true
var _last_generation: int = -1


func setup(sim: SimulationManager) -> void:
	_sim = sim
	sim.generation_complete.connect(_on_generation_complete)
	# Write an initial handshake so the Python poller detects startup.
	write_metrics(0, {})


func _on_generation_complete(generation: int, stats: Dictionary) -> void:
	if not _enabled:
		return
	_last_generation = generation
	write_metrics(generation, stats)


func write_metrics(generation: int, stats: Dictionary) -> void:
	## Write current metrics snapshot to disk. Called every generation.
	if not _sim:
		return

	var avg_nodes: float = 0.0
	var avg_connections: float = 0.0
	var avg_receptors: float = 0.0
	var avg_skills: float = 0.0
	var pop: int = _sim.get_creature_count()

	if pop > 0:
		var n_sum: int = 0
		var c_sum: int = 0
		var r_sum: int = 0
		var s_sum: int = 0
		for cid in _sim.creatures:
			var g: DynamicGenome = _sim.creatures[cid].genome
			n_sum += g.node_genes.size()
			c_sum += g.connection_genes.size()
			r_sum += g.get_receptor_count()
			s_sum += g.get_skill_count()
		avg_nodes = float(n_sum) / pop
		avg_connections = float(c_sum) / pop
		avg_receptors = float(r_sum) / pop
		avg_skills = float(s_sum) / pop

	var metrics: Dictionary = {
		"generation": generation,
		"tick": _sim.get_tick_count(),
		"best_fitness": stats.get("best_fitness", 0.0),
		"avg_fitness": stats.get("avg_fitness", 0.0),
		"population": pop,
		"species_count": _sim.species_manager.get_species_count(),
		"food_total": _sim.food_manager.get_total_food(),
		"avg_nodes": avg_nodes,
		"avg_connections": avg_connections,
		"avg_receptors": avg_receptors,
		"avg_skills": avg_skills,
		"training_complete": false,
	}

	_write_file(metrics)


func mark_complete() -> void:
	## Write a final metrics snapshot with training_complete=true.
	if not _sim:
		return
	var final_metrics: Dictionary = {
		"generation": _last_generation,
		"tick": _sim.get_tick_count(),
		"best_fitness": 0.0,
		"avg_fitness": 0.0,
		"population": _sim.get_creature_count(),
		"species_count": _sim.species_manager.get_species_count(),
		"food_total": _sim.food_manager.get_total_food(),
		"avg_nodes": 0.0,
		"avg_connections": 0.0,
		"avg_receptors": 0.0,
		"avg_skills": 0.0,
		"training_complete": true,
	}
	_write_file(final_metrics)


func _write_file(metrics: Dictionary) -> void:
	var file := FileAccess.open(METRICS_FILE, FileAccess.WRITE)
	if not file:
		push_warning("WandbLogger: cannot write " + METRICS_FILE)
		return
	file.store_string(JSON.stringify(metrics))
	file.close()
