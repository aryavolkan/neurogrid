class_name EcologySystem
extends RefCounted
## Phase 11: Behavioral ecology — predator/prey roles, territory, group bonuses, day/night, migration.

var world: GridWorld

# Day/night cycle
var _day_tick: int = 0
const DAY_CYCLE_LENGTH: int = 600  # Ticks per full day/night cycle
const NIGHT_METABOLISM_MULT: float = 0.7  # Lower metabolism at night
const NIGHT_SENSOR_MULT: float = 0.5  # Reduced sensor ranges at night
const DAY_SENSOR_MULT: float = 1.0

# Territory tracking: creature_id -> {center: Vector2i, ticks_in_area: int}
var _territories: Dictionary = {}
const TERRITORY_RADIUS: int = 5
const TERRITORY_ESTABLISH_TICKS: int = 100  # Ticks staying nearby to establish
const TERRITORY_DEFENSE_BONUS: float = 0.5  # Damage reduction in own territory
const TERRITORY_ATTACK_BONUS: float = 5.0  # Extra bite damage in own territory

# Migration: food hotspot shifts over time
var _migration_tick: int = 0
const MIGRATION_CYCLE: int = 5000  # Ticks per full migration cycle
var _food_hotspot: Vector2i = Vector2i(32, 32)
const HOTSPOT_RADIUS: int = 12
const HOTSPOT_FOOD_BONUS: float = 0.15  # Extra regen rate in hotspot


func _init(p_world: GridWorld) -> void:
	world = p_world
	_food_hotspot = Vector2i(world.width / 2, world.height / 2)


func update(tick: int, creatures: Dictionary) -> void:
	_day_tick = tick
	_migration_tick = tick

	# Update territories
	for creature_id in creatures:
		var creature: Creature = creatures[creature_id]
		_update_territory(creature)

	# Update food hotspot position (circular migration)
	_update_hotspot(tick)


func _update_territory(creature: Creature) -> void:
	var cid: int = creature.creature_id
	if not _territories.has(cid):
		_territories[cid] = {"center": creature.grid_pos, "ticks": 0}

	var info: Dictionary = _territories[cid]
	var dist: int = abs(creature.grid_pos.x - info.center.x) + abs(creature.grid_pos.y - info.center.y)

	if dist <= TERRITORY_RADIUS:
		info.ticks += 1
	else:
		# Moved too far — reset territory center
		info.center = creature.grid_pos
		info.ticks = 0


func _update_hotspot(tick: int) -> void:
	var phase: float = float(tick % MIGRATION_CYCLE) / float(MIGRATION_CYCLE) * TAU
	var cx: int = world.width / 2
	var cy: int = world.height / 2
	var radius: float = float(mini(cx, cy)) * 0.6
	_food_hotspot = Vector2i(
		int(cx + cos(phase) * radius),
		int(cy + sin(phase) * radius)
	)


func remove_creature(creature_id: int) -> void:
	_territories.erase(creature_id)


# --- Queries used by other systems ---

func is_night() -> bool:
	var phase: float = float(_day_tick % DAY_CYCLE_LENGTH) / float(DAY_CYCLE_LENGTH)
	return phase > 0.5  # Second half of cycle = night


func get_metabolism_multiplier() -> float:
	return NIGHT_METABOLISM_MULT if is_night() else 1.0


func get_sensor_multiplier() -> float:
	return NIGHT_SENSOR_MULT if is_night() else DAY_SENSOR_MULT


func has_territory(creature_id: int) -> bool:
	if not _territories.has(creature_id):
		return false
	return _territories[creature_id].ticks >= TERRITORY_ESTABLISH_TICKS


func is_in_own_territory(creature: Creature) -> bool:
	if not has_territory(creature.creature_id):
		return false
	var info: Dictionary = _territories[creature.creature_id]
	var dist: int = abs(creature.grid_pos.x - info.center.x) + abs(creature.grid_pos.y - info.center.y)
	return dist <= TERRITORY_RADIUS


func get_territory_defense_bonus(creature: Creature) -> float:
	## Returns damage reduction (0.0 to TERRITORY_DEFENSE_BONUS) when in own territory.
	if is_in_own_territory(creature):
		return TERRITORY_DEFENSE_BONUS
	return 0.0


func get_territory_attack_bonus(creature: Creature) -> float:
	## Returns extra bite damage when in own territory.
	if is_in_own_territory(creature):
		return TERRITORY_ATTACK_BONUS
	return 0.0


func get_group_fitness_bonus(creature: Creature, creatures: Dictionary) -> float:
	## Allied creatures (same species) within range 4 provide a fitness bonus.
	var allies: int = 0
	var nearby := world.find_creatures_in_range(creature.grid_pos, 4)
	for info in nearby:
		if creatures.has(info.id):
			var other: Creature = creatures[info.id]
			if other.body.species_id == creature.body.species_id:
				allies += 1
	return float(allies) * 0.5  # 0.5 fitness per nearby ally


func get_food_hotspot() -> Vector2i:
	return _food_hotspot


func is_in_hotspot(pos: Vector2i) -> bool:
	var dist: int = abs(pos.x - _food_hotspot.x) + abs(pos.y - _food_hotspot.y)
	return dist <= HOTSPOT_RADIUS


func get_hotspot_food_bonus(pos: Vector2i) -> float:
	## Extra food regen rate for tiles near the migration hotspot.
	if is_in_hotspot(pos):
		return HOTSPOT_FOOD_BONUS
	return 0.0


func get_kill_energy_bonus(attacker: Creature, victim: Creature) -> float:
	## Predator bonus: carnivores (creatures with bite skill) gain energy from kills.
	## Returns energy to award to attacker.
	if attacker.genome.get_skill_registry_ids().has(GameConfig.SKILL_BITE):
		return victim.body.energy * 0.3  # Gain 30% of victim's remaining energy
	return 0.0


func get_herbivore_food_bonus(creature: Creature) -> float:
	## Herbivores (creatures WITHOUT bite/poison) get 50% more from food.
	var skill_ids := creature.genome.get_skill_registry_ids()
	if not skill_ids.has(GameConfig.SKILL_BITE) and not skill_ids.has(GameConfig.SKILL_POISON_SPIT):
		return 0.5  # 50% food bonus
	return 0.0
