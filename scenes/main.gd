extends Node2D
## Main scene root. Sets up SimulationManager, Camera, and UI.

var sim: SimulationManager
var camera: CameraController
var hud: HUD
var inspector: CreatureInspector
var stats_panel: StatsPanel

var _headless: bool = false
var _headless_max_ticks: int = 2000


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"

	# Background color
	if not _headless:
		RenderingServer.set_default_clear_color(Color(0.08, 0.08, 0.1))

	# Simulation
	sim = SimulationManager.new()
	add_child(sim)

	if _headless:
		# Fast-forward in headless mode
		GameConfig.speed_multiplier = 16.0
		sim.tick_complete.connect(_on_headless_tick)
		sim.generation_complete.connect(_on_headless_generation)
		print("\n=== NeuroGrid Headless Simulation ===")
		print("Running %d ticks at 16x speed...\n" % _headless_max_ticks)
		print("Initial population: %d" % sim.get_creature_count())
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


func _on_headless_tick(tick: int) -> void:
	if tick % 100 == 0:
		var species := sim.get_species_counts()
		var food: float = sim.food_manager.get_total_food()
		var famine: String = " [FAMINE]" if sim.food_manager.is_famine() else ""
		print("Tick %4d | Pop: %3d | Species: %2d | Food: %5.0f%s" % [
			tick, sim.get_creature_count(), species.size(), food, famine
		])

	if tick >= _headless_max_ticks:
		_print_summary()
		get_tree().quit()


func _on_headless_generation(generation: int, stats: Dictionary) -> void:
	print("\n--- Generation %d ---" % generation)
	print("  Best fitness: %.3f | Avg fitness: %.3f | Deaths: %d" % [
		stats.get("best_fitness", 0.0), stats.get("avg_fitness", 0.0), stats.get("deaths", 0)
	])


func _print_summary() -> void:
	print("\n=== Simulation Summary ===")
	print("Ticks: %d | Gen: %d" % [sim.get_tick_count(), sim.get_generation()])
	print("Population: %d | Species: %d" % [sim.get_creature_count(), sim.get_species_counts().size()])
	print("Food: %.0f" % sim.food_manager.get_total_food())

	# Sample creature
	for cid in sim.creatures:
		var c: Creature = sim.creatures[cid]
		print("\nSample creature #%d:" % cid)
		print("  Pos: (%d, %d) | Energy: %.1f | Health: %.1f | Age: %d" % [
			c.grid_pos.x, c.grid_pos.y, c.body.energy, c.body.health, c.body.age
		])
		print("  Species: %d | Genome: %d nodes, %d conns" % [
			c.body.species_id, c.genome.node_genes.size(), c.genome.connection_genes.size()
		])
		print("  Receptors: %d | Skills: %d" % [c.genome.get_receptor_count(), c.genome.get_skill_count()])

		var receptor_names: Array = []
		for node in c.genome.get_receptor_nodes():
			var entry = Registries.receptor_registry.get_entry(node.registry_id)
			if entry:
				receptor_names.append(entry.name)
		if not receptor_names.is_empty():
			print("  Receptors: %s" % str(receptor_names))

		var skill_names: Array = []
		for node in c.genome.get_skill_nodes():
			var entry = Registries.skill_registry.get_entry(node.registry_id)
			if entry:
				skill_names.append(entry.name)
		if not skill_names.is_empty():
			print("  Skills: %s" % str(skill_names))
		break
	print("\n=== Done ===")
