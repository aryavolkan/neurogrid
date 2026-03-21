class_name Creature
extends Node2D
## A creature on the grid: visual representation + state.

signal died(creature_id: int)

var creature_id: int = -1
var grid_pos: Vector2i = Vector2i.ZERO
var body: CreatureBody
var brain: CreatureBrain
var genome: DynamicGenome
var last_action_summary: String = ""

# Visual
var base_color: Color = Color.WHITE
var _target_pixel_pos: Vector2


func setup(p_id: int, p_pos: Vector2i, p_genome: DynamicGenome,
		p_sensor: CreatureSensor, p_energy: float = GameConfig.STARTING_ENERGY) -> void:
	creature_id = p_id
	grid_pos = p_pos
	genome = p_genome
	body = CreatureBody.new()
	body.energy = p_energy
	brain = CreatureBrain.new(p_genome, p_sensor)
	_update_pixel_pos_immediate()
	_assign_color()


func _assign_color() -> void:
	## Color based on species_id (set later) and receptor/skill count.
	var hue := fmod(float(creature_id) * 0.618, 1.0)
	base_color = Color.from_hsv(hue, 0.7, 0.9)


func set_species_color(species_id: int) -> void:
	## Use golden ratio hue + alternating saturation/value for better distinction.
	var hue := fmod(float(species_id) * 0.618, 1.0)
	var sat := 0.65 + 0.2 * float(species_id % 3) / 2.0  # 0.65, 0.75, 0.85
	var val := 0.8 + 0.15 * float((species_id + 1) % 2)   # 0.8 or 0.95
	base_color = Color.from_hsv(hue, sat, val)
	body.species_id = species_id


func _update_pixel_pos_immediate() -> void:
	var ts := GameConfig.TILE_SIZE
	position = Vector2(grid_pos.x * ts + ts * 0.5, grid_pos.y * ts + ts * 0.5)
	_target_pixel_pos = position


var _prev_energy: float = -1.0
var _prev_health: float = -1.0

func update_visual(delta: float) -> void:
	## Smooth interpolation to target grid position. Only redraws if visually changed.
	var ts := GameConfig.TILE_SIZE
	_target_pixel_pos = Vector2(grid_pos.x * ts + ts * 0.5, grid_pos.y * ts + ts * 0.5)
	var old_pos := position
	position = position.lerp(_target_pixel_pos, minf(delta * 15.0, 1.0))

	# Only redraw if position changed noticeably or state changed
	var moved: bool = old_pos.distance_squared_to(position) > 0.1
	var energy_changed: bool = absf(body.energy - _prev_energy) > 1.0
	var health_changed: bool = absf(body.health - _prev_health) > 0.5
	if moved or energy_changed or health_changed or selected or species_highlighted:
		_prev_energy = body.energy
		_prev_health = body.health
		queue_redraw()


var selected: bool = false       # Set by CreatureInspector
var species_highlighted: bool = false  # Set by SpeciesPanel


func _draw() -> void:
	var radius: float = GameConfig.TILE_SIZE * 0.4
	var alive: bool = body.is_alive()
	var alpha: float = clampf(body.energy / GameConfig.MAX_ENERGY, 0.4, 1.0) if alive else 0.15

	# Species highlight ring (behind everything)
	if species_highlighted:
		draw_arc(Vector2.ZERO, radius + 4.0, 0, TAU, 24,
			Color(base_color.r, base_color.g, base_color.b, 0.5), 2.0)

	# Selection ring (bright, thick)
	if selected:
		draw_arc(Vector2.ZERO, radius + 3.0, 0, TAU, 24,
			Color.WHITE, 2.5)
		draw_arc(Vector2.ZERO, radius + 3.0, 0, TAU, 24,
			Color(1.0, 1.0, 0.5, 0.4), 4.0)  # Outer glow

	# Body circle with dark outline for visibility
	var color := base_color
	color.a = alpha
	draw_circle(Vector2.ZERO, radius + 0.5, Color(0.0, 0.0, 0.0, alpha * 0.5))
	draw_circle(Vector2.ZERO, radius, color)

	# Energy ring (arc showing energy level)
	var energy_frac: float = clampf(body.energy / GameConfig.MAX_ENERGY, 0.0, 1.0)
	if energy_frac < 1.0:
		var ring_color: Color
		if energy_frac > 0.5:
			ring_color = Color(0.2, 0.9, 0.2, 0.8)
		elif energy_frac > 0.2:
			ring_color = Color(0.9, 0.7, 0.1, 0.8)
		else:
			ring_color = Color(0.9, 0.2, 0.2, 0.9)
		draw_arc(Vector2.ZERO, radius + 1.5, -PI * 0.5,
			-PI * 0.5 + TAU * energy_frac, 24, ring_color, 1.5)

	# Facing direction indicator
	var facing_offset := Vector2(body.facing) * radius * 0.7
	draw_circle(facing_offset, radius * 0.22,
		Color(1.0, 1.0, 1.0, alpha * 0.8))

	# Health bar (if damaged)
	if body.health < GameConfig.MAX_HEALTH:
		var bar_width: float = GameConfig.TILE_SIZE * 0.9
		var health_frac: float = body.health / GameConfig.MAX_HEALTH
		var bar_y: float = -radius - 5.0
		draw_rect(Rect2(-bar_width * 0.5, bar_y, bar_width, 3),
			Color(0.3, 0.0, 0.0, 0.8))
		draw_rect(Rect2(-bar_width * 0.5, bar_y,
			bar_width * health_frac, 3),
			Color(0.1, 0.85, 0.1, 0.9))

	# Juvenile indicator (cyan dot above)
	if body.age < AdvancedEvolution.JUVENILE_AGE:
		draw_circle(Vector2(0, -radius - 7.0), 2.0,
			Color(0.4, 0.85, 1.0, 0.9))

	# Poisoned indicator (green pulse ring)
	if body.poisoned_ticks > 0:
		var pulse: float = 0.5 + 0.5 * sin(float(body.age) * 0.3)
		draw_arc(Vector2.ZERO, radius - 1.0, 0, TAU, 16,
			Color(0.2, 0.85, 0.0, pulse * 0.7), 2.0)

	# Burrowed indicator (dirt overlay)
	if body.burrowed:
		draw_circle(Vector2.ZERO, radius * 0.5,
			Color(0.45, 0.35, 0.2, 0.7))

	# Burrowed indicator
	if body.burrowed:
		draw_circle(Vector2.ZERO, radius * 0.5, Color(0.4, 0.3, 0.2, 0.6))
