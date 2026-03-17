class_name CameraController
extends Camera2D
## Pan and zoom camera for observing the grid world.

const MIN_ZOOM: float = 0.3
const MAX_ZOOM: float = 4.0
const ZOOM_STEP: float = 0.1
const PAN_SPEED: float = 400.0

var _dragging: bool = false
var _drag_start: Vector2


func _ready() -> void:
	# Center on grid
	var center_x: float = GameConfig.GRID_WIDTH * GameConfig.TILE_SIZE * 0.5
	var center_y: float = GameConfig.GRID_HEIGHT * GameConfig.TILE_SIZE * 0.5
	position = Vector2(center_x, center_y)

	# Initial zoom to fit grid
	var viewport_size := get_viewport_rect().size
	var grid_size := Vector2(GameConfig.GRID_WIDTH * GameConfig.TILE_SIZE, GameConfig.GRID_HEIGHT * GameConfig.TILE_SIZE)
	var fit_zoom: float = minf(viewport_size.x / grid_size.x, viewport_size.y / grid_size.y)
	zoom = Vector2(fit_zoom, fit_zoom)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		_zoom_at(ZOOM_STEP, get_global_mouse_position())
	elif event.is_action_pressed("zoom_out"):
		_zoom_at(-ZOOM_STEP, get_global_mouse_position())
	elif event.is_action_pressed("speed_up"):
		GameConfig.speed_multiplier = minf(GameConfig.speed_multiplier * 2.0, 32.0)
	elif event.is_action_pressed("speed_down"):
		GameConfig.speed_multiplier = maxf(GameConfig.speed_multiplier * 0.5, 0.25)
	elif event.is_action_pressed("pause_toggle"):
		GameConfig.paused = not GameConfig.paused
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
			_drag_start = event.position
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom


func _process(delta: float) -> void:
	# WASD panning
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1
	if pan != Vector2.ZERO:
		position += pan.normalized() * PAN_SPEED * delta / zoom.x


func _zoom_at(step: float, mouse_world_pos: Vector2) -> void:
	var old_zoom := zoom
	var new_zoom_val := clampf(zoom.x + step, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom_val, new_zoom_val)

	# Zoom toward mouse position
	position += (mouse_world_pos - position) * (1.0 - old_zoom.x / new_zoom_val)
