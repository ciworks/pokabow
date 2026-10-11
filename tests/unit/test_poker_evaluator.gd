extends TestCase

## Poker-hand evaluator tests (ADR-012, superseding ADR-001 section 2).
##
## Domain-level tests: no scene tree, no rendering, no input. Every expectation
## is checked against the pure evaluator and a directly built `BoardState`.
##
## ADR-012 section 1 fixes a closed list of seven hands and section 2 adds the two
## sequence hands, so these tests assert both the accepted shapes and the refusal
## of the shapes that used to be legal and are not any more.

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
const STRAIGHT_3: int = ScoringEnums.PokerHandCategory.STRAIGHT_3
const THREE_OF_A_KIND: int = ScoringEnums.PokerHandCategory.THREE_OF_A_KIND
const STRAIGHT_4: int = ScoringEnums.PokerHandCategory.STRAIGHT_4
const FULL_HOUSE: int = ScoringEnums.PokerHandCategory.FULL_HOUSE
const FOUR_OF_A_KIND: int = ScoringEnums.PokerHandCategory.FOUR_OF_A_KIND
const NO_HAND: int = ScoringEnums.PokerHandCategory.NONE


func test_every_valid_rank_frequency_hand_classifies() -> void:
	var cases: Array = [
		[[ACE, ACE], PAIR],
		[[ACE, ACE, ACE], THREE_OF_A_KIND],
		[[ACE, ACE, KING, KING], TWO_PAIR],
		[[ACE, ACE, ACE, ACE], FOUR_OF_A_KIND],
		[[ACE, ACE, KING, KING, KING], FULL_HOUSE],
	]
	for entry: Array in cases:
		check_eq(
			PokerHandEvaluator.classify_ranks(entry[0]),
			entry[1],
			"ADR-012 section 1 hand: %s" % str(entry[0])
		)


func test_sequence_hands_require_sequence_order() -> void:
	var cases: Array = [
		[[JACK, QUEEN, KING], STRAIGHT_3],
		[[KING, QUEEN, JACK], STRAIGHT_3],
		[[QUEEN, KING, ACE], STRAIGHT_3],
		[[ACE, KING, QUEEN], STRAIGHT_3],
		[[JACK, QUEEN, KING, ACE], STRAIGHT_4],
		[[ACE, KING, QUEEN, JACK], STRAIGHT_4],
	]
	for entry: Array in cases:
		check_eq(
			PokerHandEvaluator.classify_ranks(entry[0]),
			entry[1],
			"a sequence hand reads in order either way: %s" % str(entry[0])
		)

	# The right faces in the wrong order are not a sequence hand (section 2).
	for ranks: Array in [
		[JACK, KING, QUEEN], [KING, JACK, QUEEN], [JACK, KING, ACE, QUEEN]
	]:
		check_eq(
			PokerHandEvaluator.classify_ranks(ranks),
			NO_HAND,
			"order matters, so %s is not a hand" % str(ranks)
		)

	check_eq(
		PokerHandEvaluator.classify_ranks([JACK, QUEEN]),
		NO_HAND,
		"a two-tile sequence is not a hand: the shortest hand is a Pair"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([JACK, QUEEN, KING], false),
		NO_HAND,
		"an unordered multiset must never classify as a sequence hand"
	)


func test_only_a_full_house_is_valid_at_five_tiles() -> void:
	check_eq(
		PokerHandEvaluator.classify_ranks([QUEEN, QUEEN, QUEEN, JACK, JACK]),
		FULL_HOUSE,
		"3 + 2 is the one valid five-tile shape"
	)
	for ranks: Array in [
		[ACE, ACE, ACE, ACE, KING],
		[ACE, ACE, ACE, ACE, ACE],
		[ACE, ACE, ACE, KING, QUEEN],
		[KING, KING, QUEEN, QUEEN, JACK],
		[ACE, ACE, KING, QUEEN, JACK],
	]:
		check_eq(
			PokerHandEvaluator.classify_ranks(ranks),
			NO_HAND,
			"a five-tile line must be a Full House, so %s is refused" % str(ranks)
		)


