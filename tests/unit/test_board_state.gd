extends TestCase

## Milestone 2 board storage and query tests (ADR-006 sections 1, 2, 3, and 7).
##
## Domain-level tests: no scene tree, no rendering, no input. Every expectation
## is checked against `BoardState` alone.

const BLUE: int = TileEnums.EdgeColor.BLUE
const RED: int = TileEnums.EdgeColor.RED
const GREEN: int = TileEnums.EdgeColor.GREEN
const YELLOW: int = TileEnums.EdgeColor.YELLOW


func test_new_board_is_twelve_by_twelve_and_empty() -> void:
	var board: BoardState = BoardState.create()

	check_eq(board.get_width(), 12, "the board must be 12 columns wide")
	check_eq(board.get_height(), 12, "the board must be 12 rows high")
	check_eq(board.cell_count(), 144, "a 12 x 12 board holds 144 cells")
	check_eq(board.occupied_count(), 0, "a new board must be empty")
	check_eq(board.get_revision(), 0, "a new board starts at revision 0")
	check(not board.has_any_tile(), "a new board has no committed tile")
	check(not board.is_full(), "a new board is not full")
	check_eq(board.get_occupied_cells().size(), 0, "no cell may be occupied")
	check(board.get_tile(Vector2i(5, 5)) == null, "an empty cell holds no tile")


func test_bounds_and_queries_cover_every_edge_direction() -> void:
	var board: BoardState = BoardState.create()

	var inside: Array[Vector2i] = _cells([
		Vector2i(0, 0), Vector2i(11, 0), Vector2i(0, 11), Vector2i(11, 11), Vector2i(5, 5)
	])
	for cell: Vector2i in inside:
		check(board.is_in_bounds(cell), "%s must be in bounds" % BoardEnums.cell_name(cell))
		check(
			board.is_empty_cell(cell),
			"%s must be an empty in-bounds cell" % BoardEnums.cell_name(cell)
		)

	var outside: Array[Vector2i] = _cells([
		Vector2i(-1, 0),
		Vector2i(0, -1),
		Vector2i(12, 0),
		Vector2i(0, 12),
		Vector2i(12, 12),
		Vector2i(-1, -1),
		Vector2i(-1, 5),
		Vector2i(5, 12),
	])
	for cell: Vector2i in outside:
		check(not board.is_in_bounds(cell), "%s must be out of bounds" % BoardEnums.cell_name(cell))
		check(
			not board.is_empty_cell(cell),
			"%s cannot be an empty board cell" % BoardEnums.cell_name(cell)
		)
		check(not board.is_occupied(cell), "%s cannot be occupied" % BoardEnums.cell_name(cell))
		check(board.get_tile(cell) == null, "%s must hold no tile" % BoardEnums.cell_name(cell))


func test_orthogonal_neighbours_at_interior_edge_and_corner() -> void:
	var board: BoardState = BoardState.create()

	check_eq(
		board.get_orthogonal_neighbors(Vector2i(5, 5)),
		_cells([Vector2i(5, 4), Vector2i(6, 5), Vector2i(5, 6), Vector2i(4, 5)]),
		"an interior cell has four neighbours in up / right / down / left order"
	)
	check_eq(
		board.get_orthogonal_neighbors(Vector2i(0, 0)),
		_cells([Vector2i(1, 0), Vector2i(0, 1)]),
		"the top-left corner has two neighbours and no out-of-bounds entry"
	)
	check_eq(
		board.get_orthogonal_neighbors(Vector2i(11, 11)),
		_cells([Vector2i(11, 10), Vector2i(10, 11)]),
		"the bottom-right corner has two neighbours"
	)
	check_eq(
		board.get_orthogonal_neighbors(Vector2i(0, 5)),
		_cells([Vector2i(0, 4), Vector2i(1, 5), Vector2i(0, 6)]),
		"a left-edge cell drops only its out-of-bounds left neighbour"
	)
	check_eq(
		board.get_orthogonal_neighbors(Vector2i(3, 0)),
		_cells([Vector2i(4, 0), Vector2i(3, 1), Vector2i(2, 0)]),
		"a top-edge cell drops only its out-of-bounds top neighbour"
	)


