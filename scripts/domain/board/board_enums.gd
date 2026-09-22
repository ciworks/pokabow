class_name BoardEnums
extends RefCounted

## Shared board vocabulary (ADR-006 sections 1, 2, 3, and 7).
##
## This script holds board constants and small pure helpers only. It has no
## state, no scene dependency, and no Godot node usage, so every layer can share
## one definition of the board geometry instead of duplicating constants.
##
## Authority notes:
## - Board size 12 x 12 is fixed by GAME_SPEC section 4.1 and ADR-006 constraints.
## - Coordinates are integers with the origin at the top-left; `x` increases left
##   to right and `y` increases top to bottom (ADR-006 section 1,
##   docs/sections/02-board-system.md section 1.1).
## - The four opening cells are the centre of the even-sized board
##   (ADR-006 section 2).
## - The four-neighbour orthogonal neighbourhood and the touching edge pairs
##   follow docs/sections/02-board-system.md section 5.1 and are restated by
##   ADR-006 section 3.
##
## Presentation converts board cells to pixels. Nothing in this file knows about
## pixels, scene nodes, or screen sizes.

## Number of board columns (ADR-006 constraint 1).
const BOARD_WIDTH: int = 12

## Number of board rows (ADR-006 constraint 1).
const BOARD_HEIGHT: int = 12

## Total number of cells on a full board.
const CELL_COUNT: int = BOARD_WIDTH * BOARD_HEIGHT

## Inclusive column/row range of the four central opening cells.
const OPENING_MIN: int = BOARD_WIDTH / 2 - 1
const OPENING_MAX: int = BOARD_WIDTH / 2


## Returns the four orthogonal neighbour offsets in the fixed order used
## throughout the rules layer: up, right, down, left.
##
## A fresh array is returned on every call, so callers may keep or modify it.
static func neighbor_offsets() -> Array[Vector2i]:
	return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


## Returns the four central opening cells, row-major (ADR-006 section 2).
##
## A fresh array is returned on every call.
static func opening_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(OPENING_MIN, OPENING_MAX + 1):
		for x: int in range(OPENING_MIN, OPENING_MAX + 1):
			cells.append(Vector2i(x, y))
	return cells


## Returns true when `cell` is one of the four central opening cells.
##
## The opening-cell rule applies only to the first move of a match
## (ADR-006 sections 2 and 3).
static func is_opening_cell(cell: Vector2i) -> bool:
	var in_opening_columns: bool = cell.x >= OPENING_MIN and cell.x <= OPENING_MAX
	var in_opening_rows: bool = cell.y >= OPENING_MIN and cell.y <= OPENING_MAX
	return in_opening_columns and in_opening_rows


## Returns true when `cell` lies on a `width` x `height` board
## (ADR-006 section 1).
static func is_in_bounds(cell: Vector2i, width: int = BOARD_WIDTH, height: int = BOARD_HEIGHT) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


## Returns the visual edge position of a tile that touches a neighbour in the
## given orthogonal direction.
##
## Uses the canonical edge index order from `TileEnums.EdgePosition`
## ([top, right, bottom, left], clockwise from the top).
## Returns -1 when `offset` is not one of the four orthogonal neighbours.
static func edge_position_toward(offset: Vector2i) -> int:
	if offset == Vector2i(0, -1):
		return TileEnums.EdgePosition.TOP
	if offset == Vector2i(1, 0):
		return TileEnums.EdgePosition.RIGHT
	if offset == Vector2i(0, 1):
		return TileEnums.EdgePosition.BOTTOM
	if offset == Vector2i(-1, 0):
		return TileEnums.EdgePosition.LEFT
	return -1


## Returns the edge position of the neighbour that faces back across a boundary
## to the tile holding `position`.
##
## Returns -1 when `position` is not a valid edge position.
static func opposite_edge_position(position: int) -> int:
	if not TileEnums.is_valid_edge_position(position):
		return -1
	var opposite: int = (position + 2) % TileEnums.EDGE_COUNT
	return opposite


## Returns the flat storage index of a cell on a `width`-wide board.
##
## Storage is row-major, which also gives deterministic row-major iteration order.
static func cell_index(cell: Vector2i, width: int = BOARD_WIDTH) -> int:
	return cell.y * width + cell.x


## Returns a short "(x, y)" label for diagnostics and failure messages.
static func cell_name(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]
