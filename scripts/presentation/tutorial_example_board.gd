class_name TutorialExampleBoard
extends Control
## A read-only, cropped board illustration. Tile art comes from the game painter.

const Tabletop = preload("res://scripts/presentation/modern_tabletop_theme.gd")
const COLS: int = 6
const ROWS: int = 4

var example: String = "welcome":
	set(value):
		example = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 190.0
	accessibility_name = "Illustrated six-column crop of the twelve by twelve game board"


func _draw() -> void:
	var cell: float = floorf(minf((size.x - 24.0) / COLS, (size.y - 24.0) / ROWS))
	if cell < 18.0:
		return
	var extent := Vector2(cell * COLS, cell * ROWS)
	var origin: Vector2 = (size - extent) * 0.5
	var frame := Rect2(origin - Vector2(8, 8), extent + Vector2(16, 16))
	draw_rect(frame, Tabletop.ink(), true)
	for row: int in range(ROWS):
		for col: int in range(COLS):
			var rect := Rect2(origin + Vector2(col * cell + 2, row * cell + 2), Vector2.ONE * (cell - 4))
			draw_rect(rect, TilePainter.EMPTY_CELL, true)
	match example:
		"welcome", "place", "navigate":
			_draw_sample_tile(origin, cell, 2, 1, TileEnums.TileRank.KING, TileEnums.Suit.HEARTS, false)
			if example == "place":
				_outline_cell(origin, cell, 3, 1)
		"hands", "play", "actions":
			_draw_sample_tile(origin, cell, 2, 1, TileEnums.TileRank.KING, TileEnums.Suit.HEARTS, false)
			_draw_sample_tile(origin, cell, 3, 1, TileEnums.TileRank.KING, TileEnums.Suit.SPADES, true)
		"catalogue":
			for index: int in range(4):
				_draw_sample_tile(origin, cell, index + 1, 1, TileEnums.SEQUENCE_ORDER[index], TileEnums.Suit.HEARTS, index % 2 == 1)
		"edges":
			_draw_sample_tile(origin, cell, 2, 1, TileEnums.TileRank.KING, TileEnums.Suit.HEARTS, false)
			_draw_sample_tile(origin, cell, 3, 1, TileEnums.TileRank.KING, TileEnums.Suit.SPADES, true)
			var label_position: Vector2 = origin + Vector2(3 * cell - 12, cell - 4)
			draw_string(Tabletop.SEMIBOLD, label_position, "+1", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Tabletop.honey())
		"clusters":
			for index: int in range(4):
				_draw_sample_tile(origin, cell, index + 1, 1, TileEnums.TileRank.JACK, TileEnums.Suit.HEARTS, index % 2 == 1)
		"rivals":
			_draw_sample_tile(origin, cell, 2, 1, TileEnums.TileRank.QUEEN, TileEnums.Suit.HEARTS, false)
			_draw_sample_tile(origin, cell, 3, 1, TileEnums.TileRank.QUEEN, TileEnums.Suit.SPADES, true)


func _outline_cell(origin: Vector2, cell: float, col: int, row: int) -> void:
	var rect := Rect2(origin + Vector2(col * cell + 2, row * cell + 2), Vector2.ONE * (cell - 4))
	draw_rect(rect, Tabletop.honey(), false, 4.0)


func _draw_sample_tile(origin: Vector2, cell: float, col: int, row: int, rank: int, suit: int, matching_left: bool) -> void:
	# In the pair/cluster examples, every right/left boundary is blue. These are
	# illustrations only: no tutorial tile is placed in a live BoardState.
	var edges: Array[TileEnums.EdgeColor] = [
		TileEnums.EdgeColor.YELLOW,
		TileEnums.EdgeColor.BLUE,
		TileEnums.EdgeColor.GREEN,
		TileEnums.EdgeColor.BLUE if matching_left else TileEnums.EdgeColor.RED,
	]
	var definition: TileDefinition = TileDefinition.create(
		StringName("tutorial-%d-%d" % [col, row]), rank, TileEnums.color_for_suit(suit), edges, suit
	)
	var tile: TileSnapshot = TileSnapshot.create(definition, Vector2i(col, row))
	var rect := Rect2(origin + Vector2(col * cell + 1, row * cell + 1), Vector2.ONE * (cell - 2))
	TilePainter.paint_tile(self, rect, tile)
