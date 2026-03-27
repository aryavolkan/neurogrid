class_name HelpPanel
extends CanvasLayer
## In-game help reference. Toggle with F1.
## Tabs: Controls, Receptors & Skills, Genome Guide.

var _panel: PanelContainer
var _tab_container: TabContainer


func _ready() -> void:
	layer = 15
	_build_ui()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -280
	_panel.offset_right = 280
	_panel.offset_top = -260
	_panel.offset_bottom = 260
	_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10, 0.96)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.6, 0.9, 0.7)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)

	var outer := VBoxContainer.new()
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "Help  [F1 to close]"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	outer.add_child(title)

	_tab_container = TabContainer.new()
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tab_container)

	_build_controls_tab()
	_build_receptors_tab()
	_build_genome_tab()

	add_child(_panel)


func _build_controls_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_tab_container.add_child(scroll)

	var sections: Array = [
		["Simulation", [
			["Space", "Pause / Resume"],
			["[ / ]", "Decrease / Increase speed"],
			["R", "Toggle Replay panel"],
			["F2", "Toggle Config Presets panel"],
			["F5", "Quick save simulation"],
			["F9", "Quick load simulation"],
			["F6", "Export best genome per species"],
			["F7", "Export CSV population + species snapshots"],
		]],
		["View", [
			["Tab", "Toggle Stats panel (graphs)"],
			["S", "Toggle Species panel"],
			["P", "Toggle Phylogeny panel"],
			["G", "Toggle Genome viewer"],
			["H", "Cycle Heatmap overlay (food/creature/deaths)"],
			["F3", "Toggle Debug overlay"],
			["F1", "Toggle this Help panel"],
		]],
		["Camera", [
			["WASD / Arrows", "Pan camera"],
			["Scroll wheel", "Zoom in / out"],
			["Middle mouse drag", "Pan camera"],
		]],
		["Sandbox", [
			["Right-click", "Place food on tile"],
			["Shift + Right-click", "Spawn creature on tile"],
			["F (toggle)", "Food placement mode (left-click to place)"],
			["Delete", "Kill selected creature"],
			["Left-click creature", "Inspect creature"],
		]],
	]

	for section in sections:
		var section_title := Label.new()
		section_title.text = section[0]
		section_title.add_theme_font_size_override("font_size", 13)
		section_title.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		vbox.add_child(section_title)

		for entry in section[1]:
			var row := HBoxContainer.new()
			var key_lbl := Label.new()
			key_lbl.text = entry[0]
			key_lbl.custom_minimum_size = Vector2(150, 0)
			key_lbl.add_theme_font_size_override("font_size", 12)
			key_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
			var desc_lbl := Label.new()
			desc_lbl.text = entry[1]
			desc_lbl.add_theme_font_size_override("font_size", 12)
			desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
			row.add_child(key_lbl)
			row.add_child(desc_lbl)
			vbox.add_child(row)

		vbox.add_child(HSeparator.new())


