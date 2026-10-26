class_name StoreGemCluster
extends Control
## Small illustrated Gem group shared by the Shop offer cards.

const GEM: Texture2D = preload("res://assets/ui/modern_tabletop/store_gem.svg")

var gem_count: int = 1:
	set(value):
		gem_count = clampi(value, 1, 3)
		queue_redraw()
var backdrop: Color = Color.TRANSPARENT:
	set(value):
		backdrop = value
		queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.46
	if backdrop.a > 0.0:
		draw_circle(center, radius, backdrop)
	var gem_size: Vector2 = Vector2(radius * 1.16, radius * 1.04)
	var offsets: Array[Vector2] = [Vector2.ZERO]
	var angles: Array[float] = [0.0]
	if gem_count == 2:
		offsets = [Vector2(-radius * 0.25, radius * 0.09), Vector2(radius * 0.24, -radius * 0.16)]
		angles = [-0.18, 0.16]
	elif gem_count == 3:
		offsets = [Vector2(-radius * 0.31, radius * 0.22), Vector2(radius * 0.20, -radius * 0.28), Vector2(radius * 0.26, radius * 0.25)]
		angles = [-0.19, 0.12, 0.16]
		gem_size *= 0.82
	for index: int in range(offsets.size()):
		draw_set_transform(center + offsets[index], angles[index])
		draw_texture_rect(GEM, Rect2(-gem_size * 0.5, gem_size), false)
	draw_set_transform(Vector2.ZERO)
