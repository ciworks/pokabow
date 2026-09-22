extends TestCase

## Milestone 2 placement legality tests (ADR-006 sections 2, 3, 4, and 5).
##
## Every expected rejection code is asserted explicitly, because mobile UI and
## AI search both depend on `PlacementValidator` returning structured reasons
## rather than a bare true/false.

const BLUE: int = TileEnums.EdgeColor.BLUE
const RED: int = TileEnums.EdgeColor.RED
const GREEN: int = TileEnums.EdgeColor.GREEN
const YELLOW: int = TileEnums.EdgeColor.YELLOW


func test_each_opening_cell_is_accepted_on_an_empty_board() -> void:
	for cell: Vector2i in BoardEnums.opening_cells():
		var board: BoardState = BoardState.create()
		var result: PlacementResult = _validate(board, cell, 0, _tile("opening"))
		check_not_null(result, "validation must return a result for %s" % BoardEnums.cell_name(cell))
		check(
			result.accepted,
			"the opening move at %s must be legal, rejected as %s"
			% [BoardEnums.cell_name(cell), result.get_rejection_name()]
		)
		check_eq(
			result.changed_cells,
			_cells([cell]),
			"the opening move touches only its own cell"
		)


func test_cells_outside_the_central_block_are_rejected_as_opening_cells() -> void:
	var board: BoardState = BoardState.create()
	var refused: Array[Vector2i] = _cells([
		Vector2i(0, 0), Vector2i(4, 5), Vector2i(5, 4), Vector2i(6, 7), Vector2i(7, 6), Vector2i(11, 11)
	])
	for cell: Vector2i in refused:
		var result: PlacementResult = _validate(board, cell, 0, _tile("opening"))
		check(
			not result.accepted,
			"the first tile cannot open at %s" % BoardEnums.cell_name(cell)
		)
		check_eq(
			result.rejection,
			PlacementEnums.PlacementRejection.OPENING_CELL_REQUIRED,
			"%s must be refused with OPENING_CELL_REQUIRED" % BoardEnums.cell_name(cell)
		)
		check(result.placed_tile == null, "a refused placement must carry no tile")
		check_eq(result.changed_cells.size(), 0, "a refused placement must change no cell")


func test_out_of_bounds_cells_are_rejected_in_every_direction() -> void:
	var board: BoardState = BoardState.create()
	board.commit_tile(TileSnapshot.create(_tile("centre"), Vector2i(5, 5), 0))

	var outside: Array[Vector2i] = _cells([
		Vector2i(-1, 5),
		Vector2i(5, -1),
		Vector2i(12, 5),
		Vector2i(5, 12),
		Vector2i(-1, -1),
		Vector2i(12, 12),
	])
	for cell: Vector2i in outside:
		var result: PlacementResult = _validate(board, cell, 0, _tile("neighbour"))
		check(
			not result.accepted,
			"%s is off the board and must be refused" % BoardEnums.cell_name(cell)
		)
		check_eq(
			result.rejection,
			PlacementEnums.PlacementRejection.OUT_OF_BOUNDS,
			"%s must be refused with OUT_OF_BOUNDS" % BoardEnums.cell_name(cell)
		)


func test_occupied_cells_are_rejected() -> void:
	var board: BoardState = BoardState.create()
	board.commit_tile(TileSnapshot.create(_tile("centre"), Vector2i(5, 5), 0))

	var result: PlacementResult = _validate(board, Vector2i(5, 5), 0, _tile("second"))

	check(not result.accepted, "an occupied cell cannot receive another tile")
	check_eq(
		result.rejection,
		PlacementEnums.PlacementRejection.CELL_OCCUPIED,
		"an occupied cell must be refused with CELL_OCCUPIED"
	)


func test_all_four_orthogonal_directions_are_connected() -> void:
	var directions: Array[Vector2i] = _cells([
		Vector2i(5, 4), Vector2i(6, 5), Vector2i(5, 6), Vector2i(4, 5)
	])
	for cell: Vector2i in directions:
		var board: BoardState = BoardState.create()
		board.commit_tile(TileSnapshot.create(_tile("centre"), Vector2i(5, 5), 0))
		var result: PlacementResult = _validate(board, cell, 0, _tile("neighbour"))
		check(
			result.accepted,
			"placing at %s touches the centre tile, rejected as %s"
			% [BoardEnums.cell_name(cell), result.get_rejection_name()]
		)


