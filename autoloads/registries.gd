extends Node
## Singleton holding ReceptorRegistry and SkillRegistry.
## These are fixed catalogs defined at design time.

var receptor_registry: ReceptorRegistry
var skill_registry: SkillRegistry


func _ready() -> void:
	receptor_registry = ReceptorRegistry.new()
	skill_registry = SkillRegistry.new()


class ReceptorEntry:
	var id: int
	var name: String
	var sensing_range: int
	var energy_cost: float  # Per-tick cost to maintain
	var description: String

	func _init(p_id: int, p_name: String, p_range: int, p_cost: float, p_desc: String) -> void:
		id = p_id
		name = p_name
		sensing_range = p_range
		energy_cost = p_cost
		description = p_desc


class SkillEntry:
	var id: int
	var name: String
	var energy_cost: float  # Per activation
	var cooldown: float  # Seconds
	var category: String
	var activation_threshold: float
	var description: String

	func _init(p_id: int, p_name: String, p_cost: float, p_cd: float,
			p_cat: String, p_desc: String, p_thresh: float = 0.5) -> void:
		id = p_id
		name = p_name
		energy_cost = p_cost
		cooldown = p_cd
		category = p_cat
		description = p_desc
		activation_threshold = p_thresh


class ReceptorRegistry:
	var entries: Array = []  # Array[ReceptorEntry]

	func _init() -> void:
		_register_defaults()

	func _register_defaults() -> void:
		entries.append(ReceptorEntry.new(0, "smell_food_dist", 5, 0.1, "Distance to nearest food (normalized)"))
		entries.append(ReceptorEntry.new(1, "smell_food_dx", 5, 0.1, "X direction to nearest food"))
		entries.append(ReceptorEntry.new(2, "smell_food_dy", 5, 0.1, "Y direction to nearest food"))
		entries.append(ReceptorEntry.new(3, "sense_enemy_dist", 4, 0.1, "Distance to nearest enemy"))
		entries.append(ReceptorEntry.new(4, "sense_enemy_dx", 4, 0.1, "X direction to nearest enemy"))
		entries.append(ReceptorEntry.new(5, "sense_ally_count", 4, 0.1, "Count of same-species allies nearby"))
		entries.append(ReceptorEntry.new(6, "detect_pheromone", 3, 0.1, "Pheromone concentration at position"))
		entries.append(ReceptorEntry.new(7, "sense_terrain", 1, 0.05, "Current tile type encoded as float"))

	func get_entry(id: int) -> ReceptorEntry:
		if id >= 0 and id < entries.size():
			return entries[id]
		return null

	func get_count() -> int:
		return entries.size()

	func get_random_id() -> int:
		return randi() % entries.size()


class SkillRegistry:
	var entries: Array = []  # Array[SkillEntry]

	func _init() -> void:
		_register_defaults()

	func _register_defaults() -> void:
		entries.append(SkillEntry.new(0, "dash", 3.0, 2.0, "movement", "Move 3 tiles in facing direction"))
		entries.append(SkillEntry.new(1, "bite", 1.5, 1.0, "combat", "15 damage to adjacent creature"))
		entries.append(SkillEntry.new(2, "poison_spit", 4.0, 3.0, "combat", "5 dmg/tick for 5 ticks, range 2"))
		entries.append(SkillEntry.new(3, "emit_pheromone", 1.0, 2.0, "social", "Deposit pheromone at current tile"))
		entries.append(SkillEntry.new(4, "share_food", 2.0, 3.0, "social", "Transfer 5 energy to adjacent ally"))
		entries.append(SkillEntry.new(5, "build_wall", 5.0, 5.0, "defense", "Place wall on adjacent tile"))
		entries.append(SkillEntry.new(6, "heal_self", 3.0, 4.0, "defense", "Restore 10 health"))
		entries.append(SkillEntry.new(7, "burrow", 2.0, 6.0, "defense", "Burrow underground for 5 ticks, immune to damage"))

	func get_entry(id: int) -> SkillEntry:
		if id >= 0 and id < entries.size():
			return entries[id]
		return null

	func get_count() -> int:
		return entries.size()

	func get_random_id() -> int:
		return randi() % entries.size()
