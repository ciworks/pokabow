extends TestCase

## Milestone 4 turn sequencing tests (ADR-003 sections 1 to 8), retargeted to the
## deck of six and the multi-placement turn of ADR-010 sections 2 to 9.
##
## Domain-level: no scene tree, no rendering, no input. Every expectation is
## checked against the session, the turn state, and the commit result.
##
## ADR-010 changes three things this suite previously fixed as one-tile rules, and
## the expectations below follow the new rules rather than the superseded ones:
##
## - `MATCH_SETUP` deals six tiles to each player instead of one active tile, so
##   the pot starts at 132 rather than 143 (ADR-010 sections 1 and 2);
## - a turn is one or more placements, so a committed placement keeps the turn in
##   `AWAIT_ACTION`, the turn ends on the explicit `end_turn()` action, and the
##   move identifier carries a 1-based placement index (ADR-010 sections 3, 4, 6,
##   and 9);
## - the deck is topped back up at the turn boundary, and the match ends when the
##   board is full or when neither player holds a tile while the pot is empty
##   (ADR-010 sections 5 and 7), in place of ADR-003 section 5's two-consecutive
##   skip rule.
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

## The Phase 1 deck size every deck is filled to (ADR-010 section 1).
const DECK_SIZE: int = DeckRules.DEFAULT_DECK_SIZE

## Tiles dealt at `MATCH_SETUP`: one deck per Phase 1 player (ADR-010 section 2).
const TILES_DEALT_AT_SETUP: int = DECK_SIZE * 2

## Tiles the pot still holds once both decks are dealt (ADR-010 section 2).
const POT_AFTER_SETUP: int = BoardEnums.CELL_COUNT - TILES_DEALT_AT_SETUP


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

	# ADR-010 section 2: both decks are filled at setup, human first then AI.
	check_eq(
		session.deck_count(HUMAN), DECK_SIZE, "the human's deck is filled to deck_size"
	)
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival's deck is filled to deck_size")
	check(
		session.has_active_tile(HUMAN), "the human must be holding tiles to act with"
	)
	check_eq(
		session.remaining_tile_count(),
		POT_AFTER_SETUP,
		"dealing twelve tiles leaves 132 in the shared pot"
	)
	check_eq(
		session.remaining_tile_count()
			+ session.deck_count(HUMAN)
			+ session.deck_count(AI)
			+ session.get_board().occupied_count(),
		BoardEnums.CELL_COUNT,
		"the pot, both decks, and the board must account for all 144 tiles"
	)
	check_eq(
		session.verify_tile_conservation().size(),
		0,
		"every tile must sit in exactly one place after the deal: %s"
		% str(session.verify_tile_conservation())
	)
	check_eq(session.get_board().occupied_count(), 0, "setup must not place a tile")
	check(TurnManager.is_awaiting_human_action(session), "the human may act now")
	check(not TurnManager.is_awaiting_ai_action(session), "it is not the AI's turn")


func test_setup_is_refused_once_the_match_has_started() -> void:
	var session: GameSessionState = _new_session(&"turn-b", 12)
	TurnManager.setup(session)
	var dealt_ids: PackedStringArray = _deck_ids(session, HUMAN)
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
		_deck_ids(session, HUMAN),
		dealt_ids,
		"a second setup must not redeal the human's deck"
	)
	check_eq(
		session.deck_count(AI), DECK_SIZE, "a second setup must not redeal the rival's deck"
	)
	check_eq(
		session.remaining_tile_count(),
		remaining_before,
		"a second setup must not consume a tile"
	)