func test_shapes_outside_the_closed_list_are_refused() -> void:
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, ACE, ACE, ACE]),
		NO_HAND,
		"five identical ranks are no longer a hand (ADR-012 section 1)"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, KING]),
		NO_HAND,
		"two different ranks are not a hand"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, QUEEN, JACK]),
		NO_HAND,
		"three different non-sequence ranks are not a hand"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([JACK, KING, ACE, QUEEN]),
		NO_HAND,
		"four distinct ranks out of sequence are not a hand"
	)
	# ADR-012 section 1 as amended: the list is exact, so an unmatched tile is
	# refused even when the line contains a valid smaller hand.
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, KING]),
		NO_HAND,
		"a pair carrying an unmatched tile is not a hand"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, ACE, KING]),
		NO_HAND,
		"three of a kind carrying an unmatched tile is not a hand"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([KING, JACK, QUEEN, QUEEN]),
		NO_HAND,
		"a pair with two unmatched tiles is not a hand"
	)
	# ADR-012 section 1 as amended: equal ranks must sit together along the line,
	# so a hand whose ranks interleave is refused however many of each rank it
	# holds. Both of these carry the right histogram in the wrong order.
	check_eq(
		PokerHandEvaluator.classify_ranks([QUEEN, JACK, QUEEN, QUEEN, JACK]),
		NO_HAND,
		"Q J Q Q J is three Queens and two Jacks by count, but its ranks interleave"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([KING, QUEEN, KING, QUEEN]),
		NO_HAND,
		"K Q K Q is two pairs by count, but its ranks interleave"
	)


func test_grouped_ranks_are_kept_and_interleaved_ranks_are_split() -> void:
	# Either group order is legal: only the adjacency of each rank's tiles is
	# required, never a particular order of the groups (ADR-012 section 1 as
	# amended).
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, KING, KING]),
		TWO_PAIR,
		"A A K K stays the grouped Two Pair"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([KING, KING, ACE, ACE]),
		TWO_PAIR,
		"K K A A is the same Two Pair in the other group order"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, ACE, KING, KING]),
		FULL_HOUSE,
		"A A A K K stays the grouped Full House"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([KING, KING, ACE, ACE, ACE]),
		FULL_HOUSE,
		"K K A A A is the same Full House in the other group order"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([KING, JACK, KING, KING, JACK]),
		NO_HAND,
		"K J K K J interleaves its Kings, so it is not a Full House"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, KING, ACE, KING]),
		NO_HAND,
		"an interleaved four-tile hand is not a Two Pair"
	)
	check_eq(PokerHandEvaluator.is_grouped([ACE, ACE, KING, KING]), true, "A A K K is grouped")
	check_eq(PokerHandEvaluator.is_grouped([ACE, KING, ACE, KING]), false, "A K A K is not grouped")
	check_eq(
		PokerHandEvaluator.is_grouped([ACE, ACE, KING, KING, KING]),
		true,
		"A A K K K is grouped"
	)
	check_eq(
		PokerHandEvaluator.is_grouped([KING, ACE, ACE, KING, KING]),
		false,
		"K A A K K is not grouped"
	)
	check_eq(
		PokerHandEvaluator.is_grouped([QUEEN, JACK, QUEEN, QUEEN, JACK]),
		false,
		"Q J Q Q J is not grouped"
	)


func test_classification_returns_exactly_one_highest_category() -> void:
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, ACE, KING, KING]),
		FULL_HOUSE,
		"a Full House must not also report as a Pair or Three-of-a-Kind"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, ACE, KING, KING]),
		TWO_PAIR,
		"a hand holding two pairs reports Two Pair, not Pair"
	)


