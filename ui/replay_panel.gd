class_name ReplayPanel
extends CanvasLayer
## Replay browser. Toggle with R.
## Pauses simulation and lets you scrub through recorded creature snapshots.
## Draws a world-space overlay of creature positions at the selected tick.

var _sim: SimulationManager
var _recorder: ReplayRecorder

# UI
var _panel: PanelContainer
var _tick_label: Label
var _pop_label: Label
var _food_label: Label
var _slider: HSlider
var _draw_node: Control

# Playback state
var _replay_frame: int = 0
var _is_playing: bool = false
var _play_timer: float = 0.0
var _play_interval: float = 1.0 / 30.0  # Match simulation tick rate
var _was_paused: bool = false


func _ready() -> void:
	layer = 8
	_build_ui()


func setup(sim: SimulationManager, recorder: ReplayRecorder) -> void:
	_sim = sim
	_recorder = recorder


func _build_ui() -> void:
	# --- Control panel (screen-space HUD) ---
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -240
	_panel.offset_right = 240
	_panel.offset_top = -110
	_panel.offset_bottom = -8
	_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.93)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.6, 1.0, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_panel.add_child(vbox)

	var header_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "REPLAY  [R]"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)

	_tick_label = Label.new()
	_tick_label.text = "Tick: -"
	_tick_label.add_theme_font_size_override("font_size", 13)
	_tick_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	header_row.add_child(_tick_label)
	vbox.add_child(header_row)

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 16)
	_pop_label = _make_stat_label()
	_food_label = _make_stat_label()
	stats_row.add_child(_pop_label)
	stats_row.add_child(_food_label)
	vbox.add_child(stats_row)

	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = 1
	_slider.step = 1
	_slider.value = 0
	_slider.value_changed.connect(_on_slider_changed)
	vbox.add_child(_slider)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)

	_add_btn(btn_row, "|<", _on_first_pressed)
	_add_btn(btn_row, "<", _on_prev_pressed)
	var play_btn := _add_btn(btn_row, "Play", _on_play_pressed)
	play_btn.name = "PlayBtn"
	_add_btn(btn_row, ">", _on_next_pressed)
	_add_btn(btn_row, ">|", _on_last_pressed)
	vbox.add_child(btn_row)

	add_child(_panel)

	# --- World-space draw overlay (child of GridWorld) ---
	_draw_node = Control.new()
	_draw_node.custom_minimum_size = Vector2(
		GameConfig.GRID_WIDTH * GameConfig.TILE_SIZE,
		GameConfig.GRID_HEIGHT * GameConfig.TILE_SIZE
	)
	_draw_node.size = _draw_node.custom_minimum_size
	_draw_node.draw.connect(_on_draw)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.visible = false


func _make_stat_label() -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	return lbl


