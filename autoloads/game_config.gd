extends Node
## Global game configuration singleton.

# Grid
const GRID_WIDTH: int = 64
const GRID_HEIGHT: int = 64
const TILE_SIZE: int = 16  # Pixels per tile

# Population
const MAX_CREATURES: int = 300
const MIN_CREATURES: int = 40
static var INITIAL_POPULATION: int = 80

# Creature defaults
const STARTING_ENERGY: float = 80.0
const MAX_ENERGY: float = 150.0
const MAX_HEALTH: float = 30.0
const MAX_AGE: int = 3000  # Ticks

# Energy costs
static var BASE_METABOLISM: float = 0.15  # Per tick (was 0.5 — too harsh for random networks)
const MOVEMENT_COST: float = 0.1  # Per tile moved
const REPRODUCTION_COST: float = 10.0
static var REPRODUCTION_ENERGY_THRESHOLD: float = 35.0
const OFFSPRING_ENERGY: float = 30.0

# Reproduction
const MATE_DESIRE_THRESHOLD: float = 0.3
const REPRODUCTION_COOLDOWN: float = 10.0  # Seconds
const MATING_COMPATIBILITY_THRESHOLD: float = 25.0  # Very loose — random genomes have dist ~10-18

# Food
const MAX_FOOD_PER_TILE: float = 20.0
static var FOOD_REGEN_RATE: float = 0.08  # Per tick
const FOOD_SPAWN_DENSITY: float = 0.25  # Fraction of grass/forest tiles with food

# Simulation
const TICKS_PER_SECOND: int = 30
var speed_multiplier: float = 1.0
var paused: bool = false

# Core I/O counts (always present, never evolved)
const CORE_INPUT_COUNT: int = 8   # energy, health, age, pos_x, pos_y, vel_x, vel_y, food_here
const CORE_OUTPUT_COUNT: int = 4  # move_x, move_y, eat_desire, mate_desire

# NEAT config
const WEIGHT_MUTATE_RATE: float = 0.8
const WEIGHT_PERTURB_RATE: float = 0.9
const WEIGHT_PERTURB_STRENGTH: float = 0.3
static var ADD_NODE_RATE: float = 0.03
static var ADD_CONNECTION_RATE: float = 0.05
const DISABLE_CONNECTION_RATE: float = 0.01
const CROSSOVER_RATE: float = 0.75
const COMPATIBILITY_THRESHOLD: float = 3.0

# Terrain types
enum Terrain { GRASS, FOREST, WATER, ROCK, SAND }

# --- Sweep support: override/restore sweepable parameters ---

static var _defaults: Dictionary = {
	"INITIAL_POPULATION": 80,
	"BASE_METABOLISM": 0.15,
	"REPRODUCTION_ENERGY_THRESHOLD": 35.0,
	"FOOD_REGEN_RATE": 0.08,
	"ADD_NODE_RATE": 0.03,
	"ADD_CONNECTION_RATE": 0.05,
}


static func apply_overrides(overrides: Dictionary) -> void:
	for key in overrides:
		match key:
			"INITIAL_POPULATION":
				INITIAL_POPULATION = int(overrides[key])
			"BASE_METABOLISM":
				BASE_METABOLISM = float(overrides[key])
			"REPRODUCTION_ENERGY_THRESHOLD":
				REPRODUCTION_ENERGY_THRESHOLD = float(overrides[key])
			"FOOD_REGEN_RATE":
				FOOD_REGEN_RATE = float(overrides[key])
			"ADD_NODE_RATE":
				ADD_NODE_RATE = float(overrides[key])
			"ADD_CONNECTION_RATE":
				ADD_CONNECTION_RATE = float(overrides[key])
			_:
				push_warning("Unknown sweep param: " + key)


static func restore_defaults() -> void:
	INITIAL_POPULATION = int(_defaults["INITIAL_POPULATION"])
	BASE_METABOLISM = float(_defaults["BASE_METABOLISM"])
	REPRODUCTION_ENERGY_THRESHOLD = float(_defaults["REPRODUCTION_ENERGY_THRESHOLD"])
	FOOD_REGEN_RATE = float(_defaults["FOOD_REGEN_RATE"])
	ADD_NODE_RATE = float(_defaults["ADD_NODE_RATE"])
	ADD_CONNECTION_RATE = float(_defaults["ADD_CONNECTION_RATE"])
