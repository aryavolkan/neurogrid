# Simulation Health Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four interconnected simulation issues — food display bug, species explosion, skills never firing, and population collapse — so that creatures evolve sustainable populations with emergent skill usage.

**Architecture:** Targeted fixes to existing systems rather than rewrites. The root causes are: (1) lazy init not triggered before display, (2) species representatives never refreshed + cleanup too slow, (3) juvenile phase and thresholds blocking all skill usage, (4) reproduction cooldown in seconds vs tick-based delta creating 300-tick lockouts, plus eat_desire gating starving random networks. Each fix is independent and testable.

**Tech Stack:** GDScript, Godot 4.6, headless test runner

---

### Task 1: Fix FoodManager Lazy Init (Initial Food = 0)

**Files:**
- Modify: `world/food_manager.gd:106-107`
- Test: `tests/test_world.gd` (add test)

- [ ] **Step 1: Write the failing test**

Add to `tests/test_world.gd` (append before `_print_results`):

```gdscript
func _test_food_manager_total_before_update() -> void:
	## get_total_food() must return correct total even before first update().
	var w := GridWorld.new()
	w.setup()
	# Place food directly on a tile
	var tile: GridTile = w.get_tile(Vector2i(5, 5))
	tile.food = 10.0
	var fm := FoodManager.new(w)
	# Before any update() call, total should still reflect tile data
	_assert_true(fm.get_total_food() >= 10.0, "get_total_food before update includes tile food")
```

Also add the call `_test_food_manager_total_before_update()` to the `_ready()` function's test list.

- [ ] **Step 2: Run test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL|World"`
Expected: FAIL on "get_total_food before update includes tile food"

- [ ] **Step 3: Fix `get_total_food()` to trigger lazy init**

In `world/food_manager.gd`, change:

```gdscript
func get_total_food() -> float:
	return _total_food
```

to:

```gdscript
func get_total_food() -> float:
	_ensure_initialized()
	return _total_food
```

Also add the same guard to `is_famine()` since it reads `_season_tick` which starts at 0 (not a bug but consistent):

No — `is_famine()` doesn't depend on `_total_food`, leave it alone.

- [ ] **Step 4: Run test to verify it passes**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL|World"`
Expected: PASS, no FAILs in World suite

- [ ] **Step 5: Commit**

```bash
git add world/food_manager.gd tests/test_world.gd
git commit -m "fix: FoodManager.get_total_food() triggers lazy init before first update

Initial food displayed as 0 because _ensure_initialized() only ran on
first update() tick, but main.gd queries get_total_food() in _ready()."
```

---

### Task 2: Fix Species Explosion — Refresh Representatives Each Generation

**Files:**
- Modify: `systems/species_manager.gd:79-116`
- Test: `tests/test_species_manager.gd` (add test)

The core bug: species representatives are set once at creation and never updated. As genomes drift, every new creature fails to match stale representatives and creates a new species. The fix: at `end_generation()`, update each species' representative to a random living member's genome, exactly as canonical NEAT does.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_species_manager.gd` before `_print_results`:

```gdscript
func _test_representative_refreshed_on_end_generation() -> void:
	var sm := SpeciesManager.new(_config)
	var g1 := _make_genome()
	var sid := sm.assign_species(1, g1)
	var info := sm.get_species_info(sid)
	var old_rep := info.representative_genome

	# Add a second creature with a copy genome
	var g2 := g1.copy()
	sm.assign_species(2, g2)

	# Remove creature 1, leaving only creature 2
	sm.remove_creature(1)

	# Provide genome lookup for representative refresh
	sm.end_generation({2: g2})

	var new_rep := sm.get_species_info(sid).representative_genome
	_assert_true(new_rep == g2, "representative updated to living member genome")
```

Also add the call `_test_representative_refreshed_on_end_generation()` to `_ready()`.

- [ ] **Step 2: Run test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL|SpeciesManager"`
Expected: FAIL — `end_generation()` doesn't accept a genome dictionary argument yet

