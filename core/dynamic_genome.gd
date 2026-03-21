class_name DynamicGenome
extends RefCounted
## NEAT genome extended with evolvable receptor (type 3) and skill (type 4) nodes.
## Receptor/skill nodes have registry_id and io_innovation for crossover alignment.


# Node types
const TYPE_CORE_INPUT: int = 0
const TYPE_HIDDEN: int = 1
const TYPE_CORE_OUTPUT: int = 2
const TYPE_RECEPTOR: int = 3
const TYPE_SKILL: int = 4


class DynamicNodeGene:
	var id: int
	var type: int  # 0=core_input, 1=hidden, 2=core_output, 3=receptor, 4=skill
	var bias: float = 0.0
	var registry_id: int = -1  # For type 3/4 only
	var io_innovation: int = -1  # For type 3/4 crossover alignment

	func _init(p_id: int, p_type: int, p_registry_id: int = -1, p_io_innov: int = -1) -> void:
		id = p_id
		type = p_type
		registry_id = p_registry_id
		io_innovation = p_io_innov
		bias = randf_range(-1.0, 1.0)

	func copy() -> DynamicNodeGene:
		var n := DynamicNodeGene.new(id, type, registry_id, io_innovation)
		n.bias = bias
		return n

	func is_input() -> bool:
		return type == TYPE_CORE_INPUT or type == TYPE_RECEPTOR

	func is_output() -> bool:
		return type == TYPE_CORE_OUTPUT or type == TYPE_SKILL


class ConnectionGene:
	var in_id: int
	var out_id: int
	var weight: float
	var enabled: bool = true
	var innovation: int
	var learning_rate: float = 0.0  # Neuromodulation: Hebbian weight change rate

	func _init(p_in: int, p_out: int, p_weight: float, p_innovation: int) -> void:
		in_id = p_in
		out_id = p_out
		weight = p_weight
		innovation = p_innovation

	func copy() -> ConnectionGene:
		var c := ConnectionGene.new(in_id, out_id, weight, innovation)
		c.enabled = enabled
		c.learning_rate = learning_rate
		return c


# Genome data
var node_genes: Array = []  # Array[DynamicNodeGene]
var connection_genes: Array = []  # Array[ConnectionGene]
var fitness: float = 0.0
var adjusted_fitness: float = 0.0
var config: DynamicConfig
var innovation_tracker  # NeatInnovation (connection innovations)
var io_tracker: IoInnovation  # Receptor/skill innovations

# Sexual selection: evolved mate preference weights (Phase 12)
var mate_pref_complexity: float = 0.0  # Preference for genome complexity
var mate_pref_skills: float = 0.0     # Preference for skill count
var mate_pref_receptors: float = 0.0  # Preference for receptor count
var mate_pref_fitness: float = 0.0    # Preference for high fitness


static func create(p_config: DynamicConfig, p_conn_tracker, p_io_tracker: IoInnovation) -> DynamicGenome:
	## Factory: create a genome with core I/O nodes and initial connections.
	var genome := DynamicGenome.new()
	genome.config = p_config
	genome.innovation_tracker = p_conn_tracker
	genome.io_tracker = p_io_tracker

	var nc = p_config.neat_config

	# Core input nodes
	for i in nc.input_count:
		genome.node_genes.append(DynamicNodeGene.new(i, TYPE_CORE_INPUT))

	# Core output nodes
	for i in nc.output_count:
		genome.node_genes.append(DynamicNodeGene.new(nc.input_count + i, TYPE_CORE_OUTPUT))

	# Ensure innovation tracker knows about core node IDs
	var max_node_id: int = nc.input_count + nc.output_count
	while p_conn_tracker.get_next_node_id() < max_node_id:
		p_conn_tracker.allocate_node_id()

	# Add initial connections (fraction of input->output pairs)
	var input_nodes := genome.get_nodes_by_type([TYPE_CORE_INPUT])
	var output_nodes := genome.get_nodes_by_type([TYPE_CORE_OUTPUT])
	for inp_node in input_nodes:
		for out_node in output_nodes:
			if randf() < nc.initial_connection_fraction:
				var conn := ConnectionGene.new(
					inp_node.id, out_node.id,
					randf_range(-2.0, 2.0),
					p_conn_tracker.get_innovation(inp_node.id, out_node.id)
				)
				genome.connection_genes.append(conn)

	return genome


