extends TestCase

## Milestone 3 verification tests (ADR-007 sections 6, 9, and 10).
##
## Two complementary paths are exercised: the static board audit, which asks what
## the committed board alone says, and ordered full replay, which rebuilds the
## match from its move history through the same pure rules pipeline.
##
## Domain-level: no scene tree, no rendering, no input.

const BLUE: int = TileEnums.EdgeColor.BLUE
const RED: int = TileEnums.EdgeColor.RED
const GREEN: int = TileEnums.EdgeColor.GREEN
const YELLOW: int = TileEnums.EdgeColor.YELLOW

## A match that fills all 144 cells takes the whole bag, so this is the largest
## case the tests need. The scored fixtures pin their own 144-tile bag on
## purpose: the live rules hold 52 tiles (ADR-004 section 1, amended 2026-09-23)
## and could not fill the board.
const FULL_BOARD_BAG_SIZE: int = BoardEnums.CELL_COUNT
const FULL_BOARD_MOVES: int = BoardEnums.CELL_COUNT


func test_static_audit_passes_on_a_consistently_scored_board() -> void:
	var board: BoardState = BoardState.create()
	_blue_pair(board)

	var ledger: ScoreLedger = ScoreLedger.create()
	ledger.add(_edge_event(&"move:audit:1", &"p1", "edge:5,5-6,5"))

	var report: ScoringAudit.Report = ScoringAudit.audit(
		board, ledger, ScoredHandSet.create(), ScoringRules.create_default()
	)

	check_not_null(report, "the audit must return a report")
	check_eq(report.edges_on_board, 1, "two touching blue tiles hold one matching boundary")
	check_eq(report.edge_points_in_ledger, 1, "the ledger must record that boundary")
	check(report.edges_agree, "the edge count and the ledger must agree")
	check_eq(
		report.cluster_total_on_board,
		0,
		"a component of two tiles has not completed a milestone"
	)
	check(report.clusters_agree, "the cluster entitlement and the ledger must agree")
	check_eq(report.poker_window_ids.size(), 0, "two different ranks have no ranked hand")
	check(report.poker_ids_valid, "an empty scored-window set is trivially valid")
	check(report.poker_points_agree, "no ranked hand means no poker points")
	check(report.ok, "a consistent board must audit cleanly: %s" % str(report.problems))


func test_static_audit_detects_a_board_that_was_never_scored() -> void:
	var board: BoardState = BoardState.create()
	_blue_pair(board)

	var report: ScoringAudit.Report = ScoringAudit.audit(
		board, ScoreLedger.create(), ScoredHandSet.create(), ScoringRules.create_default()
	)

	check_not_null(report, "the audit must return a report")
	check_eq(report.edges_on_board, 1, "the board holds one matching boundary")
	check_eq(report.edge_points_in_ledger, 0, "nothing was scored")
	check(not report.edges_agree, "the audit must notice the missing edge award")
	check(not report.ok, "an unscored board must not audit cleanly")
	check(report.problems.size() > 0, "a failed audit must explain itself")


func test_static_audit_detects_a_cluster_award_the_board_does_not_support() -> void:
	var board: BoardState = BoardState.create()
	_blue_pair(board)

	var ledger: ScoreLedger = ScoreLedger.create()
	ledger.add(_edge_event(&"move:audit:1", &"p1", "edge:5,5-6,5"))
	ledger.add(
		ScoreEvent.create(
			&"score:move:audit:1:cluster:blue:5,5|6,5",
			&"move:audit:1",
			&"p1",
			ScoringEnums.ScoreCategory.EDGE_CLUSTER,
			3,
			[Vector2i(5, 5), Vector2i(6, 5)],
			{"color": "BLUE", "previous_entitlement": 0, "current_entitlement": 3},
			1,
			"scoring:1"
		)
	)

	var report: ScoringAudit.Report = ScoringAudit.audit(
		board, ledger, ScoredHandSet.create(), ScoringRules.create_default()
	)

	check(report.edges_agree, "the edge award is correct, so that check must pass")
	check_eq(report.cluster_total_on_board, 0, "a size-two component holds no entitlement")
	check_eq(report.cluster_points_in_ledger, 3, "the ledger claims a cluster award")
	check(not report.clusters_agree, "the audit must notice the unsupported cluster award")
	check(not report.ok, "a board whose clusters disagree with the ledger must not audit cleanly")


