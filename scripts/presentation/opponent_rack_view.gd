class_name OpponentRackView
extends Control

## Concealed opponent hand: only the public count reaches this view.
var _tile_count: int = 0
var _concealed: Array[int] = []
var _board_cell_side: float = 0.0
const TILE_SCALE: float = 1.0
const TILE_GAP_RATIO: float = 0.1


func _ready() -> void:
	resized.connect(queue_redraw)


func set_tile_count(count: int) -> void:
	_tile_count = maxi(0, count)
	queue_redraw()


func set_board_cell_side(cell_side: float) -> void:
	var bounded_side: float = maxf(0.0, cell_side)
	if is_equal_approx(_board_cell_side, bounded_side):
		return
	_board_cell_side = bounded_side
	queue_redraw()


func set_concealed(indices: Array[int]) -> void:
	if _concealed == indices:
		return
	_concealed = indices.duplicate()
	queue_redraw()


## Count override keeps departing slots stable until all played tiles have left.
func tile_rect(index: int, count: int = -1) -> Rect2:
	var total: int = _tile_count if count < 0 else count
	if total <= 0 or index < 0 or index >= total:
		return Rect2()
	var side: float = _board_cell_side * TILE_SCALE
	var gap: float = side * TILE_GAP_RATIO
	if total > 1:
		# Keep the tile faces full size. When the row is narrow, overlap the
		# spacing instead of scaling the tiles down to fit.
		gap = minf(gap, (size.x - side * float(total)) / float(total - 1))
	var group_width: float = side * float(total) + gap * float(total - 1)
	var origin := Vector2((size.x - group_width) * 0.5 + float(index) * (side + gap), (size.y - side) * 0.5)
	return Rect2(origin, Vector2.ONE * side)


func tile_global_rect(index: int, count: int = -1) -> Rect2:
	return get_global_transform() * tile_rect(index, count)


func _draw() -> void:
	for index: int in range(_tile_count):
		if not _concealed.has(index):
			TilePainter.paint_opponent_tile_back(self, tile_rect(index))
