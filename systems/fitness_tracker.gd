class_name FitnessTracker
extends RefCounted
## Tracks per-creature lifetime metrics and computes fitness on death.
## Fitness = weighted composite of survival, energy, and reproduction.

# Lifetime accumulators per creature_id
var _energy_gathered: Dictionary = {}  # creature_id -> float
var _offspring_count: Dictionary = {}  # creature_id -> int
var _food_eaten: Dictionary = {}       # creature_id -> float
var _damage_dealt: Dictionary = {}     # creature_id -> float

# Weights for fitness components
const W_SURVIVAL: float = 1.0     # Per tick alive (normalized by MAX_AGE)
const W_ENERGY: float = 0.5       # Total energy gathered over lifetime
const W_OFFSPRING: float = 3.0    # Per offspring produced
const W_FOOD: float = 0.3         # Total food consumed
const W_DAMAGE: float = 0.2       # Total damage dealt


func register(creature_id: int) -> void:
	_energy_gathered[creature_id] = 0.0
	_offspring_count[creature_id] = 0
	_food_eaten[creature_id] = 0.0
	_damage_dealt[creature_id] = 0.0


func record_energy_gained(creature_id: int, amount: float) -> void:
	_energy_gathered[creature_id] = _energy_gathered.get(creature_id, 0.0) + amount


func record_offspring(creature_id: int) -> void:
	_offspring_count[creature_id] = _offspring_count.get(creature_id, 0) + 1


func record_food_eaten(creature_id: int, amount: float) -> void:
	_food_eaten[creature_id] = _food_eaten.get(creature_id, 0.0) + amount


func record_damage_dealt(creature_id: int, amount: float) -> void:
	_damage_dealt[creature_id] = _damage_dealt.get(creature_id, 0.0) + amount


func compute_fitness(creature_id: int, age: int) -> float:
	## Compute scalar fitness for a creature (typically called on death).
	var survival := float(age) / float(GameConfig.MAX_AGE) * W_SURVIVAL
	var energy := _energy_gathered.get(creature_id, 0.0) / GameConfig.MAX_ENERGY * W_ENERGY
	var offspring := float(_offspring_count.get(creature_id, 0)) * W_OFFSPRING
	var food := _food_eaten.get(creature_id, 0.0) / 100.0 * W_FOOD
	var damage := _damage_dealt.get(creature_id, 0.0) / 100.0 * W_DAMAGE
	return survival + energy + offspring + food + damage


func compute_objectives(creature_id: int, age: int) -> Vector3:
	## Multi-objective fitness: (survival, foraging, reproduction)
	var survival := float(age) / float(GameConfig.MAX_AGE)
	var foraging := _food_eaten.get(creature_id, 0.0) / 100.0
	var reproduction := float(_offspring_count.get(creature_id, 0))
	return Vector3(survival, foraging, reproduction)


func unregister(creature_id: int) -> void:
	_energy_gathered.erase(creature_id)
	_offspring_count.erase(creature_id)
	_food_eaten.erase(creature_id)
	_damage_dealt.erase(creature_id)
