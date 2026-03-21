class_name CreatureBrain
extends RefCounted
## Wraps a DynamicNetwork. Assembles inputs from core + receptors, runs forward pass.

var network: DynamicNetwork
var genome: DynamicGenome
var sensor: CreatureSensor

# Cached last think() values for debug overlay
var last_inputs: PackedFloat32Array
var last_outputs: PackedFloat32Array

# Cached receptor energy cost (computed once at init, doesn't change during lifetime)
var _receptor_energy_cost: float = 0.0


func _init(p_genome: DynamicGenome, p_sensor: CreatureSensor) -> void:
	genome = p_genome
	sensor = p_sensor
	network = DynamicNetwork.from_genome(genome)
	# Pre-compute receptor energy cost
	for receptor_info in network.get_receptor_order():
		var entry = Registries.receptor_registry.get_entry(receptor_info.registry_id)
		if entry:
			_receptor_energy_cost += entry.energy_cost


func think(pos: Vector2i, body: CreatureBody, creature_id: int) -> PackedFloat32Array:
	## Run the neural network and return output array.
	## Output layout: [move_x, move_y, eat_desire, mate_desire, skill_0, skill_1, ...]
	var inputs := PackedFloat32Array()

	# Core inputs
	var core := sensor.get_core_inputs(pos, body)
	inputs.append_array(core)

	# Receptor inputs (in the order stored in the network)
	for receptor_info in network.get_receptor_order():
		var val: float = sensor.get_receptor_value(receptor_info.registry_id, pos, body, creature_id)
		inputs.append(val)

	last_inputs = inputs
	var result := network.forward(inputs)
	last_outputs = result
	return result


func get_receptor_energy_cost() -> float:
	## Total per-tick energy cost of all active receptors (cached at init).
	return _receptor_energy_cost


func get_skill_nodes() -> Array:
	## Returns array of {node_id, registry_id} for skill outputs.
	return network.get_skill_order()