func test_ordered_replay_matches_live_incremental_play() -> void:
	var match_result: Dictionary = _play_seeded_match(20260922, &"match-a")

	var live_board: BoardState = match_result["board"]
	var live_ledger: ScoreLedger = match_result["ledger"]
	var live_scored: ScoredHandSet = match_result["scored"]
	var moves: Array[ScoringMove] = match_result["moves"]
	var tiles: Dictionary = match_result["tiles"]
	var rules: ScoringRules = ScoringRules.create_default()

	check_eq(
		moves.size(),
		FULL_BOARD_MOVES,
		"a seeded match must commit exactly one tile per board cell"
	)
	check(live_board.is_full(), "the seeded match must fill the board")
	check(
		live_ledger.size() > 0,
		"a random board must award at least one score for this comparison to mean anything"
	)

	var replayed: ScoringReplay.Report = ScoringReplay.replay(
		moves, rules, func(tile_id): return tiles.get(tile_id)
	)

	check(replayed.completed, "the replay must apply every move: %s" % str(replayed.deviations))
	check_eq(replayed.moves_applied, FULL_BOARD_MOVES, "every move must be replayed")
	check_eq(
		replayed.board.get_revision(),
		live_board.get_revision(),
		"the replayed board must reach the same revision"
	)
	check_eq(
		ScoringReplay.compare(live_board, live_ledger, live_scored, replayed, rules),
		"",
		"incremental play and replay must agree on board, events, totals, windows, "
		+ "boundaries, and cluster entitlements"
	)
	check_eq(
		replayed.ledger.player_totals_by_name(),
		live_ledger.player_totals_by_name(),
		"replayed totals must equal the live totals"
	)
	check_eq(
		replayed.scored_hand_ids.to_array(),
		live_scored.to_array(),
		"replayed scored windows must equal the live scored windows"
	)

	var report: ScoringAudit.Report = ScoringAudit.audit(
		replayed.board, replayed.ledger, replayed.scored_hand_ids, rules
	)
	check(
		report.ok,
		"the replayed board must also pass the static audit: %s" % str(report.problems)
	)


func test_current_board_hands_are_in_incremental_history() -> void:
	var match_result: Dictionary = _play_seeded_match(7, &"match-b")
	var board: BoardState = match_result["board"]
	var ledger: ScoreLedger = match_result["ledger"]
	var scored: ScoredHandSet = match_result["scored"]
	var rules: ScoringRules = ScoringRules.create_default()

	var full_board_windows: Array[PokerHandResult] = PokerHandEvaluator.evaluate_full_board(
		board, rules.poker, null
	)
	var recorded: Array[StringName] = scored.to_array()

	check(recorded.size() > full_board_windows.size(), "history retains shorter hands after they grow")
	for result: PokerHandResult in full_board_windows:
		check(
			recorded.has(result.hand_id),
			"the incrementally scored set must contain window '%s'" % String(result.hand_id)
		)

	check_eq(
		ledger.total_for_category(ScoringEnums.ScoreCategory.EDGE_MATCH),
		EdgeMatchScorer.boundary_ids(board).size(),
		"incremental edge awards must equal the boundaries the final board holds"
	)
	check_eq(
		ledger.total_for_category(ScoringEnums.ScoreCategory.EDGE_CLUSTER),
		EdgeClusterScorer.total_entitlement(board, rules.cluster),
		"incremental cluster awards must equal the entitlement the final board represents"
	)


func test_seeded_matches_are_deterministic() -> void:
	var first: Dictionary = _play_seeded_match(31337, &"match-c")
	var second: Dictionary = _play_seeded_match(31337, &"match-c")

	var first_ledger: ScoreLedger = first["ledger"]
	var second_ledger: ScoreLedger = second["ledger"]

	check_eq(
		first_ledger.event_ids(),
		second_ledger.event_ids(),
		"the same seed and match id must produce the same events in the same order"
	)
	check_eq(
		first_ledger.player_totals_by_name(),
		second_ledger.player_totals_by_name(),
		"the same seed and match id must produce the same totals"
	)
	check_eq(
		first["scored"].to_array(),
		second["scored"].to_array(),
		"the same seed and match id must score the same windows"
	)


func test_replay_reports_a_move_its_tile_lookup_cannot_supply() -> void:
	var match_result: Dictionary = _play_seeded_match(99, &"match-d")
	var moves: Array[ScoringMove] = match_result["moves"]
	var rules: ScoringRules = ScoringRules.create_default()

	var replayed: ScoringReplay.Report = ScoringReplay.replay(
		moves, rules, func(_tile_id): return null
	)

	check(not replayed.completed, "replay cannot complete without the tiles it needs")
	check_eq(replayed.moves_applied, 0, "no move can be applied without its tile")
	check(replayed.deviations.size() > 0, "the report must explain why replay stopped")
	check(
		not ScoringReplay.compare(
			match_result["board"],
			match_result["ledger"],
			match_result["scored"],
			replayed,
			rules
		).is_empty(),
		"an incomplete replay must never be reported as equivalent"
	)

	var no_lookup: ScoringReplay.Report = ScoringReplay.replay(moves, rules)
	check(not no_lookup.completed, "replay without a tile lookup must stop at the first move")


