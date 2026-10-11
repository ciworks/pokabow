extends TestCase

const ACE: int = TileEnums.TileRank.ACE
const KING: int = TileEnums.TileRank.KING
const QUEEN: int = TileEnums.TileRank.QUEEN
const JACK: int = TileEnums.TileRank.JACK


func test_ranked_hands_of_two_through_five_classify() -> void:
	var cases: Array = [
		[[ACE, ACE], ScoringEnums.PokerHandCategory.PAIR],
		[[ACE, ACE, ACE], ScoringEnums.PokerHandCategory.THREE_OF_A_KIND],
		[[ACE, ACE, KING, KING], ScoringEnums.PokerHandCategory.TWO_PAIR],
		[[ACE, ACE, ACE, ACE], ScoringEnums.PokerHandCategory.FOUR_OF_A_KIND],
		[[ACE, ACE, ACE, KING, KING], ScoringEnums.PokerHandCategory.FULL_HOUSE],
		[[JACK, QUEEN, KING], ScoringEnums.PokerHandCategory.STRAIGHT_3],
		[[ACE, KING, QUEEN], ScoringEnums.PokerHandCategory.STRAIGHT_3],
		[[JACK, QUEEN, KING, ACE], ScoringEnums.PokerHandCategory.STRAIGHT_4],
	]
	for entry: Array in cases:
		check_eq(PokerHandEvaluator.classify_ranks(entry[0]), entry[1], str(entry[0]))
	# ADR-012 section 1: every shape outside the closed list is refused. The
	# all-distinct lines here are deliberately NOT in sequence order, and the
	# five-tile lines are the shapes the old catalogue used to accept.
	var refused: Array = [
		[ACE, KING],
		[ACE, KING, ACE],
		[JACK, KING, QUEEN],
		[JACK, KING, QUEEN, ACE],
		[ACE, ACE, ACE, ACE, KING],
		[ACE, ACE, ACE, ACE, ACE],
		[ACE, ACE, KING],
		[ACE, ACE, ACE, KING],
		[KING, JACK, QUEEN, QUEEN],
	]
	for ranks: Array in refused:
		check_eq(
			PokerHandEvaluator.classify_ranks(ranks),
			ScoringEnums.PokerHandCategory.NONE,
			"not a valid hand: %s" % str(ranks)
		)


func test_short_hand_ids_include_length_and_preserve_five_card_ids() -> void:
	var pair_cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]
	var pair_id: StringName = PokerHandEvaluator.window_id(pair_cells)
	check_eq(String(pair_id), "hand:H:5:5:2", "short hand IDs must include length")
	check_eq(PokerHandEvaluator.cells_for_window_id(pair_id), pair_cells, "short IDs round trip")
	var five: Array[Vector2i] = []
	for x: int in range(5, 10):
		five.append(Vector2i(x, 5))
	check_eq(String(PokerHandEvaluator.window_id(five)), "hand:H:5:5", "five-card IDs stay save-compatible")


func test_two_tiles_cannot_extend_a_scored_five_tile_hand_to_seven() -> void:
	var board: BoardState = BoardState.create()
	var committed: Array[TileSnapshot] = []
	for x: int in range(3, 8):
		committed.append(_snapshot(x, ACE, Vector2i(x, 5)))
	check(board.commit_tiles(committed), "fixture must hold a scored five-tile hand")
	var extension: Array[TileSnapshot] = [
		_snapshot(8, ACE, Vector2i(8, 5)),
		_snapshot(9, ACE, Vector2i(9, 5)),
	]
	var result: LineResult = LineValidator.validate(board, extension)
	check_eq(result.rejection, PlacementEnums.PlacementRejection.HAND_TOO_LONG, "a seven-tile hand is refused")
	check_eq(board.occupied_count(), 5, "validation must not change the board")