# --- Node queries ---

func get_nodes_by_type(types: Array) -> Array:
	return node_genes.filter(func(n): return n.type in types)


func get_receptor_registry_ids() -> Dictionary:
	## Returns {registry_id: true} for all receptor nodes.
	var ids: Dictionary = {}
	for node in node_genes:
		if node.type == TYPE_RECEPTOR:
			ids[node.registry_id] = true
	return ids


func get_skill_registry_ids() -> Dictionary:
	var ids: Dictionary = {}
	for node in node_genes:
		if node.type == TYPE_SKILL:
			ids[node.registry_id] = true
	return ids


func get_receptor_count() -> int:
	var count: int = 0
	for node in node_genes:
		if node.type == TYPE_RECEPTOR:
			count += 1
	return count


func get_skill_count() -> int:
	var count: int = 0
	for node in node_genes:
		if node.type == TYPE_SKILL:
			count += 1
	return count


func get_receptor_nodes() -> Array:
	return node_genes.filter(func(n): return n.type == TYPE_RECEPTOR)


func get_skill_nodes() -> Array:
	return node_genes.filter(func(n): return n.type == TYPE_SKILL)


# --- Mutations ---

func mutate_add_receptor() -> void:
	## Add a random receptor from the registry that this genome doesn't already have.
	if get_receptor_count() >= config.max_receptors:
		return

	var existing := get_receptor_registry_ids()
	var registry := Registries.receptor_registry
	var available: Array = []
	for i in registry.get_count():
		if not existing.has(i):
			available.append(i)

	if available.is_empty():
		return

	var reg_id: int = available[randi() % available.size()]
	var io_innov: int = io_tracker.get_receptor_innovation(reg_id)
	var node_id: int = innovation_tracker.allocate_node_id()
	var new_node := DynamicNodeGene.new(node_id, TYPE_RECEPTOR, reg_id, io_innov)
	node_genes.append(new_node)

	# Optionally connect to a random hidden or output node
	var targets := get_nodes_by_type([TYPE_HIDDEN, TYPE_CORE_OUTPUT, TYPE_SKILL])
	if not targets.is_empty():
		var target = targets[randi() % targets.size()]
		var conn := ConnectionGene.new(
			node_id, target.id,
			randf_range(-2.0, 2.0),
			innovation_tracker.get_innovation(node_id, target.id)
		)
		connection_genes.append(conn)


func mutate_add_skill() -> void:
	## Add a random skill from the registry that this genome doesn't already have.
	if get_skill_count() >= config.max_skills:
		return

	var existing := get_skill_registry_ids()
	var registry := Registries.skill_registry
	var available: Array = []
	for i in registry.get_count():
		if not existing.has(i):
			available.append(i)

	if available.is_empty():
		return

	var reg_id: int = available[randi() % available.size()]
	var io_innov: int = io_tracker.get_skill_innovation(reg_id)
	var node_id: int = innovation_tracker.allocate_node_id()
	var new_node := DynamicNodeGene.new(node_id, TYPE_SKILL, reg_id, io_innov)
	node_genes.append(new_node)

	# Optionally connect from a random hidden or input node
	var sources := get_nodes_by_type([TYPE_HIDDEN, TYPE_CORE_INPUT, TYPE_RECEPTOR])
	if not sources.is_empty():
		var source = sources[randi() % sources.size()]
		var conn := ConnectionGene.new(
			source.id, node_id,
			randf_range(-2.0, 2.0),
			innovation_tracker.get_innovation(source.id, node_id)
		)
		connection_genes.append(conn)


