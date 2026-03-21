class_name ReproductionSystem
extends RefCounted
## Handles sexual reproduction: mate finding, genome crossover, offspring spawning.

var world: GridWorld
var creatures: Dictionary = {}  # creature_id -> Creature (set by SimulationManager)


func _init(p_world: GridWorld) -> void:
	world = p_world


var _debug_log: bool = false

func try_reproduce(creature: Creature) -> DynamicGenome:
	## Attempt reproduction. Returns offspring genome or null.
	var body := creature.body
	if not body.can_reproduce():
		if _debug_log:
			print("  [repro] #%d can't reproduce: energy=%.1f threshold=%.1f cd=%.1f" % [
				creature.creature_id, body.energy, GameConfig.REPRODUCTION_ENERGY_THRESHOLD, body.reproduction_cooldown])
		return null

	# Find a compatible mate nearby
	var mate := _find_mate(creature)
	if not mate:
		if _debug_log:
			var nearby := world.find_creatures_in_range(creature.grid_pos, 5)
			print("  [repro] #%d (E=%.1f) no mate found. %d nearby creatures" % [
				creature.creature_id, body.energy, nearby.size()])
		return null

	# Crossover
	var child_genome := DynamicGenome.crossover(creature.genome, mate.genome)
	child_genome.mutate()

	# Pay costs
	body.energy -= GameConfig.REPRODUCTION_COST
	mate.body.energy -= GameConfig.REPRODUCTION_COST * 0.5

	# Set cooldowns
	body.reproduction_cooldown = GameConfig.REPRODUCTION_COOLDOWN
	mate.body.reproduction_cooldown = GameConfig.REPRODUCTION_COOLDOWN

	return child_genome


func _find_mate(creature: Creature) -> Creature:
	## Find nearest compatible creature within mating range.
	var nearby := world.find_creatures_in_range(creature.grid_pos, 5)
	var best_mate: Creature = null
	var best_dist: int = 999

	var best_score: float = -999.0

	var creature_gene_count: int = creature.genome.connection_genes.size()
	for info in nearby:
		if not creatures.has(info.id):
			continue
		var candidate: Creature = creatures[info.id]
		if not candidate.body.is_alive():
			if _debug_log:
				print("    [mate] #%d not alive" % info.id)
			continue
		if not candidate.body.can_reproduce():
			if _debug_log:
				print("    [mate] #%d can't reproduce (E=%.1f cd=%.1f)" % [
					info.id, candidate.body.energy, candidate.body.reproduction_cooldown])
			continue

		# Fast pre-filter: skip if gene count difference is extreme
		var cand_gene_count: int = candidate.genome.connection_genes.size()
		var n: float = maxf(creature_gene_count, cand_gene_count)
		if n >= 20.0:
			var size_diff: float = absf(creature_gene_count - cand_gene_count)
			if size_diff / n > 0.8:  # Wildly different genome sizes — skip
				continue

		# Compatibility check
		var compat := creature.genome.compatibility(candidate.genome)
		if compat < GameConfig.MATING_COMPATIBILITY_THRESHOLD:
			# Sexual selection: score candidate by evolved mate preferences
			var pref_score := AdvancedEvolution.compute_mate_preference(creature.genome, candidate.genome)
			# Combine distance proximity and preference (closer + preferred = higher score)
			var score: float = pref_score - float(info.dist) * 0.1
			if score > best_score:
				best_score = score
				best_mate = candidate
				if _debug_log:
					print("    [mate] #%d compatible (compat=%.2f, pref=%.2f, range=%d)" % [
						info.id, compat, pref_score, info.dist])
		elif _debug_log:
			print("    [mate] #%d incompatible (dist=%.2f > %.1f)" % [
				info.id, compat, GameConfig.MATING_COMPATIBILITY_THRESHOLD])

	return best_mate
