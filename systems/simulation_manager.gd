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
var advanced_evolution: AdvancedEvolution
var weather_system: WeatherSystem
var phylogeny: PhylogenyTracker
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

# Cached headless check (avoids calling DisplayServer every tick)
var _is_headless: bool = false


func _ready() -> void:
	_is_headless = DisplayServer.get_name() == "headless"
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
	weather_system = WeatherSystem.new(world)


func _init_systems() -> void:
	logger = SimLogger.new()
	fitness_tracker = FitnessTracker.new()
	species_manager = SpeciesManager.new(_dynamic_config)
	ecology_system = EcologySystem.new(world)
	advanced_evolution = AdvancedEvolution.new()
	phylogeny = PhylogenyTracker.new()

	action_system = ActionSystem.new(world, pheromone_layer)
	action_system.creatures = creatures
	action_system.fitness_tracker = fitness_tracker
	action_system.logger = logger
	action_system.ecology_system = ecology_system
	action_system.advanced_evolution = advanced_evolution

	reproduction_system = ReproductionSystem.new(world)
	reproduction_system.creatures = creatures

	spawner = CreatureSpawner.new(world, _dynamic_config, _conn_tracker, _io_tracker)
	spawner.weather_system = weather_system


func _spawn_initial_population() -> void:
	for _i in GameConfig.INITIAL_POPULATION:
		var creature := spawner.spawn_random_creature()
		if creature:
			_register_creature(creature)


func _register_creature(creature: Creature) -> void:
	creatures[creature.creature_id] = creature
	fitness_tracker.register(creature.creature_id)

	var old_species_count := species_manager.get_species_count()
	var species_id := species_manager.assign_species(creature.creature_id, creature.genome)
	creature.set_species_color(species_id)

	# Track phylogeny: new species born
	if species_manager.get_species_count() > old_species_count:
		phylogeny.record_species_born(species_id, creature.body.species_id, _tick_count)

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
	_update_metabolism(delta)
	var offspring_queue := _sense_think_act()
	_spawn_offspring(offspring_queue)
	_handle_deaths()
	_maintain_population()
	_update_world(delta)
	if _tick_count % GENERATION_INTERVAL == 0:
		_end_generation()
	logger.end_tick()
	if not _is_headless:
		_update_visuals(delta)
	tick_complete.emit(_tick_count)


func _update_metabolism(delta: float) -> void:
	## Step 1: age, cooldowns, metabolism for all creatures.
	var base_meta_mult := ecology_system.get_metabolism_multiplier()
	for creature_id in creatures:
		var creature: Creature = creatures[creature_id]
		var body := creature.body
		body.age += 1
		body.update_cooldowns(delta)
		var receptor_cost := creature.brain.get_receptor_energy_cost()
		var meta_mult := base_meta_mult * AdvancedEvolution.get_ontogeny_metabolism_mult(body.age)
		body.energy -= (GameConfig.BASE_METABOLISM * meta_mult) + receptor_cost


func _sense_think_act() -> Array:
	## Step 2: sense, think, act for living creatures. Returns offspring queue.
	world.rebuild_food_index_if_dirty()
	var offspring_queue: Array = []
	for creature_id in creatures:
		var creature: Creature = creatures[creature_id]
		if not creature.body.is_alive():
			continue

		creature.brain.sensor.begin_sensing()

		var energy_before: float = creature.body.energy
		var outputs := creature.brain.think(
			creature.grid_pos, creature.body, creature.creature_id)

		if not AdvancedEvolution.can_use_skills(creature.body.age):
			for si in range(GameConfig.CORE_OUTPUT_COUNT, outputs.size()):
				outputs[si] = 0.0
		action_system.execute(creature, outputs)

		var energy_after: float = creature.body.energy
		var reward: float = (energy_after - energy_before) * 0.01
		if reward != 0.0:
			AdvancedEvolution.apply_neuromodulation(
				creature.genome, creature.brain.network, reward)

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
	return offspring_queue


func _spawn_offspring(offspring_queue: Array) -> void:
	## Step 3: spawn offspring from the queue.
	for child_data in offspring_queue:
		if creatures.size() >= GameConfig.MAX_CREATURES:
			break
		var spawn_energy: float = GameConfig.OFFSPRING_ENERGY
		var spawn_tile: GridTile = world.get_tile(child_data.pos)
		if spawn_tile and spawn_tile.is_nest:
			spawn_energy *= 1.5
		var child := spawner.spawn_creature(
			child_data.genome, child_data.pos, spawn_energy)
		if child:
			_register_creature(child)
			fitness_tracker.record_offspring(child_data.parent_id)
			logger.births += 1
			var pid: int = child_data.parent_id
			logger.total_offspring_by_id[pid] = (
				logger.total_offspring_by_id.get(pid, 0) + 1)
			var count: int = logger.total_offspring_by_id[pid]
			if count > logger.most_offspring_count:
				logger.most_offspring_count = count
				logger.most_offspring_id = pid


func _handle_deaths() -> void:
	## Step 4: collect and process dead creatures.
	var dead_ids: Array = []
	for creature_id in creatures:
		if not creatures[creature_id].body.is_alive():
			dead_ids.append(creature_id)
	for creature_id in dead_ids:
		_kill_creature(creature_id)


func _maintain_population() -> void:
	## Step 5: spawn random creatures to maintain minimum population.
	while creatures.size() < GameConfig.MIN_CREATURES:
		var creature := spawner.spawn_random_creature()
		if creature:
			_register_creature(creature)
			logger.spawns_random += 1
		else:
			break


func _update_world(delta: float) -> void:
	## Steps 6-8: ecology, weather, food, pheromone updates.
	ecology_system.update(_tick_count, creatures)
	weather_system.update(_tick_count)
	if weather_system.is_storm():
		var storm_dmg: float = weather_system.get_storm_damage()
		for cid in creatures:
			var c: Creature = creatures[cid]
			if c.body.burrowed:
				continue
			var tile: GridTile = world.get_tile(c.grid_pos)
			if tile and tile.terrain == GameConfig.Terrain.FOREST:
				continue
			c.body.take_damage(storm_dmg)
	food_manager.update(delta, ecology_system, weather_system)
	pheromone_layer.update(delta)


func _update_visuals(delta: float) -> void:
	## Step 11: visual refresh (skipped in headless).
	for creature_id in creatures:
		creatures[creature_id].update_visual(delta)
	world.queue_redraw()


func _kill_creature(creature_id: int) -> void:
	if not creatures.has(creature_id):
		return
	var creature: Creature = creatures[creature_id]

	# Log death cause
	logger.record_death(creature_id, creature.body, creature.grid_pos)

	# Compute and record fitness (including group + coevolution bonuses)
	var fitness := fitness_tracker.compute_fitness(creature_id, creature.body.age)
	fitness += ecology_system.get_group_fitness_bonus(creature, creatures)
	fitness += advanced_evolution.get_coevolution_bonus(creature.body.species_id)
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
		food_manager.add_corpse(creature.grid_pos)

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

	# Update phylogeny: track species stats and extinctions
	var species_before := species_manager.get_species_counts()
	for sid in species_before:
		var info = species_manager.get_species_info(sid)
		if info:
			phylogeny.update_species_stats(sid, species_before[sid], info.best_fitness_ever)

	# Update species stagnation and compatibility threshold
	species_manager.end_generation()

	# Record extinctions
	for sid in species_before:
		if not species_manager.get_species_counts().has(sid):
			phylogeny.record_species_extinct(sid, _tick_count)

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
