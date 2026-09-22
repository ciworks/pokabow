extends TestCase

## Milestone 3 preview and commit tests (ADR-007 sections 3, 4, 7, and 8).
##
## Domain-level: no scene tree, no rendering. The fixture is a single placement
## that scores in all three categories at once, which is the case ADR-007
## section 6 and section 7 care about most.

const BLUE: int = TileEnums.EdgeColor.BLUE
const RED: int = TileEnums.EdgeColor.RED
const GREEN: int = TileEnums.EdgeColor.GREEN
const YELLOW: int = TileEnums.EdgeColor.YELLOW


func test_preview_reports_every_category_without_mutating_anything() -> void:
	var board: BoardState = BoardState.create()
	var ledger: ScoreLedger = ScoreLedger.create()
	var scored: ScoredHandSet = ScoredHandSet.create()
	var rules: ScoringRules = ScoringRules.create_default()
	_build_line(board)

	var preview: ScoreTransaction = ScoringCoordinator.preview(
		board, _placed_tile(), &"player-1", rules, scored
	)

	check_eq(
		preview.board_revision_before,
		board.get_revision(),
		"a preview records the board revision it was calculated against"
	)
	check_eq(preview.placed_cell, Vector2i(8, 5), "a preview reports the placement it evaluated")
	check_eq(preview.events.size(), 3, "this placement scores a hand, an edge, and a cluster")
	check_eq(
		preview.events[0].category,
		ScoringEnums.ScoreCategory.POKER_HAND,
		"poker events come first"
	)
	check_eq(
		preview.events[1].category,
		ScoringEnums.ScoreCategory.EDGE_MATCH,
		"edge events come second"
	)
	check_eq(
		preview.events[2].category,
		ScoringEnums.ScoreCategory.EDGE_CLUSTER,
		"cluster events come third"
	)
	check_eq(preview.points_for_category(ScoringEnums.ScoreCategory.POKER_HAND), 4, "the window is a Two Pair")
	check_eq(preview.points_for_category(ScoringEnums.ScoreCategory.EDGE_MATCH), 1, "one boundary matches")
	check_eq(
		preview.points_for_category(ScoringEnums.ScoreCategory.EDGE_CLUSTER),
		3,
		"the blue component completes its first milestone"
	)
	check_eq(preview.total_points(), 8, "the transaction total is the sum of its events")
	check_eq(
		preview.move_id,
		ScoringCoordinator.PREVIEW_MOVE_ID,
		"a preview must not consume a real move identifier"
	)

	# ADR-007 section 3: a preview changes nothing at all.
	check_eq(board.get_revision(), 4, "a preview must not advance the board revision")
	check_eq(board.occupied_count(), 4, "a preview must not occupy a cell")
	check(board.is_empty_cell(Vector2i(8, 5)), "a preview must not write the target cell")
	check_eq(ledger.size(), 0, "a preview must not touch the ledger")
	check_eq(scored.size(), 0, "a preview must not record a scored window")
	check_eq(preview.total_points(), 8, "a second read of the preview must be stable")


func test_a_commit_reproduces_the_preview_on_the_same_revision() -> void:
	var board: BoardState = BoardState.create()
	var ledger: ScoreLedger = ScoreLedger.create()
	var scored: ScoredHandSet = ScoredHandSet.create()
	var rules: ScoringRules = ScoringRules.create_default()
	_build_line(board)

	var move_id: StringName = ScoringCoordinator.move_id_for(&"match-1", 5)
	var preview: ScoreTransaction = ScoringCoordinator.preview(
		board, _placed_tile(), &"player-1", rules, scored
	)
	var committed: ScoreTransaction = ScoringCoordinator.commit_placement(
		board, _placed_tile(), ledger, scored, &"player-1", move_id, 5, rules
	)

	check_eq(
		committed.board_revision_before,
		preview.board_revision_before,
		"the commit must be calculated against the revision the preview used"
	)
	# Every event identifier embeds the move id it was awarded for (ADR-007
	# section 5), so a preview and its commit are expected to differ by exactly
	# that segment. Comparing what remains proves the commit produced the same
	# categories and discriminators as its preview (ADR-007 section 8).
	check_eq(
		_event_tails(committed.event_ids(), move_id),
		_event_tails(preview.event_ids(), ScoringCoordinator.PREVIEW_MOVE_ID),
		"a commit on the same revision must produce the same events as its preview"
	)
	check_eq(
		committed.total_points(),
		preview.total_points(),
		"a commit on the same revision must award the same points as its preview"
	)
	check_eq(
		committed.points_for_category(ScoringEnums.ScoreCategory.EDGE_CLUSTER),
		preview.points_for_category(ScoringEnums.ScoreCategory.EDGE_CLUSTER),
		"the cluster award must match the preview exactly"
	)

	check(board.is_occupied(Vector2i(8, 5)), "a commit writes the tile")
	check_eq(board.get_revision(), 5, "a commit advances the board revision")
	check_eq(ledger.size(), 3, "every committed event reaches the ledger")
	check_eq(ledger.total_for(&"player-1"), 8, "the player is credited with the whole award")
	check_eq(scored.size(), 1, "a scoring window must be recorded as scored")


