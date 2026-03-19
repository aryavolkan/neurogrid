class_name SpeciesPanel
extends CanvasLayer
## Species selection panel with neural topology view. Toggle with S key.
## Click a species row to highlight all its members and show the representative genome's network.

var _sim: SimulationManager
var _panel: PanelContainer
var _list_area: Control
var _network_area: Control
var _visible: bool = false
var _selected_species_id: int = -1
var _species_rows: Array = []  # Array of {id, rect} for click detection

const PANEL_WIDTH: int = 620
const PANEL_HEIGHT: int = 500
const LIST_WIDTH: float = 200.0
const LIST_ROW_HEIGHT: float = 22.0
const MARGIN: float = 10.0
const NET_NODE_RADIUS: float = 8.0

# Node type colors (matching GenomeViewer)
const COLOR_CORE_INPUT := Color(0.3, 0.5, 1.0)
const COLOR_HIDDEN := Color(0.3, 0.8, 0.3)
const COLOR_CORE_OUTPUT := Color(1.0, 0.3, 0.3)
const COLOR_RECEPTOR := Color(0.3, 0.9, 0.9)
const COLOR_SKILL := Color(1.0, 0.6, 0.2)

const CORE_INPUT_NAMES: Array = [
	"energy", "health", "age", "pos_x", "pos_y", "face_x", "face_y", "food"
]
const CORE_OUTPUT_NAMES: Array = [
	"move_x", "move_y", "eat", "mate"
]


func _ready() -> void:
	layer = 13
	_build_ui()


func setup(sim: SimulationManager) -> void:
	_sim = sim


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_WIDTH / 2
	_panel.offset_right = PANEL_WIDTH / 2
	_panel.offset_top = -PANEL_HEIGHT / 2
	_panel.offset_bottom = PANEL_HEIGHT / 2
	_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	_panel.add_child(hbox)

	# Left: species list
	_list_area = Control.new()
	_list_area.custom_minimum_size = Vector2(LIST_WIDTH, PANEL_HEIGHT - 8)
	_list_area.draw.connect(_draw_list)
	_list_area.gui_input.connect(_on_list_input)
	_list_area.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.add_child(_list_area)

	# Right: network topology
	_network_area = Control.new()
	_network_area.custom_minimum_size = Vector2(PANEL_WIDTH - LIST_WIDTH - 12, PANEL_HEIGHT - 8)
	_network_area.draw.connect(_draw_network)
	hbox.add_child(_network_area)

	add_child(_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_S:
		_visible = not _visible
		_panel.visible = _visible
		if not _visible:
			_clear_highlights()
			_selected_species_id = -1
		else:
			_list_area.queue_redraw()
			_network_area.queue_redraw()


func _process(_delta: float) -> void:
	if _visible and _panel.visible:
		_list_area.queue_redraw()
		_network_area.queue_redraw()


func _clear_highlights() -> void:
	if not _sim:
		return
	for cid in _sim.creatures:
		_sim.creatures[cid].species_highlighted = false


func _highlight_species(species_id: int) -> void:
	_clear_highlights()
	if not _sim or species_id < 0:
		return
	for cid in _sim.creatures:
		var c: Creature = _sim.creatures[cid]
		c.species_highlighted = (c.body.species_id == species_id)


func _on_list_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for row in _species_rows:
			if row.rect.has_point(event.position):
				_selected_species_id = row.id
				_highlight_species(_selected_species_id)
				_network_area.queue_redraw()
				return


# --- Drawing: Species List ---

func _draw_list() -> void:
	if not _sim:
		return

	_species_rows.clear()

	# Background
	_list_area.draw_rect(Rect2(0, 0, LIST_WIDTH, _list_area.size.y), Color(0.08, 0.08, 0.1))

	# Title
	_list_area.draw_string(
		ThemeDB.fallback_font, Vector2(MARGIN, 16),
		"Species [S]", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.9, 0.9)
	)

	var counts := _sim.get_species_counts()
	var sorted_ids: Array = counts.keys()
	sorted_ids.sort_custom(func(a, b): return counts[a] > counts[b])

	var y: float = 32.0
	for sid in sorted_ids:
		if y + LIST_ROW_HEIGHT > _list_area.size.y - 10:
			break

		var row_rect := Rect2(2, y, LIST_WIDTH - 4, LIST_ROW_HEIGHT)
		_species_rows.append({"id": sid, "rect": row_rect})

		# Highlight selected row
		if sid == _selected_species_id:
			_list_area.draw_rect(row_rect, Color(0.2, 0.3, 0.5, 0.6))

		# Species color swatch
		var swatch_color := _get_species_color(sid)
		_list_area.draw_rect(Rect2(MARGIN, y + 4, 12, 12), swatch_color)

		# Species info text
		var info = _sim.species_manager.get_species_info(sid)
		var count: int = counts[sid]
		var stag_str: String = ""
		if info and info.generations_without_improvement > 2:
			stag_str = " !"

		var label := "S%d: %d%s" % [sid, count, stag_str]
		_list_area.draw_string(
			ThemeDB.fallback_font, Vector2(MARGIN + 16, y + 15),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.85, 0.85)
		)

		# Fitness bar
		if info:
			var bar_x: float = LIST_WIDTH - 60
			var bar_w: float = 50.0
			var fitness_frac: float = clampf(info.best_fitness_ever / 20.0, 0.0, 1.0)
			_list_area.draw_rect(Rect2(bar_x, y + 6, bar_w, 8), Color(0.15, 0.15, 0.15))
			_list_area.draw_rect(Rect2(bar_x, y + 6, bar_w * fitness_frac, 8), Color(0.2, 0.7, 0.3, 0.8))

		y += LIST_ROW_HEIGHT

	# Footer with count
	_list_area.draw_string(
		ThemeDB.fallback_font, Vector2(MARGIN, _list_area.size.y - 8),
		"%d species total" % sorted_ids.size(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.5, 0.5)
	)


