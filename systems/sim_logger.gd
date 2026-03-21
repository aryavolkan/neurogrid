class_name SimLogger
extends RefCounted
## Aggregates per-tick and per-generation simulation events for exhaustive logging.

# Per-tick counters (reset each tick)
var moves: int = 0
var moves_blocked: int = 0
var eats: int = 0
var food_consumed: float = 0.0
var corpse_consumed: float = 0.0
var skills_fired: Array = [0, 0, 0, 0, 0, 0, 0, 0]  # Indexed by skill ID (8 skills)
var bites_hit: int = 0
var poisons_hit: int = 0
var reproductions: int = 0
var mate_attempts: int = 0
var mate_no_partner: int = 0
var births: int = 0
var deaths: int = 0
var deaths_energy: int = 0
var deaths_health: int = 0
var deaths_age: int = 0
var spawns_random: int = 0  # Population maintenance spawns

# Per-generation accumulators (reset each generation)
var gen_moves: int = 0
var gen_eats: int = 0
var gen_food_total: float = 0.0
var gen_skills: Array = [0, 0, 0, 0, 0, 0, 0, 0]  # Indexed by skill ID
var gen_reproductions: int = 0
var gen_births: int = 0
var gen_deaths: int = 0
var gen_deaths_energy: int = 0
var gen_deaths_health: int = 0
var gen_deaths_age: int = 0
var gen_spawns_random: int = 0
var gen_bites: int = 0
var gen_poisons: int = 0

# Death location tracking (for heatmaps)
var death_locations: Array = []  # Array[Vector2i]

# Lifetime stats
var total_births: int = 0
var total_deaths: int = 0
var total_reproductions: int = 0
var longest_lived_age: int = 0
var longest_lived_id: int = -1
var most_offspring_count: int = 0
var most_offspring_id: int = -1
var total_offspring_by_id: Dictionary = {}  # creature_id -> offspring count


func end_tick() -> void:
	## Roll tick counters into generation accumulators.
	gen_moves += moves
	gen_eats += eats
	gen_food_total += food_consumed + corpse_consumed
	gen_reproductions += reproductions
	gen_births += births
	gen_deaths += deaths
	gen_deaths_energy += deaths_energy
	gen_deaths_health += deaths_health
	gen_deaths_age += deaths_age
	gen_spawns_random += spawns_random
	gen_bites += bites_hit
	gen_poisons += poisons_hit
	for i in 8:
		gen_skills[i] += skills_fired[i]

	total_births += births
	total_deaths += deaths
	total_reproductions += reproductions

	# Reset tick counters
	moves = 0
	moves_blocked = 0
	eats = 0
	food_consumed = 0.0
	corpse_consumed = 0.0
	skills_fired = [0, 0, 0, 0, 0, 0, 0, 0]
	bites_hit = 0
	poisons_hit = 0
	reproductions = 0
	mate_attempts = 0
	mate_no_partner = 0
	births = 0
	deaths = 0
	deaths_energy = 0
	deaths_health = 0
	deaths_age = 0
	spawns_random = 0


func get_gen_report() -> String:
	var lines: Array = []
	lines.append("  Moves: %d | Eats: %d | Food consumed: %.1f" % [gen_moves, gen_eats, gen_food_total])
	lines.append("  Deaths: %d (energy: %d, health: %d, age: %d)" % [
		gen_deaths, gen_deaths_energy, gen_deaths_health, gen_deaths_age])
	lines.append("  Births: %d (reproduced: %d, random spawn: %d)" % [gen_births, gen_reproductions, gen_spawns_random])
	lines.append("  Bites landed: %d | Poisons hit: %d" % [gen_bites, gen_poisons])
	var skill_names: Array = ["dash", "bite", "poison_spit", "emit_pheromone",
		"share_food", "build_wall", "heal_self", "burrow"]
	var skill_parts: Array = []
	for i in 8:
		if gen_skills[i] > 0:
			skill_parts.append("%s: %d" % [skill_names[i], gen_skills[i]])
	if not skill_parts.is_empty():
		lines.append("  Skills: %s" % ", ".join(skill_parts))
	else:
		lines.append("  Skills: none fired")
	return "\n".join(lines)


func reset_generation() -> void:
	gen_moves = 0
	gen_eats = 0
	gen_food_total = 0.0
	gen_skills = [0, 0, 0, 0, 0, 0, 0, 0]
	gen_reproductions = 0
	gen_births = 0
	gen_deaths = 0
	gen_deaths_energy = 0
	gen_deaths_health = 0
	gen_deaths_age = 0
	gen_spawns_random = 0
	gen_bites = 0
	gen_poisons = 0


func record_death(creature_id: int, body: CreatureBody, death_pos: Vector2i = Vector2i(-1, -1)) -> void:
	deaths += 1
	if body.energy <= 0.0:
		deaths_energy += 1
	elif body.health <= 0.0:
		deaths_health += 1
	elif body.age >= GameConfig.MAX_AGE:
		deaths_age += 1
	else:
		deaths_energy += 1  # Fallback

	if death_pos.x >= 0:
		death_locations.append(death_pos)

	if body.age > longest_lived_age:
		longest_lived_age = body.age
		longest_lived_id = creature_id


func record_skill_by_id(skill_id: int) -> void:
	## Record a skill activation by skill registry ID (faster than string key).
	if skill_id >= 0 and skill_id < 8:
		skills_fired[skill_id] += 1


func record_skill(skill_name: String) -> void:
	## Legacy string-based skill recording. Prefer record_skill_by_id().
	# Map skill name to ID for backward compatibility
	var skill_names: Array = ["dash", "bite", "poison_spit", "emit_pheromone",
		"share_food", "build_wall", "heal_self", "burrow"]
	var idx: int = skill_names.find(skill_name)
	if idx >= 0:
		skills_fired[idx] += 1


func get_lifetime_report() -> String:
	var lines: Array = []
	lines.append("Total births: %d | Total deaths: %d | Total reproductions: %d" % [
		total_births, total_deaths, total_reproductions])
	lines.append("Longest lived: creature #%d (age %d ticks)" % [longest_lived_id, longest_lived_age])
	lines.append("Most offspring: creature #%d (%d offspring)" % [most_offspring_id, most_offspring_count])
	return "\n".join(lines)