func test_classification_rejects_unusable_rank_input() -> void:
	check_eq(
		PokerHandEvaluator.classify_ranks([]),
		NO_HAND,
		"an empty list is not a hand"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE]),
		NO_HAND,
		"a single tile is not a hand"
	)
	check_eq(
		PokerHandEvaluator.classify_ranks([ACE, KING, QUEEN, JACK]),
		STRAIGHT_4,
		"the whole ladder in order is now a 4-straight"
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
	check_eq(rules.points_for(STRAIGHT_3), 5, "3-straight is worth 5")
	check_eq(rules.points_for(THREE_OF_A_KIND), 6, "Three-of-a-Kind is worth 6")
	check_eq(rules.points_for(STRAIGHT_4), 9, "4-straight is worth 9")
	check_eq(rules.points_for(FULL_HOUSE), 10, "Full House is worth 10")
	check_eq(rules.points_for(FOUR_OF_A_KIND), 12, "Four-of-a-Kind is worth 12")
	check_eq(
		rules.points_by_category.size(),
		ScoringEnums.PokerHandCategory.size(),
		"the point table must carry one value per category"
	)


func test_relabelled_rules_change_the_award_without_touching_the_evaluator() -> void:
	var board: BoardState = BoardState.create()
	var cells: Array[Vector2i] = _row(5, 5, 4)
	_fill_row(board, 5, 5, [KING, KING, KING, KING])

	var approved: PokerScoreRules = PokerScoreRules.create_default()
	var rebalanced: PokerScoreRules = PokerScoreRules.create_default()
	rebalanced.points_by_category[FOUR_OF_A_KIND] = 20

	check(
		rebalanced.is_valid(),
		"a rebalance that keeps precedence order must still validate"
	)

	var before: PokerHandResult = PokerHandEvaluator.evaluate_window(board, cells, approved)
	var after: PokerHandResult = PokerHandEvaluator.evaluate_window(board, cells, rebalanced)

	check_eq(before.points, 12, "the approved values award 12 for a Four-of-a-Kind")
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
		PokerHandEvaluator.cells_for_window_id(
			PokerHandEvaluator.window_id(_row(4, 9, 3))
		),
		_row(4, 9, 3),
		"a shorter hand's identifier must rebuild its own cells"
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


func test_a_five_tile_full_house_line_scores_once() -> void:
	var board: BoardState = BoardState.create()
	_fill_row(board, 5, 5, [QUEEN, QUEEN, QUEEN, JACK, JACK])

	var results: Array[PokerHandResult] = PokerHandEvaluator.evaluate_full_board(
		board, PokerScoreRules.create_default()
	)
	check_eq(results.size(), 1, "a five-tile line holds exactly one hand")
	check_eq(results[0].category, FULL_HOUSE, "three Queens and two Jacks is a Full House")
	check_eq(results[0].points, 10, "a Full House scores its approved value")
	check_eq(
		results[0].hand_id,
		PokerHandEvaluator.window_id(_row(5, 5, 5)),
		"the hand is identified by its five-cell window"
	)

	var refused: BoardState = BoardState.create()
	_fill_row(refused, 5, 5, [ACE, ACE, ACE, ACE, KING])
	check_eq(
		PokerHandEvaluator.evaluate_full_board(
			refused, PokerScoreRules.create_default()
		).size(),
		0,
		"a five-tile line that is not a Full House holds no hand"
	)


func test_one_placement_can_complete_two_windows() -> void:
	var board: BoardState = BoardState.create()
	_fill_row(board, 3, 5, [ACE, ACE])
	_fill_column(board, 5, 3, [ACE, ACE])

	var snapshot: TileSnapshot = _snapshot("cross", ACE, Vector2i(5, 5))
	var results: Array[PokerHandResult] = PokerHandEvaluator.evaluate_placement(
		board, snapshot, PokerScoreRules.create_default()
	)

	check_eq(results.size(), 2, "one tile can complete a horizontal and a vertical hand")
	check_eq(
		results[0].hand_id,
		PokerHandEvaluator.window_id(_row(3, 5, 3)),
		"the horizontal hand is reported first"
	)
	check_eq(
		results[1].hand_id,
		PokerHandEvaluator.window_id(_column(5, 3, 3)),
		"the vertical hand is reported second"
	)
	check_eq(results[0].points, 6, "three Aces in a row are a Three-of-a-Kind")
	check_eq(results[1].points, 6, "three Aces in a column are a Three-of-a-Kind")
	check_eq(results[0].category, THREE_OF_A_KIND, "the row hand is ranked")
	check_eq(results[1].category, THREE_OF_A_KIND, "the column hand is ranked")


func test_a_scored_window_never_scores_again() -> void:
	var board: BoardState = BoardState.create()
	_fill_row(board, 3, 5, [ACE, ACE])
	_fill_column(board, 5, 3, [ACE, ACE])
	var snapshot: TileSnapshot = _snapshot("cross", ACE, Vector2i(5, 5))
	var rules: PokerScoreRules = PokerScoreRules.create_default()

	var scored: ScoredHandSet = ScoredHandSet.create()
	scored.add(PokerHandEvaluator.window_id(_row(3, 5, 3)))

	var results: Array[PokerHandResult] = PokerHandEvaluator.evaluate_placement(
		board, snapshot, rules, scored
	)
	check_eq(results.size(), 1, "an already-scored hand must be skipped")
	check_eq(
		results[0].hand_id,
		PokerHandEvaluator.window_id(_column(5, 3, 3)),
		"only the unscored vertical hand may score"
	)


func test_incremental_windows_agree_with_a_full_board_scan() -> void:
	var board: BoardState = BoardState.create()
	var rules: PokerScoreRules = PokerScoreRules.create_default()
	var incremental: Dictionary = {}

	# K K, then Q Q, then a third Q. Every newly formed distinct hand scores once,
	# including the pair the first two tiles formed (ADR-011 section 10). The
	# three-tile K K Q line in between is refused by ADR-012 section 1 - it is a
	# pair carrying an unmatched tile, not one of the closed shapes - so it forms
	# no hand and scores nothing, and the pair it contains does not score again.
	for placed: Array in [
		[KING, Vector2i(5, 5)],
		[KING, Vector2i(6, 5)],
		[QUEEN, Vector2i(7, 5)],
		[QUEEN, Vector2i(8, 5)],
		[QUEEN, Vector2i(9, 5)],
	]:
		var rank: int = int(placed[0])
		var cell: Vector2i = placed[1]
		var snapshot: TileSnapshot = _snapshot("run_%d_%d" % [cell.x, cell.y], rank, cell)
		_record(PokerHandEvaluator.evaluate_placement(board, snapshot, rules), incremental)
		board.commit_tile(snapshot)

	var five: Array[Vector2i] = _row(5, 5, 5)
	check_eq(
		PokerHandEvaluator.classify_window(board, five),
		FULL_HOUSE,
		"K K Q Q Q is the Full House the line grew into"
	)
	check(
		incremental.has(PokerHandEvaluator.window_id(five)),
		"the final five-tile Full House must have scored incrementally"
	)
	check(
		incremental.has(PokerHandEvaluator.window_id(_row(5, 5, 2))),
		"the pair the first two tiles formed must have scored (ADR-011 section 10)"
	)
	check_eq(
		incremental.size(),
		3,
		"the pair at two tiles, the two pair at four, and the Full House at five each scored once"
	)

	var full: Dictionary = {}
	for hand_id: StringName in PokerHandEvaluator.full_board_hand_ids(board):
		full[hand_id] = true
	check_eq(full.size(), 1, "a full scan finds the one maximal hand on the board")
	for hand_id: Variant in full.keys():
		check(
			incremental.has(hand_id),
			"every hand a full scan finds must have scored incrementally: %s"
			% String(hand_id)
		)


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


## Returns `count` cells starting at (`x`, `y`) running left to right.
func _row(x: int, y: int, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for step: int in range(count):
		cells.append(Vector2i(x + step, y))
	return cells


## Returns `count` cells starting at (`x`, `y`) running top to bottom.
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