func test_a_placement_that_scores_nothing_produces_an_empty_transaction() -> void:
	var board: BoardState = BoardState.create()
	var rules: ScoringRules = ScoringRules.create_default()
	_build_line(board)

	# A tile placed away from every committed tile touches no boundary and
	# completes no five-cell window, so it can score nothing at all. (A complete
	# five-tile window always contains at least a Pair, because five tiles are
	# drawn from only four ranks, so the quiet placement must not complete one.)
	var quiet: TileSnapshot = TileSnapshot.create(
		_tile("quiet", TileEnums.TileRank.QUEEN, GREEN, GREEN, GREEN, YELLOW), Vector2i(0, 0), 0
	)
	var preview: ScoreTransaction = ScoringCoordinator.preview(board, quiet, &"player-1", rules)

	check(preview.is_empty(), "a placement that scores nothing must produce no events")
	check_eq(preview.total_points(), 0, "a placement that scores nothing is worth zero")
	check_eq(
		ScoringCoordinator.breakdown(board, quiet, rules).get("valid", false),
		true,
		"the placement is still a valid one to evaluate"
	)
	check_eq(
		ScoringCoordinator.breakdown(board, quiet, rules).get("total_points", -1),
		0,
		"the breakdown must agree that nothing is awarded"
	)


func test_a_repeated_commit_never_scores_twice() -> void:
	var board: BoardState = BoardState.create()
	var ledger: ScoreLedger = ScoreLedger.create()
	var scored: ScoredHandSet = ScoredHandSet.create()
	var rules: ScoringRules = ScoringRules.create_default()
	_build_line(board)

	var first: ScoreTransaction = ScoringCoordinator.commit_placement(
		board, _placed_tile(), ledger, scored, &"player-1", &"move:match-1:5", 5, rules
	)
	check_eq(first.total_points(), 8, "the first commit awards the points")

	var revision_after_first: int = board.get_revision()
	var ledger_size_after_first: int = ledger.size()

	# Repeating the same move against the same board cannot re-award anything,
	# because the cell is now occupied and the window is recorded as scored.
	var repeat: ScoreTransaction = ScoringCoordinator.commit_placement(
		board, _placed_tile(), ledger, scored, &"player-1", &"move:match-1:5", 5, rules
	)

	check(repeat.is_empty(), "a repeated commit must award nothing")
	check_eq(board.get_revision(), revision_after_first, "a repeated commit must not change the board")
	check_eq(ledger.size(), ledger_size_after_first, "a repeated commit must not add an event")
	check_eq(ledger.total_for(&"player-1"), 8, "a repeated commit must not inflate the total")


func test_a_duplicate_event_is_refused_before_the_board_is_touched() -> void:
	var board: BoardState = BoardState.create()
	var ledger: ScoreLedger = ScoreLedger.create()
	var scored: ScoredHandSet = ScoredHandSet.create()
	var rules: ScoringRules = ScoringRules.create_default()
	_build_line(board)

	var move_id: StringName = ScoringCoordinator.move_id_for(&"match-1", 5)

	# Event identifiers embed the move id, so retrying the same move produces
	# exactly these identifiers. Building them against a copy of the board reveals
	# what the real commit will try to write, which is the state a recovery that
	# restores the board but not the ledger would leave behind (ADR-007 section 4).
	var probe: ScoreTransaction = ScoringCoordinator.commit_placement(
		board.copy(),
		_placed_tile(),
		ScoreLedger.create(),
		ScoredHandSet.create(),
		&"player-1",
		move_id,
		5,
		rules
	)
	check_eq(probe.events.size(), 3, "the probe must build the events this move creates")
	check(ledger.add(probe.events[0]), "the test must be able to stage a conflicting event")

	var revision_before: int = board.get_revision()
	var result: ScoreTransaction = ScoringCoordinator.commit_placement(
		board, _placed_tile(), ledger, scored, &"player-1", move_id, 5, rules
	)

	check(result.is_empty(), "a conflicting commit must award nothing")
	check_eq(
		board.get_revision(),
		revision_before,
		"the board must not be written when the ledger would refuse an event"
	)
	check(board.is_empty_cell(Vector2i(8, 5)), "the target cell must stay empty")
	check_eq(ledger.size(), 1, "the intentionally staged event must be the only one")
	check_eq(scored.size(), 0, "a refused commit must not record a scored window")


