class_name GemPotView
extends Control

## Small shared-pot HUD. The title, gemstones and count occupy the former tile
## stack between the two player score cards.
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")

var _total: int = 0
var _title: Label
var _count: Label
var _pulse_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Label.new()
	_title.name = "Title"
	_title.text = "GEM POT"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_override("font", Tabletop.SEMIBOLD)
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Tabletop.ink())
	add_child(_title)
	_count = Label.new()
	_count.name = "Count"
	_count.text = str(_total)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.add_theme_font_override("font", Tabletop.BOLD)
	_count.add_theme_font_size_override("font_size", 32)
	_count.add_theme_color_override("font_color", Tabletop.ink())
	add_child(_count)
	AppearanceSettings.dark_mode_changed.connect(_refresh_theme)
	resized.connect(_layout)
	_layout()


func _refresh_theme(_enabled: bool) -> void:
	_title.add_theme_color_override("font_color", Tabletop.ink())
	_count.add_theme_color_override("font_color", Tabletop.ink())
	queue_redraw()


func set_total(amount: int) -> void:
	_total = maxi(0, amount)
	if _count != null:
		_count.text = str(_total)
	_layout()


func total() -> int:
	return _total


func pulse() -> void:
	if AccessibilitySettings.reduced_motion():
		return
	if _pulse_tween != null and _pulse_tween.is_running():
		_pulse_tween.kill()
	scale = Vector2.ONE
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "scale", Vector2(1.10, 1.10), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func arrival_global() -> Vector2:
	return get_global_transform() * Vector2(size.x * 0.5, size.y * 0.48)


func _layout() -> void:
	if _title == null or _count == null:
		return
	_title.position = Vector2(0.0, 0.0)
	_title.size = Vector2(size.x, 24.0)
	_count.position = Vector2(0.0, size.y * 0.63)
	_count.size = Vector2(size.x, size.y * 0.37)
	_fit_label(_title, 18, 14)
	_fit_label(_count, 32, 20)
	pivot_offset = size * 0.5
	queue_redraw()


func _fit_label(label: Label, preferred: int, minimum: int) -> void:
	var font: Font = label.get_theme_font("font")
	var target: int = preferred
	while target > minimum and (font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, target).x > label.size.x or font.get_height(target) > label.size.y):
		target -= 1
	label.add_theme_font_size_override("font_size", target)


func _draw() -> void:
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.44)
	var unit: float = minf(size.x / 100.0, size.y / 94.0)
	# Tactile shallow bowl in deep teal, with three simple faceted gems.
	var rim: PackedVector2Array = PackedVector2Array([
		center + Vector2(-27, 8) * unit,
		center + Vector2(27, 8) * unit,
		center + Vector2(22, 21) * unit,
		center + Vector2(-22, 21) * unit,
	])
	draw_colored_polygon(rim, Color("#304747") if Tabletop.is_dark_mode() else Color("#173D42"))
	draw_line(center + Vector2(-26, 8) * unit, center + Vector2(26, 8) * unit, Color("#6B9991") if Tabletop.is_dark_mode() else Color("#4E7772"), 3.0 * unit, true)
	_draw_gem(center + Vector2(-14, 1) * unit, 12.0 * unit, Color("#F4C86A"))
	_draw_gem(center + Vector2(0, -7) * unit, 14.0 * unit, Color("#E9AC45"))
	_draw_gem(center + Vector2(15, 1) * unit, 11.0 * unit, Color("#B5D5B9"))


func _draw_gem(center: Vector2, radius: float, base: Color) -> void:
	var diamond: PackedVector2Array = PackedVector2Array([
		center + Vector2(0, -radius), center + Vector2(radius * 0.8, -radius * 0.25),
		center + Vector2(radius * 0.55, radius * 0.7), center + Vector2(0, radius),
		center + Vector2(-radius * 0.75, radius * 0.35), center + Vector2(-radius * 0.8, -radius * 0.25),
	])
	draw_colored_polygon(diamond, base)
	draw_colored_polygon(PackedVector2Array([diamond[0], diamond[1], center]), base.lightened(0.30))
	draw_colored_polygon(PackedVector2Array([diamond[3], diamond[4], center]), base.darkened(0.17))
