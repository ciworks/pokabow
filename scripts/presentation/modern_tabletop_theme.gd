extends RefCounted
## Shared Modern Tabletop tokens and component states (docs/DESIGN_SYSTEM.md).
static func is_dark_mode() -> bool:
	return is_instance_valid(AppearanceSettings) and AppearanceSettings.dark_mode

static func canvas() -> Color:
	return Color("#101F26") if is_dark_mode() else Color("#F6F2E9")

static func canvas_alt() -> Color:
	return Color("#203841") if is_dark_mode() else Color("#EFEDE1")

static func ink() -> Color:
	return Color("#F2F5EF") if is_dark_mode() else Color("#173D42")

static func sage() -> Color:
	return Color("#2D4A50") if is_dark_mode() else Color("#DFEAE4")

static func honey() -> Color:
	return Color("#F4C86A")

static func muted() -> Color:
	return Color("#BFD0D0") if is_dark_mode() else Color("#53686A")

static func icon_ink() -> Color:
	return Color("#E8F2EC") if is_dark_mode() else Color("#173D42")

static func on_primary() -> Color:
	return Color("#173D42")

static func border() -> Color:
	return Color("#47656B") if is_dark_mode() else Color("#D8D0C2")

static func icon_texture(name: String) -> Texture2D:
	var dark_path: String = "res://assets/ui/modern_tabletop/%s_dark.svg" % name
	var path: String = dark_path if is_dark_mode() and ResourceLoader.exists(dark_path) else "res://assets/ui/modern_tabletop/%s.svg" % name
	return load(path) as Texture2D

static func danger() -> Color:
	return Color("#F08A88") if is_dark_mode() else Color("#B83137")
const BOLD: Font = preload("res://assets/fonts/fredoka/Fredoka-Bold.tres")
const REGULAR: Font = preload("res://assets/fonts/fredoka/Fredoka-Regular.tres")
const MEDIUM: Font = preload("res://assets/fonts/fredoka/Fredoka-Medium.tres")
const SEMIBOLD: Font = preload("res://assets/fonts/fredoka/Fredoka-Semibold.tres")
const BACK_BUTTON_SIZE: Vector2 = Vector2(48, 48)

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
		box.border_color = border() if is_dark_mode() else ink()
	if state == "focus":
		box.bg_color = Color.TRANSPARENT
		box.set_border_width_all(3)
		box.border_color = ink()
		# An outlined button already has a border; draw focus over it as one edge.
		if kind != "secondary":
			box.expand_margin_left = 3
			box.expand_margin_right = 3
			box.expand_margin_top = 3
			box.expand_margin_bottom = 3
	return box

static func style_button(button: Button, kind: String = "secondary") -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, button_style(kind, state))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, on_primary() if kind == "primary" else ink())
	button.add_theme_color_override("font_disabled_color", muted())
	button.add_theme_font_override("font", SEMIBOLD)

static func style_back_button(button: Button) -> void:
	button.text = ""
	button.icon = icon_texture("game_back")
	button.expand_icon = false
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = BACK_BUTTON_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	style_button(button, "quiet")
	for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_disabled_color"]:
		button.add_theme_color_override(state, icon_ink())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

static func style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = border()
	track.set_corner_radius_all(5)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	var filled: StyleBoxFlat = track.duplicate() as StyleBoxFlat
	filled.bg_color = honey()
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	var knob_image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	for y: int in range(24):
		for x: int in range(24):
			var radius_squared: int = (x - 12) * (x - 12) + (y - 12) * (y - 12)
			if radius_squared <= 121:
				knob_image.set_pixel(x, y, ink() if radius_squared >= 100 else honey())
	var knob := ImageTexture.create_from_image(knob_image)
	slider.add_theme_icon_override("grabber", knob)
	slider.add_theme_icon_override("grabber_highlight", knob)

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
	var tooltip_box: StyleBoxFlat = panel(canvas_alt() if is_dark_mode() else canvas(), 12, 0)
	tooltip_box.content_margin_left = 12
	tooltip_box.content_margin_right = 12
	tooltip_box.content_margin_top = 8
	tooltip_box.content_margin_bottom = 8
	tooltip_box.set_border_width_all(1)
	tooltip_box.border_color = muted()
	tooltip_box.shadow_color = Color(0, 0, 0, 0.16)
	tooltip_box.shadow_size = 6
	tooltip_box.shadow_offset = Vector2(0, 3)
	result.set_stylebox("panel", "TooltipPanel", tooltip_box)
	result.set_color("font_color", "TooltipLabel", ink())
	result.set_font("font", "TooltipLabel", MEDIUM)
	result.set_font_size("font_size", "TooltipLabel", 20)
	return result
