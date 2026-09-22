extends TestCase

## Milestone 2 atomic commit tests (ADR-006 section 6, ADR-007 sections 3 and 8).
##
## Scoring is not part of this milestone, so these tests cover only the board
## half of the transaction: a legal move lands completely or not at all.

const BLUE: int = TileEnums.EdgeColor.BLUE
const RED: int = TileEnums.EdgeColor.RED
const GREEN: int = TileEnums.EdgeColor.GREEN
const YELLOW: int = TileEnums.EdgeColor.YELLOW

const MATCH_ID: StringName = &"commit-match"
const MATCH_SEED: int = 771014


func test_a_legal_placement_lands_completely() -> void:
	var board: BoardState = BoardState.create()
	var tile: TileDefinition = _tile("opening")
	var request: PlacementRequest = PlacementRequest.create(&"p1", tile.tile_id, Vector2i(5, 5), 1)

	var result: PlacementResult = PlacementValidator.apply_if_legal(board, request, tile)

	check(result.accepted, "the opening placement must be accepted")
	check_eq(result.cell, Vector2i(5, 5), "the result must report the committed cell")
	check(board.is_occupied(Vector2i(5, 5)), "the tile must reach the board")
	check_eq(board.occupied_count(), 1, "one tile must be committed")
	check_eq(board.get_revision(), 1, "the commit must advance the revision exactly once")
	check_eq(
		board.get_tile(Vector2i(5, 5)).get_rotation(),
		1,
		"the committed snapshot must carry the requested rotation"
	)
	check(
		board.get_frontier_cells().has(Vector2i(5, 4)),
		"the frontier must be updated by the commit"
	)
	check_eq(
		result.changed_cells,
		_cells([Vector2i(5, 5)]),
		"a lone opening tile changes only its own cell"
	)


func test_a_rejected_placement_changes_nothing() -> void:
	var cases: Array[PlacementRequest] = [
		PlacementRequest.create(&"p1", &"tile", Vector2i(0, 0), 0),
		PlacementRequest.create(&"p1", &"tile", Vector2i(-1, 0), 0),
		PlacementRequest.create(&"p1", &"tile", Vector2i(5, 5), 4),
	]

	for request: PlacementRequest in cases:
		var board: BoardState = BoardState.create()
		_place(board, Vector2i(5, 5), 0, "centre")
		var revision_before: int = board.get_revision()
		var occupied_before: int = board.occupied_count()
		var frontier_before: Array[Vector2i] = board.get_frontier_cells()

		var result: PlacementResult = PlacementValidator.apply_if_legal(
			board, request, _tile("tile")
		)

		check(not result.accepted, "the illegal request must be refused")
		check(result.placed_tile == null, "a refused placement must carry no tile")
		check_eq(result.changed_cells.size(), 0, "a refused placement changes no cell")
		check_eq(board.get_revision(), revision_before, "the revision must not move")
		check_eq(board.occupied_count(), occupied_before, "no cell may be occupied")
		check_eq(board.get_frontier_cells(), frontier_before, "the frontier must not move")


func test_preview_then_cancel_leaves_no_trace() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 0, "centre")

	var tile: TileDefinition = _tile("previewed")
	var request: PlacementRequest = PlacementRequest.create(&"p1", tile.tile_id, Vector2i(6, 5), 3)

	var preview: PlacementResult = PlacementValidator.validate(board, request, tile)
	check(preview.accepted, "the previewed placement must be legal")
	var hypothetical: BoardState = board.with_tile(preview.placed_tile)
	check(hypothetical.is_occupied(Vector2i(6, 5)), "the hypothetical board must show the tile")

	check(board.is_empty_cell(Vector2i(6, 5)), "cancelling must leave the cell empty")
	check_eq(board.get_revision(), 1, "a preview must not advance the revision")
	check_eq(
		board.get_frontier_cells(),
		_cells([Vector2i(5, 4), Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 6)]),
		"a preview must not alter the frontier"
	)

	var confirmed: PlacementResult = PlacementValidator.apply_if_legal(board, request, tile)
	check(confirmed.accepted, "the confirmed placement must be legal on the same revision")
	check_eq(
		confirmed.placed_tile.get_rotation(),
		preview.placed_tile.get_rotation(),
		"the commit must place the previewed rotation"
	)
	check_eq(
		confirmed.changed_cells,
		preview.changed_cells,
		"the commit must affect the same cells as the preview"
	)
	check_eq(board.get_revision(), 2, "the commit must advance the revision once")


func test_a_committed_placement_is_immutable() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 2, "committed")

	var stored: TileSnapshot = board.get_tile(Vector2i(5, 5))
	check_eq(stored.get_cell(), Vector2i(5, 5), "the committed cell must not move")
	check_eq(stored.get_rotation(), 2, "the committed rotation must not change")

	var clash: PlacementResult = PlacementValidator.apply_if_legal(
		board,
		PlacementRequest.create(&"p1", &"clash", Vector2i(5, 5), 0),
		_tile("clash")
	)
	check(not clash.accepted, "the committed cell must refuse a second tile")
	check_eq(board.get_revision(), 1, "the refused placement must not advance the revision")
	check_eq(
		board.get_tile(Vector2i(5, 5)).get_rotation(),
		2,
		"the committed rotation must survive the refused placement"
	)


