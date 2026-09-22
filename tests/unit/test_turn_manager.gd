extends TestCase

## Milestone 4 turn sequencing tests (ADR-003 sections 1 to 8).
##
## Domain-level: no scene tree, no rendering, no input. Every expectation is
## checked against the session, the turn state, and the commit result.
##
## Where a rule is stated as a pure function of committed totals (the winner and
## draw rule of ADR-003 section 8) it is tested both directly and against a real
## played match, so the rule and the match cannot drift apart.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

const NONE_REJECTION: int = PlacementEnums.PlacementRejection.NONE
const OPENING_REQUIRED: int = PlacementEnums.PlacementRejection.OPENING_CELL_REQUIRED
const NOT_CONNECTED: int = PlacementEnums.PlacementRejection.NOT_CONNECTED
const NOT_PLAYERS_TURN: int = PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN
const DUPLICATE_MOVE: int = PlacementEnums.PlacementRejection.DUPLICATE_MOVE
const MATCH_FINISHED: int = PlacementEnums.PlacementRejection.MATCH_FINISHED


func test_setup_hands_the_first_turn_to_the_human() -> void:
	var session: GameSessionState = _new_session(&"turn-a", 11)

	check_eq(
		TurnManager.setup(session),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"setup must open the first action phase"
	)

	var turn_state: TurnState = session.get_turn_state()
	check_eq(turn_state.active_player_id, HUMAN, "the human takes the first turn")
	check_eq(turn_state.turn_number, 1, "the first turn is turn 1")
	check_eq(turn_state.consecutive_no_tile_skips, 0, "a fresh match has no skips")
	check_eq(turn_state.last_skip_reason, TurnEnums.SkipReason.NONE, "nothing has been skipped")
	check(session.has_active_tile(HUMAN), "the human must be holding a tile to act with")
	check(not session.has_active_tile(AI), "only the active player is dealt a tile")
	check_eq(session.remaining_tile_count(), 143, "one of the 144 tiles was dealt")
	check_eq(session.get_board().occupied_count(), 0, "setup must not place a tile")
	check(TurnManager.is_awaiting_human_action(session), "the human may act now")
	check(not TurnManager.is_awaiting_ai_action(session), "it is not the AI's turn")


func test_setup_is_refused_once_the_match_has_started() -> void:
	var session: GameSessionState = _new_session(&"turn-b", 12)
	TurnManager.setup(session)
	var held_id: StringName = session.active_tile_for(HUMAN).tile_id
	var remaining_before: int = session.remaining_tile_count()

	check_eq(
		TurnManager.setup(session),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"a second setup must leave the match where it is"
	)

	check_eq(session.get_turn_state().turn_number, 1, "a second setup must not reset the turn")
	check_eq(
		session.active_tile_for(HUMAN).tile_id,
		held_id,
		"a second setup must not deal a replacement tile"
	)
	check_eq(
		session.remaining_tile_count(),
		remaining_before,
		"a second setup must not consume a tile"
	)


func test_a_committed_move_places_one_tile_and_passes_the_turn() -> void:
	var session: GameSessionState = _new_session(&"turn-c", 13)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()
	var tile_id: StringName = session.active_tile_for(HUMAN).tile_id
	var cell: Vector2i = _first_frontier(board)

	var result: PlacementResult = MoveCommitter.commit(session, HUMAN, cell, 0)

	check(result.was_committed(), "the opening move must commit: %s" % result.describe())
	check_eq(result.rejection, NONE_REJECTION, "an accepted move carries no rejection")
	check_eq(board.occupied_count(), 1, "a turn commits exactly one tile")
	check_eq(board.get_tile(cell).get_tile_id(), tile_id, "the active tile is the tile placed")
	check_eq(
		String(result.move_id),
		"move:turn-c:1",
		"the move identifier is derived from the match identity and turn number"
	)
	check_eq(result.score_events.size(), 0, "the opening move scores nothing to score")
	check(session.has_move_id(result.move_id), "the committed move joins the history")

	# ADR-003 section 1 separates the phases: RESOLVE_MOVE commits the placement
	# and its scoring, then TURN_END advances play. Every other caller in this
	# suite pairs the two calls, and this test does the same.
	TurnManager.resolve(session, result)

	var turn_state: TurnState = session.get_turn_state()
	check_eq(turn_state.active_player_id, AI, "a committed move passes the turn")
	check_eq(turn_state.turn_number, 2, "the turn number advances")
	check_eq(turn_state.consecutive_no_tile_skips, 0, "supplying a tile keeps the skip count clear")
	check(not session.has_active_tile(HUMAN), "the committed tile leaves its owner's slot")
	check(session.has_active_tile(AI), "the next player receives a tile at turn start")
	check_eq(session.remaining_tile_count(), 142, "the next player's tile was drawn")
	check(TurnManager.is_awaiting_ai_action(session), "the AI is now the active player")
	check(not TurnManager.is_awaiting_human_action(session), "human input is disabled meanwhile")


