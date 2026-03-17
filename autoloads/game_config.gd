extends Node
## Global game configuration singleton.

# Grid
const GRID_WIDTH: int = 64
const GRID_HEIGHT: int = 64
const TILE_SIZE: int = 16  # Pixels per tile

# Population
const MAX_CREATURES: int = 300
const MIN_CREATURES: int = 20
const INITIAL_POPULATION: int = 50

# Creature defaults
const STARTING_ENERGY: float = 50.0
const MAX_ENERGY: float = 100.0
const MAX_HEALTH: float = 30.0
const MAX_AGE: int = 2000  # Ticks

# Energy costs
const BASE_METABOLISM: float = 0.5  # Per tick
const MOVEMENT_COST: float = 0.2  # Per tile moved
const REPRODUCTION_COST: float = 30.0
const REPRODUCTION_ENERGY_THRESHOLD: float = 40.0
const OFFSPRING_ENERGY: float = 20.0

# Reproduction
const MATE_DESIRE_THRESHOLD: float = 0.5
const REPRODUCTION_COOLDOWN: float = 30.0  # Seconds (converted to ticks at runtime)
const MATING_COMPATIBILITY_THRESHOLD: float = 3.0

# Food
const MAX_FOOD_PER_TILE: float = 20.0
const FOOD_REGEN_RATE: float = 0.05  # Per tick
const FOOD_SPAWN_DENSITY: float = 0.15  # Fraction of grass/forest tiles with food

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
const ADD_NODE_RATE: float = 0.03
const ADD_CONNECTION_RATE: float = 0.05
const DISABLE_CONNECTION_RATE: float = 0.01
const CROSSOVER_RATE: float = 0.75
const COMPATIBILITY_THRESHOLD: float = 3.0

# Terrain types
enum Terrain { GRASS, FOREST, WATER, ROCK, SAND }