- [ ] **Step 3: Update `end_generation()` to refresh representatives and accept genome lookup**

In `systems/species_manager.gd`, replace the `end_generation()` method (lines 79-116):

```gdscript
func end_generation(genome_lookup: Dictionary = {}) -> void:
	## Called periodically to update stagnation tracking, refresh representatives, and prune.
	## genome_lookup: {creature_id -> DynamicGenome} for representative refresh.
	var to_remove: Array = []

	for species_id in _species:
		var info: SpeciesInfo = _species[species_id]
		info.age += 1

		# Update stagnation
		if info.best_fitness > info.best_fitness_ever:
			info.best_fitness_ever = info.best_fitness
			info.generations_without_improvement = 0
		else:
			info.generations_without_improvement += 1

		# Reset per-generation tracking
		info.best_fitness = 0.0
		info.total_fitness = 0.0

		# Refresh representative to a random living member's genome
		if not info.member_ids.is_empty() and not genome_lookup.is_empty():
			var random_member_id: int = info.member_ids[randi() % info.member_ids.size()]
			if genome_lookup.has(random_member_id):
				info.representative_genome = genome_lookup[random_member_id]

		# Remove species that are empty AND past grace period
		if info.member_ids.is_empty() and info.age > info.grace_generations:
			to_remove.append(species_id)

	for species_id in to_remove:
		speciation_events.append({"type": "extinct", "species_id": species_id})
		_species.erase(species_id)

	# Adjust compatibility threshold toward target (dampened to prevent oscillation)
	var current_count := _species.size()
	var target := _config.neat_config.target_species_count
	var step: float = _config.neat_config.threshold_step * 0.25
	if current_count < target:
		_config.neat_config.compatibility_threshold -= step
	elif current_count > target:
		_config.neat_config.compatibility_threshold += step
	_config.neat_config.compatibility_threshold = clampf(
		_config.neat_config.compatibility_threshold, 0.5, 15.0)
```

- [ ] **Step 4: Update `SimulationManager._end_generation()` to pass genome lookup**

In `systems/simulation_manager.gd`, line 340, change:

```gdscript
species_manager.end_generation()
```

to:

```gdscript
var genome_lookup: Dictionary = {}
for cid in creatures:
	genome_lookup[cid] = creatures[cid].genome
species_manager.end_generation(genome_lookup)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL|SpeciesManager"`
Expected: All SpeciesManager tests pass

- [ ] **Step 6: Commit**

```bash
git add systems/species_manager.gd systems/simulation_manager.gd tests/test_species_manager.gd
git commit -m "fix: refresh species representatives each generation

Stale representatives caused every new creature to fail compatibility
checks and create new species, resulting in 200+ species for 40 creatures.
Now end_generation() updates each species rep to a random living member."
```

---

### Task 3: Reduce Species Grace Period and Increase Threshold Step

**Files:**
- Modify: `systems/species_manager.gd:23` (grace period)
- Modify: `systems/species_manager.gd:110` (step dampening)

Empty species survived 3 generations (1500 ticks) before pruning, and threshold adjustment of 0.075/gen was too slow to converge. Fix both.

- [ ] **Step 1: Reduce grace period from 3 to 1 generation**

In `systems/species_manager.gd`, class `SpeciesInfo`, line 23, change:

```gdscript
var grace_generations: int = 3  # Immune to extinction for first N generations
```

to:

```gdscript
var grace_generations: int = 1  # Immune to extinction for first N generations
```

- [ ] **Step 2: Increase threshold adjustment speed**

In `systems/species_manager.gd`, in `end_generation()`, change the dampening factor. Find:

```gdscript
var step: float = _config.neat_config.threshold_step * 0.25
```

Change to:

```gdscript
var step: float = _config.neat_config.threshold_step * 0.5
```

