class_name ActionSystem
extends RefCounted
## Interprets neural network outputs into creature actions: movement, eating, skills, mating.

const EAT_DESIRE_THRESHOLD: float = 0.3
const SKILL_ACTIVATION_THRESHOLD: float = 0.5

var world: GridWorld
var pheromone_layer: PheromoneLayer

# creature_id -> Creature lookup (set by SimulationManager)
var creatures: Dictionary = {}
var fitness_tracker: FitnessTracker
var logger: SimLogger
var ecology_system: EcologySystem
var advanced_evolution: AdvancedEvolution


func _init(p_world: GridWorld, p_pheromone_layer: PheromoneLayer) -> void:
	world = p_world
	pheromone_layer = p_pheromone_layer


func execute(creature: Creature, outputs: PackedFloat32Array) -> void:
	## Parse outputs and execute actions for one creature.
	## Output layout: [move_x, move_y, eat_desire, mate_desire, skill_0, skill_1, ...]
	if outputs.size() < GameConfig.CORE_OUTPUT_COUNT:
		return

	var body := creature.body
	var actions: PackedStringArray = []

	# Movement
	_handle_movement(creature, outputs[0], outputs[1])
	if absf(outputs[0]) > 0.2 or absf(outputs[1]) > 0.2:
		actions.append("moving")

	# Eating
	if outputs[2] > EAT_DESIRE_THRESHOLD:
		_handle_eating(creature)
		actions.append("eating")

	# Skills (after core outputs)
	var skill_nodes := creature.brain.get_skill_nodes()
	for i in skill_nodes.size():
		var output_idx: int = GameConfig.CORE_OUTPUT_COUNT + i
		if output_idx < outputs.size() and outputs[output_idx] > SKILL_ACTIVATION_THRESHOLD:
			_execute_skill(creature, skill_nodes[i].registry_id)
			var entry = Registries.skill_registry.get_entry(skill_nodes[i].registry_id)
			if entry:
				actions.append(entry.name)

	creature.last_action_summary = ", ".join(actions) if not actions.is_empty() else "idle"


func _handle_movement(creature: Creature, move_x: float, move_y: float) -> void:
	## Convert continuous move_x/move_y into a grid step.
	var dx: int = 0
	var dy: int = 0

	# Threshold-based discretization
	if absf(move_x) > absf(move_y):
		dx = 1 if move_x > 0.2 else (-1 if move_x < -0.2 else 0)
	else:
		dy = 1 if move_y > 0.2 else (-1 if move_y < -0.2 else 0)

	if dx == 0 and dy == 0:
		return

	var new_pos := creature.grid_pos + Vector2i(dx, dy)
	creature.body.facing = Vector2i(dx, dy)

	# Clamp to grid boundaries
	new_pos.x = clampi(new_pos.x, 0, world.width - 1)
	new_pos.y = clampi(new_pos.y, 0, world.height - 1)

	if new_pos != creature.grid_pos and world.is_passable(new_pos):
		# Terrain + elevation movement cost modifier
		var tile: GridTile = world.get_tile(new_pos)
		var cost_mult := 1.0
		if tile:
			if tile.terrain == GameConfig.Terrain.SAND:
				cost_mult = 1.5
			cost_mult *= tile.get_elevation_movement_cost()
		world.move_creature(creature.creature_id, creature.grid_pos, new_pos)
		creature.grid_pos = new_pos
		creature.body.energy -= GameConfig.MOVEMENT_COST * cost_mult
		if logger:
			logger.moves += 1
	elif new_pos != creature.grid_pos:
		if logger:
			logger.moves_blocked += 1


func _handle_eating(creature: Creature) -> void:
	var tile: GridTile = world.get_tile(creature.grid_pos)
	if not tile:
		return

	# Eat regular food (herbivore bonus from ecology)
	if tile.food > 0.0:
		var eat_max: float = 5.0
		if ecology_system:
			eat_max += eat_max * ecology_system.get_herbivore_food_bonus(creature)
		var eat_amount := minf(tile.food, eat_max)
		var consumed := creature.body.eat_food(eat_amount)
		tile.food -= consumed
		if consumed > 0.0:
			world.mark_food_dirty()
			if fitness_tracker:
				fitness_tracker.record_food_eaten(creature.creature_id, consumed)
			if logger:
				logger.eats += 1
				logger.food_consumed += consumed

	# Eat corpse energy
	if tile.corpse_energy > 0.0:
		var eat_amount := minf(tile.corpse_energy, 3.0)
		var consumed := creature.body.eat_food(eat_amount)
		tile.corpse_energy -= consumed
		if consumed > 0.0:
			if fitness_tracker:
				fitness_tracker.record_food_eaten(creature.creature_id, consumed)
			if logger:
				logger.eats += 1
				logger.corpse_consumed += consumed