func test_perpendicular_extension_cannot_create_a_six_tile_run() -> void:
	var board: BoardState = BoardState.create()
	var committed: Array[TileSnapshot] = []
	for y: int in range(3, 8):
		committed.append(_snapshot(y, ACE, Vector2i(5, y)))
	check(board.commit_tiles(committed), "fixture must hold a vertical five-tile hand")
	var extension: Array[TileSnapshot] = [
		_snapshot(8, ACE, Vector2i(5, 8)),
		_snapshot(9, ACE, Vector2i(6, 8)),
	]
	var result: LineResult = LineValidator.validate(board, extension)
	check_eq(result.rejection, PlacementEnums.PlacementRejection.HAND_TOO_LONG, "a perpendicular six-tile run is refused")
	check_eq(board.occupied_count(), 5, "rejection keeps the board unchanged")


func test_one_new_king_can_form_a_vertical_pair_with_a_board_king() -> void:
	var board: BoardState = BoardState.create()
	check(board.commit_tiles([
		_snapshot(1, ACE, Vector2i(5, 5)),
		_snapshot(2, ACE, Vector2i(6, 5)),
		_snapshot(3, KING, Vector2i(7, 5)),
		_snapshot(4, KING, Vector2i(8, 5)),
	]), "fixture must hold the horizontal two pair")
	var single: Array[TileSnapshot] = [_snapshot(5, KING, Vector2i(7, 6))]
	var result: LineResult = LineValidator.validate(board, single)
	check(result.accepted, "a single tile may complete a pair with a board tile")
	check_eq(result.orientation, ScoringEnums.HandOrientation.VERTICAL, "the new pair is vertical")
	check_eq(result.hand_category, ScoringEnums.PokerHandCategory.PAIR, "the pair is ranked")


func test_one_new_king_completes_the_two_pair_at_the_grouped_end() -> void:
	var board: BoardState = BoardState.create()
	check(board.commit_tiles([
		_snapshot(1, ACE, Vector2i(5, 5)),
		_snapshot(2, ACE, Vector2i(6, 5)),
		_snapshot(3, KING, Vector2i(7, 5)),
		_snapshot(4, KING, Vector2i(8, 5)),
	]), "fixture must hold the horizontal two pair")
	# ADR-012 section 1 as amended: equal ranks must sit together along the line,
	# so only the end that keeps both Kings adjacent completes the hand. The right
	# end reads A A K K K, which is a full house.
	var completing: Array[TileSnapshot] = [_snapshot(5, KING, Vector2i(9, 5))]
	var result: LineResult = LineValidator.validate(board, completing)
	check(result.accepted, "a K at the right end reads A A K K K and forms a full house")
	check_eq(result.hand_category, ScoringEnums.PokerHandCategory.FULL_HOUSE, "the grouped completion is a full house")
	var events: Array[ScoreEvent] = ScoringCoordinator.build_events_for_line(
		board, completing, &"human", &"move:test:full-house:1", 1,
		ScoringRules.create_default(), ScoredHandSet.create()
	)
	check_eq(_poker_points(events), 162, "a full house includes card and edge multipliers")


func test_one_new_king_at_the_ungrouped_end_is_refused() -> void:
	var board: BoardState = BoardState.create()
	check(board.commit_tiles([
		_snapshot(1, ACE, Vector2i(5, 5)),
		_snapshot(2, ACE, Vector2i(6, 5)),
		_snapshot(3, KING, Vector2i(7, 5)),
		_snapshot(4, KING, Vector2i(8, 5)),
	]), "fixture must hold the horizontal two pair")
	# A King at the left end reads K A A K K: three Kings and two Aces by count,
	# but the King group is split, so it is not a full house (ADR-012 section 1 as
	# amended) and the move is refused rather than scored.
	var splitting: Array[TileSnapshot] = [_snapshot(5, KING, Vector2i(4, 5))]
	var result: LineResult = LineValidator.validate(board, splitting)
	check(not result.accepted, "a K at the left end reads K A A K K and is refused")
	check_eq(result.rejection, PlacementEnums.PlacementRejection.NO_REPEATED_RANK, "the split King group is not a legal hand")
	check_eq(board.occupied_count(), 4, "rejection leaves the board unchanged")


