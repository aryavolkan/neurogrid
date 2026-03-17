class_name CreatureBrain
extends RefCounted
## Wraps a DynamicNetwork. Assembles inputs from core + receptors, runs forward pass.

var network: DynamicNetwork
var genome: DynamicGenome
var sensor: CreatureSensor

# Cached last think() values for debug overlay
var last_inputs: PackedFloat32Array
var last_outputs: PackedFloat32Array


func _init(p_genome: DynamicGenome, p_sensor: CreatureSensor) -> void:
	genome = p_genome
	sensor = p_sensor
	network = DynamicNetwork.from_genome(genome)


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

	last_inputs = inputs.duplicate()
	var result := network.forward(inputs)
	last_outputs = result.duplicate()
	return result


func get_receptor_energy_cost() -> float:
	## Total per-tick energy cost of all active receptors.
	var cost: float = 0.0
	for receptor_info in network.get_receptor_order():
		var entry = Registries.receptor_registry.get_entry(receptor_info.registry_id)
		if entry:
			cost += entry.energy_cost
	return cost


func get_skill_nodes() -> Array:
	## Returns array of {node_id, registry_id} for skill outputs.
	return network.get_skill_order()
