class_name GemTravelLayer
extends Control

## A short, non-blocking presentation of a committed online hand contribution.
## The pot amount is applied on arrival; interrupted flights are reconciled from
## the authoritative ledger by GameScreen when the view is recreated.
const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const DURATION: float = 0.88
const ARRIVAL_RADIUS: float = 4.2
const START_RADIUS: float = 15.0

var _flights: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func play(start: Vector2, destination: Vector2, amount: int, arrived: Callable, delay: float = 0.0) -> void:
	if amount <= 0:
		return
	_show_gain_label(start, amount)
	if AccessibilitySettings.reduced_motion():
		arrived.call()
		return
	_flights.append({
		"start": start,
		"end": destination,
		"amount": amount,
		"elapsed": -maxf(delay, 0.0),
		"arrived": arrived,
	})
	set_process(true)
	queue_redraw()


func clear() -> void:
	_flights.clear()
	set_process(false)
	queue_redraw()
	for child: Node in get_children():
		child.queue_free()


func active_flights() -> int:
	return _flights.size()


func _process(delta: float) -> void:
	for index: int in range(_flights.size() - 1, -1, -1):
		var flight: Dictionary = _flights[index]
		flight["elapsed"] = float(flight["elapsed"]) + delta
		if float(flight["elapsed"]) >= DURATION:
			_flights.remove_at(index)
			var on_arrival: Callable = flight["arrived"]
			on_arrival.call()
	if _flights.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for flight: Dictionary in _flights:
		if float(flight["elapsed"]) <= 0.0:
			continue
		var progress: float = clampf(float(flight["elapsed"]) / DURATION, 0.0, 1.0)
		var count: int = int(flight["amount"])
		var interval: float = 0.025
		var travel_span: float = 1.0 - float(count - 1) * interval
		for gem_index: int in count:
			var shifted: float = progress - float(gem_index) * interval
			if shifted <= 0.0:
				continue
			var step: float = clampf(shifted / travel_span, 0.0, 1.0)
			var point: Vector2 = _curve(flight["start"], flight["end"], step)
			var fade: float = 1.0 - 0.15 * (1.0 - step)
			# Start as a legible board-sized Gem, then settle to the existing
			# small trail size before it reaches the pot.
			var arrival_radius: float = ARRIVAL_RADIUS + float(gem_index % 3) * 0.8
			var start_radius: float = START_RADIUS + float(gem_index % 3) * 1.2
			var radius: float = lerpf(start_radius, arrival_radius, smoothstep(0.0, 0.9, step))
			_draw_gem(point, radius, fade)
			if gem_index % 2 == 0:
				var sparkle: Color = Color("#FFE49A")
				sparkle.a = 0.4 * fade
				draw_circle(point + Vector2(-radius * 1.5, radius * 1.5), lerpf(2.2, 1.5, step), sparkle)


func _curve(start: Vector2, destination: Vector2, t: float) -> Vector2:
	var control_a: Vector2 = start + Vector2(46.0, -88.0)
	var control_b: Vector2 = destination + Vector2(-35.0, 76.0)
	var inverse: float = 1.0 - t
	return inverse * inverse * inverse * start + 3.0 * inverse * inverse * t * control_a + 3.0 * inverse * t * t * control_b + t * t * t * destination


func _draw_gem(point: Vector2, radius: float, alpha: float) -> void:
	var light: Color = Color("#FFE49A")
	light.a = alpha
	var honey: Color = Color("#E9AC45")
	honey.a = alpha
	var vertices: PackedVector2Array = PackedVector2Array([
		point + Vector2(0, -radius), point + Vector2(radius * 0.75, -radius * 0.2),
		point + Vector2(radius * 0.55, radius * 0.7), point + Vector2(0, radius),
		point + Vector2(-radius * 0.7, radius * 0.2), point + Vector2(-radius * 0.7, -radius * 0.25),
	])
	draw_colored_polygon(vertices, honey)
	draw_colored_polygon(PackedVector2Array([vertices[0], vertices[1], point]), light)


func _show_gain_label(at: Vector2, amount: int) -> void:
	var pill: PanelContainer = PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface: StyleBoxFlat = Tabletop.panel(Tabletop.honey(), 12, 7.0)
	surface.set_border_width_all(1)
	surface.border_color = Tabletop.ink()
	pill.add_theme_stylebox_override("panel", surface)
	var label: Label = Label.new()
	label.text = "+%d GEMS" % amount
	label.add_theme_font_override("font", Tabletop.SEMIBOLD)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Tabletop.ink())
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(label)
	add_child(pill)
	pill.size = pill.get_combined_minimum_size()
	pill.position = (at + Vector2(16.0, -36.0)).clamp(Vector2(4.0, 4.0), (size - pill.size - Vector2(4.0, 4.0)).max(Vector2(4.0, 4.0)))
	var fade: Tween = pill.create_tween()
	fade.tween_interval(0.55)
	fade.tween_property(pill, "modulate:a", 0.0, 0.40)
	fade.tween_callback(pill.queue_free)
