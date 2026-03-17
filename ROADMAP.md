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
- [x] Food scarcity: global food budget cap (4000), seasonal sin-wave regen modifier
- [x] Seasonal cycles: abundance/famine oscillation over 1000-tick periods
- [x] Terrain movement costs: sand costs 1.5x movement energy
- [x] Grid boundary clamping (creatures can't walk off edges)
- [x] Burrow skill (8th skill): triggers existing burrowed/burrow_ticks damage immunity

### Phase 7: Observability & Statistics (partial)
- [x] `StatsPanel` (Tab toggle): real-time line graphs for population, species, fitness
- [x] Generation stats in HUD (generation count, best/avg fitness)
- [x] Famine indicator
- [ ] Genome viewer: visual neural network graph
- [ ] Debug overlay: sensory inputs, neural activations
- [ ] Evolution dashboard: per-species detail table
- [ ] Heatmaps: food/pheromone/creature density overlays

### Phase 8: Persistence (partial)
- [x] `SaveSystem`: save/load full world state + creature genomes (F5/F9)
- [x] Export best genomes per species (F6)
- [ ] Simulation replay (tick-by-tick recording + scrubbing)
- [ ] Config presets (save/load GameConfig + DynamicConfig)

### Phase 9: Testing (partial)
- [x] Test runner: `godot --path . --headless -s tests/test_runner.gd`
- [x] `test_dynamic_genome.gd`: create, mutate, crossover, compatibility, copy, serialize
- [x] `test_dynamic_network.gd`: output dimensions, forward pass bounds, topology
- [x] `test_world.gd`: grid setup, passability, creature tracking, food index, spatial queries, pheromone
- [ ] Integration tests: full tick cycle, reproduction, death cleanup, population recovery
- [ ] CreatureBody unit tests: energy bounds, cooldown expiry, death conditions

---

## Remaining Work

### Phase 10: Polish & Advanced Features

- [ ] **Genome viewer:** visual neural network graph — nodes colored by type, weighted edges
- [ ] **Debug overlay:** show selected creature's sensory inputs, neural activations, action outputs
- [ ] **Predator/prey dynamics:** carnivores gain energy from kills, herbivores gain food bonus
- [ ] **Day/night cycles:** alternate visibility ranges, activity costs
- [ ] **Natural disasters:** periodic events (flood, drought, plague) as selection bottlenecks
- [ ] **Sandbox tools:** click to spawn/kill creatures, place/remove food and walls, drag creatures
- [ ] **Performance:** spatial hashing for neighbor queries, off-screen culling, batch pheromone diffusion
- [ ] **Heatmaps:** toggle overlays for food density, pheromone, creature density, death locations
- [ ] **Simulation replay:** record tick-by-tick snapshots, scrub timeline
- [ ] **In-game help:** tooltips, parameter descriptions, genome interpretation guide