func test_a_committed_placement_keeps_the_turn_open() -> void:
	var session: GameSessionState = _new_session(&"turn-c", 13)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()
	var tile_id: StringName = session.active_tile_for(HUMAN).tile_id
	var cell: Vector2i = _first_frontier(board)

	var result: PlacementResult = MoveCommitter.commit(session, HUMAN, cell, 0)

	check(result.was_committed(), "the opening placement must commit: %s" % result.describe())
	check_eq(result.rejection, NONE_REJECTION, "an accepted placement carries no rejection")
	check_eq(board.occupied_count(), 1, "a placement commits exactly one tile")
	check_eq(board.get_tile(cell).get_tile_id(), tile_id, "the deck tile is the tile placed")
	check_eq(
		String(result.move_id),
		"move:turn-c:1:1",
		"the move identifier is the match identity, the turn number, and the 1-based placement index"
	)
	check_eq(result.score_events.size(), 0, "the opening move scores nothing to score")
	check(session.has_move_id(result.move_id), "the committed move joins the history")
	check_eq(
		session.deck_count(HUMAN),
		DECK_SIZE - 1,
		"the committed tile leaves its owner's deck, not an active slot"
	)
	check_eq(
		session.remaining_tile_count(),
		POT_AFTER_SETUP,
		"a placement consumes no tile from the pot: refill is at the turn boundary"
	)

	# ADR-010 section 3 step 9: the placement commits, and the turn stays open.
	check_eq(
		TurnManager.resolve(session, result),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"a committed placement keeps the match in the action phase"
	)

	var turn_state: TurnState = session.get_turn_state()
	check_eq(turn_state.active_player_id, HUMAN, "a placement does not pass the turn")
	check_eq(turn_state.turn_number, 1, "a placement does not advance the turn number")
	check(
		session.has_active_tile(HUMAN),
		"the human keeps the rest of the deck for further placements"
	)
	check_eq(
		session.deck_count(AI),
		DECK_SIZE,
		"the rival's deck is untouched until the human ends the turn"
	)
	check_eq(
		turn_state.consecutive_no_tile_skips, 0, "placing a tile keeps the skip count clear"
	)
	check(TurnManager.is_awaiting_human_action(session), "the human may keep placing")
	check(not TurnManager.is_awaiting_ai_action(session), "the rival is not acting yet")
	check_eq(
		session.next_placement_index(),
		2,
		"the next placement of this turn carries index 2 (ADR-010 section 9)"
	)


func test_a_second_placement_is_a_distinct_move_and_the_deck_tops_up_at_the_turn_end() -> void:
	var session: GameSessionState = _new_session(&"turn-c2", 113)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()

	var first: PlacementResult = MoveCommitter.commit(session, HUMAN, _first_frontier(board), 0)
	check(first.was_committed(), "the first placement of the turn must commit")
	check_eq(
		TurnManager.resolve(session, first),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"the turn stays open after one placement"
	)

	var second: PlacementResult = MoveCommitter.commit(session, HUMAN, _first_frontier(board), 0)
	check(second.was_committed(), "the human may place more than one tile in a turn")
	check_eq(
		String(first.move_id),
		"move:turn-c2:1:1",
		"the first placement of turn 1 carries placement index 1"
	)
	check_eq(
		String(second.move_id),
		"move:turn-c2:1:2",
		"the second placement of turn 1 carries placement index 2"
	)
	check(first.move_id != second.move_id, "each placement gets a distinct move identifier")
	check(session.has_move_id(second.move_id), "the second placement joins the history")
	check_eq(session.move_count(), 2, "both placements are recorded")
	check_eq(
		session.deck_count(HUMAN), DECK_SIZE - 2, "two placements leave four tiles in the deck"
	)
	check_eq(
		session.remaining_tile_count(),
		POT_AFTER_SETUP,
		"the pot is untouched while the turn is still open"
	)
	check_eq(
		TurnManager.resolve(session, second),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"the second placement still leaves the turn open"
	)

	# ADR-010 section 4: the turn ends on the explicit end-turn action.
	check_eq(
		TurnManager.end_turn(session),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"an explicit end-turn closes the turn and opens the rival's"
	)

	var turn_state: TurnState = session.get_turn_state()
	check_eq(turn_state.active_player_id, AI, "the explicit end-turn passes the turn")
	check_eq(turn_state.turn_number, 2, "the explicit end-turn advances the turn number")

	# ADR-010 section 5: the refill takes exactly what was played.
	var taken: int = POT_AFTER_SETUP - session.remaining_tile_count()
	check_eq(taken, 2, "the refill takes the number of tiles played while the pot can supply it")
	check_eq(
		session.deck_count(HUMAN),
		DECK_SIZE,
		"the human's deck is topped back up to deck_size at the turn boundary"
	)
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival holds a full deck for its turn")
	check_eq(
		session.remaining_tile_count(),
		POT_AFTER_SETUP - 2,
		"the pot supplied the refill and nothing else"
	)
	check_eq(
		session.verify_tile_conservation().size(),
		0,
		"the refill must keep every tile in exactly one place"
	)