func _execute_skill(creature: Creature, skill_registry_id: int) -> void:
	var body := creature.body
	var entry = Registries.skill_registry.get_entry(skill_registry_id)
	if not entry:
		return

	# Check cooldown and energy
	if not body.is_skill_ready(skill_registry_id):
		return
	if body.energy < entry.energy_cost:
		return

	# Pay energy cost (reduced by tile resources for applicable skills)
	var skill_cost: float = entry.energy_cost
	var tile: GridTile = world.get_tile(creature.grid_pos)
	if tile:
		# Minerals reduce build_wall cost
		if skill_registry_id == 5 and tile.minerals > 0.0:
			skill_cost *= 0.5
			tile.minerals = maxf(tile.minerals - 1.0, 0.0)
		# Medicinal plants boost heal_self (reduce cost, increase effect handled below)
		if skill_registry_id == 6 and tile.medicinal > 0.0:
			skill_cost *= 0.5
			tile.medicinal = maxf(tile.medicinal - 1.0, 0.0)
	body.energy -= skill_cost
	var cd_ticks: int = int(entry.cooldown * GameConfig.TICKS_PER_SECOND)
	body.set_skill_cooldown(skill_registry_id, cd_ticks)
	if logger:
		logger.record_skill(entry.name)

	match skill_registry_id:
		0:  # dash
			_skill_dash(creature)
		1:  # bite
			_skill_bite(creature)
		2:  # poison_spit
			_skill_poison_spit(creature)
		3:  # emit_pheromone
			_skill_emit_pheromone(creature)
		4:  # share_food
			_skill_share_food(creature)
		5:  # build_wall
			_skill_build_wall(creature)
		6:  # heal_self
			_skill_heal_self(creature)
		7:  # burrow
			_skill_burrow(creature)


func _skill_dash(creature: Creature) -> void:
	## Move up to 3 tiles in facing direction.
	var dir := creature.body.facing
	for _step in 3:
		var new_pos := creature.grid_pos + dir
		if world.is_passable(new_pos):
			world.move_creature(creature.creature_id, creature.grid_pos, new_pos)
			creature.grid_pos = new_pos
		else:
			break


func _skill_bite(creature: Creature) -> void:
	## Deal 15 damage to an adjacent creature.
	var target_pos := creature.grid_pos + creature.body.facing
	var target_id := world.get_creature_at(target_pos)
	if target_id < 0:
		# Try any adjacent tile
		for offset in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			target_id = world.get_creature_at(creature.grid_pos + offset)
			if target_id >= 0:
				break
	if target_id >= 0 and creatures.has(target_id):
		var bite_damage: float = 15.0
		# Territory attack bonus
		if ecology_system:
			bite_damage += ecology_system.get_territory_attack_bonus(creature)
		# Territory defense reduction for target
		var target_creature: Creature = creatures[target_id]
		if ecology_system:
			bite_damage *= (1.0 - ecology_system.get_territory_defense_bonus(target_creature))
		target_creature.body.take_damage(bite_damage)
		# Predator kill energy bonus
		if not target_creature.body.is_alive() and ecology_system:
			var kill_bonus := ecology_system.get_kill_energy_bonus(creature, target_creature)
			if kill_bonus > 0.0:
				creature.body.eat_food(kill_bonus)
		if fitness_tracker:
			fitness_tracker.record_damage_dealt(creature.creature_id, bite_damage)
		if advanced_evolution:
			advanced_evolution.record_interaction(
				creature.body.species_id, target_creature.body.species_id,
				bite_damage, not target_creature.body.is_alive())
		if logger:
			logger.bites_hit += 1


func _skill_poison_spit(creature: Creature) -> void:
	## Apply poison (5 dmg/tick for 5 ticks) to nearest creature within range 2.
	var nearest := world.find_nearest_creature(creature.grid_pos, 2, creature.creature_id)
	if not nearest.is_empty() and creatures.has(nearest.id):
		creatures[nearest.id].body.poisoned_ticks = 5
		if logger:
			logger.poisons_hit += 1


func _skill_emit_pheromone(creature: Creature) -> void:
	pheromone_layer.deposit(creature.grid_pos, 0.5)


func _skill_share_food(creature: Creature) -> void:
	## Transfer 5 energy to an adjacent ally (same species).
	for offset in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var adj_id := world.get_creature_at(creature.grid_pos + offset)
		if adj_id >= 0 and creatures.has(adj_id):
			var target: Creature = creatures[adj_id]
			if target.body.species_id == creature.body.species_id:
				target.body.eat_food(5.0)
				return


func _skill_build_wall(creature: Creature) -> void:
	## Place a wall on the tile in facing direction.
	var target_pos := creature.grid_pos + creature.body.facing
	var tile: GridTile = world.get_tile(target_pos)
	if tile and not tile.is_occupied() and tile.is_passable():
		tile.wall = true


func _skill_heal_self(creature: Creature) -> void:
	var heal_amount: float = 10.0
	# Medicinal plants on tile boost healing
	var heal_tile: GridTile = world.get_tile(creature.grid_pos)
	if heal_tile and heal_tile.medicinal > 0.0:
		heal_amount *= 1.5  # 50% bonus from medicinal plants
	creature.body.health = minf(creature.body.health + heal_amount, GameConfig.MAX_HEALTH)


func _skill_burrow(creature: Creature) -> void:
	creature.body.burrowed = true
	creature.body.burrow_ticks = 5
