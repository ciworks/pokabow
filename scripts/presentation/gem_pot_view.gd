class_name GemPotView
extends Control

## Shared-pot HUD between the score cards. Capped AI pots fill a honey ring;
## uncapped online pots retain the neutral track without implying a limit.
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const SAFE_ICON: Texture2D = preload("res://assets/ui/modern_tabletop/gem_safe.svg")
const RING_TRACK: Color = Color("#C7D8CF")
const ICON_BACKDROP: Color = Color("#F6F2E9")

var _total: int = 0
var _cap: int = 0
var _pulse_tween: Tween
var _progress_tween: Tween
var _display_fraction: float = 0.0
var _online: bool = false
var _earning_available: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	AppearanceSettings.dark_mode_changed.connect(_refresh_theme)
	resized.connect(_on_resized)
	_update_accessibility()
	_on_resized()


func _on_resized() -> void:
	pivot_offset = size * 0.5
	queue_redraw()


func _refresh_theme(_enabled: bool) -> void:
	queue_redraw()


func set_total(amount: int, animate: bool = false) -> void:
	_total = clampi(amount, 0, _cap) if _cap > 0 else maxi(0, amount)
	_update_accessibility()
	if _progress_tween != null and _progress_tween.is_running():
		_progress_tween.kill()
	var target: float = progress_fraction()
	if animate and is_inside_tree() and not AccessibilitySettings.reduced_motion() and target > _display_fraction:
		_progress_tween = create_tween()
		_progress_tween.tween_method(_set_display_fraction, _display_fraction, target, 0.42)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_set_display_fraction(target)


func set_cap(amount: int) -> void:
	_cap = maxi(0, amount)
	set_total(_total)


func set_online(value: bool, earning_available: bool = true) -> void:
	_online = value
	_earning_available = earning_available
	_update_accessibility()
	queue_redraw()


func total() -> int:
	return _total


func cap() -> int:
	return _cap


func progress_fraction() -> float:
	return clampf(float(_total) / float(_cap), 0.0, 1.0) if _cap > 0 else 0.0


func _set_display_fraction(fraction: float) -> void:
	_display_fraction = clampf(fraction, 0.0, 1.0)
	queue_redraw()


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
	return get_global_transform() * (size * 0.5)


func _update_accessibility() -> void:
	if _online and not _earning_available:
		accessibility_name = "Online Gem earnings unavailable for this match"
	elif _cap > 0:
		var mode: String = "Online" if _online else "AI"
		accessibility_name = "%s Gem pot full: %d of %d Gems" % [mode, _total, _cap] if _total >= _cap else \
			"%s Gem pot: %d of %d Gems" % [mode, _total, _cap]
	else:
		accessibility_name = "Online Gem pot: %d Gems, no limit" % _total
	tooltip_text = accessibility_name


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var diameter: float = minf(size.x, size.y)
	if diameter <= 0.0:
		return
	var ring_width: float = maxf(6.0, diameter * 0.095)
	var radius: float = diameter * 0.43 - ring_width * 0.5
	var icon_width: float = diameter * 0.65
	var icon_size: Vector2 = Vector2(icon_width, icon_width * 408.0 / 464.0)
	var icon_rect: Rect2 = Rect2(center - icon_size * 0.5, icon_size)
	# The light disk keeps the deep-teal SVG legible in both appearance modes.
	draw_circle(center, radius + ring_width * 0.5, ICON_BACKDROP)
	draw_arc(center, radius, 0.0, TAU, 96, RING_TRACK, ring_width, true)
	if _cap > 0 and _earning_available and _display_fraction > 0.0:
		var fraction: float = _display_fraction
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * fraction,
			maxi(4, ceili(96.0 * fraction)), Tabletop.honey(), ring_width, true)
	draw_texture_rect(SAFE_ICON, icon_rect, false)