func test_an_explicit_end_turn_before_any_placement_is_accepted_and_consumes_the_turn() -> void:
	var session: GameSessionState = _new_session(&"turn-n", 23)
	TurnManager.setup(session)
	var turn_state: TurnState = session.get_turn_state()

	check_eq(
		session.deck_count(HUMAN), DECK_SIZE, "the human holds a deck before deciding to pass"
	)
	check_eq(
		TurnManager.end_turn(session),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"ending a turn with zero placements is permitted"
	)

	check_eq(turn_state.active_player_id, AI, "ending the turn hands play to the rival")
	check_eq(turn_state.turn_number, 2, "ending the turn advances the turn number")
	check_eq(session.get_board().occupied_count(), 0, "ending a turn places no tile")
	check_eq(session.move_count(), 0, "ending a turn records no move")
	check_eq(
		session.deck_count(HUMAN),
		DECK_SIZE,
		"a turn with no placement needs no refill"
	)
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival's deck is stocked for its turn")
	check_eq(
		session.remaining_tile_count(),
		POT_AFTER_SETUP,
		"ending a turn with no placement consumes no tile"
	)


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
	check_eq(
		session.deck_count(HUMAN), DECK_SIZE, "a refused move consumes no deck tile"
	)
	check_eq(
		session.remaining_tile_count(),
		POT_AFTER_SETUP,
		"a refused move consumes no tile"
	)
	check_eq(session.move_count(), 0, "a refused move is not recorded")
	check_eq(
		TurnManager.resolve(session, result),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"resolving a refused move leaves the match awaiting action"
	)
	check_eq(session.get_turn_state().turn_number, 1, "resolving a refusal still does not advance")
	check_eq(session.move_count(), 0, "resolving a refusal records nothing")
	check(session.has_active_tile(HUMAN), "the human still holds tiles after a refusal")
	check_eq(
		session.next_placement_index(),
		1,
		"a refused move consumes no placement index, so a retry is still index 1"
	)


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
	check_eq(
		session.deck_count(HUMAN), DECK_SIZE, "an invalid rotation consumes no deck tile"
	)


func test_the_wrong_player_cannot_move() -> void:
	var session: GameSessionState = _new_session(&"turn-f", 16)
	TurnManager.setup(session)
	var cell: Vector2i = _first_frontier(session.get_board())

	var result: PlacementResult = MoveCommitter.commit(session, AI, cell, 0)

	check(not result.accepted, "the inactive player must not be able to move")
	check_eq(result.rejection, NOT_PLAYERS_TURN, "the reason names turn ownership")
	check_eq(session.get_board().occupied_count(), 0, "nothing may be placed out of turn")
	check_eq(session.get_turn_state().turn_number, 1, "the turn must not advance")
	check_eq(session.deck_count(AI), DECK_SIZE, "an out-of-turn move consumes no deck tile")
	check_eq(
		session.next_placement_index(), 1, "an out-of-turn move consumes no placement index"
	)


func test_a_repeated_move_identifier_is_refused_before_anything_changes() -> void:
	var session: GameSessionState = _new_session(&"turn-g", 17)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()
	var first: PlacementResult = MoveCommitter.commit(session, HUMAN, _first_frontier(board), 0)
	check(first.was_committed(), "the first move must commit")
	check_eq(String(first.move_id), "move:turn-g:1:1", "the first placement is index 1")
	TurnManager.resolve(session, first)
	check_eq(session.next_placement_index(), 2, "the next placement of the turn is index 2")

	# Re-open turn 1 on the placement index the move already used, which is
	# exactly the state a retry of the first placement would present: ADR-010
	# section 9 keeps the identifier unique per placement, so this is the only
	# collision a caller can produce for a turn that is still open.
	var turn_state: TurnState = session.get_turn_state()
	turn_state.active_player_id = HUMAN
	turn_state.turn_number = 1
	turn_state.phase = TurnEnums.MatchPhase.AWAIT_ACTION

	var occupied_before: int = board.occupied_count()
	var ledger_before: int = session.get_ledger().size()
	var deck_before: int = session.deck_count(HUMAN)
	var retry_cell: Vector2i = _first_frontier(board)

	var repeat: PlacementResult = MoveCommitter.commit(session, HUMAN, retry_cell, 0)

	check(not repeat.accepted, "a move identifier may be committed at most once")
	check_eq(repeat.rejection, DUPLICATE_MOVE, "the reason names the duplicate move")
	check_eq(board.occupied_count(), occupied_before, "a refused retry places nothing")
	check_eq(session.get_ledger().size(), ledger_before, "a refused retry scores nothing")
	check_eq(session.deck_count(HUMAN), deck_before, "a refused retry consumes no deck tile")
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
	check_eq(session.deck_count(HUMAN), DECK_SIZE, "a finished match consumes no deck tile")
	check(session.is_over(), "the session reports the match is over")


