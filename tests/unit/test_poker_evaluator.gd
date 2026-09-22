extends TestCase

## Milestone 3 poker-window tests (ADR-001).
##
## Domain-level tests: no scene tree, no rendering, no input. Every expectation
## is checked against the pure evaluator and a directly built `BoardState`.

const ACE: int = TileEnums.TileRank.ACE
const KING: int = TileEnums.TileRank.KING
const QUEEN: int = TileEnums.TileRank.QUEEN
const JACK: int = TileEnums.TileRank.JACK
const BLUE: int = TileEnums.EdgeColor.BLUE
const RED: int = TileEnums.EdgeColor.RED
const GREEN: int = TileEnums.EdgeColor.GREEN
const YELLOW: int = TileEnums.EdgeColor.YELLOW

const PAIR: int = ScoringEnums.PokerHandCategory.PAIR
const TWO_PAIR: int = ScoringEnums.PokerHandCategory.TWO_PAIR
const THREE_OF_A_KIND: int = ScoringEnums.PokerHandCategory.THREE_OF_A_KIND
const FULL_HOUSE: int = ScoringEnums.PokerHandCategory.FULL_HOUSE
const FOUR_OF_A_KIND: int = ScoringEnums.PokerHandCategory.FOUR_OF_A_KIND
const FIVE_OF_A_KIND: int = ScoringEnums.PokerHandCategory.FIVE_OF_A_KIND
const NO_HAND: int = ScoringEnums.PokerHandCategory.NONE


func test_every_accepted_rank_frequency_pattern_classifies() -> void:
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, ACE, ACE, ACE]),
		FIVE_OF_A_KIND,
		"five identical ranks are a Five-of-a-Kind"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([KING, KING, KING, KING, ACE]),
		FOUR_OF_A_KIND,
		"4 + 1 is a Four-of-a-Kind"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([QUEEN, QUEEN, QUEEN, JACK, JACK]),
		FULL_HOUSE,
		"3 + 2 is a Full House"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, ACE, KING, QUEEN]),
		THREE_OF_A_KIND,
		"3 + 1 + 1 is a Three-of-a-Kind"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([KING, KING, QUEEN, QUEEN, JACK]),
		TWO_PAIR,
		"2 + 2 + 1 is Two Pair"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, KING, QUEEN, JACK]),
		PAIR,
		"2 + 1 + 1 + 1 is a Pair"
	)


func test_classification_returns_exactly_one_highest_category() -> void:
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, ACE, KING, KING]),
		FULL_HOUSE,
		"a Full House must not also report as a Pair or Three-of-a-Kind"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, KING, QUEEN, JACK]),
		PAIR,
		"a window with one pair reports Pair, not a stronger category"
	)


func test_classification_rejects_unusable_rank_input() -> void:
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, KING, QUEEN, JACK]),
		NO_HAND,
		"a four-rank list is not a five-cell window"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, KING, QUEEN, JACK, 99]),
		NO_HAND,
		"an undefined face rank cannot classify"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, KING, QUEEN, JACK, JACK]),
		NO_HAND,
		"a six-rank list is not a five-cell window"
	)


func test_point_values_come_from_the_rules_resource() -> void:
	var rules: PokerScoreRules = PokerScoreRules.create_default()

	check(rules.is_valid(), "the approved Phase 1 poker values must validate")
	check_eq(rules.points_for(NO_HAND), 0, "an unclassified window awards nothing")
	check_eq(rules.points_for(PAIR), 2, "Pair is worth 2 under the approved values")
	check_eq(rules.points_for(TWO_PAIR), 4, "Two Pair is worth 4")
	check_eq(rules.points_for(THREE_OF_A_KIND), 6, "Three-of-a-Kind is worth 6")
	check_eq(rules.points_for(FULL_HOUSE), 10, "Full House is worth 10")
	check_eq(rules.points_for(FOUR_OF_A_KIND), 12, "Four-of-a-Kind is worth 12")
	check_eq(rules.points_for(FIVE_OF_A_KIND), 16, "Five-of-a-Kind is worth 16")


