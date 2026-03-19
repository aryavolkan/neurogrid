class_name PhylogenyPanel
extends CanvasLayer
## Phylogenetic tree visualization. Toggle with P key.
## Shows species lineage over generations: branching, extinction, and dominance.

var _sim: SimulationManager
var _panel: PanelContainer
var _draw_area: Control
var _visible: bool = false

const PANEL_WIDTH: int = 700
const PANEL_HEIGHT: int = 450
const BAR_MIN_HEIGHT: float = 2.0
const BAR_MAX_HEIGHT: float = 8.0
const MARGIN: float = 40.0
const LABEL_FONT_SIZE: int = 10
const TITLE_FONT_SIZE: int = 14
const MAX_SPECIES_SHOWN: int = 50  # Limit for performance


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

	_draw_area = Control.new()
	_draw_area.custom_minimum_size = Vector2(PANEL_WIDTH - 8, PANEL_HEIGHT - 8)
	_draw_area.draw.connect(_on_draw)
	_panel.add_child(_draw_area)

	add_child(_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_P:
		_visible = not _visible
		_panel.visible = _visible
		if _visible:
			_draw_area.queue_redraw()


func _process(_delta: float) -> void:
	if _visible and _panel.visible:
		_draw_area.queue_redraw()


func _on_draw() -> void:
	if not _sim or not _sim.phylogeny:
		return

	var nodes: Dictionary = _sim.phylogeny.get_all_nodes()
	if nodes.is_empty():
		_draw_area.draw_string(
			ThemeDB.fallback_font, Vector2(20, 30),
			"No species data yet",
			HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE, Color(0.7, 0.7, 0.7)
		)
		return

	var current_tick: int = _sim.get_tick_count()

	# Title
	var living_count: int = _sim.phylogeny.get_living_species().size()
	var total_count: int = nodes.size()
	_draw_area.draw_string(
		ThemeDB.fallback_font, Vector2(10, 16),
		"Phylogeny — %d species (%d alive, %d extinct) | P to close" % [
			total_count, living_count, total_count - living_count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE, Color(0.9, 0.9, 0.9)
	)

	# Select species to show (most recent first, capped)
	var species_list: Array = nodes.keys()
	species_list.sort_custom(func(a, b): return nodes[a].born_tick > nodes[b].born_tick)
	if species_list.size() > MAX_SPECIES_SHOWN:
		species_list.resize(MAX_SPECIES_SHOWN)

	# Layout: assign y-slots via DFS tree traversal
	var layout: Array = _compute_layout(nodes, species_list, current_tick)

	# Find tick range for x-axis
	var min_tick: int = current_tick
	var max_tick: int = 0
	for entry in layout:
		min_tick = mini(min_tick, entry.born_tick)
		max_tick = maxi(max_tick, entry.end_tick)
	if max_tick <= min_tick:
		max_tick = min_tick + 1

	var draw_left: float = MARGIN
	var draw_right: float = _draw_area.size.x - MARGIN
	var draw_top: float = MARGIN + 10
	var draw_bottom: float = _draw_area.size.y - 20.0
	var x_scale: float = (draw_right - draw_left) / float(max_tick - min_tick)
	var slot_count: int = layout.size()
	var y_spacing: float = (draw_bottom - draw_top) / float(maxi(slot_count, 1))

	# Draw tick axis
	_draw_tick_axis(min_tick, max_tick, draw_left, draw_right, draw_bottom)

	# Draw branches and bars
	for i in layout.size():
		var entry: Dictionary = layout[i]
		var y: float = draw_top + y_spacing * (i + 0.5)
		var x_start: float = draw_left + float(entry.born_tick - min_tick) * x_scale
		var x_end: float = draw_left + float(entry.end_tick - min_tick) * x_scale
		var color: Color = _get_species_color(entry.species_id)
		var alive: bool = entry.alive

		if not alive:
			color.a = 0.4

		# Bar height based on peak members
		var bar_h: float = clampf(float(entry.peak_members) * 0.5, BAR_MIN_HEIGHT, BAR_MAX_HEIGHT)

		# Draw the lifespan bar
		var bar_rect := Rect2(x_start, y - bar_h / 2.0, maxf(x_end - x_start, 2.0), bar_h)
		_draw_area.draw_rect(bar_rect, color)

		# Extinction marker
		if not alive:
			_draw_area.draw_line(
				Vector2(x_end, y - bar_h), Vector2(x_end, y + bar_h),
				Color(1.0, 0.3, 0.3, 0.7), 1.5
			)

		# Parent connector
		if entry.parent_slot >= 0:
			var parent_y: float = draw_top + y_spacing * (entry.parent_slot + 0.5)
			var branch_x: float = x_start
			# Vertical line from parent to child
			_draw_area.draw_line(
				Vector2(branch_x, parent_y), Vector2(branch_x, y),
				Color(0.5, 0.5, 0.5, 0.5), 1.0
			)

		# Species label
		var label: String = "S%d" % entry.species_id
		if alive:
			label += " *"
		_draw_area.draw_string(
			ThemeDB.fallback_font, Vector2(x_end + 3, y + 3),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color
		)

	# Legend
	_draw_legend(draw_right - 120, draw_top)


func _compute_layout(nodes: Dictionary, species_list: Array, current_tick: int) -> Array:
	## Assign y-slots. Returns array of {species_id, born_tick, end_tick, alive, peak_members, parent_slot}.
	var layout: Array = []
	var slot_map: Dictionary = {}  # species_id -> slot index

	# Build tree order: roots first, then children
	var ordered: Array = []
	var visited: Dictionary = {}

	# DFS from roots
	var roots: Array = []
	for sid in species_list:
		var node: PhylogenyTracker.PhyloNode = nodes[sid]
		if node.parent_species_id < 0 or not nodes.has(node.parent_species_id):
			roots.append(sid)

	# Sort roots by born_tick
	roots.sort_custom(func(a, b): return nodes[a].born_tick < nodes[b].born_tick)

	for root_id in roots:
		_dfs_order(root_id, nodes, species_list, visited, ordered)

	# Add any remaining (disconnected) species
	for sid in species_list:
		if not visited.has(sid):
			ordered.append(sid)

	# Build layout entries
	for sid in ordered:
		var node: PhylogenyTracker.PhyloNode = nodes[sid]
		var end_tick: int = node.extinct_tick if node.extinct_tick >= 0 else current_tick
		var parent_slot: int = slot_map.get(node.parent_species_id, -1)
		var slot: int = layout.size()
		slot_map[sid] = slot
		layout.append({
			"species_id": sid,
			"born_tick": node.born_tick,
			"end_tick": end_tick,
			"alive": node.is_alive(),
			"peak_members": node.peak_members,
			"parent_slot": parent_slot,
		})

	return layout


func _dfs_order(sid: int, nodes: Dictionary, allowed: Array, visited: Dictionary, result: Array) -> void:
	if visited.has(sid) or sid not in allowed:
		return
	visited[sid] = true
	result.append(sid)
	var node: PhylogenyTracker.PhyloNode = nodes[sid]
	for child_id in node.children:
		_dfs_order(child_id, nodes, allowed, visited, result)


func _draw_tick_axis(min_tick: int, max_tick: int, x_left: float, x_right: float, y: float) -> void:
	## Draw a simple tick axis at the bottom.
	_draw_area.draw_line(Vector2(x_left, y), Vector2(x_right, y), Color(0.3, 0.3, 0.3), 1.0)
	var tick_range: int = max_tick - min_tick
	var step: int = maxi(tick_range / 5, 1)
	# Round step to nice number
	if step > 100:
		step = (step / 100) * 100
	elif step > 10:
		step = (step / 10) * 10
	var t: int = ((min_tick / step) + 1) * step
	var x_scale: float = (x_right - x_left) / float(tick_range)
	while t < max_tick:
		var x: float = x_left + float(t - min_tick) * x_scale
		_draw_area.draw_line(Vector2(x, y), Vector2(x, y + 5), Color(0.4, 0.4, 0.4), 1.0)
		_draw_area.draw_string(
			ThemeDB.fallback_font, Vector2(x - 10, y + 16),
			str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.5)
		)
		t += step


func _draw_legend(x: float, y: float) -> void:
	_draw_area.draw_rect(Rect2(x, y, 10, 4), Color(0.5, 0.8, 0.5))
	_draw_area.draw_string(
		ThemeDB.fallback_font, Vector2(x + 14, y + 5),
		"Alive", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.7)
	)
	_draw_area.draw_rect(Rect2(x, y + 12, 10, 4), Color(0.5, 0.5, 0.5, 0.4))
	_draw_area.draw_string(
		ThemeDB.fallback_font, Vector2(x + 14, y + 17),
		"Extinct", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.7, 0.7, 0.7)
	)
	_draw_area.draw_string(
		ThemeDB.fallback_font, Vector2(x, y + 30),
		"Bar height = pop size", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.5)
	)


static func _get_species_color(species_id: int) -> Color:
	return Color.from_hsv(fmod(float(species_id) * 0.618, 1.0), 0.7, 0.9)