func mutate_remove_receptor() -> void:
	var receptors := get_receptor_nodes()
	if receptors.is_empty():
		return
	var to_remove: DynamicNodeGene = receptors[randi() % receptors.size()]
	_remove_node(to_remove)


func mutate_remove_skill() -> void:
	var skills := get_skill_nodes()
	if skills.is_empty():
		return
	var to_remove: DynamicNodeGene = skills[randi() % skills.size()]
	_remove_node(to_remove)


func _remove_node(node: DynamicNodeGene) -> void:
	## Remove a node and disable all its connections.
	for conn in connection_genes:
		if conn.in_id == node.id or conn.out_id == node.id:
			conn.enabled = false
	node_genes.erase(node)


func mutate_add_connection() -> void:
	var possible_inputs := node_genes.filter(func(n): return n.is_input() or n.type == TYPE_HIDDEN)
	var possible_outputs := node_genes.filter(func(n): return n.is_output() or n.type == TYPE_HIDDEN)

	if possible_inputs.is_empty() or possible_outputs.is_empty():
		return

	for _attempt in 10:
		var in_node = possible_inputs[randi() % possible_inputs.size()]
		var out_node = possible_outputs[randi() % possible_outputs.size()]

		if in_node.id == out_node.id:
			continue
		if connection_genes.any(func(c): return c.in_id == in_node.id and c.out_id == out_node.id):
			continue
		if _would_create_cycle(in_node.id, out_node.id):
			continue

		var new_conn := ConnectionGene.new(
			in_node.id, out_node.id,
			randf_range(-2.0, 2.0),
			innovation_tracker.get_innovation(in_node.id, out_node.id)
		)
		connection_genes.append(new_conn)
		return


func mutate_add_node() -> void:
	var enabled_conns := connection_genes.filter(func(c): return c.enabled)
	if enabled_conns.is_empty():
		return

	var conn = enabled_conns[randi() % enabled_conns.size()]
	conn.enabled = false

	var new_node_id: int = innovation_tracker.allocate_node_id()
	var new_node := DynamicNodeGene.new(new_node_id, TYPE_HIDDEN)
	node_genes.append(new_node)

	var conn1 := ConnectionGene.new(
		conn.in_id, new_node_id, 1.0,
		innovation_tracker.get_innovation(conn.in_id, new_node_id)
	)
	var conn2 := ConnectionGene.new(
		new_node_id, conn.out_id, conn.weight,
		innovation_tracker.get_innovation(new_node_id, conn.out_id)
	)
	connection_genes.append(conn1)
	connection_genes.append(conn2)


func mutate_weights() -> void:
	var nc = config.neat_config
	for conn in connection_genes:
		if randf() < nc.weight_mutate_rate:
			if randf() < nc.weight_perturb_rate:
				conn.weight += _randn() * nc.weight_perturb_strength
			else:
				conn.weight = randf_range(-nc.weight_reset_range, nc.weight_reset_range)
		# Neuromodulation: mutate learning rate (5% chance per connection)
		if randf() < 0.05:
			conn.learning_rate += _randn() * 0.01
			conn.learning_rate = clampf(conn.learning_rate, -0.1, 0.1)


func mutate_disable_connection() -> void:
	var enabled_conns := connection_genes.filter(func(c): return c.enabled)
	if enabled_conns.is_empty():
		return
	enabled_conns[randi() % enabled_conns.size()].enabled = false


func mutate() -> void:
	## Apply all mutation operators.
	var nc = config.neat_config
	if randf() < nc.weight_mutate_rate:
		mutate_weights()
	if randf() < nc.add_connection_rate:
		mutate_add_connection()
	if randf() < nc.add_node_rate:
		mutate_add_node()
	if randf() < nc.disable_connection_rate:
		mutate_disable_connection()
	# Dynamic I/O mutations
	if randf() < config.add_receptor_rate:
		mutate_add_receptor()
	if randf() < config.add_skill_rate:
		mutate_add_skill()
	if randf() < config.remove_receptor_rate:
		mutate_remove_receptor()
	if randf() < config.remove_skill_rate:
		mutate_remove_skill()
	# Sexual selection: mutate mate preferences (10% chance)
	if randf() < 0.1:
		mate_pref_complexity += _randn() * 0.2
		mate_pref_skills += _randn() * 0.2
		mate_pref_receptors += _randn() * 0.2
		mate_pref_fitness += _randn() * 0.2


