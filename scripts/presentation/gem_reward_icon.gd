class_name GemRewardIcon
extends Control

## Small faceted Gem mark shared by the compact results payout columns.
func _draw() -> void:
	var scale_factor: float = minf(size.x, size.y) / 32.0
	var offset: Vector2 = (size - Vector2.ONE * 32.0 * scale_factor) * 0.5
	var points := PackedVector2Array([
		Vector2(10, 2), Vector2(22, 2), Vector2(30, 12),
		Vector2(16, 30), Vector2(2, 12),
	])
	for i: int in points.size():
		points[i] = offset + points[i] * scale_factor
	draw_colored_polygon(points, Color("#E9AC45"))
	var center: Vector2 = offset + Vector2(16, 12) * scale_factor
	draw_colored_polygon(PackedVector2Array([points[0], points[1], center]), Color("#FFE29B"))
	draw_colored_polygon(PackedVector2Array([points[1], points[2], center]), Color("#F4C86A"))
	draw_colored_polygon(PackedVector2Array([points[2], points[3], center]), Color("#D79532"))
	draw_colored_polygon(PackedVector2Array([points[3], points[4], center]), Color("#FFC65A"))