func test_diagonal_only_contact_is_rejected() -> void:
	var diagonals: Array[Vector2i] = _cells([
		Vector2i(4, 4), Vector2i(6, 4), Vector2i(4, 6), Vector2i(6, 6)
	])
	for cell: Vector2i in diagonals:
		var board: BoardState = BoardState.create()
		board.commit_tile(TileSnapshot.create(_tile("centre"), Vector2i(5, 5), 0))
		var result: PlacementResult = _validate(board, cell, 0, _tile("diagonal"))
		check(
			not result.accepted,
			"diagonal-only contact at %s is not a legal connection" % BoardEnums.cell_name(cell)
		)
		check_eq(
			result.rejection,
			PlacementEnums.PlacementRejection.NOT_CONNECTED,
			"%s must be refused with NOT_CONNECTED" % BoardEnums.cell_name(cell)
		)


func test_a_cell_far_from_every_tile_is_not_connected() -> void:
	var board: BoardState = BoardState.create()
	board.commit_tile(TileSnapshot.create(_tile("centre"), Vector2i(5, 5), 0))

	var result: PlacementResult = _validate(board, Vector2i(0, 0), 0, _tile("far"))

	check(not result.accepted, "a distant cell cannot join the board")
	check_eq(
		result.rejection,
		PlacementEnums.PlacementRejection.NOT_CONNECTED,
		"a distant cell must be refused with NOT_CONNECTED"
	)


func test_all_four_rotations_are_accepted() -> void:
	for rotation: int in range(TileEnums.ROTATION_COUNT):
		var board: BoardState = BoardState.create()
		var result: PlacementResult = _validate(board, Vector2i(5, 5), rotation, _tile("rotated"))
		check(
			result.accepted,
			"opening rotation %d must be legal, rejected as %s"
			% [rotation, result.get_rejection_name()]
		)
		check_eq(
			result.placed_tile.get_rotation(),
			rotation,
			"the accepted snapshot must keep rotation %d" % rotation
		)


func test_rotations_outside_zero_to_three_are_rejected() -> void:
	var board: BoardState = BoardState.create()
	for rotation: int in [4, 5, -1, 99]:
		var result: PlacementResult = _validate(board, Vector2i(5, 5), rotation, _tile("rotated"))
		check(not result.accepted, "rotation %d is not a quarter-turn index" % rotation)
		check_eq(
			result.rejection,
			PlacementEnums.PlacementRejection.INVALID_ROTATION,
			"rotation %d must be refused with INVALID_ROTATION" % rotation
		)


func test_rotation_is_checked_before_the_board() -> void:
	var board: BoardState = BoardState.create()

	var result: PlacementResult = _validate(board, Vector2i(99, 99), 7, _tile("bad"))

	check(not result.accepted, "an invalid rotation is refused even off the board")
	check_eq(
		result.rejection,
		PlacementEnums.PlacementRejection.INVALID_ROTATION,
		"the rotation check must run before the bounds check"
	)


func test_matching_and_mismatching_edges_are_both_legal() -> void:
	var matching: BoardState = BoardState.create()
	matching.commit_tile(TileSnapshot.create(_tile_with_edges("centre", BLUE, BLUE, BLUE, BLUE), Vector2i(5, 5), 0))
	var match_result: PlacementResult = _validate(
		matching, Vector2i(5, 6), 0, _tile_with_edges("match", BLUE, BLUE, BLUE, BLUE)
	)

	var mismatching: BoardState = BoardState.create()
	mismatching.commit_tile(TileSnapshot.create(_tile_with_edges("centre", BLUE, BLUE, BLUE, BLUE), Vector2i(5, 5), 0))
	var mismatch_result: PlacementResult = _validate(
		mismatching, Vector2i(5, 6), 0, _tile_with_edges("clash", RED, GREEN, YELLOW, RED)
	)

	check(match_result.accepted, "a matching edge must be legal")
	check(
		mismatch_result.accepted,
		"a mismatching edge must stay legal, edge colours are a bonus not a restriction"
	)


func test_unusable_tiles_are_refused_as_unavailable() -> void:
	var board: BoardState = BoardState.create()
	var tile: TileDefinition = _tile("opening")

	var null_tile: PlacementResult = PlacementValidator.validate(
		board, PlacementRequest.create(&"p1", &"opening", Vector2i(5, 5), 0), null
	)
	var unavailable: PlacementResult = PlacementValidator.validate(
		board, PlacementRequest.create(&"p1", &"opening", Vector2i(5, 5), 0), tile, false
	)
	var mismatched: PlacementResult = PlacementValidator.validate(
		board, PlacementRequest.create(&"p1", &"a-different-tile", Vector2i(5, 5), 0), tile
	)
	var invalid: PlacementResult = PlacementValidator.validate(
		board, PlacementRequest.create(&"p1", &"broken", Vector2i(5, 5), 0), _invalid_tile()
	)

	for result: PlacementResult in [null_tile, unavailable, mismatched, invalid]:
		check_not_null(result, "every tile problem must still return a result")
		check(not result.accepted, "an unusable tile cannot be placed")
		check_eq(
			result.rejection,
			PlacementEnums.PlacementRejection.TILE_NOT_AVAILABLE,
			"an unusable tile must be refused with TILE_NOT_AVAILABLE"
		)


