# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NeuroGrid is a 2D grid sandbox (Godot 4.5+, GDScript) where NEAT agents evolve dynamic receptors (senses) and skills (abilities) through sexual reproduction.

## Running

```bash
godot --path . --editor   # Open in editor
godot --path .            # Run directly
godot --path . --headless # Run headless (auto-detects, prints stats, 16x speed)
```

## Running Tests

```bash
godot --path . --headless -s tests/test_runner.gd
```

8 test suites, 147 tests covering genome, network, world, creature body, fitness, species, action system, and integration.

## Architecture

### Core Innovation: Dynamic I/O NEAT

Standard NEAT has fixed inputs/outputs. NeuroGrid extends this with two new node types:
- **type 3 = receptor** — evolved sensory input, drawn from `ReceptorRegistry` (8 available: food/enemy/ally/pheromone/terrain sensing)
- **type 4 = skill** — evolved action output, drawn from `SkillRegistry` (8 available: dash/bite/poison/pheromone/share_food/build_wall/heal/burrow)

Each receptor/skill gets an `io_innovation` number (via `IoInnovation` tracker) so crossover can align them across genomes, exactly like connection gene innovations in standard NEAT.

### Layer Diagram

```
Autoloads (GameConfig, Registries)
     ↓
Core NEAT Extension (DynamicGenome → DynamicNetwork, IoInnovation, DynamicConfig)
     ↓                    ↑ extends
evolve-core submodule (NeatGenome, NeatNetwork, NeatEvolution, NeatSpecies, NSGA2)
     ↓
Entities (Creature = Node2D visual + CreatureBody state + CreatureBrain network + CreatureSensor)
     ↓
World (GridWorld 64×64 + GridTile + FoodManager + PheromoneLayer + WorldGenerator)
     ↓
Systems (SimulationManager tick loop, ActionSystem, ReproductionSystem, CreatureSpawner)
```

### Key Data Flow

Each simulation tick: creatures sense → think (NEAT forward pass) → act → world updates.

- `CreatureSensor` reads from `GridWorld` (spatial queries, tile data)
- `CreatureBrain.think()` assembles `[core_inputs..., receptor_inputs...]`, runs `DynamicNetwork.forward()`, returns `[core_outputs..., skill_outputs...]`
- Core inputs (8): energy, health, age, pos_x, pos_y, facing_x, facing_y, food_here
- Core outputs (4): move_x, move_y, eat_desire, mate_desire
- Network input/output order must match genome node ordering

### Genome Mutation Types

Standard NEAT mutations plus dynamic I/O:
- `add_receptor` / `remove_receptor` (max 12 receptors per genome)
- `add_skill` / `remove_skill` (max 10 skills per genome)
- Compatibility distance includes `c4_io_diff` term for I/O set differences

### evolve-core Submodule

Shared NEAT library at `evolve-core/`. Do not modify files there directly — changes go in that repo.

Key classes used by NeuroGrid:
- `NeatGenome` (genotype), `NeatNetwork` (phenotype with topological sort + tanh activation)
- `NeatEvolution` (speciation + reproduction loop), `NeatSpecies` (fitness sharing, stagnation)
- `NSGA2` (multi-objective: Pareto fronts + crowding distance)
- Interfaces: `IAgent`, `ISensor`, `IReward` in `evolve-core/interfaces/`
- `NeatConfig` (~70 hyperparameters) extended by `DynamicConfig`

### Autoloads

- **GameConfig** — all simulation constants (grid size, energy costs, NEAT hyperparams, population bounds). Reference this instead of hardcoding values.
- **Registries** — `ReceptorRegistry` and `SkillRegistry` catalogs. Fixed at design time. Each entry has: name, category, range, energy_cost, cooldown, and a data dictionary.

### World

- `GridWorld`: 64×64 grid, 16px/tile. Manages spatial indices (`_creature_positions`, `_food_positions`) and provides `find_nearest_food()`, `find_nearest_creature()`, `find_creatures_in_range()`.
- `GridTile`: terrain (grass/forest/water/rock/sand), food, pheromone, wall, occupant_id, corpse_energy.
- `WorldGenerator`: Simplex noise → elevation/moisture → terrain type. Initial food on grass/forest.
- `FoodManager`: food regen (1.5× in forest), corpse energy decay, global food budget (8000 cap), seasonal sin-wave scarcity cycles (1000-tick period).
- `PheromoneLayer`: deposit/decay/diffusion per tick.

### Entities