func test_an_illegal_placement_does_not_consume_the_turn() -> void:
	var session: GameSessionState = _new_session(&"turn-d", 14)
	TurnManager.setup(session)
	var held_id: StringName = session.active_tile_for(HUMAN).tile_id

	# (0,0) is empty and in bounds but outside the four opening cells.
	var result: PlacementResult = MoveCommitter.commit(session, HUMAN, Vector2i(0, 0), 0)

	check(not result.accepted, "a tile outside the opening cells must be refused")
	check_eq(result.rejection, OPENING_REQUIRED, "the reason names the opening rule")
	check_eq(session.get_board().occupied_count(), 0, "a refused move places nothing")
	check_eq(session.get_turn_state().turn_number, 1, "a refused move does not advance the turn")
	check_eq(session.get_turn_state().active_player_id, HUMAN, "the turn stays with the human")
	check_eq(
		session.active_tile_for(HUMAN).tile_id,
		held_id,
		"a refused move keeps the active tile"
	)
	check_eq(session.remaining_tile_count(), 143, "a refused move consumes no tile")
	check_eq(session.move_count(), 0, "a refused move is not recorded")
	check_eq(
		TurnManager.resolve(session, result),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"resolving a refused move leaves the match awaiting action"
	)
	check_eq(session.get_turn_state().turn_number, 1, "resolving a refusal still does not advance")
	check_eq(session.move_count(), 0, "resolving a refusal records nothing")


func test_an_invalid_rotation_is_refused_without_changing_the_turn() -> void:
	var session: GameSessionState = _new_session(&"turn-e", 15)
	TurnManager.setup(session)
	var cell: Vector2i = _first_frontier(session.get_board())

	var result: PlacementResult = MoveCommitter.commit(session, HUMAN, cell, 4)

	check(not result.accepted, "a fifth orientation is not a rotation")
	check_eq(
		result.rejection,
		PlacementEnums.PlacementRejection.INVALID_ROTATION,
		"the reason names the rotation rule"
	)
	check_eq(session.get_turn_state().turn_number, 1, "the turn must not advance")
	check_eq(session.get_board().occupied_count(), 0, "nothing may be placed")


func test_the_wrong_player_cannot_move() -> void:
	var session: GameSessionState = _new_session(&"turn-f", 16)
	TurnManager.setup(session)
	var cell: Vector2i = _first_frontier(session.get_board())

	var result: PlacementResult = MoveCommitter.commit(session, AI, cell, 0)

	check(not result.accepted, "the inactive player must not be able to move")
	check_eq(result.rejection, NOT_PLAYERS_TURN, "the reason names turn ownership")
	check_eq(session.get_board().occupied_count(), 0, "nothing may be placed out of turn")
	check_eq(session.get_turn_state().turn_number, 1, "the turn must not advance")


