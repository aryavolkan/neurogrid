class_name SimulationManager
extends Node2D
## Main simulation orchestrator. Runs the sense→think→act→update loop each tick.

signal creature_spawned(creature: Creature)
signal creature_died_signal(creature_id: int)
signal tick_complete(tick: int)
signal population_changed(count: int)
signal generation_complete(generation: int, stats: Dictionary)

var world: GridWorld
var food_manager: FoodManager
var pheromone_layer: PheromoneLayer
var action_system: ActionSystem
var reproduction_system: ReproductionSystem
var spawner: CreatureSpawner
var fitness_tracker: FitnessTracker
var species_manager: SpeciesManager
var ecology_system: EcologySystem
var logger: SimLogger

var creatures: Dictionary = {}  # creature_id -> Creature
var _tick_count: int = 0
var _tick_accumulator: float = 0.0

# Shared NEAT trackers
var _conn_tracker  # NeatInnovation
var _io_tracker: IoInnovation
var _dynamic_config: DynamicConfig

# Generation tracking
var _generation: int = 0
const GENERATION_INTERVAL: int = 500  # Ticks per generation boundary
var _gen_best_fitness: float = 0.0
var _gen_avg_fitness: float = 0.0
var _gen_fitness_sum: float = 0.0
var _gen_death_count: int = 0


func _ready() -> void:
	_init_trackers()
	_init_world()
	_init_systems()
	_spawn_initial_population()


func _init_trackers() -> void:
	_conn_tracker = NeatInnovation.new()
	_io_tracker = IoInnovation.new()
	_dynamic_config = DynamicConfig.new()


func _init_world() -> void:
	world = GridWorld.new()
	world.setup()
	WorldGenerator.generate(world)
	add_child(world)

	food_manager = FoodManager.new(world)
	pheromone_layer = PheromoneLayer.new(world)


func _init_systems() -> void:
	logger = SimLogger.new()
	fitness_tracker = FitnessTracker.new()
	species_manager = SpeciesManager.new(_dynamic_config)
	ecology_system = EcologySystem.new(world)

	action_system = ActionSystem.new(world, pheromone_layer)
	action_system.creatures = creatures
	action_system.fitness_tracker = fitness_tracker
	action_system.logger = logger
	action_system.ecology_system = ecology_system

	reproduction_system = ReproductionSystem.new(world)
	reproduction_system.creatures = creatures

	spawner = CreatureSpawner.new(world, _dynamic_config, _conn_tracker, _io_tracker)


func _spawn_initial_population() -> void:
	for _i in GameConfig.INITIAL_POPULATION:
		var creature := spawner.spawn_random_creature()
		if creature:
			_register_creature(creature)


func _register_creature(creature: Creature) -> void:
	creatures[creature.creature_id] = creature
	fitness_tracker.register(creature.creature_id)

	var species_id := species_manager.assign_species(creature.creature_id, creature.genome)
	creature.set_species_color(species_id)

	add_child(creature)
	creature_spawned.emit(creature)
	population_changed.emit(creatures.size())


func _physics_process(delta: float) -> void:
	if GameConfig.paused:
		return

	_tick_accumulator += delta * GameConfig.speed_multiplier
	var tick_interval: float = 1.0 / GameConfig.TICKS_PER_SECOND

	while _tick_accumulator >= tick_interval:
		_tick_accumulator -= tick_interval
		_simulate_tick(tick_interval)


