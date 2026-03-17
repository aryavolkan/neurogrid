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

---

## In Progress

### Phase 10: Polish & Visualization (in progress)

- [ ] **Genome viewer:** visual neural network graph — nodes colored by type, weighted edges
- [ ] **Debug overlay:** show selected creature's sensory inputs, neural activations, action outputs
- [ ] **Sandbox tools:** click to spawn/kill creatures, place/remove food and walls, drag creatures
- [ ] **Heatmaps:** toggle overlays for food density, pheromone, creature density, death locations
- [ ] **Performance:** spatial hashing for neighbor queries, off-screen culling, batch pheromone diffusion
- [ ] **In-game help:** tooltips, parameter descriptions, genome interpretation guide
- [ ] Config presets (save/load GameConfig + DynamicConfig)

---

## Planned

### Phase 11: Behavioral Ecology

- [ ] **Predator/prey role specialization:** carnivores gain energy from kills, herbivores get food bonus — diet emerges from evolved receptor/skill loadouts
- [ ] **Territorial behavior:** creatures that stay in an area accumulate defensive bonuses (reduced damage taken, increased bite damage within territory)
- [ ] **Group behavior incentives:** allied creatures (same species) near each other receive a fitness bonus, encouraging flocking and cooperative strategies
- [ ] **Nocturnal/diurnal cycles:** alternate activity costs and sensor ranges — some receptors become more effective at night, movement costs shift by time of day
- [ ] **Migration patterns:** food spawn locations shift gradually over long time scales (thousands of ticks), rewarding creatures that track resource movement

### Phase 12: Advanced Evolution

- [ ] **Neuromodulation:** evolved learning rates attached to connections that modify weights during a creature's lifetime based on reward signals
- [ ] **Sexual selection:** mate preference genes that bias partner choice beyond compatibility distance — creatures evolve aesthetic or behavioral criteria for mates
- [ ] **Ontogeny:** genome expression changes with creature age — juvenile creatures have reduced skill access and lower metabolism, adults unlock full genome potential
- [ ] **Coevolutionary arms races:** track and reward competitive interactions between species — predator species and prey species drive each other's evolution
- [ ] **Speciation events tracking:** log when species split, merge, or go extinct with full lineage metadata for post-hoc analysis

### Phase 13: World Complexity

- [ ] **Multi-level terrain:** elevation values per tile affecting movement cost and visibility range (high ground = longer sensor range, valleys = shelter)
- [ ] **Dynamic terrain:** erosion, flooding, and vegetation growth that change the map over generations — terrain is no longer static after world generation
- [ ] **Resource types beyond food:** minerals for wall building (reduces build_wall energy cost), medicinal plants for healing (boosts heal_self effectiveness)
- [ ] **Nesting sites:** protected tile locations where offspring have higher initial energy and reduced predation risk during early life
- [ ] **Weather system:** rain boosts food regeneration, storms deal damage to exposed creatures, fog reduces all sensor ranges temporarily

### Phase 14: Analysis & Tooling

- [ ] **Phylogenetic tree visualization:** species lineage graph over generations showing branching, extinction, and dominance shifts
- [ ] **Genome diff tool:** compare two creatures' genomes side by side — highlight matching innovations, unique receptors/skills, and structural differences
- [ ] **Experiment runner:** batch headless runs with parameter sweeps across GameConfig/DynamicConfig values, automatic CSV export of per-generation statistics
- [ ] **W&B integration:** connect via `shared-evolve-utils` for cloud-based experiment tracking — log fitness curves, species counts, genome complexity, and population metrics
- [ ] **Replay system:** record tick-by-tick snapshots of full simulation state, scrub timeline forward/backward, export to video for presentations and analysis