func test_a_move_cannot_leave_a_touched_perpendicular_hand_unranked() -> void:
	var board: BoardState = BoardState.create()
	check(board.commit_tiles([
		_snapshot(1, KING, Vector2i(5, 3)),
		_snapshot(2, QUEEN, Vector2i(5, 4)),
	]), "fixture must hold the committed crossing tiles")
	var staged: Array[TileSnapshot] = [
		_snapshot(3, ACE, Vector2i(5, 5)),
		_snapshot(4, ACE, Vector2i(6, 5)),
	]
	var result: LineResult = LineValidator.validate(board, staged)
	check_eq(result.rejection, PlacementEnums.PlacementRejection.NO_REPEATED_RANK, "the perpendicular K-Q-A line is invalid")
	check_eq(board.occupied_count(), 2, "rejection leaves the board unchanged")


func test_a_larger_hand_scores_once_after_a_pair() -> void:
	var board: BoardState = BoardState.create()
	var rules: ScoringRules = ScoringRules.create_default()
	var scored: ScoredHandSet = ScoredHandSet.create()
	var pair: Array[TileSnapshot] = [
		_snapshot(1, ACE, Vector2i(5, 5)),
		_snapshot(2, ACE, Vector2i(6, 5)),
	]
	var first: Array[ScoreEvent] = ScoringCoordinator.build_events_for_line(
		board, pair, &"human", &"move:test:1:1", 1, rules, scored
	)
	check_eq(_poker_points(first), 80, "the two-card pair uses the new formula")
	for event: ScoreEvent in first:
		if event.category == ScoringEnums.ScoreCategory.POKER_HAND:
			scored.add(StringName(String(event.evidence["hand_id"])))
	check(board.commit_tiles(pair), "the first pair commits")
	var extension: Array[TileSnapshot] = [
		_snapshot(3, ACE, Vector2i(7, 5)),
		_snapshot(4, ACE, Vector2i(8, 5)),
	]
	var second: Array[ScoreEvent] = ScoringCoordinator.build_events_for_line(
		board, extension, &"human", &"move:test:2:1", 2, rules, scored
	)
	check_eq(_poker_points(second), 336, "the new four-card hand scores once without subtracting the pair")
	check_eq(_poker_event_count(second), 1, "subsets of the four-card hand do not also score")


func test_distinct_perpendicular_hands_both_score() -> void:
	var board: BoardState = BoardState.create()
	check(board.commit_tiles([
		_snapshot(1, ACE, Vector2i(5, 4)),
		_snapshot(2, ACE, Vector2i(5, 5)),
	]), "the vertical fixture commits")
	var placed: Array[TileSnapshot] = [
		_snapshot(3, ACE, Vector2i(5, 6)),
		_snapshot(4, ACE, Vector2i(6, 6)),
	]
	var events: Array[ScoreEvent] = ScoringCoordinator.build_events_for_line(
		board, placed, &"human", &"move:test:3:1", 3,
		ScoringRules.create_default(), ScoredHandSet.create()
	)
	check_eq(_poker_event_count(events), 2, "the new horizontal pair and vertical triple both score")
	check_eq(_poker_points(events), 224, "both perpendicular hands use the new formula")


func _snapshot(index: int, rank: int, cell: Vector2i) -> TileSnapshot:
	var blue: TileEnums.EdgeColor = TileEnums.EdgeColor.BLUE
	var tile: TileDefinition = TileDefinition.create(
		StringName("variable-hand:tile:%d" % index), rank,
		TileEnums.FaceColor.RED, [blue, blue, blue, blue]
	)
	return TileSnapshot.create(tile, cell, 0)


func _poker_points(events: Array[ScoreEvent]) -> int:
	var total: int = 0
	for event: ScoreEvent in events:
		if event.category == ScoringEnums.ScoreCategory.POKER_HAND:
			total += event.points
	return total


func _poker_event_count(events: Array[ScoreEvent]) -> int:
	var count: int = 0
	for event: ScoreEvent in events:
		if event.category == ScoringEnums.ScoreCategory.POKER_HAND:
			count += 1
	return count