func _build_receptors_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Receptors & Skills"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_tab_container.add_child(scroll)

	_add_section_heading(vbox, "Receptors (evolved sensory inputs)")

	var receptors: Array = [
		["smell_food_dist", "Distance to nearest food (range 5)"],
		["smell_food_dx", "X-direction to nearest food"],
		["smell_food_dy", "Y-direction to nearest food"],
		["sense_enemy_dist", "Distance to nearest non-ally (range 4)"],
		["sense_enemy_dx", "X-direction to nearest non-ally"],
		["sense_ally_count", "Count of same-species allies nearby (range 4)"],
		["detect_pheromone", "Pheromone concentration at current tile (range 3)"],
		["sense_terrain", "Current tile terrain type encoded as float (range 1)"],
	]

	for entry in receptors:
		_add_entry_row(vbox, entry[0], entry[1], Color(0.4, 1.0, 0.6))

	vbox.add_child(HSeparator.new())
	_add_section_heading(vbox, "Skills (evolved action outputs)")

	var skills: Array = [
		["dash", "Move 3 tiles — cost 3.0, cooldown 2s"],
		["bite", "15 damage to adjacent creature — cost 1.5, cooldown 1s"],
		["poison_spit", "5 dmg/tick for 5 ticks (range 2) — cost 4.0, cooldown 3s"],
		["emit_pheromone", "Deposit pheromone at tile — cost 1.0, cooldown 2s"],
		["share_food", "Give 5 energy to adjacent ally — cost 2.0, cooldown 3s"],
		["build_wall", "Place wall on adjacent tile — cost 5.0, cooldown 5s"],
		["heal_self", "Restore 10 health — cost 3.0, cooldown 4s"],
		["burrow", "Underground 5 ticks (damage immune) — cost 2.0, cooldown 6s"],
	]

	for entry in skills:
		_add_entry_row(vbox, entry[0], entry[1], Color(1.0, 0.6, 0.4))


func _build_genome_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Genome Guide"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_tab_container.add_child(scroll)

	var lines: Array = [
		["Dynamic I/O NEAT", Color(0.6, 0.85, 1.0)],
		["NeuroGrid extends standard NEAT with two evolvable node types:", Color(0.8, 0.8, 0.8)],
		["  • Type 3 = Receptor — a sensory input evolved from the receptor registry.", Color(0.8, 0.8, 0.8)],
		["  • Type 4 = Skill — an action output evolved from the skill registry.", Color(0.8, 0.8, 0.8)],
		["", Color(0.0, 0.0, 0.0)],
		["Core Inputs (always present)", Color(0.6, 0.85, 1.0)],
		["energy, health, age, pos_x, pos_y, facing_x, facing_y, food_here", Color(0.8, 0.8, 0.8)],
		["", Color(0.0, 0.0, 0.0)],
		["Core Outputs (always present)", Color(0.6, 0.85, 1.0)],
		["move_x, move_y, eat_desire, mate_desire", Color(0.8, 0.8, 0.8)],
		["", Color(0.0, 0.0, 0.0)],
		["Genome Viewer [G]", Color(0.6, 0.85, 1.0)],
		["Node colors: blue = input, red = output, green = hidden,", Color(0.8, 0.8, 0.8)],
		["  teal = receptor, orange = skill.", Color(0.8, 0.8, 0.8)],
		["Edge thickness ∝ |weight|. Dashed = disabled connection.", Color(0.8, 0.8, 0.8)],
		["", Color(0.0, 0.0, 0.0)],
		["Speciation", Color(0.6, 0.85, 1.0)],
		["Creatures are grouped by genome compatibility distance.", Color(0.8, 0.8, 0.8)],
		["Distance = c1·excess + c2·disjoint + c3·avg_weight + c4·I/O_diff", Color(0.8, 0.8, 0.8)],
		["Species that don't improve for many generations are culled.", Color(0.8, 0.8, 0.8)],
		["", Color(0.0, 0.0, 0.0)],
		["Fitness", Color(0.6, 0.85, 1.0)],
		["Scalar: survival + foraging + reproduction + damage_bonus.", Color(0.8, 0.8, 0.8)],
		["Multi-objective: Vector3(survival, foraging, reproduction)", Color(0.8, 0.8, 0.8)],
		["  used by NSGA-II for Pareto-front selection.", Color(0.8, 0.8, 0.8)],
	]

	for entry in lines:
		var lbl := Label.new()
		lbl.text = entry[0]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", entry[1])
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(lbl)


func _add_section_heading(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	parent.add_child(lbl)


func _add_entry_row(parent: VBoxContainer, name_str: String, desc: String, name_color: Color) -> void:
	var row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = name_str
	name_lbl.custom_minimum_size = Vector2(145, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", name_color)
	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)
	row.add_child(desc_lbl)
	parent.add_child(row)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_panel.visible = not _panel.visible
