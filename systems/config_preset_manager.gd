class_name ConfigPresetManager
extends RefCounted
## Save and load named configuration presets for GameConfig + DynamicConfig.
## Built-in presets are read-only. User presets are saved to user://presets/.

const PRESET_DIR: String = "user://presets/"

# Built-in preset definitions (sweepable GameConfig keys + DynamicConfig rates).
const BUILTIN_PRESETS: Dictionary = {
	"default": {
		"INITIAL_POPULATION": 80,
		"BASE_METABOLISM": 0.15,
		"REPRODUCTION_ENERGY_THRESHOLD": 35.0,
		"FOOD_REGEN_RATE": 0.08,
		"ADD_NODE_RATE": 0.03,
		"ADD_CONNECTION_RATE": 0.05,
		"add_receptor_rate": 0.03,
		"add_skill_rate": 0.02,
		"remove_receptor_rate": 0.005,
		"remove_skill_rate": 0.005,
	},
	"fast_evolution": {
		"INITIAL_POPULATION": 120,
		"BASE_METABOLISM": 0.12,
		"REPRODUCTION_ENERGY_THRESHOLD": 28.0,
		"FOOD_REGEN_RATE": 0.12,
		"ADD_NODE_RATE": 0.06,
		"ADD_CONNECTION_RATE": 0.10,
		"add_receptor_rate": 0.06,
		"add_skill_rate": 0.05,
		"remove_receptor_rate": 0.01,
		"remove_skill_rate": 0.01,
	},
	"rich_ecology": {
		"INITIAL_POPULATION": 160,
		"BASE_METABOLISM": 0.10,
		"REPRODUCTION_ENERGY_THRESHOLD": 40.0,
		"FOOD_REGEN_RATE": 0.15,
		"ADD_NODE_RATE": 0.02,
		"ADD_CONNECTION_RATE": 0.04,
		"add_receptor_rate": 0.04,
		"add_skill_rate": 0.03,
		"remove_receptor_rate": 0.003,
		"remove_skill_rate": 0.003,
	},
	"minimal": {
		"INITIAL_POPULATION": 40,
		"BASE_METABOLISM": 0.20,
		"REPRODUCTION_ENERGY_THRESHOLD": 30.0,
		"FOOD_REGEN_RATE": 0.05,
		"ADD_NODE_RATE": 0.02,
		"ADD_CONNECTION_RATE": 0.03,
		"add_receptor_rate": 0.02,
		"add_skill_rate": 0.01,
		"remove_receptor_rate": 0.002,
		"remove_skill_rate": 0.002,
	},
}


static func list_presets() -> Array:
	## Returns all preset names: built-ins first, then user presets sorted.
	var names: Array = BUILTIN_PRESETS.keys()
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var dir := DirAccess.open(PRESET_DIR)
	if dir:
		dir.list_dir_begin()
		var fname: String = dir.get_next()
		while fname != "":
			if fname.ends_with(".json"):
				var preset_name := fname.get_basename()
				if not names.has(preset_name):
					names.append(preset_name)
			fname = dir.get_next()
		dir.list_dir_end()
	return names


static func is_builtin(preset_name: String) -> bool:
	return BUILTIN_PRESETS.has(preset_name)


static func load_preset(preset_name: String) -> Dictionary:
	## Returns preset params dict, or empty dict on failure.
	if BUILTIN_PRESETS.has(preset_name):
		return BUILTIN_PRESETS[preset_name].duplicate()

	var path := PRESET_DIR + preset_name + ".json"
	if not FileAccess.file_exists(path):
		push_warning("Preset not found: " + preset_name)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Failed to parse preset: " + path)
		return {}
	file.close()

	var data = json.data
	if data is Dictionary:
		return data
	return {}


static func save_preset(preset_name: String, dynamic_config: DynamicConfig) -> bool:
	## Save current config state as a named user preset. Cannot overwrite built-ins.
	if BUILTIN_PRESETS.has(preset_name):
		push_warning("Cannot overwrite built-in preset: " + preset_name)
		return false

	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var path := PRESET_DIR + preset_name + ".json"
	var params := get_current_as_dict(dynamic_config)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Failed to write preset: " + path)
		return false
	file.store_string(JSON.stringify(params, "\t"))
	file.close()
	return true


static func delete_preset(preset_name: String) -> bool:
	## Delete a user preset. Built-ins cannot be deleted.
	if BUILTIN_PRESETS.has(preset_name):
		push_warning("Cannot delete built-in preset: " + preset_name)
		return false

	var path := PRESET_DIR + preset_name + ".json"
	if not FileAccess.file_exists(path):
		return false

	return DirAccess.remove_absolute(path) == OK


static func apply_preset(params: Dictionary, dynamic_config: DynamicConfig) -> void:
	## Apply a preset dict to GameConfig and DynamicConfig. Restarts take effect immediately.
	var gc_keys: Array = [
		"INITIAL_POPULATION", "BASE_METABOLISM", "REPRODUCTION_ENERGY_THRESHOLD",
		"FOOD_REGEN_RATE", "ADD_NODE_RATE", "ADD_CONNECTION_RATE",
	]
	var gc_overrides: Dictionary = {}
	for key in gc_keys:
		if params.has(key):
			gc_overrides[key] = params[key]
	if not gc_overrides.is_empty():
		GameConfig.apply_overrides(gc_overrides)

	if dynamic_config:
		if params.has("add_receptor_rate"):
			dynamic_config.add_receptor_rate = float(params["add_receptor_rate"])
		if params.has("add_skill_rate"):
			dynamic_config.add_skill_rate = float(params["add_skill_rate"])
		if params.has("remove_receptor_rate"):
			dynamic_config.remove_receptor_rate = float(params["remove_receptor_rate"])
		if params.has("remove_skill_rate"):
			dynamic_config.remove_skill_rate = float(params["remove_skill_rate"])


static func get_current_as_dict(dynamic_config: DynamicConfig) -> Dictionary:
	## Snapshot the current config state as a serializable dict.
	var d: Dictionary = {
		"INITIAL_POPULATION": GameConfig.INITIAL_POPULATION,
		"BASE_METABOLISM": GameConfig.BASE_METABOLISM,
		"REPRODUCTION_ENERGY_THRESHOLD": GameConfig.REPRODUCTION_ENERGY_THRESHOLD,
		"FOOD_REGEN_RATE": GameConfig.FOOD_REGEN_RATE,
		"ADD_NODE_RATE": GameConfig.ADD_NODE_RATE,
		"ADD_CONNECTION_RATE": GameConfig.ADD_CONNECTION_RATE,
	}
	if dynamic_config:
		d["add_receptor_rate"] = dynamic_config.add_receptor_rate
		d["add_skill_rate"] = dynamic_config.add_skill_rate
		d["remove_receptor_rate"] = dynamic_config.remove_receptor_rate
		d["remove_skill_rate"] = dynamic_config.remove_skill_rate
	return d
