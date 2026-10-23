extends RefCounted
## Shared Modern Tabletop tokens and component states (docs/DESIGN_SYSTEM.md).
static func is_dark_mode() -> bool:
	return is_instance_valid(AppearanceSettings) and AppearanceSettings.dark_mode

static func canvas() -> Color:
	return Color("#142224") if is_dark_mode() else Color("#F6F2E9")

static func canvas_alt() -> Color:
	return Color("#203234") if is_dark_mode() else Color("#EFEDE1")

static func ink() -> Color:
	return Color("#F6F2E9") if is_dark_mode() else Color("#173D42")

static func sage() -> Color:
	return Color("#304747") if is_dark_mode() else Color("#DFEAE4")

static func honey() -> Color:
	return Color("#F4C86A")

static func muted() -> Color:
	return Color("#B6C7C4") if is_dark_mode() else Color("#53686A")

static func danger() -> Color:
	return Color("#F08A88") if is_dark_mode() else Color("#B83137")
const BOLD: Font = preload("res://assets/fonts/fredoka/Fredoka-Bold.tres")
const REGULAR: Font = preload("res://assets/fonts/fredoka/Fredoka-Regular.tres")
const MEDIUM: Font = preload("res://assets/fonts/fredoka/Fredoka-Medium.tres")
const SEMIBOLD: Font = preload("res://assets/fonts/fredoka/Fredoka-Semibold.tres")

static func panel(fill: Color, radius: int = 22, inset: float = 20.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.content_margin_left = inset
	box.content_margin_right = inset
	box.content_margin_top = inset
	box.content_margin_bottom = inset
	return box

static func button_style(kind: String, state: String) -> StyleBoxFlat:
	var fill: Color = honey() if kind == "primary" else canvas()
	if kind == "quiet":
		fill = Color.TRANSPARENT
	if kind == "selected":
		fill = sage()
	if state == "hover":
		fill = fill.lerp(ink(), 0.05) if fill.a > 0 else sage()
	elif state == "pressed":
		fill = fill.lerp(ink(), 0.12) if fill.a > 0 else sage().darkened(0.08)
	elif state == "disabled":
		fill = sage()
	var box: StyleBoxFlat = panel(fill, 18, 12.0)
	if kind == "secondary":
		box.set_border_width_all(2)
		box.border_color = ink()
	if state == "focus":
		box.bg_color = Color.TRANSPARENT
		box.set_border_width_all(3)
		box.border_color = ink()
		box.expand_margin_left = 3
		box.expand_margin_right = 3
		box.expand_margin_top = 3
		box.expand_margin_bottom = 3
	return box

static func style_button(button: Button, kind: String = "secondary") -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, button_style(kind, state))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, ink())
	button.add_theme_color_override("font_disabled_color", muted())
	button.add_theme_font_override("font", SEMIBOLD)

static func create() -> Theme:
	var result := Theme.new()
	result.default_font = REGULAR
	result.default_font_size = 24
	result.set_color("font_color", "Label", ink())
	result.set_color("font_color", "CheckButton", ink())
	result.set_color("font_hover_color", "CheckButton", ink())
	result.set_color("font_pressed_color", "CheckButton", ink())
	result.set_color("font_focus_color", "CheckButton", ink())
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		result.set_stylebox(state, "CheckButton", button_style("quiet", state))
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		result.set_stylebox(state, "Button", button_style("secondary", state))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		result.set_color(state, "Button", ink())
	result.set_color("font_disabled_color", "Button", muted())
	result.set_font("font", "Button", SEMIBOLD)
	result.set_color("font_color", "LineEdit", ink())
	result.set_color("font_placeholder_color", "LineEdit", muted())
	result.set_color("caret_color", "LineEdit", ink())
	result.set_color("selection_color", "LineEdit", sage().darkened(0.1))
	result.set_stylebox("normal", "LineEdit", panel(sage(), 12, 10))
	result.set_stylebox("focus", "LineEdit", button_style("secondary", "focus"))
	result.set_stylebox("panel", "PanelContainer", panel(canvas()))
	return result
