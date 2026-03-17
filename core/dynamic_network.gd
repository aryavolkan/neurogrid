class_name DynamicNetwork
extends RefCounted
## Phenotype network built from a DynamicGenome.
## Handles variable I/O: core inputs/outputs + evolved receptors/skills.

var _node_order: PackedInt32Array  # Topologically sorted node IDs
var _input_ids: PackedInt32Array   # Core inputs + receptors (in order)
var _output_ids: PackedInt32Array  # Core outputs + skills (in order)
var _biases: Dictionary = {}
var _incoming: Dictionary = {}  # node_id -> [{in_id, weight}]
var _is_input: Dictionary = {}
var _activations: Dictionary = {}
var _cached_outputs: PackedFloat32Array

# Maps for receptor/skill ordering
var _receptor_order: Array = []  # Array of {node_id, registry_id} in input order
var _skill_order: Array = []     # Array of {node_id, registry_id} in output order
var _core_input_count: int = 0
var _core_output_count: int = 0


static func from_genome(genome: DynamicGenome) -> DynamicNetwork:
	var net := DynamicNetwork.new()

	var core_inputs: Array = []
	var receptor_inputs: Array = []
	var core_outputs: Array = []
	var skill_outputs: Array = []

	for node in genome.node_genes:
		net._biases[node.id] = node.bias
		net._incoming[node.id] = []

		match node.type:
			DynamicGenome.TYPE_CORE_INPUT:
				core_inputs.append(node)
				net._is_input[node.id] = true
			DynamicGenome.TYPE_RECEPTOR:
				receptor_inputs.append(node)
				net._is_input[node.id] = true
			DynamicGenome.TYPE_CORE_OUTPUT:
				core_outputs.append(node)
			DynamicGenome.TYPE_SKILL:
				skill_outputs.append(node)

	# Build input_ids: core first, then receptors
	for node in core_inputs:
		net._input_ids.append(node.id)
	for node in receptor_inputs:
		net._input_ids.append(node.id)
		net._receptor_order.append({"node_id": node.id, "registry_id": node.registry_id})

	# Build output_ids: core first, then skills
	for node in core_outputs:
		net._output_ids.append(node.id)
	for node in skill_outputs:
		net._output_ids.append(node.id)
		net._skill_order.append({"node_id": node.id, "registry_id": node.registry_id})

	net._core_input_count = core_inputs.size()
	net._core_output_count = core_outputs.size()

	# Build adjacency from enabled connections
	for conn in genome.connection_genes:
		if conn.enabled:
			if net._incoming.has(conn.out_id):
				net._incoming[conn.out_id].append({"in_id": conn.in_id, "weight": conn.weight})

	# Topological sort
	net._node_order = net._topological_sort(genome)

	# Init activations
	for node in genome.node_genes:
		net._activations[node.id] = 0.0

	# Pre-allocate output
	net._cached_outputs.resize(net._output_ids.size())

	return net


func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
	## Feed inputs through network. Inputs: [core_inputs..., receptor_values...]
	for i in _input_ids.size():
		if i < inputs.size():
			_activations[_input_ids[i]] = inputs[i]
		else:
			_activations[_input_ids[i]] = 0.0

	for node_id in _node_order:
		if _is_input.has(node_id):
			continue
		var sum: float = _biases.get(node_id, 0.0)
		var incoming: Array = _incoming.get(node_id, [])
		for edge in incoming:
			sum += _activations.get(edge.in_id, 0.0) * edge.weight
		_activations[node_id] = tanh(sum)

	for i in _output_ids.size():
		_cached_outputs[i] = _activations.get(_output_ids[i], 0.0)

	return _cached_outputs


func get_activation(node_id: int) -> float:
	return _activations.get(node_id, 0.0)


func get_input_count() -> int:
	return _input_ids.size()


func get_output_count() -> int:
	return _output_ids.size()


func get_core_input_count() -> int:
	return _core_input_count


func get_core_output_count() -> int:
	return _core_output_count


func get_receptor_order() -> Array:
	return _receptor_order


func get_skill_order() -> Array:
	return _skill_order


func _topological_sort(genome: DynamicGenome) -> PackedInt32Array:
	## Kahn's algorithm for topological ordering.
	var in_degree: Dictionary = {}
	var adj: Dictionary = {}

	for node in genome.node_genes:
		in_degree[node.id] = 0
		adj[node.id] = []

	for conn in genome.connection_genes:
		if conn.enabled:
			if adj.has(conn.in_id) and in_degree.has(conn.out_id):
				adj[conn.in_id].append(conn.out_id)
				in_degree[conn.out_id] += 1

	# Start with nodes that have no incoming edges
	var queue: Array[int] = []
	for node_id in in_degree:
		if in_degree[node_id] == 0:
			queue.append(node_id)

	var order: PackedInt32Array = []
	while not queue.is_empty():
		var current: int = queue.pop_front()
		order.append(current)
		for neighbor in adj.get(current, []):
			in_degree[neighbor] -= 1
			if in_degree[neighbor] == 0:
				queue.append(neighbor)

	# If order doesn't include all nodes (cycle), fall back to type ordering
	if order.size() < genome.node_genes.size():
		order.clear()
		# Input nodes first
		for node in genome.node_genes:
			if node.is_input():
				order.append(node.id)
		# Hidden nodes
		for node in genome.node_genes:
			if node.type == DynamicGenome.TYPE_HIDDEN:
				order.append(node.id)
		# Output nodes
		for node in genome.node_genes:
			if node.is_output():
				order.append(node.id)

	return order
