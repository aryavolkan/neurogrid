class_name SpeciesManager
extends RefCounted
## Manages species assignment, tracking, and speciation using DynamicGenome compatibility.

var _species: Dictionary = {}       # species_id -> SpeciesInfo
var _creature_species: Dictionary = {}  # creature_id -> species_id
var _next_species_id: int = 1
var _config: DynamicConfig

# Per-species tracking
class SpeciesInfo:
	var id: int
	var representative_genome: DynamicGenome
	var member_ids: Array = []       # creature_ids
	var best_fitness: float = 0.0
	var best_fitness_ever: float = 0.0
	var generations_without_improvement: int = 0
	var total_fitness: float = 0.0
	var age: int = 0

	func _init(p_id: int, p_genome: DynamicGenome) -> void:
		id = p_id
		representative_genome = p_genome


func _init(p_config: DynamicConfig) -> void:
	_config = p_config


func assign_species(creature_id: int, genome: DynamicGenome) -> int:
	## Assign creature to an existing compatible species, or create a new one.
	for species_id in _species:
		var info: SpeciesInfo = _species[species_id]
		var dist := genome.compatibility(info.representative_genome)
		if dist < _config.neat_config.compatibility_threshold:
			info.member_ids.append(creature_id)
			_creature_species[creature_id] = species_id
			return species_id

	# New species
	var new_id := _next_species_id
	_next_species_id += 1
	var info := SpeciesInfo.new(new_id, genome.copy())
	info.member_ids.append(creature_id)
	_species[new_id] = info
	_creature_species[creature_id] = new_id
	return new_id


func remove_creature(creature_id: int) -> void:
	var species_id: int = _creature_species.get(creature_id, -1)
	if species_id >= 0 and _species.has(species_id):
		_species[species_id].member_ids.erase(creature_id)
	_creature_species.erase(creature_id)


func update_fitness(creature_id: int, fitness: float) -> void:
	var species_id: int = _creature_species.get(creature_id, -1)
	if species_id >= 0 and _species.has(species_id):
		_species[species_id].total_fitness += fitness
		if fitness > _species[species_id].best_fitness:
			_species[species_id].best_fitness = fitness


func end_generation() -> void:
	## Called periodically to update stagnation tracking and prune empty species.
	var to_remove: Array = []

	for species_id in _species:
		var info: SpeciesInfo = _species[species_id]
		info.age += 1

		# Update stagnation
		if info.best_fitness > info.best_fitness_ever:
			info.best_fitness_ever = info.best_fitness
			info.generations_without_improvement = 0
		else:
			info.generations_without_improvement += 1

		# Reset per-generation tracking
		info.best_fitness = 0.0
		info.total_fitness = 0.0

		# Update representative (random living member)
		if info.member_ids.is_empty():
			to_remove.append(species_id)

	for species_id in to_remove:
		_species.erase(species_id)

	# Adjust compatibility threshold toward target
	var current_count := _species.size()
	var target := _config.neat_config.target_species_count
	if current_count < target:
		_config.neat_config.compatibility_threshold -= _config.neat_config.threshold_step * 0.5
	elif current_count > target:
		_config.neat_config.compatibility_threshold += _config.neat_config.threshold_step * 0.5
	_config.neat_config.compatibility_threshold = maxf(_config.neat_config.compatibility_threshold, 0.3)


func is_stagnant(species_id: int) -> bool:
	if not _species.has(species_id):
		return false
	return _species[species_id].generations_without_improvement >= _config.neat_config.stagnation_kill_threshold


func get_species_id(creature_id: int) -> int:
	return _creature_species.get(creature_id, -1)


func get_species_count() -> int:
	return _species.size()


func get_species_counts() -> Dictionary:
	## Returns {species_id: member_count}
	var counts: Dictionary = {}
	for species_id in _species:
		counts[species_id] = _species[species_id].member_ids.size()
	return counts


func get_species_info(species_id: int) -> SpeciesInfo:
	return _species.get(species_id)


func get_all_species() -> Dictionary:
	return _species


func update_representative(species_id: int, genome: DynamicGenome) -> void:
	if _species.has(species_id):
		_species[species_id].representative_genome = genome.copy()
