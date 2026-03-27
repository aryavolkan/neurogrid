# NeuroGrid Roadmap

## Completed

### Phases 1–4: Core Simulation (done)
Creatures spawn, sense, think (NEAT forward pass), act (move, eat, 8 skills), reproduce sexually with genome crossover + mutation, and die on a procedurally generated 64x64 grid. UI: HUD, camera, creature inspector.

### Phase 5: Evolution Engine Integration (done)
- [x] `SpeciesManager`: compatibility-based speciation with stagnation detection and threshold adjustment
- [x] `FitnessTracker`: per-creature lifetime metrics (survival, energy, food, offspring, damage)
- [x] Scalar fitness computed on death, populates `DynamicGenome.fitness`
- [x] Multi-objective support via `Vector3(survival, foraging, reproduction)`
- [x] Generation boundaries every 500 ticks with stats emission
- [x] Innovation cache reset per generation

### Phase 6: Environmental Pressure & Dynamics (done)
- [x] Food scarcity: global food budget cap (8000), seasonal sin-wave regen modifier
- [x] Seasonal cycles: abundance/famine oscillation over 1000-tick periods
- [x] Terrain movement costs: sand costs 1.5x movement energy
- [x] Grid boundary clamping (creatures can't walk off edges)
- [x] Burrow skill (8th skill): triggers existing burrowed/burrow_ticks damage immunity

### Phase 7: Observability & Statistics (done)
- [x] `StatsPanel` (Tab toggle): real-time line graphs for population, species, fitness
- [x] Generation stats in HUD (generation count, best/avg fitness)
- [x] Famine indicator
- [x] `SimLogger`: exhaustive per-tick event counters (moves, eats, skills by name, bites, poisons, births, deaths by cause, random spawns)
- [x] Headless mode: terrain census, energy distribution, population trajectory, creature census with receptor/skill inventory, species breakdown with stagnation
- [x] Lifetime stats: longest lived creature, most prolific parent, total births/deaths

### Phase 8: Persistence (partial)
- [x] `SaveSystem`: save/load full world state + creature genomes (F5/F9)
- [x] Export best genomes per species (F6)
- [ ] Simulation replay (tick-by-tick recording + scrubbing)
- [ ] Config presets (save/load GameConfig + DynamicConfig)

### Phase 9: Testing & CI (done)
- [x] Test runner: `godot --path . --headless -s tests/test_runner.gd`
- [x] 147 tests across 8 suites:
  - `test_dynamic_genome.gd` (20): create, mutate, crossover, compatibility, copy, serialize
  - `test_dynamic_network.gd` (10): output dimensions, forward pass bounds, topology
  - `test_world.gd` (21): grid setup, passability, creature tracking, food index, spatial queries, pheromone
  - `test_creature_body.gd` (29): alive checks, energy/health bounds, metabolism, cooldowns, poison, burrow
  - `test_fitness_tracker.gd` (10): registration, recording, weighted fitness, multi-objective
  - `test_species_manager.gd` (11): assignment, compatibility, stagnation, threshold adjustment, pruning
  - `test_action_system.gd` (25): movement, boundaries, terrain costs, eating, all 8 skills, cooldowns, fitness integration
  - `test_integration.gd` (21): spawn/register, death/corpse, spatial cleanup, reproduction, food regen, genome roundtrip, IoInnovation, sensor bounds
- [x] GitHub Actions CI: test runner + GDScript validation on push/PR
- [x] Economy rebalanced via data-driven headless testing (metabolism, reproduction costs, mating threshold)

### Phase 10: Polish & Visualization (done)
- [x] Genome viewer, debug overlay, sandbox tools, heatmaps, spatial hashing (see commit d113d87)
- [ ] In-game help: tooltips, parameter descriptions, genome interpretation guide
- [ ] Config presets (save/load GameConfig + DynamicConfig)

### Phase 11: Behavioral Ecology (done)
- [x] **Predator/prey role specialization:** carnivores gain 30% energy from kills via `EcologySystem.get_kill_energy_bonus()`, herbivores (no combat skills) get 50% food bonus
- [x] **Territorial behavior:** creatures accumulate territory after 100 ticks in area — defense and attack bonuses within established territory
- [x] **Group behavior incentives:** 0.5 fitness bonus per nearby ally (same species, range 4)
- [x] **Nocturnal/diurnal cycles:** 600-tick day/night period — night: 0.7× metabolism, 0.5× sensor multiplier
- [x] **Migration patterns:** food hotspot circulates over 5000-tick period (12-tile radius, 0.15 extra food regen)

### Phase 12: Advanced Evolution (done)
- [x] **Neuromodulation:** per-tick Hebbian-like connection weight adjustment (energy change × learning_rate × pre/post activation)
- [x] **Sexual selection:** 4 evolved mate preference weights (complexity, skills, receptors, fitness) used during mate selection in `ReproductionSystem`
- [x] **Ontogeny:** juvenile phase (first 200 ticks) with 0.6× metabolism and blocked skill access
- [x] **Coevolutionary arms races:** inter-species interaction tracking (attacks, kills, damage) with escalation rewards
- [x] **Speciation events tracking:** `PhylogenyTracker` logs species births, extinctions, lineage depth, and peak stats

### Phase 13: World Complexity (done)
- [x] **Multi-level terrain:** per-tile elevation from noise generation, affects movement cost (valleys cost more)
- [x] **Dynamic terrain:** vegetation growth (grass→forest at high density, boosted by rain) and erosion (water-adjacent tiles lose elevation, sand→water)
- [x] **Resource types:** minerals near rock/sand (reduce wall build cost), medicinal plants in forests (boost heal effectiveness)
- [x] **Nesting sites:** up to 10 high-elevation sheltered locations where offspring get 1.5× initial energy
- [x] **Weather system:** rain (food regen bonus), storms (damage to exposed creatures), fog (sensor range reduction) with configurable durations/probabilities

---

## In Progress

### Phase 14: Analysis & Tooling (done)

- [x] **Phylogenetic tree tracking:** `PhylogenyTracker` records species lineage, birth/extinction events, peak stats, tree depth, and generates text reports
- [x] **Genome diff tool:** `GenomeDiff.compare()` produces structured diff — matching/disjoint/excess connections, weight differences, shared/unique receptors and skills, compatibility distance
- [x] **Experiment runner (CSV export):** `ExperimentRunner` exports population snapshots, species snapshots, and generation stats to CSV (`user://experiments/`). F7 key for manual export, auto-export in headless mode
- [x] **Phylogenetic tree visualization:** `PhylogenyPanel` (P key) — species lineage graph with DFS-ordered tree layout, lifespan bars colored by species, bar height scaled by population, parent-child connectors, extinction markers, tick axis, legend
- [x] **Batch experiment runner:** `BatchRunner` + CLI `--sweep` mode — parameter sweeps across 6 sweepable GameConfig params (INITIAL_POPULATION, BASE_METABOLISM, REPRODUCTION_ENERGY_THRESHOLD, FOOD_REGEN_RATE, ADD_NODE_RATE, ADD_CONNECTION_RATE) with Cartesian product combos, multiple runs, and aggregated CSV export
- [x] **Sensor range integration:** elevation bonus and weather fog multiplier now applied to actual `CreatureSensor` queries via `_effective_range()` helper

---

## Planned

### Phase 15: Polish & Completeness (done)

- [x] **W&B integration:** `WandbLogger` writes `user://metrics.json` per generation; `scripts/neurogrid_train.py` launches headless Godot and logs to W&B via `shared-evolve-utils/godot_wandb.py`. Metrics: fitness, population, species count, food, avg genome complexity (nodes, connections, receptors, skills).
- [x] **Replay system:** `ReplayRecorder` ring-buffer (3000 frames) captures creature snapshots each tick. `ReplayPanel` (R key) pauses simulation, shows world-space creature overlay from recorded data, provides scrubber + play/pause/step controls.
- [x] **In-game help:** `HelpPanel` (F1 key) — three tabs: Controls (all key bindings), Receptors & Skills (descriptions, costs, cooldowns), Genome Guide (NEAT architecture, node types, fitness formula).
- [x] **Config presets:** `ConfigPresetManager` saves/loads named JSON presets covering all 6 sweepable `GameConfig` params + 4 `DynamicConfig` I/O rates. Four built-in presets: default, fast_evolution, rich_ecology, minimal. `PresetPanel` (F2 key) provides load/save/delete UI.