func test_validation_never_mutates_the_board() -> void:
	var board: BoardState = BoardState.create()
	board.commit_tile(TileSnapshot.create(_tile("centre"), Vector2i(5, 5), 0))

	var revision_before: int = board.get_revision()
	var occupied_before: int = board.occupied_count()
	var frontier_before: Array[Vector2i] = board.get_frontier_cells()

	for x: int in range(-1, 13):
		for y: int in range(-1, 13):
			for rotation: int in range(TileEnums.ROTATION_COUNT):
				var result: PlacementResult = _validate(
					board, Vector2i(x, y), rotation, _tile("probe")
				)
				check_not_null(result, "every probe must return a result")

	check_eq(board.get_revision(), revision_before, "validation must not advance the revision")
	check_eq(board.occupied_count(), occupied_before, "validation must not occupy a cell")
	check_eq(board.get_frontier_cells(), frontier_before, "validation must not alter the frontier")
	check(board.is_empty_cell(Vector2i(6, 5)), "the probed cells must stay empty")


func test_changed_cells_list_the_placed_cell_then_its_neighbours() -> void:
	var board: BoardState = BoardState.create()
	board.commit_tile(TileSnapshot.create(_tile("centre"), Vector2i(5, 5), 0))
	board.commit_tile(TileSnapshot.create(_tile("above"), Vector2i(5, 4), 0))

	var result: PlacementResult = _validate(board, Vector2i(6, 5), 0, _tile("probe"))

	check(result.accepted, "the probe placement must be legal")
	check_eq(
		result.changed_cells,
		_cells([Vector2i(6, 5), Vector2i(5, 5)]),
		"changed cells must start with the placed cell then list occupied neighbours"
	)


func test_null_board_or_request_is_reported_as_a_programming_error() -> void:
	var board: BoardState = BoardState.create()
	var request: PlacementRequest = PlacementRequest.create(&"p1", &"opening", Vector2i(5, 5), 0)

	check(
		PlacementValidator.validate(null, request, _tile("opening")) == null,
		"a missing board must not produce a game outcome"
	)
	check(
		PlacementValidator.validate(board, null, _tile("opening")) == null,
		"a missing request must not produce a game outcome"
	)


func test_rejection_names_are_available_for_diagnostics() -> void:
	check_eq(
		PlacementEnums.rejection_name(PlacementEnums.PlacementRejection.NONE),
		"NONE",
		"NONE must be named"
	)
	check_eq(
		PlacementEnums.rejection_name(PlacementEnums.PlacementRejection.NOT_CONNECTED),
		"NOT_CONNECTED",
		"NOT_CONNECTED must be named"
	)
	check_eq(
		PlacementEnums.rejection_name(999),
		"UNKNOWN_REJECTION",
		"an unknown rejection code must not be named as a real reason"
	)


func _validate(
	board: BoardState, cell: Vector2i, rotation: int, tile: TileDefinition
) -> PlacementResult:
	return PlacementValidator.validate(
		board, PlacementRequest.create(&"p1", tile.tile_id, cell, rotation), tile
	)


func _tile(id: String) -> TileDefinition:
	return _tile_with_edges(id, BLUE, RED, GREEN, YELLOW)


func _tile_with_edges(id: String, top: int, right: int, bottom: int, left: int) -> TileDefinition:
	var edges: Array[TileEnums.EdgeColor] = []
	edges.append(top)
	edges.append(right)
	edges.append(bottom)
	edges.append(left)
	return TileDefinition.create(
		StringName(id), TileEnums.TileRank.ACE, TileEnums.FaceColor.RED, edges
	)


func _invalid_tile() -> TileDefinition:
	var edges: Array[TileEnums.EdgeColor] = []
	edges.append(BLUE)
	return TileDefinition.create(
		StringName("broken"), TileEnums.TileRank.ACE, TileEnums.FaceColor.RED, edges
	)


func _cells(values: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for value: Variant in values:
		cells.append(value)
	return cells