## Plays a deterministic seeded match that fills the whole board, returning the
## live board, ledger, scored-window set, move history, and tile lookup.
##
## Every move takes the first frontier cell in row-major order at rotation zero
## and is validated through the same `PlacementValidator` a human move uses, so
## the match exercises the real placement and scoring paths rather than a
## test-only shortcut.
##
## Each call commits one tile through ADR-007 section 4's per-tile transaction,
## which ADR-011 section 5 supersedes for live play, and records it as
## `ScoringMove.create_single`. The one-placement record is deliberately kept:
## ADR-011 section 10 leaves scoring untouched, and `ScoringReplay` still replays
## that record shape, so this fixture audits the unchanged scoring over a full
## board through the history the replay layer reads.
func _play_seeded_match(seed: int, match_id: StringName) -> Dictionary:
	var rules: ScoringRules = ScoringRules.create_default()
	var board: BoardState = BoardState.create()
	var ledger: ScoreLedger = ScoreLedger.create()
	var scored: ScoredHandSet = ScoredHandSet.create()
	var moves: Array[ScoringMove] = []
	var tiles: Dictionary = {}

	var generation: TileGenerationRules = TileGenerationRules.create_default()
	generation.bag_size = FULL_BOARD_BAG_SIZE

	var source: TileSource = TileSource.new()
	if not source.initialize(match_id, seed, generation):
		push_error("the test could not initialize a tile source")
		return {"board": board, "ledger": ledger, "scored": scored, "moves": moves, "tiles": tiles}

	while not board.is_full():
		var tile: TileDefinition = source.draw()
		if tile == null:
			break

		var cell: Vector2i = Vector2i.ZERO
		if board.has_any_tile():
			var frontier: Array[Vector2i] = board.get_frontier_cells()
			if frontier.is_empty():
				break
			cell = frontier[0]
		else:
			cell = Vector2i(5, 5)

		var turn_number: int = moves.size() + 1
		var move_id: StringName = ScoringCoordinator.move_id_for(match_id, turn_number)
		var request: PlacementRequest = PlacementRequest.create(
			&"player-1", tile.tile_id, cell, 0
		)
		var result: PlacementResult = PlacementValidator.validate(board, request, tile, true)
		if result == null or not result.accepted:
			push_error(
				"the test could not place tile '%s' at %s: %s"
				% [String(tile.tile_id), BoardEnums.cell_name(cell), result.get_rejection_name()]
			)
			break

		ScoringCoordinator.commit_placement(
			board,
			result.placed_tile,
			ledger,
			scored,
			&"player-1",
			move_id,
			turn_number,
			rules
		)
		moves.append(
			ScoringMove.create_single(
				move_id, turn_number, &"player-1", tile.tile_id, cell, 0, turn_number == 1
			)
		)
		tiles[tile.tile_id] = tile

	return {"board": board, "ledger": ledger, "scored": scored, "moves": moves, "tiles": tiles}


## Commits two touching blue tiles, which hold exactly one matching boundary and
## a blue component of two unique tiles.
func _blue_pair(board: BoardState) -> void:
	for cell: Vector2i in [Vector2i(5, 5), Vector2i(6, 5)]:
		var edges: Array[TileEnums.EdgeColor] = [BLUE, BLUE, BLUE, BLUE]
		var tile: TileDefinition = TileDefinition.create(
			StringName("blue-%d-%d" % [cell.x, cell.y]),
			TileEnums.TileRank.ACE if cell.x == 5 else TileEnums.TileRank.KING,
			TileEnums.FaceColor.RED,
			edges
		)
		if not board.commit_tile(TileSnapshot.create(tile, cell, 0)):
			push_error("the test could not commit a blue tile")


## Builds an edge-match event for the audit fixtures.
func _edge_event(move_id: StringName, player_id: StringName, boundary_id: String) -> ScoreEvent:
	return ScoreEvent.create(
		StringName("score:%s:edge:%s" % [String(move_id), boundary_id]),
		move_id,
		player_id,
		ScoringEnums.ScoreCategory.EDGE_MATCH,
		ScoringEnums.EDGE_MATCH_POINTS,
		[Vector2i(5, 5), Vector2i(6, 5)],
		{"boundary_id": boundary_id, "color": "BLUE"},
		1,
		"scoring:1"
	)