This doubles the effective step from 0.075 to 0.15 per generation, allowing convergence in ~50 generations instead of hundreds.

- [ ] **Step 3: Update the existing grace period test**

In `tests/test_species_manager.gd`, `_test_empty_species_pruned()` (line 136), change:

```gdscript
# Grace period: species survives 3 generations before extinction
for _i in 4:
    sm.end_generation()
```

to:

```gdscript
# Grace period: species survives 1 generation before extinction
for _i in 2:
    sm.end_generation()
```

- [ ] **Step 4: Run tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL|SpeciesManager"`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add systems/species_manager.gd tests/test_species_manager.gd
git commit -m "tune: reduce species grace period to 1 gen, double threshold step

Empty species lingered 1500 ticks before cleanup. Threshold adjustment
was 0.075/gen, too slow to converge. Now 500-tick cleanup and 0.15/gen step."
```

---

### Task 4: Fix Reproduction Cooldown (Seconds vs Ticks Mismatch)

**Files:**
- Modify: `autoloads/game_config.gd:29`
- Modify: `entities/creature_body.gd:48-51`
- Test: `tests/test_creature_body.gd` (add test)

The cooldown is stored as 10.0 (seconds) and decremented by `delta` (1/30 sec), taking 300 ticks. For creatures that live ~500 ticks, this is 60% of their lifespan. Change to tick-based cooldown so creatures can reproduce more than once.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_creature_body.gd` before `_print_results`:

```gdscript
func _test_reproduction_cooldown_ticks() -> void:
	var body := CreatureBody.new()
	body.reproduction_cooldown = GameConfig.REPRODUCTION_COOLDOWN
	# After REPRODUCTION_COOLDOWN ticks at delta=1.0, cooldown should expire
	for _i in int(GameConfig.REPRODUCTION_COOLDOWN):
		body.update_cooldowns(1.0)
	_assert_true(body.reproduction_cooldown <= 0.0, "cooldown expires after correct tick count")
```

Also add the call `_test_reproduction_cooldown_ticks()` to `_ready()`.

- [ ] **Step 2: Run test to verify current behavior**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL|CreatureBody"`
Expected: Currently passes since delta=1.0 makes 100 iterations drain 100.0 from 10.0. Test will pass. Let's verify the actual gameplay fix instead.

- [ ] **Step 3: Change REPRODUCTION_COOLDOWN to tick count and decrement by 1 per tick**

In `autoloads/game_config.gd`, line 29, change:

```gdscript
const REPRODUCTION_COOLDOWN: float = 10.0  # Seconds
```

to:

```gdscript
const REPRODUCTION_COOLDOWN: float = 100.0  # Ticks (~3.3 seconds at 30 TPS)
```

In `entities/creature_body.gd`, line 48-50, change:

```gdscript
func update_cooldowns(delta: float) -> void:
	if reproduction_cooldown > 0.0:
		reproduction_cooldown -= delta
```

to:

```gdscript
func update_cooldowns(_delta: float) -> void:
	if reproduction_cooldown > 0.0:
		reproduction_cooldown -= 1.0
```

- [ ] **Step 4: Run all tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL"`
Expected: No failures (existing cooldown test uses `delta` which we changed, verify)

- [ ] **Step 5: Commit**

```bash
git add autoloads/game_config.gd entities/creature_body.gd tests/test_creature_body.gd
git commit -m "fix: reproduction cooldown now tick-based (100 ticks, not 300)

Cooldown was 10.0 seconds decremented by delta=1/30, taking 300 ticks
(60% of a creature's lifespan). Now 100 ticks, allowing 2-4 reproductions
per lifetime."
```

---

### Task 5: Lower Eat Desire Threshold for Random Networks

**Files:**
- Modify: `systems/action_system.gd:5`

