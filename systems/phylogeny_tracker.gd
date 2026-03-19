class_name PhylogenyTracker
extends RefCounted
## Tracks species lineage over generations for phylogenetic tree visualization.
## Records birth, split, extinction events with timestamps.

# Lineage nodes: species_id -> PhyloNode
var _nodes: Dictionary = {}

class PhyloNode:
	var species_id: int
	var parent_species_id: int = -1  # Species this split from (-1 = root)
	var born_tick: int = 0
	var extinct_tick: int = -1       # -1 = still alive
	var peak_members: int = 0
	var peak_fitness: float = 0.0
	var children: Array = []         # species_ids that split from this

	func _init(p_id: int, p_parent: int, p_tick: int) -> void:
		species_id = p_id
		parent_species_id = p_parent
		born_tick = p_tick

	func is_alive() -> bool:
		return extinct_tick < 0


func record_species_born(species_id: int, parent_species_id: int, tick: int) -> void:
	var node := PhyloNode.new(species_id, parent_species_id, tick)
	_nodes[species_id] = node
	if _nodes.has(parent_species_id):
		_nodes[parent_species_id].children.append(species_id)


func record_species_extinct(species_id: int, tick: int) -> void:
	if _nodes.has(species_id):
		_nodes[species_id].extinct_tick = tick


func update_species_stats(species_id: int, member_count: int, best_fitness: float) -> void:
	if _nodes.has(species_id):
		var node: PhyloNode = _nodes[species_id]
		node.peak_members = maxi(node.peak_members, member_count)
		node.peak_fitness = maxf(node.peak_fitness, best_fitness)


func get_node(species_id: int) -> PhyloNode:
	return _nodes.get(species_id)


func get_all_nodes() -> Dictionary:
	return _nodes


func get_living_species() -> Array:
	var result: Array = []
	for sid in _nodes:
		if _nodes[sid].is_alive():
			result.append(sid)
	return result


func get_tree_depth(species_id: int) -> int:
	var depth: int = 0
	var current: int = species_id
	while _nodes.has(current) and _nodes[current].parent_species_id >= 0:
		depth += 1
		current = _nodes[current].parent_species_id
	return depth


func get_lineage(species_id: int) -> Array:
	## Returns array of species_ids from root to this species.
	var path: Array = []
	var current: int = species_id
	while current >= 0 and _nodes.has(current):
		path.push_front(current)
		current = _nodes[current].parent_species_id
	return path


func get_report(current_tick: int) -> String:
	var living := get_living_species()
	var extinct_count: int = 0
	var max_depth: int = 0
	for sid in _nodes:
		if not _nodes[sid].is_alive():
			extinct_count += 1
		max_depth = maxi(max_depth, get_tree_depth(sid))

	var lines: Array = []
	lines.append("Phylogeny: %d total species (%d alive, %d extinct)" % [
		_nodes.size(), living.size(), extinct_count])
	lines.append("Max tree depth: %d" % max_depth)

	# Show top 5 longest-lived species
	var by_age: Array = []
	for sid in _nodes:
		var node: PhyloNode = _nodes[sid]
		var age: int = (node.extinct_tick if node.extinct_tick >= 0 else current_tick) - node.born_tick
		by_age.append({"id": sid, "age": age, "alive": node.is_alive(), "peak": node.peak_fitness})
	by_age.sort_custom(func(a, b): return a.age > b.age)

	lines.append("Longest-lived species:")
	for i in mini(5, by_age.size()):
		var s: Dictionary = by_age[i]
		var status: String = "alive" if s.alive else "extinct"
		lines.append("  Species %d: %d ticks (%s, peak fitness %.2f)" % [s.id, s.age, status, s.peak])

	return "\n".join(lines)
