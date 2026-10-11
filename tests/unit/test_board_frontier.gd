extends TestCase

## Milestone 2 legal-placement frontier tests (ADR-006 section 7).
##
## The frontier is a performance index, not a source of truth, so every test
## that walks the board also compares the incremental index with a full rebuild.

const BLUE: int = TileEnums.EdgeColor.BLUE
const RED: int = TileEnums.EdgeColor.RED
const GREEN: int = TileEnums.EdgeColor.GREEN
const YELLOW: int = TileEnums.EdgeColor.YELLOW

const MATCH_ID: StringName = &"frontier-match"
const MATCH_SEED: int = 20260922


func test_frontier_before_the_first_move_is_the_four_central_cells() -> void:
	var board: BoardState = BoardState.create()

	check_eq(
		board.get_frontier_cells(),
		_cells([Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6), Vector2i(6, 6)]),
		"an empty board must offer the four central opening cells"
	)
	check(board.is_frontier_cell(Vector2i(6, 6)), "(6,6) must be an opening cell")
	check(not board.is_frontier_cell(Vector2i(4, 5)), "(4,5) must not be playable yet")
	check(
		board.frontier_matches_rebuild(),
		"the opening frontier must equal a full rebuild"
	)


func test_first_commit_replaces_the_opening_set_with_its_ring() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 0, "opening")

	check_eq(
		board.get_frontier_cells(),
		_cells([Vector2i(5, 4), Vector2i(4, 5), Vector2i(6, 5), Vector2i(5, 6)]),
		"after the opening move the frontier is the ring around the committed tile"
	)
	check(
		not board.is_frontier_cell(Vector2i(6, 6)),
		"a diagonal-only cell must leave the frontier once the board is no longer empty"
	)
	check(
		not board.is_frontier_cell(Vector2i(5, 5)),
		"the committed cell must leave the frontier"
	)
	check(board.frontier_matches_rebuild(), "the frontier must still equal a full rebuild")


func test_frontier_grows_from_an_interior_placement() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 0, "opening")
	_place(board, Vector2i(6, 5), 0, "right")

	check(
		board.is_frontier_cell(Vector2i(7, 5)),
		"the cell beyond the newest tile must become playable"
	)
	check(
		board.is_frontier_cell(Vector2i(6, 4)),
		"a side neighbour of the newest tile must become playable"
	)
	check(
		not board.is_frontier_cell(Vector2i(6, 5)),
		"the committed cell must not be playable"
	)
	check(board.frontier_matches_rebuild(), "the frontier must still equal a full rebuild")


func test_frontier_updates_at_a_board_edge() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 0, "opening")
	for x: int in range(4, -1, -1):
		_place(board, Vector2i(x, 5), 0, "row-%d" % x)

	check(
		board.is_frontier_cell(Vector2i(0, 4)),
		"the cell above the left-edge tile must be playable"
	)
	check(
		board.is_frontier_cell(Vector2i(0, 6)),
		"the cell below the left-edge tile must be playable"
	)
	check(
		not board.is_frontier_cell(Vector2i(-1, 5)),
		"no out-of-bounds cell may enter the frontier"
	)
	for cell: Vector2i in board.get_frontier_cells():
		check(
			board.is_in_bounds(cell),
			"every frontier cell must be on the board, found %s" % BoardEnums.cell_name(cell)
		)


func test_frontier_updates_at_a_board_corner() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 0, "opening")
	for x: int in range(4, -1, -1):
		_place(board, Vector2i(x, 5), 0, "row-%d" % x)
	for y: int in range(4, -1, -1):
		_place(board, Vector2i(0, y), 0, "column-%d" % y)

	check(board.is_occupied(Vector2i(0, 0)), "the walk must reach the top-left corner")
	check(
		board.is_frontier_cell(Vector2i(1, 0)),
		"the corner's only empty neighbour must become playable"
	)
	check_eq(
		board.get_occupied_neighbors(Vector2i(0, 0)),
		_cells([Vector2i(0, 1)]),
		"the corner touches only the tile below it in this walk"
	)

	_place(board, Vector2i(1, 0), 0, "top-edge")
	check(
		not board.is_frontier_cell(Vector2i(1, 0)),
		"a committed cell must leave the frontier"
	)
	check_eq(
		board.get_occupied_neighbors(Vector2i(0, 0)),
		_cells([Vector2i(1, 0), Vector2i(0, 1)]),
		"a corner cell reports its two neighbours in up / right / down / left order"
	)
	check(
		not board.is_frontier_cell(Vector2i(-1, 0)),
		"no out-of-bounds cell may enter the frontier at a corner"
	)
	check(board.frontier_matches_rebuild(), "the frontier must still equal a full rebuild")


