class_name GameBottomNavigation
extends PanelContainer

## Presentation-only action bar; GameScreen supplies availability and handlers.
signal action_requested(action: StringName)

const ACTIONS: Array[StringName] = [&"Undo", &"Swap", &"Play", &"Resign", &"Pot"]
const BAR_HEIGHT: float = 112.0
const PLAY_BUTTON_HEIGHT: float = 78.0
const PLAY_BUTTON_STRETCH_RATIO: float = 2.0
const PLAY_LABEL_FONT_SIZE: int = 30
const TOOLTIPS: Array[String] = [
	"Return staged tiles to your hand",
	"Choose tiles to return to the pot",
	"Play the staged hand",
	"Resign this match",
	"View tiles in the pot",
]
const ICONS: Dictionary = {
	&"Undo": "undo",
	&"Play": "play_hand",
	&"Swap": "swap",
	&"Resign": "flag",
	&"Pot": "pot_sack",
}
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")

var buttons: Dictionary[StringName, Button] = {}
var _pot_count_label: Label = null


func _ready() -> void:
	custom_minimum_size.y = BAR_HEIGHT
	var panel := Tabletop.panel(Tabletop.canvas(), 0, 0.0)
	panel.border_color = Tabletop.border()
	panel.border_width_top = 1
	panel.content_margin_top = 1.0
	add_theme_stylebox_override("panel", panel)
	var row := HBoxContainer.new()
	row.name = "Actions"
	row.add_theme_constant_override("separation", 2)
	add_child(row)
	for index: int in range(ACTIONS.size()):
		var action: StringName = ACTIONS[index]
		var button := Button.new()
		button.name = String(action) + "Button"
		button.custom_minimum_size = Vector2(48, PLAY_BUTTON_HEIGHT if action == &"Play" else BAR_HEIGHT - 12.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if action == &"Play":
			button.size_flags_stretch_ratio = PLAY_BUTTON_STRETCH_RATIO
			button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.tooltip_text = TOOLTIPS[index]
		if action == &"Resign":
			button.accessibility_name = "Resign this match"
		elif action == &"Pot":
			button.accessibility_name = "Tile pot"
		Tabletop.style_button(button, "primary" if action == &"Play" else "quiet")
		if action == &"Play":
			# The reference keeps Play honey-filled even before a hand is staged.
			button.add_theme_stylebox_override("disabled", Tabletop.button_style("primary", "normal"))
		row.add_child(button)
		var content := VBoxContainer.new()
		content.name = "Content"
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.add_theme_constant_override("separation", 2)
		button.add_child(content)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var icon_surface := PanelContainer.new()
		icon_surface.name = "IconSurface"
		icon_surface.custom_minimum_size = Vector2(52, 52)
		icon_surface.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_surface.add_theme_stylebox_override("panel", Tabletop.panel(Tabletop.canvas_alt(), 26, 0.0))
		icon_surface.visible = action != &"Play"
		content.add_child(icon_surface)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture = Tabletop.icon_texture(ICONS[action])
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_center := CenterContainer.new()
		icon_center.name = "IconCenter"
		icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_surface.add_child(icon_center)
		icon_center.add_child(icon)
		if action == &"Pot":
			icon.custom_minimum_size = Vector2(38, 38)
			_pot_count_label = Label.new()
			_pot_count_label.name = "PotCount"
			_pot_count_label.text = "0"
			_pot_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_pot_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_pot_count_label.add_theme_font_override("font", Tabletop.BOLD)
			_pot_count_label.add_theme_font_size_override("font_size", 12)
			_pot_count_label.add_theme_color_override("font_color", Tabletop.canvas())
			_pot_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.add_child(_pot_count_label)
			_pot_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_pot_count_label.offset_top = 13.0
		var label := Label.new()
		label.name = "Label"
		label.text = "Play hand" if action == &"Play" else String(action)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", Tabletop.SEMIBOLD)
		label.add_theme_color_override("font_color", Tabletop.on_primary() if action == &"Play" else Tabletop.ink())
		label.add_theme_font_size_override("font_size", PLAY_LABEL_FONT_SIZE if action == &"Play" else 18)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
		buttons[action] = button
		button.pressed.connect(func() -> void: action_requested.emit(action))
	set_available(&"Resign", false)
	set_available(&"Undo", false)
	set_available(&"Play", false)
	set_available(&"Swap", false)
	set_available(&"Pot", false)


func set_pot_count(count: int) -> void:
	if _pot_count_label == null:
		return
	_pot_count_label.text = str(maxi(0, count))
	var button: Button = buttons[&"Pot"]
	button.tooltip_text = "Tile pot: %d available" % count
	button.accessibility_name = button.tooltip_text


## Reuses the primary and left actions while the player chooses tiles to swap.
func set_swap_selection(active: bool, selected_count: int) -> void:
	var play: Button = buttons[&"Play"]
	var undo: Button = buttons[&"Undo"]
	var swap_label: String = "Select tiles" if selected_count <= 0 else "Swap %d %s" % [
		selected_count, "tile" if selected_count == 1 else "tiles"
	]
	(play.get_node("Content/Label") as Label).text = swap_label if active else "Play hand"
	(undo.get_node("Content/Label") as Label).text = "Keep" if active else "Undo"
	play.tooltip_text = ("Select tiles to swap" if selected_count <= 0 else
		"Swap %d selected %s" % [selected_count, "tile" if selected_count == 1 else "tiles"]) if active else TOOLTIPS[2]
	undo.tooltip_text = "Keep your tiles and cancel the swap" if active else TOOLTIPS[0]
	play.accessibility_name = play.tooltip_text
	undo.accessibility_name = undo.tooltip_text


func set_available(action: StringName, available: bool) -> void:
	if not buttons.has(action):
		return
	var button: Button = buttons[action]
	button.disabled = not available
	var content: Control = button.get_node("Content") as Control
	content.modulate = (
		Color.WHITE
		if available or action == &"Play"
		else (Color(1, 1, 1, 0.75) if Tabletop.is_dark_mode() else Color(0.42, 0.49, 0.50, 0.55))
	)
