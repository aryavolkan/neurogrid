# NeuroGrid

A 2D grid-based evolutionary simulation sandbox built in Godot 4.5+ (GDScript). Creatures evolve neural networks, sensory organs, and behavioral abilities through a novel extension of the NEAT algorithm — **Dynamic I/O NEAT** — where input/output neuron sets are themselves subject to evolution.

## What Makes This Different

Standard NEAT fixes the number of inputs and outputs. NeuroGrid introduces two new evolvable node types:

- **Receptors** — evolved sensory inputs drawn from an 8-entry registry (e.g. smell food distance, detect pheromone, sense terrain)
- **Skills** — evolved action outputs drawn from an 8-entry registry (e.g. dash, bite, poison spit, emit pheromone, heal self)

Each receptor/skill carries an `io_innovation` number for proper alignment during crossover, enabling creatures to sexually reproduce even when their sensor/action layouts differ.

## Features

### Simulation
- **Sense → Think → Act loop** with NEAT-based neural networks
- **64x64 procedural world** with terrain types (grass, forest, water, rock, sand), elevation, and passability
- **Food ecology** — global budget cap, sinusoidal scarcity cycles, forest regen bonus, migrating hotspots
- **Pheromone layer** with deposit, decay, and diffusion
- **Weather system** — rain (food bonus), storms (damage), fog (reduced sensor range)
- **Dynamic terrain** — vegetation growth, water erosion
- **Resources** — minerals near rocks, medicinal plants in forests, nesting sites at elevation

### Evolution
- **Dynamic I/O NEAT** — creatures evolve which senses and skills they possess
- **Sexual reproduction** with genome crossover and structural mutation
- **Speciation** — compatibility-based clustering with dynamic threshold
- **Multi-objective fitness** — survival, foraging, reproduction (NSGA-II support)
- **Neuromodulation** — Hebbian-like per-tick weight adjustment
- **Sexual selection** — 4 evolved mate preference weights (complexity, skills, receptors, fitness)
- **Ontogeny** — juvenile phase with reduced metabolism and blocked skills
- **Coevolutionary tracking** — inter-species interaction logging with escalation rewards

### Behavioral Ecology
- **Predator/prey roles** with energy bonuses for each strategy
- **Territory** — creatures establish home ranges with defense bonuses
- **Group bonuses** — fitness reward for nearby allies of the same species
- **Day/night cycles** — 600-tick period affecting metabolism and sensor range
- **Migration** — food hotspot circles the map over 5000-tick periods

### Analysis & Observability
- **Phylogenetic tracker** — species lineage, birth/extinction events, tree visualization (P key)
- **Genome diff tool** — structured comparison of any two genomes
- **Experiment runner** — CSV export of population, species, and generation stats
- **Batch parameter sweeper** — Cartesian product over sweepable params with multi-run aggregation
- **Simulation logger** — per-tick event counters (moves, eats, skills, births, deaths by cause)

### UI
- **HUD** with real-time stats
- **Camera** — WASD pan, scroll zoom, speed controls
- **Creature inspector** — click to view vitals, genome, receptors, skills
- **Stats panel** (Tab) — line graphs for population, species count, fitness
- **Genome viewer** (G) — network topology visualization
- **Heatmap overlay** (H) — spatial data visualization
- **Debug overlay** (F3) — spatial debug info

## Getting Started

### Prerequisites

- [Godot 4.5+](https://godotengine.org)
- Git with submodule support

### Installation

```bash
git clone --recursive https://github.com/aryavolkan/neurogrid.git
cd neurogrid
```

### Run

```bash
# Interactive (with UI)
godot --path .

# Editor
godot --path . --editor

# Headless (automated, 16x speed, auto-exports CSVs)
godot --path . --headless
```

### Run Tests

```bash
godot --path . --headless -s tests/test_runner.gd
```

9 test suites, 200+ tests covering genome operations, network topology, world systems, creature mechanics, fitness tracking, speciation, action execution, integration, and analysis tooling.

### Run Parameter Sweep

```bash
godot --path . --headless -- --sweep my_experiment \
  BASE_METABOLISM=0.1,0.15,0.2 \
  FOOD_REGEN_RATE=0.05,0.08 \
  --ticks 5000 --runs 3
```

Generates all parameter combinations, runs each for N ticks across M runs, and outputs aggregated CSVs to `user://experiments/`.

## Controls

| Key | Action |
|-----|--------|
| WASD / Arrows | Pan camera |
| Scroll wheel | Zoom |
| `[` / `]` | Slow down / speed up |
| Space | Pause / resume |
| Tab | Toggle stats panel |
| G | Toggle genome viewer |
| H | Toggle heatmap overlay |
| P | Toggle phylogeny panel |
| F3 | Toggle debug overlay |
| Click creature | Inspect vitals & genome |
| F5 / F9 | Save / load state |
| F6 | Export best genomes per species |
| F7 | Export CSV snapshots |

## Architecture

```
autoloads/       Global config (~70 hyperparameters) and receptor/skill registries
core/            Dynamic NEAT extension (genome, network, I/O innovation tracking)
entities/        Creature (body, brain, sensor) and corpse
world/           Grid, terrain, food, pheromone, weather, world generation
systems/         Simulation loop, actions, reproduction, speciation, ecology,
                 fitness, phylogeny, experiments, save/load
ui/              HUD, camera, inspector, stats, genome viewer, overlays
tests/           9 test suites (200+ tests)
evolve-core/     Git submodule — shared NEAT library
```

## Key Configuration

All parameters live in `GameConfig` (autoload). Notable sweepable params:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `INITIAL_POPULATION` | 80 | Starting creature count |
| `BASE_METABOLISM` | 0.15 | Energy cost per tick |
| `FOOD_REGEN_RATE` | 0.08 | Food regrowth per tick |
| `REPRODUCTION_THRESHOLD` | 35 | Min energy to reproduce |
| `ADD_NODE_RATE` | 0.03 | NEAT structural mutation rate |
| `ADD_CONNECTION_RATE` | 0.05 | NEAT connection mutation rate |

## License

See [LICENSE](LICENSE) for details.