func _add_btn(parent: HBoxContainer, text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(40, 0)
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_toggle()


func _toggle() -> void:
	if not _recorder:
		return
	_panel.visible = not _panel.visible
	if _panel.visible:
		_enter_replay()
	else:
		_exit_replay()


func _enter_replay() -> void:
	if not _sim or not _recorder:
		return
	_was_paused = GameConfig.paused
	GameConfig.paused = true
	_is_playing = false

	_replay_frame = maxi(0, _recorder.get_frame_count() - 1)
	_slider.max_value = maxi(0, _recorder.get_frame_count() - 1)
	_slider.value = _replay_frame

	# Attach draw node to world
	if _sim.world and _draw_node.get_parent() != _sim.world:
		if _draw_node.get_parent():
			_draw_node.get_parent().remove_child(_draw_node)
		_sim.world.add_child(_draw_node)
	_draw_node.visible = true
	_refresh_display()


func _exit_replay() -> void:
	_is_playing = false
	GameConfig.paused = _was_paused
	_draw_node.visible = false


func _process(delta: float) -> void:
	if not _panel.visible or not _is_playing:
		return

	_play_timer += delta
	if _play_timer >= _play_interval:
		_play_timer = 0.0
		var next: int = _replay_frame + 1
		if next >= _recorder.get_frame_count():
			_is_playing = false
			_update_play_button()
		else:
			_replay_frame = next
			_slider.value = _replay_frame
			_refresh_display()


func _on_slider_changed(value: float) -> void:
	_replay_frame = int(value)
	_refresh_display()


func _on_first_pressed() -> void:
	_replay_frame = 0
	_slider.value = 0
	_refresh_display()


func _on_prev_pressed() -> void:
	_replay_frame = maxi(0, _replay_frame - 1)
	_slider.value = _replay_frame
	_refresh_display()


func _on_next_pressed() -> void:
	_replay_frame = mini(_replay_frame + 1, _recorder.get_frame_count() - 1)
	_slider.value = _replay_frame
	_refresh_display()


func _on_last_pressed() -> void:
	_replay_frame = maxi(0, _recorder.get_frame_count() - 1)
	_slider.value = _replay_frame
	_refresh_display()


func _on_play_pressed() -> void:
	_is_playing = not _is_playing
	_play_timer = 0.0
	if _is_playing and _replay_frame >= _recorder.get_frame_count() - 1:
		_replay_frame = 0
		_slider.value = 0
	_update_play_button()


func _update_play_button() -> void:
	var row: Node = _panel.get_child(0).get_child(3)  # btn_row
	if row:
		for child in row.get_children():
			if child is Button and child.name == "PlayBtn":
				child.text = "Pause" if _is_playing else "Play"
				return


func _refresh_display() -> void:
	if not _recorder:
		return
	var frame := _recorder.get_frame(_replay_frame)
	if frame.is_empty():
		return

	_tick_label.text = "Tick: %d" % frame.get("tick", 0)
	_pop_label.text = "Pop: %d" % frame.get("pop", 0)
	_food_label.text = "Food: %.0f" % frame.get("food_total", 0.0)
	_slider.max_value = maxi(0, _recorder.get_frame_count() - 1)
	_draw_node.queue_redraw()


func _on_draw() -> void:
	if not _recorder or not _panel.visible:
		return

	var frame := _recorder.get_frame(_replay_frame)
	if frame.is_empty():
		return

	var ts: int = GameConfig.TILE_SIZE
	var r: float = ts * 0.45

	# Semi-transparent background to distinguish replay from live view
	var world_rect := Rect2(
		0, 0,
		GameConfig.GRID_WIDTH * ts,
		GameConfig.GRID_HEIGHT * ts
	)
	_draw_node.draw_rect(world_rect, Color(0.0, 0.0, 0.08, 0.45))

	# Draw each creature as a colored circle, colored by species
	var creatures: Array = frame.get("creatures", [])
	for cd in creatures:
		var cx: float = float(cd.get("x", 0)) * ts + ts * 0.5
		var cy: float = float(cd.get("y", 0)) * ts + ts * 0.5
		var sid: int = cd.get("species_id", 0)
		var energy: float = cd.get("energy", 50.0)
		var col: Color = _species_color(sid)
		col.a = clampf(energy / 80.0, 0.4, 1.0)
		_draw_node.draw_circle(Vector2(cx, cy), r, col)


static func _species_color(species_id: int) -> Color:
	## Deterministic color per species id.
	var palette: Array = [
		Color(0.2, 0.7, 1.0),   # cyan
		Color(1.0, 0.5, 0.2),   # orange
		Color(0.5, 1.0, 0.4),   # green
		Color(1.0, 0.3, 0.5),   # pink
		Color(0.8, 0.7, 0.2),   # yellow
		Color(0.7, 0.3, 1.0),   # purple
		Color(1.0, 0.8, 0.3),   # gold
		Color(0.3, 0.9, 0.8),   # teal
	]
	return palette[species_id % palette.size()]
