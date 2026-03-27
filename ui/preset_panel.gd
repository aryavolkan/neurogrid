class_name PresetPanel
extends CanvasLayer
## Config preset browser. Toggle with F2.
## Lists built-in and user presets; load, save as, or delete them.

var _sim: SimulationManager

var _panel: PanelContainer
var _list: ItemList
var _name_edit: LineEdit
var _status_label: Label
var _delete_btn: Button
var _save_btn: Button


func _ready() -> void:
	layer = 12
	_build_ui()


func setup(sim: SimulationManager) -> void:
	_sim = sim


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -160
	_panel.offset_right = 160
	_panel.offset_top = -200
	_panel.offset_bottom = 200
	_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.5, 0.8, 0.8)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Config Presets  [F2]"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Changes take effect on next simulation start."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 160)
	_list.item_selected.connect(_on_preset_selected)
	vbox.add_child(_list)

	var load_btn := Button.new()
	load_btn.text = "Load Selected"
	load_btn.pressed.connect(_on_load_pressed)
	vbox.add_child(load_btn)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var save_row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "New preset name..."
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(_name_edit)
	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.pressed.connect(_on_save_pressed)
	save_row.add_child(_save_btn)
	vbox.add_child(save_row)

	_delete_btn = Button.new()
	_delete_btn.text = "Delete Selected"
	_delete_btn.pressed.connect(_on_delete_pressed)
	vbox.add_child(_delete_btn)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_status_label.text = ""
	vbox.add_child(_status_label)

	add_child(_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh_list()


func _refresh_list() -> void:
	_list.clear()
	var presets := ConfigPresetManager.list_presets()
	for preset_name in presets:
		var suffix: String = " [built-in]" if ConfigPresetManager.is_builtin(preset_name) else ""
		_list.add_item(preset_name + suffix)
	_status_label.text = ""


func _on_preset_selected(_index: int) -> void:
	var selected := _get_selected_name()
	_delete_btn.disabled = ConfigPresetManager.is_builtin(selected)


func _get_selected_name() -> String:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return ""
	var label: String = _list.get_item_text(selected[0])
	return label.replace(" [built-in]", "")


func _on_load_pressed() -> void:
	var preset_name := _get_selected_name()
	if preset_name.is_empty():
		_status_label.text = "Select a preset first."
		return

	var params := ConfigPresetManager.load_preset(preset_name)
	if params.is_empty():
		_status_label.text = "Failed to load preset."
		return

	var dyn_cfg: DynamicConfig = _sim._dynamic_config if _sim else null
	ConfigPresetManager.apply_preset(params, dyn_cfg)
	_status_label.text = "Loaded: %s" % preset_name


func _on_save_pressed() -> void:
	var name_str := _name_edit.text.strip_edges()
	if name_str.is_empty():
		_status_label.text = "Enter a preset name."
		return

	var dyn_cfg: DynamicConfig = _sim._dynamic_config if _sim else null
	if ConfigPresetManager.save_preset(name_str, dyn_cfg):
		_name_edit.text = ""
		_refresh_list()
		_status_label.text = "Saved: %s" % name_str
	else:
		_status_label.text = "Cannot overwrite built-in preset."


func _on_delete_pressed() -> void:
	var preset_name := _get_selected_name()
	if preset_name.is_empty():
		return
	if ConfigPresetManager.delete_preset(preset_name):
		_refresh_list()
		_status_label.text = "Deleted: %s" % preset_name
	else:
		_status_label.text = "Cannot delete built-in preset."
