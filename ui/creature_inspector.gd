class_name CreatureInspector
extends CanvasLayer
## Click a creature to see its stats, genome info, and neural network summary.

var _sim: SimulationManager
var _selected_creature_id: int = -1
var _panel: PanelContainer
var _info_label: RichTextLabel
var _update_timer: float = 0.0


func _ready() -> void:
	layer = 10
	_build_ui()


func setup(sim: SimulationManager) -> void:
	_sim = sim


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.offset_left = -220
	_panel.offset_right = -8
	_panel.offset_top = 8
	_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)

	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = true
	_info_label.custom_minimum_size = Vector2(200, 0)
	_info_label.add_theme_font_size_override("normal_font_size", 12)
	_info_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	_panel.add_child(_info_label)

	add_child(_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_try_select(event.global_position)


func _try_select(screen_pos: Vector2) -> void:
	if not _sim:
		return

	# Convert screen position to world position
	var camera := get_viewport().get_camera_2d()
	if not camera:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var world_pos := camera.position + (screen_pos - viewport_size * 0.5) / camera.zoom

	# Find which tile was clicked
	var tile_pos := Vector2i(int(world_pos.x) / GameConfig.TILE_SIZE, int(world_pos.y) / GameConfig.TILE_SIZE)
	var creature_id := _sim.world.get_creature_at(tile_pos)

	if creature_id >= 0:
		# Clear previous selection highlight
		if _selected_creature_id >= 0 and _sim.creatures.has(_selected_creature_id):
			_sim.creatures[_selected_creature_id].selected = false
		_selected_creature_id = creature_id
		_sim.creatures[creature_id].selected = true
		_panel.visible = true
		_update_info()
	else:
		if _selected_creature_id >= 0 and _sim.creatures.has(_selected_creature_id):
			_sim.creatures[_selected_creature_id].selected = false
		_selected_creature_id = -1
		_panel.visible = false


func _process(delta: float) -> void:
	if not _panel.visible or _selected_creature_id < 0:
		return

	_update_timer += delta
	if _update_timer < 0.25:
		return
	_update_timer = 0.0
	_update_info()


func _update_info() -> void:
	if not _sim or not _sim.creatures.has(_selected_creature_id):
		_panel.visible = false
		_selected_creature_id = -1
		return

	var creature: Creature = _sim.creatures[_selected_creature_id]
	var body := creature.body
	var genome := creature.genome

	var text := ""
	text += "[b]Creature #%d[/b]\n" % creature.creature_id
	text += "Species: %d\n" % body.species_id
	text += "Pos: (%d, %d)\n\n" % [creature.grid_pos.x, creature.grid_pos.y]

	text += "[b]Vitals[/b]\n"
	text += "Energy: %.1f / %.0f\n" % [body.energy, GameConfig.MAX_ENERGY]
	text += "Health: %.1f / %.0f\n" % [body.health, GameConfig.MAX_HEALTH]
	text += "Age: %d / %d\n\n" % [body.age, GameConfig.MAX_AGE]

	text += "[b]Brain[/b]\n"
	text += "Nodes: %d\n" % genome.node_genes.size()
	text += "Connections: %d\n" % genome.connection_genes.size()
	text += "Receptors: %d\n" % genome.get_receptor_count()
	text += "Skills: %d\n\n" % genome.get_skill_count()

	# List receptors
	var receptors := genome.get_receptor_nodes()
	if not receptors.is_empty():
		text += "[b]Receptors[/b]\n"
		for node in receptors:
			var entry = Registries.receptor_registry.get_entry(node.registry_id)
			if entry:
				text += "  %s\n" % entry.name
		text += "\n"

	# List skills
	var skills := genome.get_skill_nodes()
	if not skills.is_empty():
		text += "[b]Skills[/b]\n"
		for node in skills:
			var entry = Registries.skill_registry.get_entry(node.registry_id)
			if entry:
				text += "  %s\n" % entry.name

	# Status indicators
	var status_parts: Array = []
	if body.age < AdvancedEvolution.JUVENILE_AGE:
		status_parts.append("[color=cyan]JUVENILE[/color]")
	if body.poisoned_ticks > 0:
		status_parts.append("[color=green]POISONED (%d)[/color]" % body.poisoned_ticks)
	if body.burrowed:
		status_parts.append("[color=orange]BURROWED[/color]")

	if not status_parts.is_empty():
		text += "\n" + "\n".join(status_parts)

	text += "\n\nFitness: %.2f" % genome.fitness

	_info_label.text = text
