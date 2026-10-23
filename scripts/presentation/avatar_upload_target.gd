extends Button
## Dashed upload target, drawn at the actual responsive control size.

const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")

func _draw() -> void:
	var bounds := Rect2(Vector2.ONE * 2.0, size - Vector2.ONE * 4.0)
	var color: Color = Tabletop.muted()
	draw_dashed_line(bounds.position, Vector2(bounds.end.x, bounds.position.y), color, 1.0, 9.0)
	draw_dashed_line(Vector2(bounds.end.x, bounds.position.y), bounds.end, color, 1.0, 9.0)
	draw_dashed_line(bounds.end, Vector2(bounds.position.x, bounds.end.y), color, 1.0, 9.0)
	draw_dashed_line(Vector2(bounds.position.x, bounds.end.y), bounds.position, color, 1.0, 9.0)