# --- Drawing: Neural Topology ---

func _draw_network() -> void:
	if not _sim:
		return

	# Background
	_network_area.draw_rect(Rect2(0, 0, _network_area.size.x, _network_area.size.y), Color(0.06, 0.06, 0.09))

	if _selected_species_id < 0:
		_network_area.draw_string(
			ThemeDB.fallback_font, Vector2(20, 30),
			"Select a species to view topology",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.5, 0.5)
		)
		return

	var info = _sim.species_manager.get_species_info(_selected_species_id)
	if not info:
		_network_area.draw_string(
			ThemeDB.fallback_font, Vector2(20, 30),
			"Species extinct",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.3, 0.3)
		)
		return

	var genome: DynamicGenome = info.representative_genome
	var counts := _sim.get_species_counts()
	var count: int = counts.get(_selected_species_id, 0)

	# Title
	var title_color := _get_species_color(_selected_species_id)
	_network_area.draw_string(
		ThemeDB.fallback_font, Vector2(MARGIN, 16),
		"Species %d — %d members" % [_selected_species_id, count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, title_color
	)

	# Stats line
	var stats_text := "Nodes: %d | Conns: %d | Receptors: %d | Skills: %d | Best: %.2f | Age: %d | Stag: %d" % [
		genome.node_genes.size(), genome.connection_genes.size(),
		genome.get_receptor_count(), genome.get_skill_count(),
		info.best_fitness_ever, info.age, info.generations_without_improvement,
	]
	_network_area.draw_string(
		ThemeDB.fallback_font, Vector2(MARGIN, 30),
		stats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.6)
	)

	# Draw network
	_draw_genome_network(genome, 40.0)