# --- Compatibility ---

func compatibility(other: DynamicGenome) -> float:
	## Compatibility distance including connection genes AND I/O node differences.
	var nc = config.neat_config

	# Connection-based distance (same as NeatGenome)
	var conn_dist := _connection_compatibility(other, nc)

	# I/O-based distance
	var io_dist := _io_compatibility(other)

	return conn_dist + config.c4_io_diff * io_dist


func _connection_compatibility(other: DynamicGenome, nc) -> float:
	var genes_a := connection_genes
	var genes_b := other.connection_genes

	if genes_a.is_empty() and genes_b.is_empty():
		return 0.0

	var map_a: Dictionary = {}
	var max_innov_a: int = 0
	for g in genes_a:
		map_a[g.innovation] = g.weight
		if g.innovation > max_innov_a:
			max_innov_a = g.innovation

	var map_b: Dictionary = {}
	var max_innov_b: int = 0
	for g in genes_b:
		map_b[g.innovation] = g.weight
		if g.innovation > max_innov_b:
			max_innov_b = g.innovation

	var smaller_max: int = mini(max_innov_a, max_innov_b)
	var excess: int = 0
	var disjoint: int = 0
	var weight_diff_sum: float = 0.0
	var matching_count: int = 0

	for innov in map_a:
		if map_b.has(innov):
			weight_diff_sum += absf(map_a[innov] - map_b[innov])
			matching_count += 1
		elif innov > smaller_max:
			excess += 1
		else:
			disjoint += 1

	for innov in map_b:
		if not map_a.has(innov):
			if innov > smaller_max:
				excess += 1
			else:
				disjoint += 1

	var n: float = maxf(genes_a.size(), genes_b.size())
	if n < 20:
		n = 1.0

	var avg_w: float = weight_diff_sum / matching_count if matching_count > 0 else 0.0
	return (nc.c1_excess * excess / n) + (nc.c2_disjoint * disjoint / n) + (nc.c3_weight_diff * avg_w)


func _io_compatibility(other: DynamicGenome) -> float:
	var self_r := get_receptor_registry_ids()
	var other_r := other.get_receptor_registry_ids()
	var self_s := get_skill_registry_ids()
	var other_s := other.get_skill_registry_ids()
	return float(_symmetric_diff_count(self_r, other_r) + _symmetric_diff_count(self_s, other_s))


static func _symmetric_diff_count(a: Dictionary, b: Dictionary) -> int:
	var count: int = 0
	for key in a:
		if not b.has(key):
			count += 1
	for key in b:
		if not a.has(key):
			count += 1
	return count


# --- Crossover ---

