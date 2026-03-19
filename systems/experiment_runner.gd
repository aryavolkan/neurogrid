class_name ExperimentRunner
extends RefCounted
## Batch headless simulation runner with parameter sweeps and CSV export.

const SAVE_DIR: String = "user://experiments/"

class ExperimentConfig:
	var name: String = "experiment"
	var ticks: int = 5000
	var runs: int = 1
	var param_overrides: Dictionary = {}  # "param_name" -> value


class SweepConfig:
	var name: String = "sweep"
	var ticks: int = 5000
	var runs_per_combo: int = 3
	var param_grid: Dictionary = {}  # "param_name" -> [val1, val2, ...]


class RunResult:
	var run_id: int
	var final_population: int
	var final_species: int
	var total_births: int
	var total_deaths: int
	var best_fitness: float
	var avg_fitness: float
	var longest_lived: int
	var total_food_consumed: float
	var params: Dictionary


static func export_generation_csv(sim: SimulationManager, filename: String = "generations") -> bool:
	## Export per-generation statistics to CSV from a running simulation's logger.
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + filename + ".csv"

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to write CSV: " + path)
		return false

	file.store_line("tick,generation,population,species_count,best_fitness,avg_fitness,deaths,births,food_consumed")

	# We can only export current state — store generation stats as they come
	# For now, export a summary of current state
	var stats_line := "%d,%d,%d,%d,%.4f,%.4f,%d,%d,%.1f" % [
		sim.get_tick_count(),
		sim.get_generation(),
		sim.get_creature_count(),
		sim.get_species_counts().size(),
		sim.logger.gen_bites,  # Placeholder for best fitness
		0.0,
		sim.logger.total_deaths,
		sim.logger.total_births,
		sim.logger.gen_food_total,
	]
	file.store_line(stats_line)
	file.close()
	print("CSV exported to: ", path)
	return true


static func export_population_snapshot(sim: SimulationManager, filename: String = "population") -> bool:
	## Export current population as CSV with per-creature stats.
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + filename + ".csv"

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false

	file.store_line("creature_id,species_id,pos_x,pos_y,energy,health,age,nodes,connections,receptors,skills,fitness")

	for cid in sim.creatures:
		var c: Creature = sim.creatures[cid]
		var g := c.genome
		file.store_line("%d,%d,%d,%d,%.2f,%.2f,%d,%d,%d,%d,%d,%.4f" % [
			c.creature_id, c.body.species_id,
			c.grid_pos.x, c.grid_pos.y,
			c.body.energy, c.body.health, c.body.age,
			g.node_genes.size(), g.connection_genes.size(),
			g.get_receptor_count(), g.get_skill_count(),
			g.fitness,
		])

	file.close()
	print("Population CSV exported to: ", path)
	return true


static func export_species_snapshot(sim: SimulationManager, filename: String = "species") -> bool:
	## Export species data as CSV.
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + filename + ".csv"

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false

	file.store_line("species_id,member_count,best_fitness_ever,stagnation,age")

	var all_species := sim.species_manager.get_all_species()
	for sid in all_species:
		var info = all_species[sid]
		var counts := sim.species_manager.get_species_counts()
		var count: int = counts.get(sid, 0)
		file.store_line("%d,%d,%.4f,%d,%d" % [
			sid, count, info.best_fitness_ever,
			info.generations_without_improvement, info.age,
		])

	file.close()
	print("Species CSV exported to: ", path)
	return true


static func generate_combinations(param_grid: Dictionary) -> Array:
	## Cartesian product of all parameter value arrays.
	## Returns Array[Dictionary] where each dict maps param_name -> specific value.
	var keys: Array = param_grid.keys()
	if keys.is_empty():
		return [{}]

	var combos: Array = [{}]
	for key in keys:
		var values: Array = param_grid[key]
		var new_combos: Array = []
		for combo in combos:
			for val in values:
				var extended: Dictionary = combo.duplicate()
				extended[key] = val
				new_combos.append(extended)
		combos = new_combos
	return combos


static func collect_run_result(sim: SimulationManager, combo: Dictionary, run_id: int) -> RunResult:
	## Populate RunResult from current simulation state.
	var result := RunResult.new()
	result.run_id = run_id
	result.final_population = sim.get_creature_count()
	result.final_species = sim.get_species_counts().size()
	result.total_births = sim.logger.total_births
	result.total_deaths = sim.logger.total_deaths
	result.best_fitness = sim._gen_best_fitness
	result.longest_lived = sim.logger.longest_lived_age
	result.total_food_consumed = sim.logger.gen_food_total
	result.params = combo.duplicate()

	# Compute avg fitness from living creatures
	var fitness_sum: float = 0.0
	var count: int = 0
	for cid in sim.creatures:
		fitness_sum += sim.creatures[cid].genome.fitness
		count += 1
	result.avg_fitness = fitness_sum / count if count > 0 else 0.0

	return result


static func export_sweep_csv(results: Array, param_names: Array, filename: String) -> bool:
	## Export sweep results with dynamic columns for swept parameters.
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + filename + "_results.csv"

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to write sweep CSV: " + path)
		return false

	# Build header
	var header: String = "run_id"
	for pname in param_names:
		header += "," + pname
	header += ",final_population,final_species,total_births,total_deaths,best_fitness,avg_fitness,longest_lived,total_food_consumed"
	file.store_line(header)

	# Write rows
	for result in results:
		var r: RunResult = result
		var line: String = str(r.run_id)
		for pname in param_names:
			line += "," + str(r.params.get(pname, ""))
		line += ",%d,%d,%d,%d,%.4f,%.4f,%d,%.1f" % [
			r.final_population, r.final_species,
			r.total_births, r.total_deaths,
			r.best_fitness, r.avg_fitness,
			r.longest_lived, r.total_food_consumed,
		]
		file.store_line(line)

	file.close()
	print("Sweep results exported to: ", path)
	return true
