extends Node2D
## Main scene root. Sets up SimulationManager, Camera, and UI.

var sim: SimulationManager
var camera: CameraController
var hud: HUD
var inspector: CreatureInspector
var stats_panel: StatsPanel


func _ready() -> void:
	# Background color
	RenderingServer.set_default_clear_color(Color(0.08, 0.08, 0.1))

	# Simulation
	sim = SimulationManager.new()
	add_child(sim)

	# Camera
	camera = CameraController.new()
	camera.make_current()
	add_child(camera)

	# HUD
	hud = HUD.new()
	hud.setup(sim)
	add_child(hud)

	# Creature inspector
	inspector = CreatureInspector.new()
	inspector.setup(sim)
	add_child(inspector)

	# Stats panel (Tab to toggle)
	stats_panel = StatsPanel.new()
	stats_panel.setup(sim)
	add_child(stats_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F5:
				SaveSystem.save_simulation(sim)
			KEY_F9:
				SaveSystem.load_simulation(sim)
			KEY_F6:
				SaveSystem.export_best_genomes(sim)