func _simulate_tick(delta: float) -> void:
	_tick_count += 1

	# 1. Update cooldowns, age, poison
	for creature_id in creatures:
		var creature: Creature = creatures[creature_id]
		var body := creature.body
		body.age += 1
		body.update_cooldowns(delta)

		# Metabolism (modified by day/night cycle)
		var receptor_cost := creature.brain.get_receptor_energy_cost()
		var meta_mult := ecology_system.get_metabolism_multiplier()
		body.energy -= (GameConfig.BASE_METABOLISM * meta_mult) + receptor_cost

	# 2. Sense → Think → Act
	var offspring_queue: Array = []  # [{genome, parent_id, parent_pos}]
	for creature_id in creatures:
		var creature: Creature = creatures[creature_id]
		if not creature.body.is_alive():
			continue

		# Think
		var outputs := creature.brain.think(creature.grid_pos, creature.body, creature.creature_id)

		# Act
		action_system.execute(creature, outputs)

		# Reproduction check (mate_desire is output index 3)
		if outputs.size() > 3 and outputs[3] > GameConfig.MATE_DESIRE_THRESHOLD:
			logger.mate_attempts += 1
			var child_genome := reproduction_system.try_reproduce(creature)
			if child_genome:
				var spawn_pos := world.find_empty_adjacent(creature.grid_pos)
				if spawn_pos != Vector2i(-1, -1):
					offspring_queue.append({
						"genome": child_genome,
						"pos": spawn_pos,
						"parent_id": creature.creature_id,
					})
					logger.reproductions += 1
			else:
				logger.mate_no_partner += 1

	# 3. Spawn offspring
	for child_data in offspring_queue:
		if creatures.size() >= GameConfig.MAX_CREATURES:
			break
		var child := spawner.spawn_creature(child_data.genome, child_data.pos, GameConfig.OFFSPRING_ENERGY)
		if child:
			_register_creature(child)
			fitness_tracker.record_offspring(child_data.parent_id)
			logger.births += 1
			logger.total_offspring_by_id[child_data.parent_id] = logger.total_offspring_by_id.get(child_data.parent_id, 0) + 1
			var count: int = logger.total_offspring_by_id[child_data.parent_id]
			if count > logger.most_offspring_count:
				logger.most_offspring_count = count
				logger.most_offspring_id = child_data.parent_id

	# 4. Check deaths
	var dead_ids: Array = []
	for creature_id in creatures:
		var creature: Creature = creatures[creature_id]
		if not creature.body.is_alive():
			dead_ids.append(creature_id)

	for creature_id in dead_ids:
		_kill_creature(creature_id)

	# 5. Maintain minimum population
	while creatures.size() < GameConfig.MIN_CREATURES:
		var creature := spawner.spawn_random_creature()
		if creature:
			_register_creature(creature)
			logger.spawns_random += 1
		else:
			break

	# 6. Ecology updates (territory, migration, day/night)
	ecology_system.update(_tick_count, creatures)

	# 7. World updates (food manager uses hotspot from ecology)
	food_manager.update(delta, ecology_system)
	pheromone_layer.update(delta)

	# 8. Generation boundary check
	if _tick_count % GENERATION_INTERVAL == 0:
		_end_generation()

	# 9. End-of-tick logging
	logger.end_tick()

	# 10. Visual refresh (skip in headless)
	if DisplayServer.get_name() != "headless":
		for creature_id in creatures:
			creatures[creature_id].update_visual(delta)
		world.queue_redraw()

	tick_complete.emit(_tick_count)


func _kill_creature(creature_id: int) -> void:
	if not creatures.has(creature_id):
		return
	var creature: Creature = creatures[creature_id]

	# Log death cause
	logger.record_death(creature_id, creature.body, creature.grid_pos)

	# Compute and record fitness (including group bonus)
	var fitness := fitness_tracker.compute_fitness(creature_id, creature.body.age)
	fitness += ecology_system.get_group_fitness_bonus(creature, creatures)
	creature.genome.fitness = fitness
	species_manager.update_fitness(creature_id, fitness)

	# Track generation stats
	_gen_fitness_sum += fitness
	_gen_death_count += 1
	if fitness > _gen_best_fitness:
		_gen_best_fitness = fitness

	# Deposit corpse energy
	var tile: GridTile = world.get_tile(creature.grid_pos)
	if tile:
		Corpse.create_from_creature(creature.body, tile)

	# Clean up spatial index
	world.clear_creature_position(creature.grid_pos)
	if tile:
		tile.occupant_id = -1

	# Clean up tracking
	species_manager.remove_creature(creature_id)
	fitness_tracker.unregister(creature_id)
	ecology_system.remove_creature(creature_id)

	# Remove from scene
	creature.died.emit(creature_id)
	creature.queue_free()
	creatures.erase(creature_id)
	creature_died_signal.emit(creature_id)
	population_changed.emit(creatures.size())


func _end_generation() -> void:
	_generation += 1

	_gen_avg_fitness = _gen_fitness_sum / _gen_death_count if _gen_death_count > 0 else 0.0

	var stats := {
		"generation": _generation,
		"tick": _tick_count,
		"population": creatures.size(),
		"species_count": species_manager.get_species_count(),
		"best_fitness": _gen_best_fitness,
		"avg_fitness": _gen_avg_fitness,
		"deaths": _gen_death_count,
		"log_report": logger.get_gen_report(),
	}

	# Update species stagnation and compatibility threshold
	species_manager.end_generation()

	# Reset innovation cache for new generation
	_conn_tracker.reset_generation_cache()

	# Reset generation accumulators
	_gen_best_fitness = 0.0
	_gen_fitness_sum = 0.0
	_gen_death_count = 0
	logger.reset_generation()

	generation_complete.emit(_generation, stats)


func get_tick_count() -> int:
	return _tick_count


func get_generation() -> int:
	return _generation


func get_creature_count() -> int:
	return creatures.size()


func get_species_counts() -> Dictionary:
	return species_manager.get_species_counts()