static func crossover(parent_a: DynamicGenome, parent_b: DynamicGenome) -> DynamicGenome:
	## NEAT crossover extended with I/O node alignment.
	var child := DynamicGenome.new()
	child.config = parent_a.config
	child.innovation_tracker = parent_a.innovation_tracker
	child.io_tracker = parent_a.io_tracker

	# Ensure parent_a is fitter
	var a := parent_a
	var b := parent_b
	if b.fitness > a.fitness:
		a = parent_b
		b = parent_a
	var equal_fitness: bool = absf(a.fitness - b.fitness) < 0.001

	# --- Connection gene crossover (standard NEAT) ---
	var map_a: Dictionary = {}
	for conn in a.connection_genes:
		map_a[conn.innovation] = conn
	var map_b: Dictionary = {}
	for conn in b.connection_genes:
		map_b[conn.innovation] = conn

	var all_innovs: Dictionary = {}
	for key in map_a:
		all_innovs[key] = true
	for key in map_b:
		all_innovs[key] = true

	var child_conns: Array = []
	for innov in all_innovs:
		var in_a: bool = map_a.has(innov)
		var in_b: bool = map_b.has(innov)
		if in_a and in_b:
			var source = map_a[innov] if randf() < 0.5 else map_b[innov]
			var gene_copy = source.copy()
			if not map_a[innov].enabled or not map_b[innov].enabled:
				gene_copy.enabled = randf() >= a.config.neat_config.disabled_gene_inherit_rate
			child_conns.append(gene_copy)
		elif in_a:
			child_conns.append(map_a[innov].copy())
		elif in_b and equal_fitness:
			child_conns.append(map_b[innov].copy())

	child.connection_genes = child_conns

	# --- I/O node crossover (receptor + skill alignment by io_innovation) ---
	# Build io_innovation -> node maps for receptor and skill nodes
	var receptor_map_a: Dictionary = {}
	var receptor_map_b: Dictionary = {}
	var skill_map_a: Dictionary = {}
	var skill_map_b: Dictionary = {}

	for node in a.node_genes:
		if node.type == TYPE_RECEPTOR:
			receptor_map_a[node.io_innovation] = node
		elif node.type == TYPE_SKILL:
			skill_map_a[node.io_innovation] = node

	for node in b.node_genes:
		if node.type == TYPE_RECEPTOR:
			receptor_map_b[node.io_innovation] = node
		elif node.type == TYPE_SKILL:
			skill_map_b[node.io_innovation] = node

	# Merge receptors
	var child_io_nodes: Array = []
	child_io_nodes.append_array(_crossover_io_nodes(receptor_map_a, receptor_map_b, equal_fitness))
	child_io_nodes.append_array(_crossover_io_nodes(skill_map_a, skill_map_b, equal_fitness))

	# --- Collect all child nodes ---
	# Core nodes from fitter parent
	var needed_node_ids: Dictionary = {}
	for node in a.node_genes:
		if node.type == TYPE_CORE_INPUT or node.type == TYPE_CORE_OUTPUT:
			needed_node_ids[node.id] = true

	# Hidden nodes referenced by child connections
	for conn in child_conns:
		needed_node_ids[conn.in_id] = true
		needed_node_ids[conn.out_id] = true

	# Build node maps from both parents
	var node_map_a: Dictionary = {}
	for node in a.node_genes:
		node_map_a[node.id] = node
	var node_map_b: Dictionary = {}
	for node in b.node_genes:
		node_map_b[node.id] = node

	var child_nodes: Array = []
	for node_id in needed_node_ids:
		# Skip receptor/skill nodes (handled separately by io_innovation alignment)
		var na = node_map_a.get(node_id)
		var nb = node_map_b.get(node_id)
		var source_node = na if na else nb
		if source_node and source_node.type != TYPE_RECEPTOR and source_node.type != TYPE_SKILL:
			child_nodes.append(source_node.copy())

	# Add the I/O nodes from crossover
	child_nodes.append_array(child_io_nodes)

	# Sort: core_input(0) < hidden(1) < core_output(2) < receptor(3) < skill(4)
	child_nodes.sort_custom(func(x, y):
		if x.type != y.type:
			return x.type < y.type
		return x.id < y.id
	)
	child.node_genes = child_nodes

	return child


static func _crossover_io_nodes(map_a: Dictionary, map_b: Dictionary, equal_fitness: bool) -> Array:
	## Crossover I/O nodes aligned by io_innovation (same as connection alignment).
	var result: Array = []
	var all_innovs: Dictionary = {}
	for key in map_a:
		all_innovs[key] = true
	for key in map_b:
		all_innovs[key] = true

	for innov in all_innovs:
		var in_a: bool = map_a.has(innov)
		var in_b: bool = map_b.has(innov)
		if in_a and in_b:
			var source = map_a[innov] if randf() < 0.5 else map_b[innov]
			result.append(source.copy())
		elif in_a:
			result.append(map_a[innov].copy())
		elif in_b and equal_fitness:
			result.append(map_b[innov].copy())

	return result


