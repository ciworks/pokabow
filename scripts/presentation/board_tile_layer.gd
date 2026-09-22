class_name BoardTileLayer
extends Control

## Draws the board grid and every committed tile (ADR-008 section 4).
##
## Committed tiles are read straight from the authoritative `BoardState` on each
## redraw, so this layer has no copy of the board to fall out of step with it.
## A redraw is requested only when the state changed or the view resized
## (ADR-008 section 9: render committed tiles from the authoritative snapshot).

## Current render state, assigned by `BoardView`.
var state: BoardRenderState = null

## Colour of the board backing, seen between cells as the grid.
##
## Painted under every cell so the separations read as grid lines: without it the
## empty cells are one continuous block the colour of the screen background, and
## the player cannot see which cell they are tapping.
const GRID_LINE: Color = Color(0.09, 0.10, 0.13, 1.0)

## Pixels trimmed from each cell so the backing shows through as a separator.
const CELL_INSET: float = 1.0


func _ready() -> void:
	# Pointer handling belongs to BoardInputController. A Control that accepted
	# mouse input here would silently swallow board gestures before
	# `_unhandled_input` ever saw them (ADR-008 section 8).
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if state == null or state.board == null:
		return
	_draw_board()


## Draws every cell: an empty slot, or the tile committed to it.
##
## The board backing is painted first and each cell is inset slightly, so the
## backing shows through as the grid the player aims at.
func _draw_board() -> void:
	var grid: int = state.grid
	TilePainter.paint_cell(self, state.board_rect, GRID_LINE)
	for y: int in range(grid):
		for x: int in range(grid):
			var cell: Vector2i = Vector2i(x, y)
			var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, grid)
			var slot: Rect2 = rect.grow(-CELL_INSET)
			TilePainter.paint_cell(self, slot, TilePainter.EMPTY_CELL)
			var snapshot: TileSnapshot = state.board.get_tile(cell)
			if snapshot != null:
				TilePainter.paint_tile(self, slot, snapshot)