func test_relabelled_rules_change_the_award_without_touching_the_evaluator() -> void:
	var board: BoardState = BoardState.create()
	var cells: Array[Vector2i] = _row(5, 5, 5)
	_fill_row(board, 5, 5, [ACE, ACE, ACE, ACE, ACE])

	var approved: PokerScoreRules = PokerScoreRules.create_default()
	var rebalanced: PokerScoreRules = PokerScoreRules.create_default()
	rebalanced.points_by_category[FIVE_OF_A_KIND] = 20

	check(
		rebalanced.is_valid(),
		"a rebalance that keeps precedence order must still validate"
	)

	var before: PokerHandResult = PokerHandEvaluator.evaluate_window(board, cells, approved)
	var after: PokerHandResult = PokerHandEvaluator.evaluate_window(board, cells, rebalanced)

	check_eq(before.points, 16, "the approved values award 16 for Five-of-a-Kind")
	check_eq(after.points, 20, "the award follows the rules resource, not a hard-coded table")
	check_eq(before.category, after.category, "a point rebalance must not change classification")
	check_eq(
		rebalanced.points_for(PAIR),
		2,
		"categories that were not rebalanced keep their approved values"
	)


func test_canonical_window_identity_is_orientation_and_direction_independent() -> void:
	var horizontal: Array[Vector2i] = _row(4, 5, 5)
	var reversed_horizontal: Array[Vector2i] = []
	for index: int in range(horizontal.size() - 1, -1, -1):
		reversed_horizontal.append(horizontal[index])

	check_eq(
		PokerHandEvaluator.window_id(horizontal),
		PokerHandEvaluator.window_id(reversed_horizontal),
		"a horizontal window's identity must not depend on walk direction"
	)
	check_eq(
		String(PokerHandEvaluator.window_id(horizontal)),
		"hand:H:5:4",
		"a horizontal window is identified by its row then its lowest column"
	)

	var vertical: Array[Vector2i] = _column(4, 5, 5)
	var reversed_vertical: Array[Vector2i] = []
	for index: int in range(vertical.size() - 1, -1, -1):
		reversed_vertical.append(vertical[index])

	check_eq(
		PokerHandEvaluator.window_id(vertical),
		PokerHandEvaluator.window_id(reversed_vertical),
		"a vertical window's identity must not depend on walk direction"
	)
	check_eq(
		String(PokerHandEvaluator.window_id(vertical)),
		"hand:V:4:5",
		"a vertical window is identified by its column then its lowest row"
	)

	var diagonal: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 3), Vector2i(4, 4)
	]
	check_eq(
		String(PokerHandEvaluator.window_id(diagonal)),
		"",
		"a diagonal line is not a poker window"
	)

	var gapped: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(5, 0)
	]
	check_eq(
		String(PokerHandEvaluator.window_id(gapped)),
		"",
		"a gapped line is not a contiguous window"
	)


func test_window_identifier_round_trips_through_its_cells() -> void:
	var horizontal: Array[Vector2i] = _row(4, 7, 5)
	var vertical: Array[Vector2i] = _column(9, 2, 5)

	check_eq(
		PokerHandEvaluator.cells_for_window_id(PokerHandEvaluator.window_id(horizontal)),
		horizontal,
		"a horizontal identifier must rebuild its own cells"
	)
	check_eq(
		PokerHandEvaluator.cells_for_window_id(PokerHandEvaluator.window_id(vertical)),
		vertical,
		"a vertical identifier must rebuild its own cells"
	)
	check_eq(
		PokerHandEvaluator.cells_for_window_id(&"hand:H:99:99").size(),
		0,
		"an out-of-bounds identifier must not resolve to cells"
	)
	check_eq(
		PokerHandEvaluator.cells_for_window_id(&"nonsense").size(),
		0,
		"a malformed identifier must not resolve to cells"
	)


func test_candidate_windows_contain_the_placed_cell_and_stay_in_bounds() -> void:
	var centre: Array = PokerHandEvaluator.candidate_windows(Vector2i(5, 5))
	check_eq(centre.size(), 10, "an interior cell sits in five horizontal and five vertical windows")
	for window: Variant in centre:
		var cells: Array[Vector2i] = window
		check(cells.has(Vector2i(5, 5)), "every candidate window must contain the placed cell")

	var corner: Array = PokerHandEvaluator.candidate_windows(Vector2i(0, 0))
	check_eq(corner.size(), 2, "the top-left corner starts exactly one window per orientation")

	var edge: Array = PokerHandEvaluator.candidate_windows(Vector2i(0, 5))
	check_eq(edge.size(), 6, "a left-edge cell has one horizontal and five vertical windows")

	check_eq(
		PokerHandEvaluator.candidate_windows(Vector2i(12, 0)).size(),
		0,
		"an out-of-bounds cell has no candidate windows"
	)


