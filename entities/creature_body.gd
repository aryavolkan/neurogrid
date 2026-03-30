class_name CreatureBody
extends RefCounted
## Physical state of a creature: energy, health, age, cooldowns.

var energy: float = GameConfig.STARTING_ENERGY
var health: float = GameConfig.MAX_HEALTH
var age: int = 0  # Ticks alive
var reproduction_cooldown: float = 0.0  # Seconds remaining
var skill_cooldowns: Array = [0, 0, 0, 0, 0, 0, 0, 0]  # Indexed by skill ID
var facing: Vector2i = Vector2i(1, 0)  # Last movement direction
var poisoned_ticks: int = 0  # Poison damage remaining
var burrowed: bool = false  # Immune to damage when burrowed
var burrow_ticks: int = 0

# Species ID for compatibility (assigned by ecosystem)
var species_id: int = -1


func is_alive() -> bool:
	return energy > 0.0 and health > 0.0 and age < GameConfig.MAX_AGE


func can_reproduce() -> bool:
	return energy > GameConfig.REPRODUCTION_ENERGY_THRESHOLD and reproduction_cooldown <= 0.0


func take_damage(amount: float) -> void:
	if burrowed:
		return
	health = maxf(health - amount, 0.0)


func eat_food(amount: float) -> float:
	## Eat food, return amount actually consumed.
	var consumed := minf(amount, GameConfig.MAX_ENERGY - energy)
	energy += consumed
	return consumed


func apply_metabolism(receptor_cost: float) -> void:
	energy -= GameConfig.BASE_METABOLISM + receptor_cost


func apply_movement_cost() -> void:
	energy -= GameConfig.MOVEMENT_COST


func update_cooldowns(_delta: float) -> void:
	if reproduction_cooldown > 0.0:
		reproduction_cooldown -= 1.0

	for i in 8:
		if skill_cooldowns[i] > 0:
			skill_cooldowns[i] -= 1

	# Poison
	if poisoned_ticks > 0:
		health = maxf(health - 5.0, 0.0)
		poisoned_ticks -= 1

	# Burrow
	if burrow_ticks > 0:
		burrow_ticks -= 1
		if burrow_ticks <= 0:
			burrowed = false


func set_skill_cooldown(skill_id: int, ticks: int) -> void:
	if skill_id >= 0 and skill_id < 8:
		skill_cooldowns[skill_id] = ticks


func is_skill_ready(skill_id: int) -> bool:
	if skill_id >= 0 and skill_id < 8:
		return skill_cooldowns[skill_id] <= 0
	return false
