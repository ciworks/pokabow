class_name BoardMetrics
extends RefCounted

## Pure board-to-pixel geometry for presentation (ADR-008 sections 4 and 8).
##
## The board is a centred square inside whatever rectangle the layout gives it,
## so the same arithmetic works on a 1280 x 720 desktop window and on a
## landscape phone. Nothing here reads a node, the scene tree, or a game rule:
## `BoardView` and `BoardInputController` both call these functions, which is
## what keeps pointer-to-cell conversion in exactly one place
## (ADR-008 section 8).
##
## Cell (0, 0) is the top-left cell (ADR-006 section 1), so cell coordinates
## increase left to right and top to bottom exactly as board coordinates do.
##
## These functions are pure and scene-free, so the responsive-fit and
## pointer-mapping behaviour ADR-008 section 13 asks scene smoke tests to cover
## can also be unit tested headlessly.

const DEFAULT_GRID: int = BoardEnums.BOARD_WIDTH

## Returned by `cell_from_point` for a point that is not on the board.
const NO_CELL: Vector2i = Vector2i(-1, -1)


## A camera expressed as a normalized board center; clamp it so no blank space
## can be dragged into the viewport. Shared by drawing and hit testing.
static func camera_rect(viewport_size: Vector2, zoom: float, center: Vector2) -> Rect2:
	var bounded_zoom: float = maxf(1.0, zoom)
	var side: float = maxf(viewport_size.x * bounded_zoom, viewport_size.y)
	if side <= 0.0:
		return Rect2()
	var board_size: Vector2 = Vector2.ONE * side
	var half_visible: Vector2 = viewport_size / (2.0 * side)
	var bounded_center := center.clamp(half_visible, Vector2.ONE - half_visible)
	return Rect2(viewport_size * 0.5 - bounded_center * board_size, board_size)


## Fits a centered viewport without stretching its square board cells.
static func fit_aspect(available: Rect2, aspect: float, padding: float = 0.0) -> Rect2:
	var inner: Vector2 = (available.size - Vector2.ONE * maxf(padding, 0.0) * 2.0).max(Vector2.ZERO)
	var ratio: float = maxf(aspect, 0.001)
	var width: float = minf(inner.x, inner.y * ratio)
	var fitted: Vector2 = Vector2(width, width / ratio)
	return Rect2(available.position + (available.size - fitted) * 0.5, fitted)


## Returns the largest centred square that fits inside `available` once
## `padding` has been removed from every side.
##
## A centred square stops the 12 x 12 grid from stretching on a wide landscape
## display and keeps every tile square at any viewport size.
static func fit_square(available: Rect2, padding: float = 0.0) -> Rect2:
	var safe_padding: float = maxf(padding, 0.0)
	var inner: Vector2 = Vector2(
		maxf(available.size.x - safe_padding * 2.0, 0.0),
		maxf(available.size.y - safe_padding * 2.0, 0.0)
	)
	var side: float = minf(inner.x, inner.y)
	var square_size: Vector2 = Vector2(side, side)
	var centred: Vector2 = available.position + (available.size - square_size) * 0.5
	return Rect2(centred, square_size)


## Returns the side length of one cell on a `grid` x `grid` board.
static func cell_size(board_rect: Rect2, grid: int = DEFAULT_GRID) -> float:
	if grid <= 0:
		return 0.0
	return board_rect.size.x / float(grid)


## Returns the pixel rectangle of one cell.
static func cell_rect(board_rect: Rect2, cell: Vector2i, grid: int = DEFAULT_GRID) -> Rect2:
	var side: float = cell_size(board_rect, grid)
	var origin: Vector2 = board_rect.position + Vector2(cell.x, cell.y) * side
	return Rect2(origin, Vector2(side, side))


## Returns the centre point of one cell.
static func cell_center(board_rect: Rect2, cell: Vector2i, grid: int = DEFAULT_GRID) -> Vector2:
	var side: float = cell_size(board_rect, grid)
	return cell_rect(board_rect, cell, grid).position + Vector2(side, side) * 0.5


## Returns the cell containing `point`, or `NO_CELL` when the point is outside.
##
## The check uses the board rectangle's own bounds rather than `Rect2.has_point`
## so a point exactly on the far edge is treated as outside; the last cell ends
## just before it.
static func cell_from_point(
	board_rect: Rect2, point: Vector2, grid: int = DEFAULT_GRID
) -> Vector2i:
	if grid <= 0:
		return NO_CELL
	var side: float = cell_size(board_rect, grid)
	if side <= 0.0:
		return NO_CELL
	var local: Vector2 = point - board_rect.position
	if local.x < 0.0 or local.y < 0.0:
		return NO_CELL
	var cell: Vector2i = Vector2i(int(floor(local.x / side)), int(floor(local.y / side)))
	if not is_valid_cell(cell, grid):
		return NO_CELL
	return cell


## Returns true when `cell` lies on a `grid` x `grid` board.
static func is_valid_cell(cell: Vector2i, grid: int = DEFAULT_GRID) -> bool:
	return cell.x >= 0 and cell.x < grid and cell.y >= 0 and cell.y < grid