func test_each_window_scores_once_for_the_whole_match() -> void:
	var board: BoardState = BoardState.create()
	var ledger: ScoreLedger = ScoreLedger.create()
	var scored: ScoredHandSet = ScoredHandSet.create()
	var rules: ScoringRules = ScoringRules.create_default()
	_build_line(board)

	var committed: ScoreTransaction = ScoringCoordinator.commit_placement(
		board, _placed_tile(), ledger, scored, &"player-1", &"move:match-1:5", 5, rules
	)
	check_eq(committed.total_points(), 8, "the window must score on commit")

	var without_history: Array[PokerHandResult] = PokerHandEvaluator.evaluate_full_board(
		board, rules.poker, null
	)
	var with_history: Array[PokerHandResult] = PokerHandEvaluator.evaluate_full_board(
		board, rules.poker, scored
	)

	check_eq(without_history.size(), 1, "the board holds exactly one complete five-cell window")
	check_eq(
		with_history.size(),
		0,
		"a window already recorded as scored must never score again"
	)
	check_eq(
		without_history[0].cells.size(),
		5,
		"a hand result must report all five cells for highlighting"
	)
	check_eq(
		String(without_history[0].hand_id),
		"hand:H:5:4",
		"the window identifier must name its orientation and origin"
	)
	check_eq(
		PokerHandEvaluator.cells_for_window_id(&"hand:H:5:4"),
		without_history[0].cells,
		"a window identifier must round-trip back to its cells"
	)


## Builds the fixture: four committed tiles on row five with base edges in
## top / right / bottom / left order.
##
## (5,5), (6,5) and (7,5) form a blue component of three, while (4,5)'s right
## edge is red and faces (5,5)'s yellow left edge, so the line is joined for
## connectivity but not for the blue cluster.
func _build_line(board: BoardState) -> void:
	_commit(board, Vector2i(4, 5), _tile("a", TileEnums.TileRank.ACE, GREEN, RED, GREEN, GREEN))
	_commit(board, Vector2i(5, 5), _tile("b", TileEnums.TileRank.ACE, GREEN, BLUE, GREEN, YELLOW))
	_commit(board, Vector2i(6, 5), _tile("c", TileEnums.TileRank.KING, GREEN, BLUE, GREEN, BLUE))
	_commit(board, Vector2i(7, 5), _tile("d", TileEnums.TileRank.KING, GREEN, BLUE, GREEN, BLUE))


## Returns the tile under test: a jack whose left edge matches the blue line.
func _placed_tile() -> TileSnapshot:
	return TileSnapshot.create(
		_tile("e", TileEnums.TileRank.JACK, GREEN, GREEN, GREEN, BLUE), Vector2i(8, 5), 0
	)


## Builds a valid tile with base edges in top / right / bottom / left order.
func _tile(id: String, rank: int, top: int, right: int, bottom: int, left: int) -> TileDefinition:
	var edges: Array[TileEnums.EdgeColor] = [top, right, bottom, left]
	return TileDefinition.create(StringName(id), rank, TileEnums.FaceColor.RED, edges)


## Commits a tile directly, as the authoritative writer would.
func _commit(board: BoardState, cell: Vector2i, tile: TileDefinition) -> void:
	if not board.commit_tile(TileSnapshot.create(tile, cell, 0)):
		push_error("test fixture could not commit tile '%s'" % String(tile.tile_id))


## Strips the "score:<move-id>:" prefix from each event identifier.
##
## Event identifiers are `score:<move-id>:<category>:<discriminator>`
## (ADR-007 section 5), so this leaves the category and discriminator, which are
## the parts a preview and its commit must agree on.
func _event_tails(ids: Array[StringName], move_id: StringName) -> Array[String]:
	var tails: Array[String] = []
	var prefix: String = "score:%s:" % String(move_id)
	for id: StringName in ids:
		tails.append(String(id).replace(prefix, ""))
	return tails
