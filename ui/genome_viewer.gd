class_name GenomeViewer
extends CanvasLayer
## Visual neural network graph for the selected creature.
## Toggle with G key. Shows nodes colored by type with weighted connections.

var _sim: SimulationManager
var _inspector: CreatureInspector
var _panel: PanelContainer
var _draw_area: Control
var _visible: bool = false

# Layout constants
const PANEL_WIDTH: int = 500
const PANEL_HEIGHT: int = 400
const NODE_RADIUS: float = 10.0
const MARGIN: float = 30.0

# Colors by node type
const COLOR_CORE_INPUT := Color(0.3, 0.5, 1.0)   # blue
const COLOR_HIDDEN := Color(0.3, 0.8, 0.3)        # green
const COLOR_CORE_OUTPUT := Color(1.0, 0.3, 0.3)   # red
const COLOR_RECEPTOR := Color(0.3, 0.9, 0.9)      # cyan
const COLOR_SKILL := Color(1.0, 0.6, 0.2)         # orange

# Core input/output labels
const CORE_INPUT_NAMES: Array = [
	"energy", "health", "age", "pos_x", "pos_y", "face_x", "face_y", "food"
]
const CORE_OUTPUT_NAMES: Array = [
	"move_x", "move_y", "eat", "mate"
]


func _ready() -> void:
	layer = 12
	_build_ui()


func setup(sim: SimulationManager, inspector: CreatureInspector) -> void:
	_sim = sim
	_inspector = inspector


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

	_draw_area = Control.new()
	_draw_area.custom_minimum_size = Vector2(PANEL_WIDTH - 8, PANEL_HEIGHT - 8)
	_draw_area.draw.connect(_on_draw)
	_panel.add_child(_draw_area)

	add_child(_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_G:
		_visible = not _visible
		_panel.visible = _visible
		if _visible:
			_draw_area.queue_redraw()


func _process(_delta: float) -> void:
	if _visible and _panel.visible:
		_draw_area.queue_redraw()


func _on_draw() -> void:
	if not _sim or not _inspector:
		return

	var creature_id: int = _inspector._selected_creature_id
	if creature_id < 0 or not _sim.creatures.has(creature_id):
		_draw_area.draw_string(
			ThemeDB.fallback_font, Vector2(20, 30),
			"No creature selected (click one first)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7)
		)
		return

	var creature: Creature = _sim.creatures[creature_id]
	var genome: DynamicGenome = creature.genome

	# Title
	_draw_area.draw_string(
		ThemeDB.fallback_font, Vector2(10, 16),
		"Genome Viewer — Creature #%d" % creature_id,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.9)
	)

	# Categorize nodes into layers
	var input_nodes: Array = []   # core_input + receptor
	var hidden_nodes: Array = []
	var output_nodes: Array = []  # core_output + skill

	for node in genome.node_genes:
		match node.type:
			DynamicGenome.TYPE_CORE_INPUT, DynamicGenome.TYPE_RECEPTOR:
				input_nodes.append(node)
			DynamicGenome.TYPE_HIDDEN:
				hidden_nodes.append(node)
			DynamicGenome.TYPE_CORE_OUTPUT, DynamicGenome.TYPE_SKILL:
				output_nodes.append(node)

	# Compute positions for each node
	var node_positions: Dictionary = {}  # node_id -> Vector2
	var draw_area_size := _draw_area.size
	var usable_width: float = draw_area_size.x - MARGIN * 2
	var usable_height: float = draw_area_size.y - MARGIN * 2 - 20  # leave room for title

	var num_layers: int = 3 if hidden_nodes.is_empty() else 3
	var layer_x: Array = []
	if hidden_nodes.is_empty():
		layer_x = [MARGIN, MARGIN + usable_width]
	else:
		layer_x = [MARGIN, MARGIN + usable_width * 0.5, MARGIN + usable_width]

	var y_start: float = MARGIN + 24  # below title

	# Position input nodes (left column)
	_position_column(input_nodes, layer_x[0], y_start, usable_height, node_positions)

	# Position hidden nodes (middle column)
	if not hidden_nodes.is_empty():
		_position_column(hidden_nodes, layer_x[1], y_start, usable_height, node_positions)

	# Position output nodes (right column)
	var out_x: float = layer_x[-1]
	_position_column(output_nodes, out_x, y_start, usable_height, node_positions)

	# Draw connections
	for conn in genome.connection_genes:
		if not conn.enabled:
			continue
		if not node_positions.has(conn.in_id) or not node_positions.has(conn.out_id):
			continue
		var from_pos: Vector2 = node_positions[conn.in_id]
		var to_pos: Vector2 = node_positions[conn.out_id]
		var weight: float = conn.weight
		var thickness: float = clampf(absf(weight) * 1.5, 0.5, 4.0)
		var color: Color = Color(0.2, 0.8, 0.2, 0.6) if weight >= 0 else Color(0.8, 0.2, 0.2, 0.6)
		_draw_area.draw_line(from_pos, to_pos, color, thickness)

	# Draw nodes and labels
	for node in genome.node_genes:
		if not node_positions.has(node.id):
			continue
		var pos: Vector2 = node_positions[node.id]
		var color: Color = _get_node_color(node.type)
		_draw_area.draw_circle(pos, NODE_RADIUS, color)
		_draw_area.draw_circle(pos, NODE_RADIUS, Color(0.8, 0.8, 0.8, 0.7), false, 1.0)

		# Label
		var label: String = _get_node_label(node)
		var label_offset := Vector2(NODE_RADIUS + 4, 4)
		if node.is_output():
			# Draw label to the left for output nodes
			label_offset = Vector2(-NODE_RADIUS - 4 - label.length() * 6.0, 4)
		_draw_area.draw_string(
			ThemeDB.fallback_font, pos + label_offset,
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.8)
		)


func _position_column(nodes: Array, x: float, y_start: float, height: float, positions: Dictionary) -> void:
	var count: int = nodes.size()
	if count == 0:
		return
	var spacing: float = height / float(count + 1)
	for i in count:
		var y: float = y_start + spacing * (i + 1)
		positions[nodes[i].id] = Vector2(x, y)


func _get_node_color(type: int) -> Color:
	match type:
		DynamicGenome.TYPE_CORE_INPUT:
			return COLOR_CORE_INPUT
		DynamicGenome.TYPE_HIDDEN:
			return COLOR_HIDDEN
		DynamicGenome.TYPE_CORE_OUTPUT:
			return COLOR_CORE_OUTPUT
		DynamicGenome.TYPE_RECEPTOR:
			return COLOR_RECEPTOR
		DynamicGenome.TYPE_SKILL:
			return COLOR_SKILL
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