func test_frontier_never_contains_an_occupied_cell() -> void:
	var board: BoardState = BoardState.create()
	var source: TileSource = _seeded_source()

	var placed: int = 0
	while placed < 60 and not board.is_full():
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
			break
		placed += 1
		for cell: Vector2i in board.get_frontier_cells():
			check(
				not board.is_occupied(cell),
				"frontier cell %s must be empty" % BoardEnums.cell_name(cell)
			)
		if not board.frontier_matches_rebuild():
			check(false, "the frontier diverged from a full rebuild after %d placements" % placed)
			break
	check(placed > 0, "the walk must place at least one tile")
	check(
		board.frontier_matches_rebuild(),
		"the incremental frontier must match a full rebuild at every step"
	)


func test_incremental_frontier_matches_a_full_rebuild_at_every_step() -> void:
	var board: BoardState = BoardState.create()
	var source: TileSource = _seeded_source()
	var mismatches: int = 0

	for placed: int in range(20):
		var frontier: Array[Vector2i] = board.get_frontier_cells()
		check(not frontier.is_empty(), "the frontier must offer a move at step %d" % placed)
		if frontier.is_empty():
			break
		var tile: TileDefinition = source.draw()
		check_not_null(tile, "the seeded bag must supply a tile at step %d" % placed)
		if tile == null:
			break
		var request: PlacementRequest = PlacementRequest.create(
			&"p1", tile.tile_id, frontier[placed % frontier.size()], placed % 4
		)
		var result: PlacementResult = PlacementValidator.apply_if_legal(board, request, tile)
		check_not_null(result, "validation must return a result at step %d" % placed)
		if result == null or not result.accepted:
			check(false, "a frontier placement must be legal at step %d" % placed)
			break
		if not board.frontier_matches_rebuild():
			mismatches += 1

	check_eq(mismatches, 0, "no step may let the incremental frontier drift from a rebuild")


func test_rebuild_frontier_restores_a_consistent_index() -> void:
	var board: BoardState = BoardState.create()
	_place(board, Vector2i(5, 5), 0, "opening")
	_place(board, Vector2i(6, 5), 0, "right")

	var rebuilt: Array[Vector2i] = board.rebuild_frontier()

	check_eq(
		rebuilt,
		board.compute_frontier(),
		"rebuild must return exactly what the pure computation returns"
	)
	check_eq(
		board.get_frontier_cells(),
		rebuilt,
		"the stored index must equal the rebuilt frontier"
	)
	check(board.frontier_matches_rebuild(), "the rebuilt index must agree with a fresh rebuild")


func test_full_board_has_an_empty_frontier() -> void:
	var board: BoardState = BoardState.create()
	var source: TileSource = _seeded_source()
	var placed: int = _fill_board(board, source)

	check_eq(placed, 144, "a seeded bag must be able to fill every board cell")
	check(board.is_full(), "the board must report that it is full")
	check_eq(board.occupied_count(), 144, "all 144 cells must be occupied")
	check_eq(board.get_frontier_cells().size(), 0, "a full board has no playable cell")
	check(board.frontier_matches_rebuild(), "a full board must rebuild to an empty frontier")


## Builds a deterministic source holding exactly one tile per board cell.
##
## This fixture pins its own 144-tile bag on purpose, so a walk can fill the
## board. The live rules hold 52 tiles (ADR-004 section 1, amended 2026-09-23)
## and could never fill 144 cells. ADR-004 section 8 makes bag_size data, so a
## fixture may size its own bag without touching a rule.
func _seeded_source() -> TileSource:
	var source: TileSource = TileSource.new()
	var rules: TileGenerationRules = TileGenerationRules.create_default()
	rules.bag_size = BoardEnums.CELL_COUNT
	check(
		source.initialize(MATCH_ID, MATCH_SEED, rules),
		"the seeded tile source must initialize"
	)
	return source


## Places tiles greedily onto the first frontier cell in row-major order.
##
## Returns how many placements were accepted. Because edge colours never
## restrict placement, this walk always progresses until the board is full.
func _fill_board(board: BoardState, source: TileSource) -> int:
	var placed: int = 0
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
			break
		placed += 1
	return placed


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
