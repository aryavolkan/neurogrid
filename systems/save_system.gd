class_name SaveSystem
extends RefCounted
## Save and load simulation state: world grid + all creature genomes.

const SAVE_DIR: String = "user://saves/"


static func save_simulation(sim: SimulationManager, filename: String = "autosave") -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + filename + ".json"

	var creature_data: Array = []
	for creature_id in sim.creatures:
		var creature: Creature = sim.creatures[creature_id]
		creature_data.append({
			"id": creature.creature_id,
			"pos_x": creature.grid_pos.x,
			"pos_y": creature.grid_pos.y,
			"energy": creature.body.energy,
			"health": creature.body.health,
			"age": creature.body.age,
			"species_id": creature.body.species_id,
			"genome": creature.genome.serialize(),
		})

	# Save world tiles that have non-default state
	var tile_data: Array = []
	for pos in sim.world.tiles:
		var tile: GridTile = sim.world.tiles[pos]
		if tile.food > 0.0 or tile.wall or tile.corpse_energy > 0.0 or tile.pheromone > 0.01:
			tile_data.append({
				"x": pos.x, "y": pos.y,
				"food": tile.food,
				"wall": tile.wall,
				"corpse": tile.corpse_energy,
				"pheromone": tile.pheromone,
			})

	var save_data := {
		"version": 1,
		"tick": sim.get_tick_count(),
		"generation": sim.get_generation(),
		"creatures": creature_data,
		"tiles": tile_data,
	}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to save: " + path)
		return false
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	print("Saved to: ", path)
	return true


static func load_simulation(sim: SimulationManager, filename: String = "autosave") -> bool:
	var path := SAVE_DIR + filename + ".json"
	if not FileAccess.file_exists(path):
		push_error("Save file not found: " + path)
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Failed to parse save file")
		return false
	file.close()

	var data: Dictionary = json.data

	# Clear current creatures
	var ids_to_remove: Array = sim.creatures.keys()
	for cid in ids_to_remove:
		sim._kill_creature(cid)

	# Restore tile state
	for td in data.get("tiles", []):
		var pos := Vector2i(int(td.x), int(td.y))
		var tile: GridTile = sim.world.get_tile(pos)
		if tile:
			tile.food = float(td.get("food", 0.0))
			tile.wall = bool(td.get("wall", false))
			tile.corpse_energy = float(td.get("corpse", 0.0))
			tile.pheromone = float(td.get("pheromone", 0.0))
	sim.world.mark_food_dirty()

	# Restore creatures
	for cd in data.get("creatures", []):
		var genome := DynamicGenome.deserialize(
			cd.genome, sim._dynamic_config, sim._conn_tracker, sim._io_tracker
		)
		var pos := Vector2i(int(cd.pos_x), int(cd.pos_y))
		var creature := sim.spawner.spawn_creature(genome, pos, float(cd.get("energy", GameConfig.STARTING_ENERGY)))
		if creature:
			creature.body.health = float(cd.get("health", GameConfig.MAX_HEALTH))
			creature.body.age = int(cd.get("age", 0))
			sim._register_creature(creature)

	sim._tick_count = int(data.get("tick", 0))
	sim._generation = int(data.get("generation", 0))

	print("Loaded from: ", path)
	return true


static func export_best_genomes(sim: SimulationManager, filename: String = "best_genomes") -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + filename + ".json"

	# Collect best genome per species
	var best_per_species: Dictionary = {}  # species_id -> {fitness, genome_data}
	for creature_id in sim.creatures:
		var creature: Creature = sim.creatures[creature_id]
		var sid := creature.body.species_id
		var fitness := creature.genome.fitness
		if not best_per_species.has(sid) or fitness > best_per_species[sid].fitness:
			best_per_species[sid] = {
				"fitness": fitness,
				"species_id": sid,
				"genome": creature.genome.serialize(),
			}

	var export_data := {
		"tick": sim.get_tick_count(),
		"generation": sim.get_generation(),
		"genomes": best_per_species.values(),
	}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(export_data, "\t"))
	file.close()
	print("Exported best genomes to: ", path)
	return true
