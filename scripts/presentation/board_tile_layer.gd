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
const GRID_LINE: Color = Color("#173D42")

## Pixels trimmed from each cell so the backing shows through as a separator.
## At 1 px per edge, adjacent cells have a compact 2 px deep-teal gap.
const CELL_INSET: float = 1.0

const DEFAULT_CELL_TEXTURE: Texture2D = preload("res://assets/board/board_cell_default.png")


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
			if DEFAULT_CELL_TEXTURE != null:
				draw_texture_rect(DEFAULT_CELL_TEXTURE, slot, false)
			var snapshot: TileSnapshot = state.board.get_tile(cell)
			# A tile a scoring bounce is growing is left to the second pass
			# below, so the tile in the next cell along cannot cover it.
			if snapshot == null or state.concealed_cells.has(cell) or state.zoom_for(cell) > 1.0:
				continue
			TilePainter.paint_tile(self, slot, snapshot)
	_draw_zooming_tiles()


## Draws the tiles a scoring bounce is growing, after the grid.
##
## The main pass runs in row-major order, so a tile that grows past its own cell
## would be painted over by the next cell's tile. Drawing the growing tiles last
## is what makes the bounce read as rising toward the viewer rather than being
## clipped by its neighbour.
func _draw_zooming_tiles() -> void:
	if state.cell_zoom.is_empty():
		return
	for raw: Variant in state.cell_zoom.keys():
		var cell: Vector2i = raw
		if not BoardMetrics.is_valid_cell(cell, state.grid):
			continue
		var scale: float = state.zoom_for(cell)
		if scale <= 1.0:
			continue
		var snapshot: TileSnapshot = state.board.get_tile(cell)
		if snapshot == null or state.concealed_cells.has(cell):
			continue
		var rect: Rect2 = BoardMetrics.cell_rect(state.board_rect, cell, state.grid)
		var slot: Rect2 = rect.grow(-CELL_INSET)
		# Scaled about the slot's centre, so the tile grows toward the viewer
		# while staying centred on the cell it belongs to.
		var grown: Vector2 = slot.size * scale
		TilePainter.paint_tile(
			self, Rect2(slot.get_center() - grown * 0.5, grown), snapshot
		)
