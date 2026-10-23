extends Control
## Decorative samples use the real tile painter and never enter match state.
var _samples: Array[TileSnapshot] = []

func _ready() -> void:
	var edges: Array[TileEnums.EdgeColor] = [TileEnums.EdgeColor.YELLOW, TileEnums.EdgeColor.RED, TileEnums.EdgeColor.GREEN, TileEnums.EdgeColor.BLUE]
	_samples.append(TileSnapshot.create(TileDefinition.create(&"preview-ace", TileEnums.TileRank.ACE, TileEnums.FaceColor.BLACK, edges, TileEnums.Suit.SPADES), Vector2i.ZERO))
	_samples.append(TileSnapshot.create(TileDefinition.create(&"preview-king", TileEnums.TileRank.KING, TileEnums.FaceColor.RED, edges, TileEnums.Suit.HEARTS), Vector2i.ZERO))
	resized.connect(queue_redraw)

func _draw() -> void:
	var side: float = size.y * 0.7
	for i: int in range(_samples.size()):
		var center := Vector2(size.x * 0.5 + (float(i) - 0.5) * side * 1.13, size.y * 0.5)
		draw_set_transform(center, -0.14 if i == 0 else 0.14)
		TilePainter.paint_tile(self, Rect2(Vector2.ONE * -side * 0.5, Vector2.ONE * side), _samples[i])
	draw_set_transform(Vector2.ZERO)