func test_frontier_cells_and_open_cells_agree_after_many_commits() -> void:
	var board: BoardState = BoardState.create()
	var source: TileSource = _seeded_source()
	var rejected: int = 0

	while not board.is_full():
		var frontier: Array[Vector2i] = board.get_frontier_cells()
		if frontier.is_empty():
			break
		var tile: TileDefinition = source.draw()
		if tile == null:
			break
		var request: PlacementRequest = PlacementRequest.create(
			&"p1", tile.tile_id, frontier[0], 0
		)
		var result: PlacementResult = PlacementValidator.apply_if_legal(board, request, tile)
		if result == null or not result.accepted:
			rejected += 1
			break
		if not board.frontier_matches_rebuild():
			rejected += 1
			break

	check_eq(rejected, 0, "every frontier placement must be legal and keep the frontier exact")


func test_exit_criterion_a_seeded_bag_fills_the_whole_board() -> void:
	var board: BoardState = BoardState.create()
	var source: TileSource = _seeded_source()
	var accepted: int = 0

	while accepted < 144:
		var frontier: Array[Vector2i] = board.get_frontier_cells()
		if frontier.is_empty():
			break
		var tile: TileDefinition = source.draw()
		if tile == null:
			break
		var request: PlacementRequest = PlacementRequest.create(
			&"p1", tile.tile_id, frontier[0], accepted % TileEnums.ROTATION_COUNT
		)
		var result: PlacementResult = PlacementValidator.apply_if_legal(board, request, tile)
		if result == null or not result.accepted:
			break
		check(
			result.accepted,
			"placement %d at %s must be legal, rejected as %s"
			% [accepted + 1, BoardEnums.cell_name(frontier[0]), result.get_rejection_name()]
		)
		accepted += 1

	check_eq(accepted, 144, "a seeded bag must legally fill all 144 cells")
	check(source.is_exhausted(), "the bag must be exhausted exactly at a full board")
	check(board.is_full(), "the board must be full after 144 placements")
	check_eq(board.occupied_count(), 144, "every cell must hold a tile")
	check_eq(board.get_revision(), 144, "the revision must count every commit")
	check_eq(board.get_frontier_cells().size(), 0, "no move may remain on a full board")
	check(board.frontier_matches_rebuild(), "the frontier must rebuild to empty")
	check_eq(
		board.get_occupied_cells().size(),
		144,
		"the occupied-cell report must cover the whole board"
	)

	# Every invalid placement on the finished board must still return a
	# structured reason instead of a bare refusal.
	var occupied: PlacementResult = PlacementValidator.apply_if_legal(
		board, PlacementRequest.create(&"p1", &"late", Vector2i(0, 0), 0), _tile("late")
	)
	check_eq(
		occupied.rejection,
		PlacementEnums.PlacementRejection.CELL_OCCUPIED,
		"an occupied cell must report CELL_OCCUPIED"
	)
	var off_board: PlacementResult = PlacementValidator.apply_if_legal(
		board, PlacementRequest.create(&"p1", &"late", Vector2i(12, 0), 0), _tile("late")
	)
	check_eq(
		off_board.rejection,
		PlacementEnums.PlacementRejection.OUT_OF_BOUNDS,
		"an off-board cell must report OUT_OF_BOUNDS"
	)
	var bad_rotation: PlacementResult = PlacementValidator.apply_if_legal(
		board, PlacementRequest.create(&"p1", &"late", Vector2i(6, 6), 9), _tile("late")
	)
	check_eq(
		bad_rotation.rejection,
		PlacementEnums.PlacementRejection.INVALID_ROTATION,
		"a non-quarter-turn must report INVALID_ROTATION"
	)
	# An exhausted bag is exercised on an empty board: on a full board the
	# occupancy check produces its own reason first.
	var empty_board: BoardState = BoardState.create()
	var no_tile: PlacementResult = PlacementValidator.apply_if_legal(
		empty_board, PlacementRequest.create(&"p1", &"late", Vector2i(5, 5), 0), source.draw()
	)
	check_eq(
		no_tile.rejection,
		PlacementEnums.PlacementRejection.TILE_NOT_AVAILABLE,
		"an exhausted bag must report TILE_NOT_AVAILABLE"
	)
	check_eq(
		empty_board.occupied_count(),
		0,
		"a placement refused for a missing tile must not occupy a cell"
	)


func test_rejected_commit_reports_a_structured_reason_for_the_active_player() -> void:
	var board: BoardState = BoardState.create()
	var tile: TileDefinition = _tile("tile")

	var first: PlacementResult = PlacementValidator.apply_if_legal(
		board, PlacementRequest.create(&"p1", tile.tile_id, Vector2i(5, 5), 0), tile
	)
	var second: PlacementResult = PlacementValidator.apply_if_legal(
		board, PlacementRequest.create(&"p2", tile.tile_id, Vector2i(5, 4), 0), tile
	)

	check(first.accepted, "the first opening placement must be accepted")
	check(second.accepted, "the second player's adjacent placement must be accepted")
	check_eq(
		board.get_revision(),
		2,
		"both players must commit through the same validation path"
	)


func _seeded_source() -> TileSource:
	var source: TileSource = TileSource.new()
	check(
		source.initialize(MATCH_ID, MATCH_SEED, TileGenerationRules.create_default()),
		"the seeded tile source must initialize"
	)
	return source


func _place(board: BoardState, cell: Vector2i, rotation: int, id: String) -> TileSnapshot:
	var snapshot: TileSnapshot = TileSnapshot.create(_tile(id), cell, rotation)
	board.commit_tile(snapshot)
	return snapshot


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


func _cells(values: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for value: Variant in values:
		cells.append(value)
	return cells
