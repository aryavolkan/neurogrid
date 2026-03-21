class_name DynamicNetwork
extends RefCounted
## Phenotype network built from a DynamicGenome.
## Handles variable I/O: core inputs/outputs + evolved receptors/skills.

var _node_order: PackedInt32Array  # Topologically sorted node IDs (non-input only)
var _input_ids: PackedInt32Array   # Core inputs + receptors (in order)
var _output_ids: PackedInt32Array  # Core outputs + skills (in order)
var _cached_outputs: PackedFloat32Array

# Array-indexed node data (node_id → index via _id_to_idx)
var _id_to_idx: Dictionary = {}   # node_id -> dense index
var _biases_arr: PackedFloat32Array
var _activations_arr: PackedFloat32Array
var _is_input_arr: PackedByteArray  # 1 = input, 0 = not

# Pre-flattened edge data for fast forward pass
var _edge_target_idx: PackedInt32Array   # Which node index this edge feeds into
var _edge_source_idx: PackedInt32Array   # Source node index
var _edge_weight: PackedFloat32Array     # Connection weight
# Per-node edge ranges: node at _node_order[i] has edges [_edge_start[i], _edge_start[i+1])
var _edge_start: PackedInt32Array

# Legacy dict for get_activation() compatibility
var _activations: Dictionary = {}

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

	# Build id_to_idx mapping (dense index for each node)
	var node_count: int = genome.node_genes.size()
	net._biases_arr.resize(node_count)
	net._activations_arr.resize(node_count)
	net._is_input_arr.resize(node_count)

	# Temporary adjacency for edge flattening
	var incoming_edges: Dictionary = {}  # node_id -> [{in_id, weight}]

	for i in node_count:
		var node = genome.node_genes[i]
		net._id_to_idx[node.id] = i
		net._biases_arr[i] = node.bias
		net._activations_arr[i] = 0.0
		net._is_input_arr[i] = 0
		net._activations[node.id] = 0.0
		incoming_edges[node.id] = []

		match node.type:
			DynamicGenome.TYPE_CORE_INPUT:
				core_inputs.append(node)
				net._is_input_arr[i] = 1
			DynamicGenome.TYPE_RECEPTOR:
				receptor_inputs.append(node)
				net._is_input_arr[i] = 1
			DynamicGenome.TYPE_CORE_OUTPUT:
				core_outputs.append(node)
			DynamicGenome.TYPE_SKILL:
				skill_outputs.append(node)

	# Build input_ids: core first, then receptors
	for node in core_inputs:
		net._input_ids.append(node.id)
	for node in receptor_inputs:
		net._input_ids.append(node.id)
		net._receptor_order.append({
			"node_id": node.id,
			"registry_id": node.registry_id
		})

	# Build output_ids: core first, then skills
	for node in core_outputs:
		net._output_ids.append(node.id)
	for node in skill_outputs:
		net._output_ids.append(node.id)
		net._skill_order.append({
			"node_id": node.id,
			"registry_id": node.registry_id
		})

	net._core_input_count = core_inputs.size()
	net._core_output_count = core_outputs.size()

	# Build adjacency from enabled connections
	for conn in genome.connection_genes:
		if conn.enabled:
			if incoming_edges.has(conn.out_id):
				incoming_edges[conn.out_id].append({
					"in_id": conn.in_id,
					"weight": conn.weight
				})

	# Topological sort
	var full_order := net._topological_sort(genome)

	# Build non-input node order and flatten edges
	var non_input_order: PackedInt32Array = []
	for node_id in full_order:
		if net._id_to_idx.has(node_id):
			var idx: int = net._id_to_idx[node_id]
			if net._is_input_arr[idx] == 0:
				non_input_order.append(node_id)

	# Flatten edges in node_order traversal order
	net._edge_start.resize(non_input_order.size() + 1)
	var edge_idx: int = 0
	for i in non_input_order.size():
		var node_id: int = non_input_order[i]
		net._edge_start[i] = edge_idx
		var edges: Array = incoming_edges.get(node_id, [])
		for edge in edges:
			if net._id_to_idx.has(edge.in_id):
				net._edge_source_idx.append(net._id_to_idx[edge.in_id])
				net._edge_weight.append(edge.weight)
				edge_idx += 1
	net._edge_start[non_input_order.size()] = edge_idx
	net._node_order = non_input_order

	# Pre-allocate output
	net._cached_outputs.resize(net._output_ids.size())

	return net


func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
	## Feed inputs through network using array-indexed activations.
	# Set input activations
	for i in _input_ids.size():
		var idx: int = _id_to_idx[_input_ids[i]]
		if i < inputs.size():
			_activations_arr[idx] = inputs[i]
		else:
			_activations_arr[idx] = 0.0

	# Process non-input nodes in topological order
	for i in _node_order.size():
		var node_id: int = _node_order[i]
		var node_idx: int = _id_to_idx[node_id]
		var sum: float = _biases_arr[node_idx]
		var e_start: int = _edge_start[i]
		var e_end: int = _edge_start[i + 1]
		for e in range(e_start, e_end):
			sum += _activations_arr[_edge_source_idx[e]] * _edge_weight[e]
		_activations_arr[node_idx] = tanh(sum)

	# Extract outputs
	for i in _output_ids.size():
		_cached_outputs[i] = _activations_arr[_id_to_idx[_output_ids[i]]]

	return _cached_outputs


func get_activation(node_id: int) -> float:
	if _id_to_idx.has(node_id):
		return _activations_arr[_id_to_idx[node_id]]
	return 0.0


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