func test_neither_player_holding_a_tile_while_the_pot_is_empty_ends_the_match() -> void:
	# ADR-010 section 7 condition 2 replaces ADR-003 section 7's two-consecutive
	# skip rule: the match ends when neither player holds a tile and the pot
	# cannot supply one. Two tiles with a deck of one each is the smallest board
	# that reaches it, because the pot is empty the moment both decks are dealt.
	var generation: TileGenerationRules = TileGenerationRules.new()
	generation.bag_size = 2
	var deck_rules: DeckRules = DeckRules.new()
	deck_rules.deck_size = 1
	var session: GameSessionState = GameSessionState.create(
		&"turn-i", 19, ScoringRules.create_default(), generation, deck_rules
	)
	check_not_null(session, "a two-tile match must be constructible")
	TurnManager.setup(session)
	var board: BoardState = session.get_board()

	check_eq(session.deck_count(HUMAN), 1, "a deck_size of one deals one tile to each player")
	check_eq(session.deck_count(AI), 1, "a deck_size of one deals one tile to each player")
	check_eq(session.remaining_tile_count(), 0, "the whole pot is dealt at setup")
	check_eq(
		TurnManager.detect_end_reason(session),
		TurnEnums.EndReason.NONE,
		"the match continues while a player still holds a tile"
	)

	var human_move: PlacementResult = MoveCommitter.commit(session, HUMAN, _first_frontier(board), 0)
	check(human_move.was_committed(), "the human's move must commit")
	check_eq(
		TurnManager.resolve(session, human_move),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"play continues because the rival still holds a tile"
	)
	check_eq(
		session.deck_count(HUMAN), 0, "the human's only tile left the deck when it was placed"
	)

	var ai_move: PlacementResult = MoveCommitter.commit(session, AI, _first_frontier(board), 0)
	check(ai_move.was_committed(), "the AI's move must commit")
	check_eq(
		TurnManager.resolve(session, ai_move),
		TurnEnums.MatchPhase.GAME_OVER,
		"the match ends when neither player holds a tile and the pot is empty"
	)

	var turn_state: TurnState = session.get_turn_state()
	check_eq(
		session.get_end_reason(),
		TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED,
		"the end reason is the empty pot"
	)
	check_eq(board.occupied_count(), 2, "both supplied tiles were placed")
	check_eq(session.deck_count(HUMAN), 0, "no player holds a tile at the end")
	check_eq(session.deck_count(AI), 0, "no player holds a tile at the end")
	check(not session.holds_any_tile(), "the end condition is that neither player holds a tile")
	check_eq(session.remaining_tile_count(), 0, "the pot is exhausted")
	check_eq(
		turn_state.turn_number,
		2,
		"the match ends on the turn that emptied the decks without opening another"
	)
	check_eq(
		turn_state.consecutive_no_tile_skips,
		0,
		"no skip count is read: ADR-010 section 7 removed the two-consecutive-skip rule"
	)
	check_eq(
		session.get_outcome(),
		TurnEnums.outcome_for_scores(
			session.score_for(HUMAN), session.score_for(AI), TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED
		),
		"the outcome must match the committed totals"
	)