- `Creature` (Node2D): visual representation + `creature_id`, `grid_pos`, `genome`, `body`, `brain`
- `CreatureBody` (RefCounted): energy, health, age, cooldowns, poison state. Methods: `is_alive()`, `can_reproduce()`, `apply_metabolism()`
- `CreatureBrain` (RefCounted): wraps `DynamicNetwork`, tracks receptor energy costs
- `CreatureSensor` (RefCounted): reads world state for a creature's position
- `Corpse` (RefCounted): factory `create_from_creature()` deposits 50% energy on tile

### Systems

- `SimulationManager` (Node2D): main tick loop — sense → think → act → spawn offspring → kill dead → maintain population → update world → refresh visuals. Owns all creatures, world, and sub-systems. Generation boundaries every 500 ticks. Skips visual refresh in headless mode.
- `ActionSystem` (RefCounted): interprets neural network outputs — discretizes movement (with terrain cost modifiers), handles eating (food + corpse), executes all 8 skills (dash, bite, poison_spit, emit_pheromone, share_food, build_wall, heal_self, burrow) with cooldown/energy enforcement. Grid boundary clamping. Logs events to `SimLogger`.
- `ReproductionSystem` (RefCounted): finds compatible mates within range 5, performs `DynamicGenome.crossover()` + `mutate()`, handles energy costs and cooldowns. Debug logging via `_debug_log` flag.
- `CreatureSpawner` (RefCounted): factory for creatures with random or provided genomes, finds empty passable tiles, registers in spatial index.
- `FitnessTracker` (RefCounted): per-creature lifetime metrics (energy gathered, food eaten, offspring, damage dealt). Computes scalar fitness and multi-objective `Vector3(survival, foraging, reproduction)` on death.
- `SpeciesManager` (RefCounted): assigns creatures to species by genome compatibility, tracks per-species fitness/stagnation, adjusts compatibility threshold toward target species count.
- `SimLogger` (RefCounted): per-tick and per-generation event counters (moves, eats, skills fired by name, bites, poisons, births, deaths by cause, random spawns). Lifetime stats (longest lived, most prolific parent).
- `SaveSystem` (RefCounted): save/load full simulation state (world + genomes) to JSON. Export best genomes per species. Keys: F5 save, F9 load, F6 export.

### UI

- `HUD` (CanvasLayer): population, tick, generation, speed, species count, FPS, fitness stats, pause state.
- `CameraController` (Camera2D): WASD/arrow pan, scroll zoom, middle-drag, speed controls (`[`/`]`), pause (Space).
- `CreatureInspector` (CanvasLayer): click creature to see vitals, genome stats (nodes, connections, receptors, skills), receptor/skill names.
- `StatsPanel` (CanvasLayer): toggle with Tab. Real-time line graphs for population, species count, and fitness history. Shows generation stats, food totals, famine indicator.

### evolve-core Class Name Wrappers

evolve-core removed its `class_name` declarations to avoid conflicts. `core/neat_*.gd` files re-export them for this project:
`NeatConfig`, `NeatInnovation`, `NeatGenome`, `NeatNetwork`, `NeatSpecies`, `NeatEvolution` — each is a one-line `extends` of the corresponding evolve-core script.

## Code Conventions

- Type hints on all function signatures: `func foo(x: int) -> void:`
- `class_name` declarations for all public classes
- `@export` for editor-configurable properties
- Constants in `UPPER_SNAKE_CASE`
- Data objects use `RefCounted` (automatic memory management), scene objects use `Node2D`
- Inner classes (e.g., `NodeGene`, `ConnectionGene`) live in their parent file
- Signal-based communication between systems
- Follow evolve-core interfaces (`IAgent`, `ISensor`, `IReward`)

## Economy Balance (tuned via headless observation)

Key parameters in `GameConfig` — these were data-driven from 5000-tick headless runs:
- Metabolism 0.15/tick, movement 0.1/tile — creatures survive ~500 ticks without food
- Reproduction threshold 35 energy, cost 10 — achievable once creatures find food
- Mating compatibility 25.0 — loose enough for random genomes (which have dist ~10-18)
- Mating range 5 tiles — with 40 creatures on 64×64 grid, encounters are possible
- Food budget 8000 globally, 0.08 regen/tick, 25% initial spawn density

## Current State

Full simulation loop with evolution: creatures spawn, sense, think, act (move, eat, 8 skills including burrow), reproduce with genome crossover, and die with fitness tracking. Species are managed with compatibility-based speciation and stagnation detection. Food has seasonal scarcity cycles. Save/load via F5/F9. Stats panel via Tab.

Headless mode auto-detects and prints exhaustive per-generation reports (deaths by cause, births, food consumed, skills fired, species breakdown).

Verified via 5000-tick headless runs: reproduction working (98 births/run), fitness climbing across generations (0→14), multi-member species emerging, genome complexity growing (hidden nodes, receptors, skills appearing).

See `ROADMAP.md` for remaining work (Phase 10: polish, advanced features).