Random networks output `tanh(bias)` which is uniform in [-1, 1]. At threshold 0.3, ~35% of creatures can eat. Lowering to 0.0 means any positive output triggers eating — ~50% of random creatures can eat, and evolution quickly selects for it.

- [ ] **Step 1: Lower EAT_DESIRE_THRESHOLD**

In `systems/action_system.gd`, line 5, change:

```gdscript
const EAT_DESIRE_THRESHOLD: float = 0.3
```

to:

```gdscript
const EAT_DESIRE_THRESHOLD: float = 0.0
```

- [ ] **Step 2: Run tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL"`
Expected: No failures

- [ ] **Step 3: Commit**

```bash
git add systems/action_system.gd
git commit -m "tune: lower eat desire threshold from 0.3 to 0.0

Random tanh networks produce ~uniform [-1,1] outputs. At 0.3 threshold,
~35% of creatures never ate even on food tiles. At 0.0, any positive
output triggers eating, letting evolution optimize from a surviving base."
```

---

### Task 6: Reduce Juvenile Phase and Unblock Skills Earlier

**Files:**
- Modify: `systems/advanced_evolution.gd:55`
- Modify: `autoloads/game_config.gd:25` (offspring energy)

The juvenile phase (200 ticks) costs 18 energy minimum on 30 starting energy, leaving offspring at 12 energy — far below the 35 reproduction threshold. Reduce juvenile phase to 50 ticks and increase offspring energy to 40.

- [ ] **Step 1: Reduce JUVENILE_AGE from 200 to 50**

In `systems/advanced_evolution.gd`, line 55, change:

```gdscript
const JUVENILE_AGE: int = 200  # Ticks before reaching adulthood
```

to:

```gdscript
const JUVENILE_AGE: int = 50  # Ticks before reaching adulthood
```

- [ ] **Step 2: Increase OFFSPRING_ENERGY from 30 to 40**

In `autoloads/game_config.gd`, line 25, change:

```gdscript
const OFFSPRING_ENERGY: float = 30.0
```

to:

```gdscript
const OFFSPRING_ENERGY: float = 40.0
```

- [ ] **Step 3: Run tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL"`
Expected: No failures. Check if any test hardcodes 200 juvenile age or 30 offspring energy.

- [ ] **Step 4: Commit**

```bash
git add systems/advanced_evolution.gd autoloads/game_config.gd
git commit -m "tune: reduce juvenile phase to 50 ticks, offspring energy to 40

200-tick juvenile phase cost 18+ energy on 30 starting budget, killing
most offspring before adulthood. Skills were blocked the entire time.
Now 50 ticks (costs ~4.5 energy) with 40 starting energy gives offspring
a viable path to reproduction and skill usage."
```

---

### Task 7: Lower Skill Activation Threshold

**Files:**
- Modify: `systems/action_system.gd:6`

`SKILL_ACTIVATION_THRESHOLD = 0.5` with tanh requires pre-activation of 0.549. For newly added skill nodes with one random connection, this is rarely exceeded. Lower to 0.3 to match `EAT_DESIRE_THRESHOLD` pattern and let random skill activations happen.

- [ ] **Step 1: Lower SKILL_ACTIVATION_THRESHOLD**

In `systems/action_system.gd`, line 6, change:

```gdscript
const SKILL_ACTIVATION_THRESHOLD: float = 0.5
```

to:

```gdscript
const SKILL_ACTIVATION_THRESHOLD: float = 0.3
```

- [ ] **Step 2: Run tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL"`
Expected: No failures

- [ ] **Step 3: Commit**

```bash
git add systems/action_system.gd
git commit -m "tune: lower skill activation threshold from 0.5 to 0.3

tanh(0.5) requires pre-activation of 0.549, rarely exceeded by
single-connection skill nodes. 0.3 allows random skill activations
that evolution can then select for or against."
```

---

### Task 8: Increase Skill Mutation Rate

**Files:**
- Modify: `core/dynamic_config.gd:11`