func test_the_match_ends_when_every_cell_is_filled() -> void:
	# ADR-010 section 7 condition 1: the match ends after the placement that fills
	# the board. The placements run through the ordinary commit-and-resolve path
	# and close their own turns, because a placement never ends a turn by itself.
	var session: GameSessionState = _new_session(&"turn-o", 24)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()
	var placements: int = 0

	while (
		placements < BoardEnums.CELL_COUNT
		and not session.is_over()
		and not board.is_full()
	):
		var frontier: Array[Vector2i] = board.get_frontier_cells()
		if frontier.is_empty():
			break
		var result: PlacementResult = MoveCommitter.commit(
			session, session.get_turn_state().active_player_id, frontier[0], 0
		)
		if not result.was_committed():
			break
		TurnManager.resolve(session, result)
		placements += 1

	check_eq(placements, BoardEnums.CELL_COUNT, "every cell must be filled exactly once")
	check(board.is_full(), "the loop must end with the board full")
	check(session.is_over(), "the match must be over")
	check_eq(
		session.get_turn_state().phase,
		TurnEnums.MatchPhase.GAME_OVER,
		"filling the board moves the match to GAME_OVER"
	)
	check_eq(
		session.get_end_reason(),
		TurnEnums.EndReason.BOARD_FULL,
		"filling the board is end condition 1 (ADR-010 section 7)"
	)
	check_eq(
		TurnManager.detect_end_reason(session),
		TurnEnums.EndReason.BOARD_FULL,
		"the end-condition check reports the full board"
	)
	check_eq(session.move_count(), BoardEnums.CELL_COUNT, "every placement joins the history")
	check_eq(
		session.remaining_tile_count()
			+ session.deck_count(HUMAN)
			+ session.deck_count(AI)
			+ board.occupied_count(),
		BoardEnums.CELL_COUNT,
		"a full board must still account for every tile exactly once"
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
	check_eq(
		TurnManager.resolve(session, human_move),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"the human's placement leaves their turn open"
	)
	# ADR-010 section 4: the human hands over with an explicit end-turn.
	check_eq(
		TurnManager.end_turn(session),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"the human's turn ends and the rival takes its turn"
	)
	var ai_cell: Vector2i = _first_frontier(board)
	var ai_move: PlacementResult = MoveCommitter.commit(session, AI, ai_cell, 0)

	check(human_move.was_committed(), "the human's move commits through the transaction")
	check(ai_move.was_committed(), "the AI's move commits through the same transaction")
	check_eq(
		human_move.move_id,
		StringName("move:turn-k:1:1"),
		"the human's opening placement is turn 1, placement 1"
	)
	check_eq(
		ai_move.move_id,
		StringName("move:turn-k:2:1"),
		"the rival's opening placement is turn 2, placement 1"
	)
	check_eq(session.move_count(), 2, "both moves are recorded in history")

	# The same rule refuses both players equally: a cell touching nothing.
	var off_board_cell: Vector2i = _isolated_cell(board)
	if off_board_cell != Vector2i(-1, -1):
		TurnManager.resolve(session, ai_move)
		check_eq(
			TurnManager.end_turn(session),
			TurnEnums.MatchPhase.AWAIT_ACTION,
			"the rival's turn ends before the human's next turn"
		)
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
	check_eq(session.remaining_tile_count(), POT_AFTER_SETUP, "the remaining count is public")
	check_eq(
		session.get_tile_source().get_draw_index(),
		TILES_DEALT_AT_SETUP,
		"twelve tiles were dealt, and the pot still holds the rest undrawn"
	)

	# ADR-010 section 4: a placement commits a tile the player already holds, so
	# the tile the human would place is a member of their own deck.
	var human_tile: TileDefinition = session.active_tile_for(HUMAN)
	check_not_null(human_tile, "the active player's own tile is known to them")
	check(human_tile.is_valid(), "the active player's own tile is a usable tile")
	check(
		session.holds_deck_tile(HUMAN, human_tile.tile_id),
		"the tile the human would place is one of their own deck"
	)

	# ADR-010 section 2 gives both players a deck, so the rival's deck is a known
	# size while its contents are the rival's own business.
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival's deck size is known")
	check_eq(
		session.deck_for(AI).size(), DECK_SIZE, "the rival's deck exists across the turn boundary"
	)


## Builds a standard-rules session at MATCH_SETUP.
func _new_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = GameSessionState.create(
		match_id, seed, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(session, "the session must be constructible")
	return session


## Returns one player's deck as a list of tile identities, in deal order.
func _deck_ids(session: GameSessionState, player_id: StringName) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for tile: TileDefinition in session.deck_for(player_id):
		if tile != null:
			ids.append(String(tile.tile_id))
	return ids


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
