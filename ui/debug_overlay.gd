class_name DebugOverlay
extends CanvasLayer
## Shows selected creature's sensory inputs, outputs, and action summary.
## Toggle with F3.

var _sim: SimulationManager
var _inspector: CreatureInspector
var _panel: PanelContainer
var _draw_area: Control
var _visible: bool = false

const PANEL_WIDTH: int = 280
const BAR_HEIGHT: float = 14.0
const BAR_WIDTH: float = 120.0
const LINE_SPACING: float = 18.0
const LABEL_WIDTH: float = 110.0

const CORE_INPUT_NAMES: Array = [
	"energy", "health", "age", "pos_x", "pos_y", "face_x", "face_y", "food"
]
const CORE_OUTPUT_NAMES: Array = [
	"move_x", "move_y", "eat", "mate"
]


func _ready() -> void:
	layer = 11
	_build_ui()


func setup(sim: SimulationManager, inspector: CreatureInspector) -> void:
	_sim = sim
	_inspector = inspector


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.offset_left = 8
	_panel.offset_top = 8
	_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.85)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", style)

	_draw_area = Control.new()
	_draw_area.custom_minimum_size = Vector2(PANEL_WIDTH, 100)
	_draw_area.draw.connect(_on_draw)
	_panel.add_child(_draw_area)

	add_child(_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
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
		_draw_area.custom_minimum_size = Vector2(PANEL_WIDTH, 30)
		_draw_area.draw_string(
			ThemeDB.fallback_font, Vector2(4, 16),
			"No creature selected",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.7)
		)
		return

	var creature: Creature = _sim.creatures[creature_id]
	var brain: CreatureBrain = creature.brain
	var y: float = 0.0

	# Title
	y += 14.0
	_draw_area.draw_string(
		ThemeDB.fallback_font, Vector2(4, y),
		"Debug — Creature #%d" % creature_id,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.9)
	)
	y += 6.0

	# Core inputs
	y += 14.0
	_draw_area.draw_string(
		ThemeDB.fallback_font, Vector2(4, y),
		"Core Inputs", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.5, 1.0)
	)
	y += 4.0

	if brain.last_inputs.size() > 0:
		for i in mini(brain.last_inputs.size(), GameConfig.CORE_INPUT_COUNT):
			var name: String = CORE_INPUT_NAMES[i] if i < CORE_INPUT_NAMES.size() else "in_%d" % i
			y += LINE_SPACING
			_draw_bar(y, name, brain.last_inputs[i], Color(0.3, 0.5, 1.0))

	# Receptor inputs
	var receptor_order := brain.network.get_receptor_order()
	if not receptor_order.is_empty():
		y += LINE_SPACING + 4.0
		_draw_area.draw_string(
			ThemeDB.fallback_font, Vector2(4, y),
			"Receptors", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.3, 0.9, 0.9)
		)
		y += 4.0

		for i in receptor_order.size():
			var input_idx: int = GameConfig.CORE_INPUT_COUNT + i
			var val: float = brain.last_inputs[input_idx] if input_idx < brain.last_inputs.size() else 0.0
			var entry = Registries.receptor_registry.get_entry(receptor_order[i].registry_id)
			var name: String = entry.name if entry else "r%d" % receptor_order[i].registry_id
			y += LINE_SPACING
			_draw_bar(y, name, val, Color(0.3, 0.9, 0.9))

	# Core outputs
	y += LINE_SPACING + 4.0
	_draw_area.draw_string(
		ThemeDB.fallback_font, Vector2(4, y),
		"Core Outputs", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.3, 0.3)
	)
	y += 4.0

	if brain.last_outputs.size() > 0:
		for i in mini(brain.last_outputs.size(), GameConfig.CORE_OUTPUT_COUNT):
			var name: String = CORE_OUTPUT_NAMES[i] if i < CORE_OUTPUT_NAMES.size() else "out_%d" % i
			y += LINE_SPACING
			_draw_bar(y, name, brain.last_outputs[i], Color(1.0, 0.3, 0.3))

	# Skill outputs
	var skill_order := brain.network.get_skill_order()
	if not skill_order.is_empty():
		y += LINE_SPACING + 4.0
		_draw_area.draw_string(
			ThemeDB.fallback_font, Vector2(4, y),
			"Skills", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.6, 0.2)
		)
		y += 4.0

		for i in skill_order.size():
			var output_idx: int = GameConfig.CORE_OUTPUT_COUNT + i
			var val: float = brain.last_outputs[output_idx] if output_idx < brain.last_outputs.size() else 0.0
			var entry = Registries.skill_registry.get_entry(skill_order[i].registry_id)
			var name: String = entry.name if entry else "s%d" % skill_order[i].registry_id
			y += LINE_SPACING
			_draw_bar(y, name, val, Color(1.0, 0.6, 0.2))

	# Action summary
	y += LINE_SPACING + 4.0
	_draw_area.draw_string(
		ThemeDB.fallback_font, Vector2(4, y),
		"Action: %s" % creature.last_action_summary,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.9, 0.5)
	)
	y += 8.0

	# Resize panel to fit content
	_draw_area.custom_minimum_size = Vector2(PANEL_WIDTH, y)


func _draw_bar(y: float, label: String, value: float, color: Color) -> void:
	# Label
	_draw_area.draw_string(
		ThemeDB.fallback_font, Vector2(8, y),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.8)
	)

	# Bar background
	var bar_x: float = LABEL_WIDTH
	var bar_y: float = y - BAR_HEIGHT + 3.0
	_draw_area.draw_rect(
		Rect2(bar_x, bar_y, BAR_WIDTH, BAR_HEIGHT),
		Color(0.15, 0.15, 0.15)
	)

	# Bar fill (supports negative values)
	var clamped: float = clampf(value, -1.0, 1.0)
	if clamped >= 0:
		var fill_w: float = clamped * BAR_WIDTH
		_draw_area.draw_rect(
			Rect2(bar_x, bar_y, fill_w, BAR_HEIGHT),
			Color(color.r, color.g, color.b, 0.7)
		)
	else:
		var fill_w: float = absf(clamped) * BAR_WIDTH
		_draw_area.draw_rect(
			Rect2(bar_x + BAR_WIDTH - fill_w, bar_y, fill_w, BAR_HEIGHT),
			Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.7)
		)

	# Value text
	_draw_area.draw_string(
		ThemeDB.fallback_font,
		Vector2(bar_x + BAR_WIDTH + 4, y),
		"%.2f" % value,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7)
	)
