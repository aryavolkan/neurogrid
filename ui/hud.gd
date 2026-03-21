class_name HUD
extends CanvasLayer
## Heads-up display showing simulation stats and controls.

var _sim: SimulationManager

var _population_label: Label
var _tick_label: Label
var _speed_label: Label
var _species_label: Label
var _fps_label: Label
var _gen_label: Label
var _fitness_label: Label
var _info_label: Label

var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.2  # Refresh HUD 5x/sec


func _ready() -> void:
	layer = 10
	_build_ui()


func setup(sim: SimulationManager) -> void:
	_sim = sim
	sim.population_changed.connect(_on_population_changed)
	sim.generation_complete.connect(_on_generation_complete)


func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.offset_left = 8
	panel.offset_top = 8

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.7)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	_population_label = _add_label(vbox, "Population: 0")
	_tick_label = _add_label(vbox, "Tick: 0")
	_speed_label = _add_label(vbox, "Speed: 1.0x")
	_species_label = _add_label(vbox, "Species: 0")
	_fps_label = _add_label(vbox, "FPS: 0")
	_gen_label = _add_label(vbox, "Gen: 0")
	_fitness_label = _add_label(vbox, "Fitness: -")

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Controls help
	var controls_label := _add_label(vbox, "")
	controls_label.text = (
		"[Space] Pause  [/] Speed\n"
		+ "[Tab] Stats  [S] Species  [P] Phylogeny\n"
		+ "[G] Genome  [H] Heatmap  [F3] Debug\n"
		+ "Click creature to inspect"
	)
	controls_label.add_theme_font_size_override("font_size", 11)
	controls_label.add_theme_color_override(
		"font_color", Color(0.6, 0.6, 0.7))

	_info_label = _add_label(vbox, "")

	add_child(panel)


func _add_label(parent: VBoxContainer, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	parent.add_child(label)
	return label


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	if not _sim:
		return

	_tick_label.text = "Tick: %d" % _sim.get_tick_count()
	_speed_label.text = "Speed: %.1fx" % GameConfig.speed_multiplier
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	_gen_label.text = "Gen: %d" % _sim.get_generation()

	_species_label.text = "Species: %d" % _sim.species_manager.get_species_count()

	var status_parts: Array = []
	if GameConfig.paused:
		status_parts.append("[PAUSED]")
	if _sim.ecology_system and _sim.ecology_system.is_night():
		status_parts.append("[NIGHT]")
	if _sim.weather_system and _sim.weather_system.current_weather != WeatherSystem.Weather.CLEAR:
		status_parts.append("[%s]" % _sim.weather_system.get_weather_name().to_upper())
	var status_str: String = " ".join(status_parts)
	_info_label.text = status_str


func _on_population_changed(count: int) -> void:
	_population_label.text = "Population: %d" % count


func _on_generation_complete(_generation: int, stats: Dictionary) -> void:
	var best: float = stats.get("best_fitness", 0.0)
	var avg: float = stats.get("avg_fitness", 0.0)
	_fitness_label.text = "Fitness: %.1f best / %.1f avg" % [best, avg]
