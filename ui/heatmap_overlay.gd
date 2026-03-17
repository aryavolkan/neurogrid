class_name HeatmapOverlay
extends CanvasLayer
## Semi-transparent grid overlay showing density heatmaps.
## Toggle with H key; cycles through: Food -> Creature -> Deaths -> Off

enum Mode { OFF, FOOD, CREATURE, DEATH }

var _sim: SimulationManager
var _mode: Mode = Mode.OFF
var _draw_node: Control
var _label: Label

const MODE_NAMES: Array = ["Off", "Food Density", "Creature Density", "Death Locations"]


func _ready() -> void:
	layer = 5
	_build_ui()


func setup(sim: SimulationManager) -> void:
	_sim = sim


func _build_ui() -> void:
	# The draw node is a Control overlaid on the world (not in screen space).
	# We use SubViewport approach: a simple Control node drawn in world coords.
	_draw_node = Control.new()
	_draw_node.custom_minimum_size = Vector2(
		GameConfig.GRID_WIDTH * GameConfig.TILE_SIZE,
		GameConfig.GRID_HEIGHT * GameConfig.TILE_SIZE
	)
	_draw_node.size = _draw_node.custom_minimum_size
	_draw_node.draw.connect(_on_draw)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.visible = false

	# Mode indicator label
	_label = Label.new()
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.anchor_top = 1.0
	_label.offset_top = -30
	_label.offset_left = -80
	_label.offset_right = 80
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_label.visible = false
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		_mode = (_mode + 1) % Mode.size() as Mode
		_label.text = "Heatmap: %s" % MODE_NAMES[_mode]
		_label.visible = _mode != Mode.OFF
		if _mode == Mode.OFF:
			_remove_draw_node()
		else:
			_ensure_draw_node()
			_draw_node.queue_redraw()


func _process(_delta: float) -> void:
	if _mode != Mode.OFF and _draw_node.visible:
		_draw_node.queue_redraw()


func _ensure_draw_node() -> void:
	if not _sim:
		return
	# Add draw_node as child of GridWorld so it inherits world transform
	if _draw_node.get_parent() != _sim.world:
		if _draw_node.get_parent():
			_draw_node.get_parent().remove_child(_draw_node)
		_sim.world.add_child(_draw_node)
	_draw_node.visible = true


func _remove_draw_node() -> void:
	_draw_node.visible = false


func _on_draw() -> void:
	if not _sim or _mode == Mode.OFF:
		return

	var ts: int = GameConfig.TILE_SIZE

	match _mode:
		Mode.FOOD:
			_draw_food_heatmap(ts)
		Mode.CREATURE:
			_draw_creature_heatmap(ts)
		Mode.DEATH:
			_draw_death_heatmap(ts)


func _draw_food_heatmap(ts: int) -> void:
	for pos in _sim.world.tiles:
		var tile: GridTile = _sim.world.tiles[pos]
		if tile.food > 0.0:
			var intensity: float = clampf(tile.food / GameConfig.MAX_FOOD_PER_TILE, 0.05, 1.0)
			var rect := Rect2(pos.x * ts, pos.y * ts, ts, ts)
			_draw_node.draw_rect(rect, Color(0.1, 0.9, 0.1, intensity * 0.5))


func _draw_creature_heatmap(ts: int) -> void:
	# Build density grid using 4x4 cell buckets
	var cell_size: int = 4
	var cells_w: int = ceili(float(GameConfig.GRID_WIDTH) / cell_size)
	var cells_h: int = ceili(float(GameConfig.GRID_HEIGHT) / cell_size)
	var density: Dictionary = {}  # Vector2i(cell_x, cell_y) -> count
	var max_density: int = 1

	for pos in _sim.world._creature_positions:
		var cell := Vector2i(pos.x / cell_size, pos.y / cell_size)
		density[cell] = density.get(cell, 0) + 1
		if density[cell] > max_density:
			max_density = density[cell]

	for cell in density:
		var intensity: float = float(density[cell]) / float(max_density)
		var rect := Rect2(
			cell.x * cell_size * ts, cell.y * cell_size * ts,
			cell_size * ts, cell_size * ts
		)
		_draw_node.draw_rect(rect, Color(0.2, 0.4, 1.0, intensity * 0.5))


func _draw_death_heatmap(ts: int) -> void:
	if not _sim.logger:
		return
	for death_pos in _sim.logger.death_locations:
		var center := Vector2(
			death_pos.x * ts + ts * 0.5,
			death_pos.y * ts + ts * 0.5
		)
		_draw_node.draw_circle(center, ts * 0.3, Color(1.0, 0.1, 0.1, 0.4))
