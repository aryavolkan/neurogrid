class_name StatsPanel
extends CanvasLayer
## Real-time statistics panel with history graphs drawn via _draw().

var _sim: SimulationManager
var _panel: PanelContainer
var _graph_node: Control
var _text_label: RichTextLabel
var _visible: bool = false

# History buffers (ring buffers)
const MAX_HISTORY: int = 200
var _pop_history: PackedFloat32Array
var _fitness_history: PackedFloat32Array
var _species_history: PackedFloat32Array
var _history_index: int = 0
var _history_count: int = 0

const GRAPH_WIDTH: float = 280.0
const GRAPH_HEIGHT: float = 60.0


func _ready() -> void:
	layer = 10
	_pop_history.resize(MAX_HISTORY)
	_fitness_history.resize(MAX_HISTORY)
	_species_history.resize(MAX_HISTORY)
	_build_ui()


func setup(sim: SimulationManager) -> void:
	_sim = sim
	sim.generation_complete.connect(_on_generation_complete)
	sim.tick_complete.connect(_on_tick)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 8
	_panel.offset_bottom = -8
	_panel.offset_top = -280
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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Statistics [Tab to toggle]"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(title)

	_graph_node = Control.new()
	_graph_node.custom_minimum_size = Vector2(GRAPH_WIDTH, GRAPH_HEIGHT * 3 + 20)
	_graph_node.draw.connect(_draw_graphs)
	vbox.add_child(_graph_node)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.custom_minimum_size = Vector2(GRAPH_WIDTH, 0)
	_text_label.add_theme_font_size_override("normal_font_size", 11)
	_text_label.add_theme_color_override("default_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_text_label)

	add_child(_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_visible = not _visible
		_panel.visible = _visible


func _on_tick(_tick: int) -> void:
	if not _sim or not _visible:
		return
	if _tick % 10 != 0:  # Sample every 10 ticks
		return

	_pop_history[_history_index] = float(_sim.get_creature_count())
	_species_history[_history_index] = float(_sim.get_species_counts().size())
	_history_index = (_history_index + 1) % MAX_HISTORY
	_history_count = mini(_history_count + 1, MAX_HISTORY)

	_graph_node.queue_redraw()


func _on_generation_complete(_generation: int, stats: Dictionary) -> void:
	_fitness_history[_history_index] = stats.get("avg_fitness", 0.0)

	if not _visible:
		return

	var text := ""
	text += "Gen %d | Deaths: %d\n" % [stats.get("generation", 0), stats.get("deaths", 0)]
	text += "Best: %.2f | Avg: %.2f\n" % [stats.get("best_fitness", 0.0), stats.get("avg_fitness", 0.0)]
	if _sim:
		text += "Food: %.0f" % _sim.food_manager.get_total_food()
		if _sim.food_manager.is_famine():
			text += " [color=red](FAMINE)[/color]"
	_text_label.text = text


func _draw_graphs() -> void:
	if _history_count < 2:
		return

	var y_offset: float = 0.0
	_draw_graph(_graph_node, _pop_history, Color(0.2, 0.8, 0.2), "Pop", y_offset)
	y_offset += GRAPH_HEIGHT + 10
	_draw_graph(_graph_node, _species_history, Color(0.8, 0.6, 0.2), "Species", y_offset)
	y_offset += GRAPH_HEIGHT + 10
	_draw_graph(_graph_node, _fitness_history, Color(0.2, 0.6, 0.8), "Fitness", y_offset)


func _draw_graph(node: Control, data: PackedFloat32Array, color: Color, label: String, y_off: float) -> void:
	# Background
	node.draw_rect(Rect2(0, y_off, GRAPH_WIDTH, GRAPH_HEIGHT), Color(0.1, 0.1, 0.1, 0.5))

	# Find range
	var max_val: float = 1.0
	for i in _history_count:
		var idx := (_history_index - _history_count + i + MAX_HISTORY) % MAX_HISTORY
		max_val = maxf(max_val, data[idx])

	# Draw line
	var prev_point := Vector2.ZERO
	for i in _history_count:
		var idx := (_history_index - _history_count + i + MAX_HISTORY) % MAX_HISTORY
		var x: float = float(i) / float(maxi(_history_count - 1, 1)) * GRAPH_WIDTH
		var y: float = y_off + GRAPH_HEIGHT - (data[idx] / max_val) * GRAPH_HEIGHT
		var point := Vector2(x, y)
		if i > 0:
			node.draw_line(prev_point, point, color, 1.5)
		prev_point = point

	# Label
	node.draw_string(ThemeDB.fallback_font, Vector2(2, y_off + 12), "%s (max: %.0f)" % [label, max_val], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))
