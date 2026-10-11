class_name TurnTimerOutline
extends PanelContainer

## Presentation only: the controller supplies whole seconds. A continuous
## rounded perimeter loses one equal-length segment per second (ADR-017).
const COLOR: Color = Color(1.0, 0.87, 0.30, 1.0)
const WIDTH: float = 3.0
const RADIUS: float = 10.0
const CORNER_STEPS: int = 12

var seconds_left: int = 0


func set_seconds_left(seconds: int) -> void:
	var bounded: int = clampi(seconds, 0, int(TurnManager.TURN_SECONDS))
	if seconds_left == bounded:
		return
	seconds_left = bounded
	queue_redraw()


func _draw() -> void:
	var visible_path: PackedVector2Array = remaining_path()
	if visible_path.size() >= 2:
		draw_polyline(visible_path, COLOR, WIDTH, true)


## Follow clockwise from the top-left straight edge, clipping by distance
## rather than point count so straight sides and curved corners drain evenly.
func remaining_path() -> PackedVector2Array:
	if seconds_left <= 0 or size.x <= WIDTH or size.y <= WIDTH:
		return PackedVector2Array()
	var inset: float = WIDTH * 0.5
	var radius: float = minf(RADIUS, minf(size.x, size.y) * 0.5 - inset)
	var left: float = inset
	var top: float = inset
	var right: float = size.x - inset
	var bottom: float = size.y - inset
	var path := PackedVector2Array([Vector2(left + radius, top)])
	var centers: Array[Vector2] = [
		Vector2(right - radius, top + radius),
		Vector2(right - radius, bottom - radius),
		Vector2(left + radius, bottom - radius),
		Vector2(left + radius, top + radius),
	]
	for corner: int in range(4):
		for step: int in range(CORNER_STEPS + 1):
			var angle: float = -PI * 0.5 + corner * PI * 0.5 + float(step) / CORNER_STEPS * PI * 0.5
			path.append(centers[corner] + Vector2(cos(angle), sin(angle)) * radius)
	var length: float = 0.0
	for index: int in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	var removed: float = length * (1.0 - float(seconds_left) / TurnManager.TURN_SECONDS)
	var visible_path := PackedVector2Array()
	for index: int in range(1, path.size()):
		var segment_length: float = path[index - 1].distance_to(path[index])
		if removed >= segment_length:
			removed -= segment_length
			continue
		if visible_path.is_empty():
			visible_path.append(path[index - 1].lerp(path[index], removed / segment_length))
		visible_path.append(path[index])
		removed = 0.0
	return visible_path