func test_commit_writes_the_snapshot_and_bumps_the_revision() -> void:
	var board: BoardState = BoardState.create()
	var snapshot: TileSnapshot = _place(board, Vector2i(5, 5), 1, "opening")

	check_eq(board.occupied_count(), 1, "one committed tile must be recorded")
	check(board.is_occupied(Vector2i(5, 5)), "the target cell must become occupied")
	check(not board.is_empty_cell(Vector2i(5, 5)), "an occupied cell is no longer empty")
	check_eq(board.get_revision(), 1, "a commit must advance the board revision")
	check(board.has_any_tile(), "the board must report that it holds a tile")
	check_not_null(board.get_tile(Vector2i(5, 5)), "the committed tile must be readable")
	check_eq(
		board.get_tile(Vector2i(5, 5)).get_tile_id(),
		snapshot.get_tile_id(),
		"the committed snapshot must be the one that was placed"
	)
	check_eq(
		board.get_tile(Vector2i(5, 5)).get_rotation(),
		1,
		"the committed rotation must be preserved"
	)
	check_eq(
		board.get_occupied_cells(),
		_cells([Vector2i(5, 5)]),
		"the occupied-cell list must report the committed cell"
	)


func test_commit_rejects_illegal_snapshots_without_mutating() -> void:
	var board: BoardState = BoardState.create()

	check(not board.commit_tile(null), "a null snapshot cannot be committed")
	check(
		not board.commit_tile(TileSnapshot.create(_invalid_tile(), Vector2i(5, 5), 0)),
		"a snapshot wrapping an invalid tile cannot be committed"
	)
	check(
		not board.commit_tile(TileSnapshot.create(_tile("oob"), Vector2i(12, 0), 0)),
		"an out-of-bounds snapshot cannot be committed"
	)
	check_eq(board.occupied_count(), 0, "rejected commits must not occupy a cell")
	check_eq(board.get_revision(), 0, "rejected commits must not advance the revision")

	_place(board, Vector2i(5, 5), 0, "first")
	check(
		not board.commit_tile(TileSnapshot.create(_tile("second"), Vector2i(5, 5), 0)),
		"an occupied cell cannot receive a second tile"
	)
	check_eq(board.occupied_count(), 1, "the rejected second commit must change nothing")
	check_eq(board.get_revision(), 1, "the rejected second commit must not advance the revision")
	check_eq(
		board.get_tile(Vector2i(5, 5)).get_tile_id(),
		&"first",
		"the original committed tile must be untouched"
	)


func test_occupied_neighbours_are_reported_in_fixed_order() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 0, "centre")
	_place(board, Vector2i(5, 4), 0, "above")
	_place(board, Vector2i(6, 5), 0, "right")
	_place(board, Vector2i(4, 6), 0, "diagonal")

	check(board.has_occupied_neighbor(Vector2i(5, 5)), "the centre tile has tiled neighbours")
	check_eq(
		board.get_occupied_neighbors(Vector2i(5, 5)),
		_cells([Vector2i(5, 4), Vector2i(6, 5)]),
		"occupied neighbours must follow up / right / down / left order"
	)
	check_eq(
		board.get_occupied_neighbors(Vector2i(4, 6)),
		_cells([]),
		"the diagonally placed tile has no orthogonal neighbour, (5,5) touches it only corner to corner"
	)
	check(
		not board.get_occupied_neighbors(Vector2i(5, 5)).has(Vector2i(4, 6)),
		"a diagonally touching tile is not an orthogonal neighbour"
	)
	check(
		not board.has_occupied_neighbor(Vector2i(0, 0)),
		"a cell away from every tile has no occupied neighbour"
	)


func test_copy_is_independent_of_its_source() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 0, "original")
	var clone: BoardState = board.copy()

	check_eq(clone.get_revision(), board.get_revision(), "a copy keeps the source revision")
	check_eq(clone.occupied_count(), 1, "a copy keeps the source occupancy")

	_place(clone, Vector2i(6, 5), 0, "clone-only")

	check_eq(clone.occupied_count(), 2, "the copy must accept its own commit")
	check_eq(board.occupied_count(), 1, "committing to a copy must not touch the source")
	check(board.is_empty_cell(Vector2i(6, 5)), "the source cell must stay empty")
	check_eq(board.get_revision(), 1, "the source revision must not move for a copy commit")


func test_hypothetical_view_leaves_the_source_untouched() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 0, "committed")

	var hypothetical: BoardState = board.with_tile(
		TileSnapshot.create(_tile("preview"), Vector2i(6, 5), 2)
	)

	check(hypothetical.is_occupied(Vector2i(6, 5)), "the hypothetical view must hold the preview")
	check_eq(hypothetical.occupied_count(), 2, "the hypothetical view counts the preview")
	check_eq(
		hypothetical.get_revision(),
		board.get_revision(),
		"a preview is not a commit, so the revision must not change"
	)
	check(board.is_empty_cell(Vector2i(6, 5)), "the real board must stay empty")
	check_eq(board.occupied_count(), 1, "the real board must keep its occupancy")
	check_eq(board.get_revision(), 1, "the real board revision must not change")

	var unchanged: BoardState = board.with_tile(
		TileSnapshot.create(_tile("clash"), Vector2i(5, 5), 0)
	)
	check_eq(
		unchanged.occupied_count(),
		board.occupied_count(),
		"a hypothetical tile on an occupied cell must be ignored"
	)
	check(not board.is_frontier_cell(Vector2i(5, 5)), "the source frontier must not gain the cell")


