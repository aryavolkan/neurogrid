class_name DynamicConfig
extends RefCounted
## NEAT config extended with dynamic I/O mutation rates.

# Wraps a NeatConfig and adds new fields for receptor/skill evolution.

var neat_config: NeatConfig

# Dynamic I/O rates
var add_receptor_rate: float = 0.01
var add_skill_rate: float = 0.008
var remove_receptor_rate: float = 0.005
var remove_skill_rate: float = 0.005
var max_receptors: int = 12
var max_skills: int = 10

# I/O compatibility weight
var c4_io_diff: float = 1.0


func _init() -> void:
	neat_config = NeatConfig.new()
	neat_config.input_count = GameConfig.CORE_INPUT_COUNT
	neat_config.output_count = GameConfig.CORE_OUTPUT_COUNT
	neat_config.use_bias = false
	neat_config.allow_recurrent = false
	neat_config.population_size = GameConfig.INITIAL_POPULATION
	neat_config.compatibility_threshold = GameConfig.COMPATIBILITY_THRESHOLD
	neat_config.weight_mutate_rate = GameConfig.WEIGHT_MUTATE_RATE
	neat_config.weight_perturb_rate = GameConfig.WEIGHT_PERTURB_RATE
	neat_config.weight_perturb_strength = GameConfig.WEIGHT_PERTURB_STRENGTH
	neat_config.add_node_rate = GameConfig.ADD_NODE_RATE
	neat_config.add_connection_rate = GameConfig.ADD_CONNECTION_RATE
	neat_config.disable_connection_rate = GameConfig.DISABLE_CONNECTION_RATE
	neat_config.crossover_rate = GameConfig.CROSSOVER_RATE
	neat_config.initial_connection_fraction = 0.3
	neat_config.target_species_count = 8
