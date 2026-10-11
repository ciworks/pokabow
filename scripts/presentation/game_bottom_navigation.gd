class_name GameBottomNavigation
extends PanelContainer

## Presentation-only shortcuts; GameScreen supplies availability and handlers.
signal action_requested(action: StringName)

const ACTIONS: Array[StringName] = [&"Play", &"Skip", &"Swap", &"Undo", &"Quit"]
const BAR_HEIGHT: float = 76.0
const TOOLTIPS: Array[String] = [
	"Place your hand on the board",
	"Skip is unavailable",
	"Choose tiles to return to the pot",
	"Return unplayed tiles to your rack",
	"Back to hub",
]

var buttons: Dictionary[StringName, Button] = {}


func _ready() -> void:
	custom_minimum_size.y = BAR_HEIGHT
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("101b25")
	panel.border_color = Color("31434e")
	panel.border_width_top = 1
	panel.content_margin_left = 0.0
	panel.content_margin_right = 0.0
	panel.content_margin_top = 1.0
	panel.content_margin_bottom = 0.0
	add_theme_stylebox_override("panel", panel)
	var row := HBoxContainer.new()
	row.name = "Actions"
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	for index: int in range(ACTIONS.size()):
		var action: StringName = ACTIONS[index]
		var button := Button.new()
		button.name = String(action) + "Button"
		button.custom_minimum_size = Vector2(48, BAR_HEIGHT - 1.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = TOOLTIPS[index]
		var empty := StyleBoxEmpty.new()
		button.add_theme_stylebox_override("normal", empty)
		button.add_theme_stylebox_override("disabled", empty)
		var highlight := StyleBoxFlat.new()
		highlight.bg_color = Color("1b2b37")
		button.add_theme_stylebox_override("hover", highlight)
		var pressed := StyleBoxFlat.new()
		pressed.bg_color = Color("233b43")
		pressed.border_color = Color("66ffb8")
		pressed.border_width_top = 3
		button.add_theme_stylebox_override("pressed", pressed)
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color.TRANSPARENT
		focus.border_color = Color("66ffb8")
		focus.set_border_width_all(2)
		button.add_theme_stylebox_override("focus", focus)
		row.add_child(button)
		var content := VBoxContainer.new()
		content.name = "Content"
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 5)
		button.add_child(content)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/ui/navigation/%s.svg" % String(action).to_lower())
		icon.custom_minimum_size = Vector2(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)
		var label := Label.new()
		label.text = String(action)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 13)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
		buttons[action] = button
		# Skip has no matching drawer command.
		if action != &"Skip":
			button.pressed.connect(func() -> void: action_requested.emit(action))
	set_available(&"Play", false)
	set_available(&"Skip", false)
	set_available(&"Swap", false)
	set_available(&"Undo", false)


func set_available(action: StringName, available: bool) -> void:
	if not buttons.has(action):
		return
	var button: Button = buttons[action]
	button.disabled = not available
	var content: Control = button.get_node("Content") as Control
	content.modulate = Color(0.4, 1.0, 0.72) if available and action == &"Play" else Color("c5d0d8")
	content.modulate.a = 1.0 if available else 0.4
