extends Control
## A subtle winner ring and two hand-drawn sparkles driven by the results screen.
const T = preload("res://scripts/presentation/modern_tabletop_theme.gd")
var winner: bool = false
var pulse: float = 0.0
var sparkle_alpha: float = 0.0

func _draw() -> void:
	if not winner:
		return
	var radius: float = minf(size.x, size.y) * 0.48
	draw_arc(size * 0.5, radius * (1.0 + pulse * 0.03), 0, TAU, 96, T.honey(), maxf(2, radius * 0.055), true)
	if sparkle_alpha <= 0:
		return
	for center: Vector2 in [Vector2(0.02, 0.18) * size, Vector2(0.98, 0.28) * size]:
		var points := PackedVector2Array()
		for i: int in range(8):
			var angle: float = float(i) * PI / 4.0
			var length: float = radius * (0.16 if i % 2 == 0 else 0.045)
			points.append(center + Vector2(cos(angle), sin(angle)) * length)
		draw_colored_polygon(points, Color(T.honey(), sparkle_alpha))