func test_gaps_and_diagonals_do_not_form_windows() -> void:
	var gapped: BoardState = BoardState.create()
	_place(gapped, Vector2i(4, 5), ACE, "g1")
	_place(gapped, Vector2i(5, 5), ACE, "g2")
	_place(gapped, Vector2i(6, 5), ACE, "g3")
	_place(gapped, Vector2i(8, 5), ACE, "g4")
	_place(gapped, Vector2i(9, 5), ACE, "g5")

	check_eq(
		PokerHandEvaluator.enumerate_windows(gapped).size(),
		0,
		"an empty cell in the middle must break the sequence"
	)

	var diagonal: BoardState = BoardState.create()
	for step: int in range(5):
		_place(diagonal, Vector2i(step, step), ACE, "d%d" % step)
	check_eq(
		PokerHandEvaluator.enumerate_windows(diagonal).size(),
		0,
		"diagonal sequences must never form a window"
	)


func test_a_long_line_scores_every_distinct_window() -> void:
	var board: BoardState = BoardState.create()
	_fill_row(board, 0, 5, [ACE, ACE, ACE, ACE, ACE])
	_fill_row(board, 5, 5, [KING, KING, KING])

	check_eq(
		PokerHandEvaluator.enumerate_windows(board).size(),
		4,
		"eight occupied cells in a row hold four distinct five-cell windows"
	)

	var results: Array[PokerHandResult] = PokerHandEvaluator.evaluate_full_board(
		board, PokerScoreRules.create_default()
	)
	check_eq(results.size(), 4, "every complete window must be classified")

	var ids: Array[StringName] = []
	for result: PokerHandResult in results:
		ids.append(result.hand_id)
	check_eq(
		ids,
		[
			StringName("hand:H:5:0"),
			StringName("hand:H:5:1"),
			StringName("hand:H:5:2"),
			StringName("hand:H:5:3"),
		],
		"windows must be reported in canonical identifier order"
	)
	check_eq(
		results[0].points,
		16,
		"five identical ranks in the first window are a Five-of-a-Kind"
	)
	check_eq(
		results[2].category,
		FULL_HOUSE,
		"the third window holds three Aces and two Kings"
	)


func test_one_placement_can_complete_two_windows() -> void:
	var board: BoardState = BoardState.create()
	_fill_row(board, 6, 5, [ACE, ACE, ACE, ACE])
	_fill_column(board, 5, 6, [ACE, ACE, ACE, ACE])

	var snapshot: TileSnapshot = _snapshot("cross", ACE, Vector2i(5, 5))
	var results: Array[PokerHandResult] = PokerHandEvaluator.evaluate_placement(
		board, snapshot, PokerScoreRules.create_default()
	)

	check_eq(results.size(), 2, "one tile can complete a horizontal and a vertical window")
	check_eq(
		results[0].hand_id,
		StringName("hand:H:5:5"),
		"the horizontal window is reported first"
	)
	check_eq(
		results[1].hand_id,
		StringName("hand:V:5:5"),
		"the vertical window is reported second"
	)
	check_eq(results[0].points, 16, "the horizontal window is a Five-of-a-Kind")
	check_eq(results[1].points, 16, "the vertical window is a Five-of-a-Kind")


func test_a_scored_window_never_scores_again() -> void:
	var board: BoardState = BoardState.create()
	_fill_row(board, 6, 5, [ACE, ACE, ACE, ACE])
	_fill_column(board, 5, 6, [ACE, ACE, ACE, ACE])
	var snapshot: TileSnapshot = _snapshot("cross", ACE, Vector2i(5, 5))
	var rules: PokerScoreRules = PokerScoreRules.create_default()

	var scored: ScoredHandSet = ScoredHandSet.create()
	scored.add(StringName("hand:H:5:5"))

	var results: Array[PokerHandResult] = PokerHandEvaluator.evaluate_placement(
		board, snapshot, rules, scored
	)
	check_eq(results.size(), 1, "an already-scored window must be skipped")
	check_eq(
		results[0].hand_id,
		StringName("hand:V:5:5"),
		"only the unscored vertical window may score"
	)