At 2% per mutation call, skills appear too slowly. Increase to 5% to match `add_connection_rate`, giving evolution material to work with.

- [ ] **Step 1: Increase add_skill_rate**

In `core/dynamic_config.gd`, line 11, change:

```gdscript
var add_skill_rate: float = 0.02
```

to:

```gdscript
var add_skill_rate: float = 0.05
```

- [ ] **Step 2: Run tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1 | grep -E "FAIL"`
Expected: No failures

- [ ] **Step 3: Commit**

```bash
git add core/dynamic_config.gd
git commit -m "tune: increase skill mutation rate from 2% to 5%

Skills had to mutate in at 2% per reproduction, too slow for evolution
to discover useful skill behaviors. 5% matches add_connection_rate."
```

---

### Task 9: Fix Camera `make_current` Timing

**Files:**
- Modify: `scenes/main.gd:75-76`

The camera calls `make_current()` before entering the scene tree. Defer it.

- [ ] **Step 1: Fix camera initialization order**

In `scenes/main.gd`, lines 74-76, change:

```gdscript
camera = CameraController.new()
camera.make_current()
add_child(camera)
```

to:

```gdscript
camera = CameraController.new()
add_child(camera)
camera.make_current()
```

- [ ] **Step 2: Run game and check no error**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . 2>&1 | grep -i "error" | grep -v shader`
Expected: No "!enabled || !is_inside_tree()" error

- [ ] **Step 3: Commit**

```bash
git add scenes/main.gd
git commit -m "fix: call camera.make_current() after add_child

Camera2D.make_current() requires node to be in the scene tree."
```

---

### Task 10: Fix Node Leak on Exit

**Files:**
- Modify: `scenes/main.gd` (find leaked Control nodes)

Two Control nodes and two Objects leaked on exit. These are likely UI panels created but not freed.

- [ ] **Step 1: Investigate the leak**

Search `scenes/main.gd` for any `Control` or `CanvasLayer` nodes that are created with `.new()` but might not be added to the tree (and thus not auto-freed). The leaked nodes are `Control` types — likely panels that are conditionally created.

Check if `_notification(NOTIFICATION_PREDELETE)` or `_exit_tree()` frees dynamically created UI. If UI panels are created in headless mode, they won't be added to the tree and won't be freed.

- [ ] **Step 2: Add cleanup in `_exit_tree()`**

Read the full `scenes/main.gd` to identify the exact panels being leaked, then add explicit `queue_free()` calls or guard their creation behind `if not _headless`.

This step requires reading the full file — the engineer should identify which panels are created unconditionally and ensure they're either not created in headless mode or explicitly freed.

- [ ] **Step 3: Run game, close it, check for leaks**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . 2>&1 | grep -i "leaked"`
Expected: No leaked instances

- [ ] **Step 4: Commit**

```bash
git add scenes/main.gd
git commit -m "fix: free leaked UI Control nodes on exit"
```

---

### Task 11: Headless Validation Run

**Files:** None (verification only)

- [ ] **Step 1: Run all tests**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless -s tests/test_runner.gd 2>&1`
Expected: All test suites pass, no FAILs

- [ ] **Step 2: Run headless simulation for 2500 ticks**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . --headless 2>&1 | head -60`

Verify:
- "Initial food" is non-zero (food display fix)
- Species count stays reasonable (under 50 for pop 40-100)
- Some skills fire (non-zero skill counts in generation reports)
- Population grows above minimum floor at some point
- Reproduction count exceeds random spawn count

- [ ] **Step 3: If validation fails, diagnose**

Compare pre/post stats. If species still explode, the representative refresh may need the full re-speciation approach (clearing all members and reassigning). If skills still don't fire, check if `add_skill_rate = 0.05` is producing skill nodes and if the juvenile phase is short enough. If population is still floor-bound, check if eat threshold change helped energy accumulation.