func test_a_repeated_move_identifier_is_refused_before_anything_changes() -> void:
	var session: GameSessionState = _new_session(&"turn-g", 17)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()
	var first: PlacementResult = MoveCommitter.commit(session, HUMAN, _first_frontier(board), 0)
	check(first.was_committed(), "the first move must commit")
	TurnManager.resolve(session, first)

	# Re-open turn 1 with a tile in hand, which is the state a retry would present.
	var turn_state: TurnState = session.get_turn_state()
	session.set_active_tile(HUMAN, session.get_tile_source().draw())
	turn_state.active_player_id = HUMAN
	turn_state.turn_number = 1
	turn_state.phase = TurnEnums.MatchPhase.AWAIT_ACTION

	var occupied_before: int = board.occupied_count()
	var ledger_before: int = session.get_ledger().size()
	var retry_cell: Vector2i = _first_frontier(board)

	var repeat: PlacementResult = MoveCommitter.commit(session, HUMAN, retry_cell, 0)

	check(not repeat.accepted, "a move identifier may be committed at most once")
	check_eq(repeat.rejection, DUPLICATE_MOVE, "the reason names the duplicate move")
	check_eq(board.occupied_count(), occupied_before, "a refused retry places nothing")
	check_eq(session.get_ledger().size(), ledger_before, "a refused retry scores nothing")
	check_eq(session.move_count(), 1, "the history keeps exactly one move")


func test_a_finished_match_refuses_further_moves() -> void:
	var session: GameSessionState = _new_session(&"turn-h", 18)
	TurnManager.setup(session)
	session.finish(TurnEnums.MatchOutcome.DRAW, TurnEnums.EndReason.BOARD_FULL)
	session.get_turn_state().phase = TurnEnums.MatchPhase.GAME_OVER

	var result: PlacementResult = MoveCommitter.commit(
		session, HUMAN, _first_frontier(session.get_board()), 0
	)

	check(not result.accepted, "a finished match must refuse a move")
	check_eq(result.rejection, MATCH_FINISHED, "the reason names the finished match")
	check_eq(session.get_board().occupied_count(), 0, "nothing may be placed after the match")
	check(session.is_over(), "the session reports the match is over")


func test_a_short_bag_exhausts_after_two_automatic_skips() -> void:
	# Two tiles: one for each player, so the third turn finds an empty source.
	var generation: TileGenerationRules = TileGenerationRules.new()
	generation.bag_size = 2
	var session: GameSessionState = GameSessionState.create(
		&"turn-i", 19, ScoringRules.create_default(), generation
	)
	check_not_null(session, "a two-tile match must be constructible")
	TurnManager.setup(session)
	var board: BoardState = session.get_board()

	var human_move: PlacementResult = MoveCommitter.commit(session, HUMAN, _first_frontier(board), 0)
	check(human_move.was_committed(), "the human's move must commit")
	check_eq(TurnManager.resolve(session, human_move), TurnEnums.MatchPhase.AWAIT_ACTION, "play continues")

	var ai_move: PlacementResult = MoveCommitter.commit(session, AI, _first_frontier(board), 0)
	check(ai_move.was_committed(), "the AI's move must commit")
	check_eq(
		TurnManager.resolve(session, ai_move),
		TurnEnums.MatchPhase.GAME_OVER,
		"an exhausted source must end the match after both players skip"
	)

	var turn_state: TurnState = session.get_turn_state()
	check_eq(
		turn_state.consecutive_no_tile_skips,
		TurnEnums.MAX_CONSECUTIVE_SKIPS,
		"both automatic skips must be counted"
	)
	check_eq(
		turn_state.last_skip_reason,
		TurnEnums.SkipReason.NO_TILE_AVAILABLE,
		"the skip must be recorded with its reason"
	)
	check_eq(turn_state.turn_number, 4, "each skipped turn handed play on")
	check_eq(session.remaining_tile_count(), 0, "the source is exhausted")
	check(not session.has_active_tile(HUMAN), "no player holds a tile at the end")
	check(not session.has_active_tile(AI), "no player holds a tile at the end")
	check_eq(
		session.get_end_reason(),
		TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED,
		"the end reason is the exhausted source"
	)
	check_eq(board.occupied_count(), 2, "both supplied tiles were placed")
	check_eq(
		session.get_outcome(),
		TurnEnums.outcome_for_scores(
			session.score_for(HUMAN), session.score_for(AI), TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED
		),
		"the outcome must match the committed totals"
	)