func _draw_genome_network(genome: DynamicGenome, y_start: float) -> void:
	## Draw the neural network topology for the representative genome.
	var area_w: float = _network_area.size.x - MARGIN * 2
	var area_h: float = _network_area.size.y - y_start - MARGIN

	# Categorize nodes
	var input_nodes: Array = []
	var hidden_nodes: Array = []
	var output_nodes: Array = []

	for node in genome.node_genes:
		match node.type:
			DynamicGenome.TYPE_CORE_INPUT, DynamicGenome.TYPE_RECEPTOR:
				input_nodes.append(node)
			DynamicGenome.TYPE_HIDDEN:
				hidden_nodes.append(node)
			DynamicGenome.TYPE_CORE_OUTPUT, DynamicGenome.TYPE_SKILL:
				output_nodes.append(node)

	# Compute positions
	var node_positions: Dictionary = {}

	var layer_x: Array
	if hidden_nodes.is_empty():
		layer_x = [MARGIN + 60, MARGIN + area_w - 60]
	else:
		layer_x = [MARGIN + 60, MARGIN + area_w * 0.5, MARGIN + area_w - 60]

	_layout_column(input_nodes, layer_x[0], y_start, area_h, node_positions)
	if not hidden_nodes.is_empty():
		_layout_column(hidden_nodes, layer_x[1], y_start, area_h, node_positions)
	_layout_column(output_nodes, layer_x[-1], y_start, area_h, node_positions)

	# Draw connections
	for conn in genome.connection_genes:
		if not conn.enabled:
			continue
		if not node_positions.has(conn.in_id) or not node_positions.has(conn.out_id):
			continue
		var from_pos: Vector2 = node_positions[conn.in_id]
		var to_pos: Vector2 = node_positions[conn.out_id]
		var weight: float = conn.weight
		var thickness: float = clampf(absf(weight) * 1.5, 0.5, 3.0)
		var color: Color = Color(0.2, 0.7, 0.2, 0.5) if weight >= 0 else Color(0.7, 0.2, 0.2, 0.5)
		_network_area.draw_line(from_pos, to_pos, color, thickness)

	# Draw nodes
	for node in genome.node_genes:
		if not node_positions.has(node.id):
			continue
		var pos: Vector2 = node_positions[node.id]
		var color: Color = _get_node_color(node.type)
		_network_area.draw_circle(pos, NET_NODE_RADIUS, color)
		_network_area.draw_arc(pos, NET_NODE_RADIUS, 0, TAU, 16, Color(0.7, 0.7, 0.7, 0.5), 1.0)

		# Labels
		var label: String = _get_node_label(node)
		var label_x: float
		if node.type == DynamicGenome.TYPE_CORE_INPUT or node.type == DynamicGenome.TYPE_RECEPTOR:
			label_x = pos.x - NET_NODE_RADIUS - 4 - label.length() * 5.5
		else:
			label_x = pos.x + NET_NODE_RADIUS + 4
		_network_area.draw_string(
			ThemeDB.fallback_font, Vector2(label_x, pos.y + 3),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.7)
		)

	# Legend at bottom
	_draw_legend(MARGIN, _network_area.size.y - 16)


func _layout_column(nodes: Array, x: float, y_start: float, height: float, positions: Dictionary) -> void:
	var count: int = nodes.size()
	if count == 0:
		return
	var spacing: float = height / float(count + 1)
	for i in count:
		var y: float = y_start + spacing * (i + 1)
		positions[nodes[i].id] = Vector2(x, y)


func _draw_legend(x: float, y: float) -> void:
	var items: Array = [
		{"color": COLOR_CORE_INPUT, "label": "Input"},
		{"color": COLOR_RECEPTOR, "label": "Receptor"},
		{"color": COLOR_HIDDEN, "label": "Hidden"},
		{"color": COLOR_CORE_OUTPUT, "label": "Output"},
		{"color": COLOR_SKILL, "label": "Skill"},
	]
	var cx: float = x
	for item in items:
		_network_area.draw_circle(Vector2(cx, y), 4, item.color)
		_network_area.draw_string(
			ThemeDB.fallback_font, Vector2(cx + 7, y + 3),
			item.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.5)
		)
		cx += item.label.length() * 6 + 20


func _get_node_color(type: int) -> Color:
	match type:
		DynamicGenome.TYPE_CORE_INPUT: return COLOR_CORE_INPUT
		DynamicGenome.TYPE_HIDDEN: return COLOR_HIDDEN
		DynamicGenome.TYPE_CORE_OUTPUT: return COLOR_CORE_OUTPUT
		DynamicGenome.TYPE_RECEPTOR: return COLOR_RECEPTOR
		DynamicGenome.TYPE_SKILL: return COLOR_SKILL
	return Color.WHITE


func _get_node_label(node: DynamicGenome.DynamicNodeGene) -> String:
	match node.type:
		DynamicGenome.TYPE_CORE_INPUT:
			if node.id < CORE_INPUT_NAMES.size():
				return CORE_INPUT_NAMES[node.id]
			return "in_%d" % node.id
		DynamicGenome.TYPE_CORE_OUTPUT:
			var out_idx: int = node.id - GameConfig.CORE_INPUT_COUNT
			if out_idx >= 0 and out_idx < CORE_OUTPUT_NAMES.size():
				return CORE_OUTPUT_NAMES[out_idx]
			return "out_%d" % node.id
		DynamicGenome.TYPE_HIDDEN:
			return "h%d" % node.id
		DynamicGenome.TYPE_RECEPTOR:
			var entry = Registries.receptor_registry.get_entry(node.registry_id)
			return entry.name if entry else "r%d" % node.registry_id
		DynamicGenome.TYPE_SKILL:
			var entry = Registries.skill_registry.get_entry(node.registry_id)
			return entry.name if entry else "s%d" % node.registry_id
	return str(node.id)


static func _get_species_color(species_id: int) -> Color:
	return Color.from_hsv(fmod(float(species_id) * 0.618, 1.0), 0.7, 0.9)
