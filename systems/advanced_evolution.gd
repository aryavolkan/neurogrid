class_name AdvancedEvolution
extends RefCounted
## Phase 12: Advanced evolution — neuromodulation, sexual selection, ontogeny,
## coevolutionary arms races, and speciation event tracking.


# --- Neuromodulation ---
# Each connection can have a learning_rate that modifies its weight during lifetime
# based on pre/post-synaptic activity (Hebbian-like learning).

static func apply_neuromodulation(genome: DynamicGenome, network: DynamicNetwork, reward: float) -> void:
	## Modify connection weights during creature's lifetime based on reward signal.
	## Connections with learning_rate != 0 get weight adjustments proportional to
	## reward * learning_rate * pre_activation * post_activation.
	for conn in genome.connection_genes:
		if not conn.enabled or conn.learning_rate == 0.0:
			continue
		var pre_act: float = network.get_activation(conn.in_id)
		var post_act: float = network.get_activation(conn.out_id)
		var delta: float = conn.learning_rate * reward * pre_act * post_act
		conn.weight = clampf(conn.weight + delta, -4.0, 4.0)


# --- Sexual Selection ---
# Mate preference score based on genome traits. Creatures evolve preferences
# for mates with certain characteristics (complexity, skill count, etc.).

static func compute_mate_preference(chooser: DynamicGenome, candidate: DynamicGenome) -> float:
	## Returns a preference score (higher = more preferred).
	## Based on chooser's evolved preference weights applied to candidate traits.
	var score: float = 0.0

	# Trait 1: genome complexity (node count) — preference for complex or simple mates
	var complexity_trait: float = float(candidate.node_genes.size()) / 20.0
	score += chooser.mate_pref_complexity * complexity_trait

	# Trait 2: skill diversity — preference for mates with many skills
	var skill_trait: float = float(candidate.get_skill_count()) / 5.0
	score += chooser.mate_pref_skills * skill_trait

	# Trait 3: receptor count — preference for perceptive mates
	var receptor_trait: float = float(candidate.get_receptor_count()) / 5.0
	score += chooser.mate_pref_receptors * receptor_trait

	# Trait 4: fitness — preference for high-fitness mates
	var fitness_trait: float = clampf(candidate.fitness / 10.0, 0.0, 1.0)
	score += chooser.mate_pref_fitness * fitness_trait

	return score


# --- Ontogeny ---
# Genome expression changes with age. Juveniles have restricted capabilities.

const JUVENILE_AGE: int = 200  # Ticks before reaching adulthood
const JUVENILE_METABOLISM_MULT: float = 0.6  # Lower metabolism as juvenile
const JUVENILE_SKILL_BLOCK: bool = true  # Juveniles can't use skills

static func is_juvenile(age: int) -> bool:
	return age < JUVENILE_AGE


static func get_ontogeny_metabolism_mult(age: int) -> float:
	if age < JUVENILE_AGE:
		return JUVENILE_METABOLISM_MULT
	return 1.0


static func can_use_skills(age: int) -> bool:
	if JUVENILE_SKILL_BLOCK and age < JUVENILE_AGE:
		return false
	return true


# --- Coevolutionary Arms Races ---
# Track competitive interactions between species and reward escalation.

var _species_interactions: Dictionary = {}  # "attacker_sp:defender_sp" -> {attacks, kills, damage}


func record_interaction(attacker_species: int, defender_species: int, damage: float, killed: bool) -> void:
	if attacker_species == defender_species:
		return  # Intra-species doesn't count
	var key: String = "%d:%d" % [attacker_species, defender_species]
	if not _species_interactions.has(key):
		_species_interactions[key] = {"attacks": 0, "kills": 0, "damage": 0.0}
	_species_interactions[key].attacks += 1
	_species_interactions[key].damage += damage
	if killed:
		_species_interactions[key].kills += 1


func get_coevolution_bonus(species_id: int) -> float:
	## Species that actively engage in inter-species combat get a fitness bonus.
	## Rewards both predators (killing) and prey (surviving attacks).
	var attack_score: float = 0.0
	var defense_score: float = 0.0

	for key in _species_interactions:
		var parts: PackedStringArray = key.split(":")
		var attacker: int = int(parts[0])
		var defender: int = int(parts[1])
		var info: Dictionary = _species_interactions[key]

		if attacker == species_id:
			attack_score += float(info.kills) * 2.0 + info.damage / 100.0
		if defender == species_id:
			# Surviving attacks is valuable
			defense_score += float(info.attacks - info.kills) * 0.5

	return (attack_score + defense_score) * 0.1


func reset_interactions() -> void:
	_species_interactions.clear()


func get_interaction_report() -> String:
	if _species_interactions.is_empty():
		return "  No inter-species interactions"
	var lines: Array = []
	for key in _species_interactions:
		var info: Dictionary = _species_interactions[key]
		lines.append("  %s: %d attacks, %d kills, %.1f dmg" % [key, info.attacks, info.kills, info.damage])
	return "\n".join(lines)
