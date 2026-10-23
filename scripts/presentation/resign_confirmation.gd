class_name ResignConfirmation
extends Control
## In-game confirmation that keeps the resign decision inside the shared theme.

signal confirmed

const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")

var _panel: PanelContainer
var _actions: GridContainer
var _keep_button: Button
var _previous_focus: Control

func _ready() -> void:
	if _panel != null:
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	var scrim := Button.new()
	scrim.name = "ResignScrim"
	scrim.flat = false
	scrim.focus_mode = Control.FOCUS_NONE
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim_style := T.panel(Color("#142224", 0.66), 0, 0)
	for state: String in ["normal", "hover", "pressed"]:
		scrim.add_theme_stylebox_override(state, scrim_style)
	scrim.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.pressed.connect(close)
	var center := CenterContainer.new()
	center.name = "ResignCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.name = "ResignPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", T.panel(T.canvas(), 22, 22))
	center.add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	_panel.add_child(content)
	var eyebrow := _label(content, "MATCH OPTIONS", T.MEDIUM, 18, T.muted())
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _label(content, "Resign this match?", T.BOLD, 38, T.ink())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var question := _label(content, "Are you sure you want to end the game?", T.REGULAR, 22, T.muted())
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var warning := PanelContainer.new()
	warning.add_theme_stylebox_override("panel", T.panel(T.sage(), 12, 12))
	content.add_child(warning)
	var warning_text := _label(warning, "This will be marked as a Loss.", T.SEMIBOLD, 20, T.danger())
	warning_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_actions = GridContainer.new()
	_actions.columns = 2
	_actions.add_theme_constant_override("h_separation", 8)
	_actions.add_theme_constant_override("v_separation", 8)
	content.add_child(_actions)
	_keep_button = Button.new()
	_keep_button.name = "KeepPlayingButton"
	_keep_button.text = "Keep playing"
	_keep_button.custom_minimum_size.y = 82
	_keep_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	T.style_button(_keep_button, "primary")
	_keep_button.add_theme_font_size_override("font_size", 22)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_keep_button.add_theme_color_override(state, Color("#173D42"))
	_actions.add_child(_keep_button)
	_keep_button.pressed.connect(close)
	var resign_button := Button.new()
	resign_button.name = "ConfirmResignButton"
	resign_button.text = "Yes, resign"
	resign_button.custom_minimum_size.y = 82
	resign_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	T.style_button(resign_button, "secondary")
	resign_button.add_theme_font_size_override("font_size", 22)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		resign_button.add_theme_color_override(state, T.danger())
	resign_button.pressed.connect(_confirm)
	_actions.add_child(resign_button)
	resized.connect(_fit)
	_fit()

func _label(parent: Node, caption: String, font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _fit() -> void:
	if _panel != null:
		_panel.custom_minimum_size.x = minf(460.0, maxf(240.0, size.x - 48.0))
		_actions.columns = 1 if size.x < 400.0 else 2

func open() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	show()
	_keep_button.grab_focus()

func close() -> void:
	if not visible:
		return
	var return_focus: Control = _previous_focus
	dismiss()
	if is_instance_valid(return_focus) and return_focus.is_visible_in_tree():
		return_focus.grab_focus()

func dismiss() -> void:
	hide()
	_previous_focus = null

func _confirm() -> void:
	dismiss()
	confirmed.emit()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
