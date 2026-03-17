extends Node2D
## Main scene root. Sets up SimulationManager, Camera, and UI.

var sim: SimulationManager
var camera: CameraController
var hud: HUD
var inspector: CreatureInspector
var stats_panel: StatsPanel

var _headless: bool = false
var _headless_max_ticks: int = 5000

# Headless tracking
var _energy_snapshots: Array = []  # Array of {tick, min, max, avg}
var _pop_at_tick: Array = []       # Array of {tick, pop}


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"

	# Background color
	if not _headless:
		RenderingServer.set_default_clear_color(Color(0.08, 0.08, 0.1))

	# Simulation
	sim = SimulationManager.new()
	add_child(sim)

	if _headless:
		GameConfig.speed_multiplier = 16.0
		sim.tick_complete.connect(_on_headless_tick)
		sim.generation_complete.connect(_on_headless_generation)
		print("\n=== NeuroGrid Headless Simulation ===")
		print("Config: %dx%d grid | Pop %d-%d | Metabolism %.1f/tick | Start energy %.0f" % [
			GameConfig.GRID_WIDTH, GameConfig.GRID_HEIGHT,
			GameConfig.MIN_CREATURES, GameConfig.MAX_CREATURES,
			GameConfig.BASE_METABOLISM, GameConfig.STARTING_ENERGY,
		])
		print("NEAT: compat_threshold %.1f | crossover %.0f%% | add_node %.0f%% | add_conn %.0f%%" % [
			GameConfig.COMPATIBILITY_THRESHOLD, GameConfig.CROSSOVER_RATE * 100,
			GameConfig.ADD_NODE_RATE * 100, GameConfig.ADD_CONNECTION_RATE * 100,
		])
		print("Running %d ticks...\n" % _headless_max_ticks)
		_print_world_terrain_stats()
		print("")
		print("Initial population: %d" % sim.get_creature_count())
		print("Initial food: %.0f" % sim.food_manager.get_total_food())
		# sim.reproduction_system._debug_log = true  # Enable for repro debugging
		print("")
		return

	# Camera
	camera = CameraController.new()
	camera.make_current()
	add_child(camera)

	# HUD
	hud = HUD.new()
	hud.setup(sim)
	add_child(hud)

	# Creature inspector
	inspector = CreatureInspector.new()
	inspector.setup(sim)
	add_child(inspector)

	# Stats panel (Tab to toggle)
	stats_panel = StatsPanel.new()
	stats_panel.setup(sim)
	add_child(stats_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F5:
				SaveSystem.save_simulation(sim)
			KEY_F9:
				SaveSystem.load_simulation(sim)
			KEY_F6:
				SaveSystem.export_best_genomes(sim)


# --- Headless logging ---

func _print_world_terrain_stats() -> void:
	var counts: Dictionary = {}
	var passable: int = 0
	for pos in sim.world.tiles:
		var tile: GridTile = sim.world.tiles[pos]
		counts[tile.terrain] = counts.get(tile.terrain, 0) + 1
		if tile.is_passable():
			passable += 1
	var total: int = sim.world.tiles.size()
	print("Terrain: grass=%d forest=%d water=%d rock=%d sand=%d | Passable: %d/%d (%.0f%%)" % [
		counts.get(GameConfig.Terrain.GRASS, 0),
		counts.get(GameConfig.Terrain.FOREST, 0),
		counts.get(GameConfig.Terrain.WATER, 0),
		counts.get(GameConfig.Terrain.ROCK, 0),
		counts.get(GameConfig.Terrain.SAND, 0),
		passable, total, float(passable) / float(total) * 100.0,
	])


func _on_headless_tick(tick: int) -> void:
	# Energy distribution snapshot every 50 ticks
	if tick % 50 == 0:
		var min_e: float = 999.0
		var max_e: float = 0.0
		var sum_e: float = 0.0
		var count: int = 0
		for cid in sim.creatures:
			var e: float = sim.creatures[cid].body.energy
			min_e = minf(min_e, e)
			max_e = maxf(max_e, e)
			sum_e += e
			count += 1
		if count > 0:
			_energy_snapshots.append({
				"tick": tick,
				"min": min_e,
				"max": max_e,
				"avg": sum_e / count,
			})

	# Status line every 100 ticks
	if tick % 100 == 0:
		var species := sim.get_species_counts()
		var food: float = sim.food_manager.get_total_food()
		var famine: String = " FAMINE" if sim.food_manager.is_famine() else ""
		var pop: int = sim.get_creature_count()
		_pop_at_tick.append({"tick": tick, "pop": pop})

		# Count creatures with receptors/skills
		var with_receptors: int = 0
		var with_skills: int = 0
		var total_receptors: int = 0
		var total_skills: int = 0
		for cid in sim.creatures:
			var g: DynamicGenome = sim.creatures[cid].genome
			var rc: int = g.get_receptor_count()
			var sc: int = g.get_skill_count()
			if rc > 0:
				with_receptors += 1
			if sc > 0:
				with_skills += 1
			total_receptors += rc
			total_skills += sc

		var avg_energy: float = 0.0
		if not _energy_snapshots.is_empty():
			avg_energy = _energy_snapshots[-1].avg

		print("T%5d | Pop:%3d | Sp:%2d | Food:%5.0f%s | E(avg):%.1f | R:%d(%d) S:%d(%d)" % [
			tick, pop, species.size(), food, famine,
			avg_energy, with_receptors, total_receptors, with_skills, total_skills,
		])

	if tick >= _headless_max_ticks:
		_print_full_summary()
		get_tree().quit()


func _on_headless_generation(generation: int, stats: Dictionary) -> void:
	print("\n--- Generation %d (tick %d) ---" % [generation, stats.get("tick", 0)])
	print("  Fitness: best=%.3f avg=%.3f | Pop: %d | Species: %d" % [
		stats.get("best_fitness", 0.0), stats.get("avg_fitness", 0.0),
		stats.get("population", 0), stats.get("species_count", 0),
	])
	var log_report: String = stats.get("log_report", "")
	if not log_report.is_empty():
		print(log_report)
	print("")


func _print_full_summary() -> void:
	print("\n" + "=".repeat(60))
	print("SIMULATION SUMMARY — %d ticks, %d generations" % [sim.get_tick_count(), sim.get_generation()])
	print("=".repeat(60))

	print("\nPopulation: %d | Species: %d" % [sim.get_creature_count(), sim.get_species_counts().size()])
	print("Food remaining: %.0f" % sim.food_manager.get_total_food())

	# Lifetime stats from logger
	print("\n--- Lifetime Stats ---")
	print(sim.logger.get_lifetime_report())

	# Energy distribution over time
	print("\n--- Energy Distribution Over Time ---")
	for snap in _energy_snapshots:
		if snap.tick % 500 == 0:
			print("  T%5d: min=%.1f avg=%.1f max=%.1f" % [snap.tick, snap.min, snap.avg, snap.max])

	# Population trajectory
	print("\n--- Population Trajectory ---")
	var pop_line: String = ""
	for pt in _pop_at_tick:
		if pt.tick % 500 == 0:
			pop_line += "T%d:%d  " % [pt.tick, pt.pop]
	print("  " + pop_line)

	# All living creatures census
	print("\n--- Living Creatures Census (sample up to 10) ---")
	var count: int = 0
	var age_sum: int = 0
	var energy_sum: float = 0.0
	var receptor_counts: Dictionary = {}  # receptor_name -> count
	var skill_counts: Dictionary = {}     # skill_name -> count
	var genome_sizes: Array = []

	for cid in sim.creatures:
		var c: Creature = sim.creatures[cid]
		age_sum += c.body.age
		energy_sum += c.body.energy
		genome_sizes.append(c.genome.node_genes.size())

		for node in c.genome.get_receptor_nodes():
			var entry = Registries.receptor_registry.get_entry(node.registry_id)
			if entry:
				receptor_counts[entry.name] = receptor_counts.get(entry.name, 0) + 1

		for node in c.genome.get_skill_nodes():
			var entry = Registries.skill_registry.get_entry(node.registry_id)
			if entry:
				skill_counts[entry.name] = skill_counts.get(entry.name, 0) + 1

		if count < 10:
			var rnames: Array = []
			for node in c.genome.get_receptor_nodes():
				var entry = Registries.receptor_registry.get_entry(node.registry_id)
				if entry:
					rnames.append(entry.name)
			var snames: Array = []
			for node in c.genome.get_skill_nodes():
				var entry = Registries.skill_registry.get_entry(node.registry_id)
				if entry:
					snames.append(entry.name)
			print("  #%d: pos=(%d,%d) E=%.1f H=%.1f age=%d sp=%d nodes=%d conns=%d R=%s S=%s" % [
				cid, c.grid_pos.x, c.grid_pos.y, c.body.energy, c.body.health,
				c.body.age, c.body.species_id,
				c.genome.node_genes.size(), c.genome.connection_genes.size(),
				str(rnames), str(snames),
			])
		count += 1

	var pop: int = sim.get_creature_count()
	if pop > 0:
		print("\n--- Population Averages ---")
		print("  Avg age: %.0f | Avg energy: %.1f" % [float(age_sum) / pop, energy_sum / pop])
		var avg_genome: float = 0.0
		for gs in genome_sizes:
			avg_genome += gs
		print("  Avg genome nodes: %.1f" % (avg_genome / pop))

	if not receptor_counts.is_empty():
		print("\n--- Receptor Distribution Across Population ---")
		for rname in receptor_counts:
			print("  %s: %d creatures" % [rname, receptor_counts[rname]])

	if not skill_counts.is_empty():
		print("\n--- Skill Distribution Across Population ---")
		for sname in skill_counts:
			print("  %s: %d creatures" % [sname, skill_counts[sname]])

	# Species breakdown
	print("\n--- Species Breakdown ---")
	var species_counts := sim.get_species_counts()
	var sorted_species: Array = species_counts.keys()
	sorted_species.sort()
	for sid in sorted_species:
		var info = sim.species_manager.get_species_info(sid)
		if info:
			print("  Species %d: %d members | best_ever=%.3f | stagnation=%d" % [
				sid, species_counts[sid], info.best_fitness_ever, info.generations_without_improvement,
			])

	print("\n" + "=".repeat(60))
	print("END OF REPORT")
	print("=".repeat(60))