# --- Copy ---

func copy() -> DynamicGenome:
	var g := DynamicGenome.new()
	g.config = config
	g.innovation_tracker = innovation_tracker
	g.io_tracker = io_tracker
	g.node_genes = node_genes.map(func(n): return n.copy())
	g.connection_genes = connection_genes.map(func(c): return c.copy())
	g.fitness = fitness
	g.adjusted_fitness = adjusted_fitness
	g.mate_pref_complexity = mate_pref_complexity
	g.mate_pref_skills = mate_pref_skills
	g.mate_pref_receptors = mate_pref_receptors
	g.mate_pref_fitness = mate_pref_fitness
	return g


# --- Helpers ---

func _would_create_cycle(from_id: int, to_id: int) -> bool:
	var visited: Dictionary = {}
	var stack: Array[int] = [to_id]
	while not stack.is_empty():
		var current: int = stack.pop_back()
		if current == from_id:
			return true
		if visited.has(current):
			continue
		visited[current] = true
		for conn in connection_genes:
			if conn.enabled and conn.in_id == current:
				stack.append(conn.out_id)
	return false


func get_total_input_count() -> int:
	var count: int = 0
	for node in node_genes:
		if node.is_input():
			count += 1
	return count


func get_total_output_count() -> int:
	var count: int = 0
	for node in node_genes:
		if node.is_output():
			count += 1
	return count


static func _randn() -> float:
	var u1 := randf()
	var u2 := randf()
	if u1 < 0.0001:
		u1 = 0.0001
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)


# --- Serialization ---

func serialize() -> Dictionary:
	var nodes: Array = []
	for node in node_genes:
		nodes.append({
			"id": node.id, "type": node.type, "bias": node.bias,
			"registry_id": node.registry_id, "io_innovation": node.io_innovation,
		})
	var connections: Array = []
	for conn in connection_genes:
		connections.append({
			"in": conn.in_id, "out": conn.out_id,
			"weight": conn.weight, "enabled": conn.enabled,
			"innovation": conn.innovation,
			"learning_rate": conn.learning_rate,
		})
	return {
		"nodes": nodes, "connections": connections, "fitness": fitness,
		"mate_pref_complexity": mate_pref_complexity,
		"mate_pref_skills": mate_pref_skills,
		"mate_pref_receptors": mate_pref_receptors,
		"mate_pref_fitness": mate_pref_fitness,
	}


static func deserialize(data: Dictionary, p_config: DynamicConfig,
		p_conn_tracker, p_io_tracker: IoInnovation) -> DynamicGenome:
	var genome := DynamicGenome.new()
	genome.config = p_config
	genome.innovation_tracker = p_conn_tracker
	genome.io_tracker = p_io_tracker

	for nd in data.get("nodes", []):
		var node := DynamicNodeGene.new(
			int(nd.id), int(nd.type),
			int(nd.get("registry_id", -1)),
			int(nd.get("io_innovation", -1)),
		)
		node.bias = float(nd.bias)
		genome.node_genes.append(node)

	for cd in data.get("connections", []):
		var conn := ConnectionGene.new(
			int(cd["in"]), int(cd.out),
			float(cd.weight), int(cd.innovation),
		)
		conn.enabled = bool(cd.enabled)
		conn.learning_rate = float(cd.get("learning_rate", 0.0))
		genome.connection_genes.append(conn)

	genome.fitness = float(data.get("fitness", 0.0))
	genome.mate_pref_complexity = float(data.get("mate_pref_complexity", 0.0))
	genome.mate_pref_skills = float(data.get("mate_pref_skills", 0.0))
	genome.mate_pref_receptors = float(data.get("mate_pref_receptors", 0.0))
	genome.mate_pref_fitness = float(data.get("mate_pref_fitness", 0.0))
	return genome