func test_occupied_cells_are_reported_in_row_major_order() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 0, "a")
	_place(board, Vector2i(6, 5), 0, "b")
	_place(board, Vector2i(5, 6), 0, "c")

	check_eq(
		board.get_occupied_cells(),
		_cells([Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6)]),
		"occupied cells must be listed top-to-bottom then left-to-right"
	)


func test_board_vocabulary_helpers_follow_the_documented_convention() -> void:
	check_eq(
		BoardEnums.edge_position_toward(Vector2i(0, -1)),
		TileEnums.EdgePosition.TOP,
		"the neighbour above a cell touches its top edge"
	)
	check_eq(
		BoardEnums.edge_position_toward(Vector2i(1, 0)),
		TileEnums.EdgePosition.RIGHT,
		"the neighbour to the right touches the right edge"
	)
	check_eq(
		BoardEnums.edge_position_toward(Vector2i(0, 1)),
		TileEnums.EdgePosition.BOTTOM,
		"the neighbour below touches the bottom edge"
	)
	check_eq(
		BoardEnums.edge_position_toward(Vector2i(-1, 0)),
		TileEnums.EdgePosition.LEFT,
		"the neighbour to the left touches the left edge"
	)
	check_eq(
		BoardEnums.edge_position_toward(Vector2i(1, 1)),
		-1,
		"a diagonal offset is not an edge relationship"
	)
	check_eq(
		BoardEnums.opposite_edge_position(TileEnums.EdgePosition.TOP),
		TileEnums.EdgePosition.BOTTOM,
		"top and bottom are touching edge positions"
	)
	check_eq(
		BoardEnums.opposite_edge_position(TileEnums.EdgePosition.LEFT),
		TileEnums.EdgePosition.RIGHT,
		"left and right are touching edge positions"
	)
	check_eq(BoardEnums.cell_index(Vector2i(3, 2), 12), 27, "cells index row-major")
	check_eq(BoardEnums.opening_cells().size(), 4, "four opening cells are defined")
	for cell: Vector2i in BoardEnums.opening_cells():
		check(BoardEnums.is_opening_cell(cell), "%s must be an opening cell" % BoardEnums.cell_name(cell))
	check(not BoardEnums.is_opening_cell(Vector2i(4, 5)), "(4,5) is outside the central block")
	check(not BoardEnums.is_opening_cell(Vector2i(5, 4)), "(5,4) is outside the central block")
	check(not BoardEnums.is_opening_cell(Vector2i(7, 6)), "(7,6) is outside the central block")


## Places a snapshot directly on the board, as the authoritative writer would.
func _place(board: BoardState, cell: Vector2i, rotation: int, id: String) -> TileSnapshot:
	var snapshot: TileSnapshot = TileSnapshot.create(_tile(id), cell, rotation)
	board.commit_tile(snapshot)
	return snapshot


## Builds a valid tile with four distinct edge colours so rotation is observable.
func _tile(id: String) -> TileDefinition:
	return _tile_with_edges(id, BLUE, RED, GREEN, YELLOW)


## Builds a valid tile from explicit edge colours in top / right / bottom / left order.
func _tile_with_edges(id: String, top: int, right: int, bottom: int, left: int) -> TileDefinition:
	var edges: Array[TileEnums.EdgeColor] = []
	edges.append(top)
	edges.append(right)
	edges.append(bottom)
	edges.append(left)
	return TileDefinition.create(
		StringName(id), TileEnums.TileRank.ACE, TileEnums.FaceColor.RED, edges
	)


## Builds a tile whose edge count violates the tile contract.
func _invalid_tile() -> TileDefinition:
	var edges: Array[TileEnums.EdgeColor] = []
	edges.append(BLUE)
	return TileDefinition.create(
		StringName("invalid"), TileEnums.TileRank.ACE, TileEnums.FaceColor.RED, edges
	)


## Converts a literal list into a typed cell array for comparison.
func _cells(values: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for value: Variant in values:
		cells.append(value)
	return cells