func test_incremental_windows_agree_with_a_full_board_scan() -> void:
	var board: BoardState = BoardState.create()
	var incremental: Dictionary = {}

	for cell: Vector2i in _column(5, 6, 4):
		var snapshot: TileSnapshot = _snapshot("v%d" % cell.y, ACE, cell)
		_record(PokerHandEvaluator.evaluate_placement(board, snapshot, PokerScoreRules.create_default()), incremental)
		board.commit_tile(snapshot)
	for cell: Vector2i in _row(6, 5, 4):
		var snapshot: TileSnapshot = _snapshot("h%d" % cell.x, ACE, cell)
		_record(PokerHandEvaluator.evaluate_placement(board, snapshot, PokerScoreRules.create_default()), incremental)
		board.commit_tile(snapshot)

	var cross: TileSnapshot = _snapshot("cross", ACE, Vector2i(5, 5))
	_record(PokerHandEvaluator.evaluate_placement(board, cross, PokerScoreRules.create_default()), incremental)
	board.commit_tile(cross)

	check_eq(incremental.size(), 2, "the crossing move must create two windows in total")

	var full: Dictionary = {}
	for hand_id: StringName in PokerHandEvaluator.full_board_hand_ids(board):
		full[hand_id] = true
	check_eq(full.size(), 2, "a full scan must find the same two windows")
	check_eq(full.keys().size(), incremental.keys().size(), "the two paths must agree on the count")
	for hand_id: Variant in incremental.keys():
		check(full.has(hand_id), "the full scan must find the window %s" % String(hand_id))


func test_empty_and_partial_windows_are_never_classified() -> void:
	var board: BoardState = BoardState.create()
	_fill_row(board, 4, 5, [ACE, ACE, ACE, ACE])

	check_eq(
		PokerHandEvaluator.classify_window(board, _row(4, 5, 5)),
		NO_HAND,
		"a window containing an empty cell cannot classify"
	)
	check_eq(
		PokerHandEvaluator.evaluate_window(
			board, _row(4, 5, 5), PokerScoreRules.create_default()
		),
		null,
		"an incomplete window produces no result"
	)
	check_eq(
		PokerHandEvaluator.evaluate_placement(
			board, _snapshot("oob", ACE, Vector2i(0, 0)), PokerScoreRules.create_default()
		).size(),
		0,
		"a placement that completes no window produces no result"
	)


## Returns five cells starting at (`x`, `y`) running left to right.
func _row(x: int, y: int, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for step: int in range(count):
		cells.append(Vector2i(x + step, y))
	return cells


## Returns five cells starting at (`x`, `y`) running top to bottom.
func _column(x: int, y: int, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for step: int in range(count):
		cells.append(Vector2i(x, y + step))
	return cells


## Places a run of ranked tiles left to right.
func _fill_row(board: BoardState, x: int, y: int, ranks: Array) -> void:
	for step: int in range(ranks.size()):
		_place(board, Vector2i(x + step, y), int(ranks[step]), "r%d_%d" % [x + step, y])


## Places a run of ranked tiles top to bottom.
func _fill_column(board: BoardState, x: int, y: int, ranks: Array) -> void:
	for step: int in range(ranks.size()):
		_place(board, Vector2i(x, y + step), int(ranks[step]), "c%d_%d" % [x, y + step])


## Commits a tile of one rank directly, as the authoritative writer would.
func _place(board: BoardState, cell: Vector2i, rank: int, id: String) -> TileSnapshot:
	var snapshot: TileSnapshot = _snapshot(id, rank, cell)
	board.commit_tile(snapshot)
	return snapshot


## Builds a valid tile of one rank with four distinct edge colours.
func _snapshot(id: String, rank: int, cell: Vector2i, rotation: int = 0) -> TileSnapshot:
	var edges: Array[TileEnums.EdgeColor] = [BLUE, RED, GREEN, YELLOW]
	var tile: TileDefinition = TileDefinition.create(
		StringName(id), rank, TileEnums.FaceColor.RED, edges
	)
	return TileSnapshot.create(tile, cell, rotation)


## Records the identifiers of a result list into a set.
func _record(results: Array[PokerHandResult], into: Dictionary) -> void:
	for result: PokerHandResult in results:
		into[result.hand_id] = true
