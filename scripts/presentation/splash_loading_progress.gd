extends ProgressBar
## Four tiles display the existing warm-up progress without a looping animation.
## Keeping Range/ProgressBar semantics preserves AppRoot's startup contract.
const TABLETOP = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const TILE_COUNT: int = 4

func _ready() -> void:
	show_percentage = false
	add_theme_stylebox_override("background", StyleBoxEmpty.new())
	add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	value_changed.connect(_on_value_changed)
	resized.connect(queue_redraw)
	queue_redraw()

func _on_value_changed(_progress: float) -> void:
	queue_redraw()

func _draw() -> void:
	var edge: float = minf(size.y, size.x / 5.0)
	var gap: float = edge * 0.28
	var left: float = (size.x - TILE_COUNT * edge - (TILE_COUNT - 1) * gap) * 0.5
	var completed: int = clampi(floori(ratio * TILE_COUNT), 0, TILE_COUNT)
	for index: int in range(TILE_COUNT):
		var colour: Color = TABLETOP.sage()
		if index < completed:
			colour = TABLETOP.ink()
		elif index == completed:
			colour = TABLETOP.honey()
		# Keep the concept's final honey tile during the existing branding hold.
		if completed == TILE_COUNT and index == TILE_COUNT - 1:
			colour = TABLETOP.honey()
		var box: StyleBoxFlat = TABLETOP.panel(colour, maxi(2, roundi(edge * 0.22)), 0)
		draw_style_box(box, Rect2(left + index * (edge + gap), (size.y - edge) * 0.5, edge, edge))