func test_the_winner_rule_has_no_tie_breaker() -> void:
	check_eq(
		TurnEnums.outcome_for_scores(10, 4, TurnEnums.EndReason.BOARD_FULL),
		TurnEnums.MatchOutcome.HUMAN_WIN,
		"the greater committed total wins"
	)
	check_eq(
		TurnEnums.outcome_for_scores(4, 10, TurnEnums.EndReason.BOARD_FULL),
		TurnEnums.MatchOutcome.AI_WIN,
		"either player may win"
	)
	check_eq(
		TurnEnums.outcome_for_scores(7, 7, TurnEnums.EndReason.BOARD_FULL),
		TurnEnums.MatchOutcome.DRAW,
		"equal totals are a draw, with no tie-breaker"
	)
	check_eq(
		TurnEnums.outcome_for_scores(99, 0, TurnEnums.EndReason.RULES_FAILURE),
		TurnEnums.MatchOutcome.INCOMPLETE,
		"an unrecoverable failure awards no winner however the scores stand"
	)


func test_a_rules_failure_stops_the_match_without_a_winner() -> void:
	var session: GameSessionState = _new_session(&"turn-j", 20)
	TurnManager.setup(session)

	check_eq(
		TurnManager.fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE),
		TurnEnums.MatchPhase.RECOVERY_ERROR,
		"a rules failure moves the match into recovery"
	)
	check(session.is_over(), "a match in recovery accepts no further move")
	check_eq(
		session.get_outcome(),
		TurnEnums.MatchOutcome.INCOMPLETE,
		"no winner is awarded"
	)
	check_eq(
		session.get_end_reason(),
		TurnEnums.EndReason.RULES_FAILURE,
		"the end reason is recorded"
	)


func test_human_and_ai_reach_scoring_through_the_same_path() -> void:
	var session: GameSessionState = _new_session(&"turn-k", 21)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()

	var human_move: PlacementResult = MoveCommitter.commit(session, HUMAN, _first_frontier(board), 0)
	TurnManager.resolve(session, human_move)
	var ai_cell: Vector2i = _first_frontier(board)
	var ai_move: PlacementResult = MoveCommitter.commit(session, AI, ai_cell, 0)

	check(human_move.was_committed(), "the human's move commits through the transaction")
	check(ai_move.was_committed(), "the AI's move commits through the same transaction")
	check_eq(human_move.move_id, StringName("move:turn-k:1"), "the human's move is turn 1")
	check_eq(ai_move.move_id, StringName("move:turn-k:2"), "the AI's move is turn 2")
	check_eq(session.move_count(), 2, "both moves are recorded in history")

	# The same rule refuses both players equally: a cell touching nothing.
	var off_board_cell: Vector2i = _isolated_cell(board)
	if off_board_cell != Vector2i(-1, -1):
		TurnManager.resolve(session, ai_move)
		var check_result: PlacementResult = MoveCommitter.commit(session, HUMAN, off_board_cell, 0)
		check(not check_result.accepted, "an unconnected cell is refused")
		check_eq(
			check_result.rejection,
			NOT_CONNECTED,
			"the connection rule applies to the human exactly as it would to the AI"
		)


func test_the_remaining_count_is_visible_but_the_bag_is_not() -> void:
	var session: GameSessionState = _new_session(&"turn-l", 22)
	TurnManager.setup(session)

	check_eq(
		session.get_tile_source().get_bag_size(),
		144,
		"the configured bag holds one tile per board cell"
	)
	check_eq(session.remaining_tile_count(), 143, "the remaining count is public")
	check_eq(
		session.active_tile_for(HUMAN).is_valid(),
		true,
		"the active player's own tile is known to them"
	)
	check(session.active_tile_for(AI) == null, "the opponent's undrawn tile is not exposed")


## Builds a standard-rules session at MATCH_SETUP.
func _new_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = GameSessionState.create(
		match_id, seed, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(session, "the session must be constructible")
	return session


## Returns the first legal frontier cell in row-major order.
func _first_frontier(board: BoardState) -> Vector2i:
	var frontier: Array[Vector2i] = board.get_frontier_cells()
	if frontier.is_empty():
		return Vector2i(-1, -1)
	return frontier[0]


## Returns an empty in-bounds cell that touches no committed tile, or (-1, -1).
func _isolated_cell(board: BoardState) -> Vector2i:
	for y: int in range(BoardEnums.BOARD_HEIGHT):
		for x: int in range(BoardEnums.BOARD_WIDTH):
			var cell: Vector2i = Vector2i(x, y)
			if board.is_empty_cell(cell) and not board.has_occupied_neighbor(cell):
				return cell
	return Vector2i(-1, -1)
