class_name TurnManager
extends RefCounted

## The Phase 1 match lifecycle state machine (ADR-003 sections 1, 2, 6, and 8;
## ADR-010 sections 2 to 7).
##
## ADR-003 section 1 states that the rules state machine, not UI animation, owns
## match progression, and section "Data ownership" gives `TurnManager` ownership
## of the active player, the turn number, and phase transitions. This type is
## that state machine. It is stateless itself: every method takes the session and
## drives the session's `TurnState`, so there is exactly one mutable copy of the
## turn position.
##
## Phase flow (ADR-003 section 1):
##
##     MATCH_SETUP -> TURN_START -> AWAIT_ACTION -> RESOLVE_MOVE
##                        ^                              |
##                        +---------- TURN_END <--------+
##
##     TURN_END -> GAME_OVER when an end condition is met
##
## ADR-010 changes what a turn is, not the phase names:
##
## - `MATCH_SETUP` deals each player a deck of `deck_size` tiles instead of one
##   active tile per player (ADR-010 section 2);
## - a turn holds ONE OR MORE placements, so `resolve()` keeps the turn open in
##   `AWAIT_ACTION` after a committed placement (ADR-010 section 3 step 9);
## - the turn ends on the explicit `end_turn()` action, or automatically when the
##   active player holds no tiles and the pot cannot supply one
##   (ADR-010 section 4);
## - the active player's deck is topped back up to `deck_size` at the turn
##   boundary, never mid-turn (ADR-010 section 5);
## - the match ends when the board is full, or when neither player holds a tile
##   and the pot cannot supply one (ADR-010 section 7), in place of ADR-003
##   section 7's two-consecutive-skip rule.
##
## The human always takes the first turn (ADR-003 section 2). A turn is skipped
## only when its player cannot be supplied a tile at `TURN_START`, so canceling a
## preview or retrying an illegal placement never consumes a tile or a turn
## (ADR-003 section 5).
##
## Every method returns the phase the match now sits in, so a caller can branch
## without inspecting internals; the full details stay on the session.

## Handovers one `TURN_START` may perform before it gives up (ADR-010 section 4).
##
## ADR-010 section 4 makes a turn end automatically when its player holds no
## tiles and the pot cannot supply one. With the Phase 1 two-player rules at most
## one handover can happen before end condition 2 of ADR-010 section 7 fires, so
## the loops below are bounded rather than endless; the bound exists so every
## function provably returns on every path, which a `while true` loop does not
## guarantee to the static analyzer.
const MAX_TURN_HANDOVERS: int = 4


## Deals both decks and opens the first turn (ADR-010 section 2).
##
## Moves the match from `MATCH_SETUP` to `AWAIT_ACTION` with the human holding a
## stocked deck. Returns the current phase unchanged, with an error, when the
## match is not sitting at `MATCH_SETUP`, so setup cannot silently restart a live
## match.
static func setup(session: GameSessionState) -> int:
	if session == null:
		push_error("TurnManager.setup: a session is required.")
		return TurnEnums.MatchPhase.MATCH_SETUP

	var turn_state: TurnState = session.get_turn_state()
	if turn_state.phase != TurnEnums.MatchPhase.MATCH_SETUP:
		push_error(
			"TurnManager.setup: the match is at %s, not MATCH_SETUP."
			% TurnEnums.phase_name(turn_state.phase)
		)
		return turn_state.phase

	# ADR-010 section 2: the human's deck is filled first, then the AI's, in the
	# fixed deal order, so a replay reproduces the same decks from the same seed
	# (ADR-004 section 3).
	if not session.deal_decks():
		push_error("TurnManager.setup: the opening decks could not be dealt.")
		return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)

	# ADR-003 section 2: the human takes the first turn in the Phase 1 demo.
	turn_state.active_player_id = TurnEnums.HUMAN_PLAYER_ID
	turn_state.turn_number = 1
	turn_state.consecutive_no_tile_skips = 0
	turn_state.last_skip_reason = TurnEnums.SkipReason.NONE
	return _enter_turn_start(session)


## Resolves one committed placement without closing the turn (ADR-010 section 3).
##
## Call this after `MoveCommitter.commit()`. A refused or canceled move leaves the
## match at `AWAIT_ACTION` with the deck untouched, so an invalid action never
## consumes the turn (ADR-003 section 5).
##
## ADR-010 sections 3 and 9 make a turn a sequence of independent committed
## placements rather than one transaction, so a committed placement keeps the
## match in `AWAIT_ACTION` and the caller repeats it with any remaining deck tile
## or ends the turn through `end_turn()`. The only exceptions are the two end
## conditions of ADR-010 section 7, which end the match from the placement that
## meets them, and an emptied deck, which ends the turn automatically because that
## player has no legal placement for the rest of the turn (ADR-010 sections 4 and
## 6). An empty deck is empty whatever the pot still holds: the deck does not
## refill mid-turn, so the pot cannot rescue the turn it is in.
##
## That automatic end applies the whole turn boundary, exactly as `end_turn()`
## does: the deck is refilled, the end conditions are checked, and the other
## player is then seated with their turn position reset. A caller that also closes
## the turn it has just resolved therefore closes the NEW turn instead, so the
## boundary runs twice. That consumes an extra turn number (ADR-010 section 4),
## and while one player can no longer be supplied from the pot it hands that
## player's turn straight back, leaving the caller with the turn it was about to
## take untaken. The two cases are distinguishable only through the turn position,
## because seating a player resets `TurnState.placements_this_turn` (ADR-010
## section 9): a caller that reads a reset count is looking at a new turn and must
## not close it again.
static func resolve(session: GameSessionState, result: PlacementResult) -> int:
	if session == null:
		push_error("TurnManager.resolve: a session is required.")
		return TurnEnums.MatchPhase.MATCH_SETUP

	var turn_state: TurnState = session.get_turn_state()
	if not turn_state.is_awaiting_action():
		push_error(
			"TurnManager.resolve: no move is awaiting resolution; the match is at %s."
			% TurnEnums.phase_name(turn_state.phase)
		)
		return turn_state.phase

	turn_state.phase = TurnEnums.MatchPhase.RESOLVE_MOVE

	if result == null or not result.was_committed():
		# ADR-003 section 5: the player may retry until a legal move is committed.
		turn_state.phase = TurnEnums.MatchPhase.AWAIT_ACTION
		return TurnEnums.MatchPhase.AWAIT_ACTION

	# ADR-010 section 7: the match ends after resolving the placement that fills
	# the board or leaves both players with nothing to play.
	var reason: int = detect_end_reason(session)
	if reason != TurnEnums.EndReason.NONE:
		_finish(session, reason)
		return TurnEnums.MatchPhase.GAME_OVER

	# ADR-010 section 3 step 9: the turn stays open so the active player may place
	# any remaining deck tile, or end the turn.
	if session.has_active_tile(turn_state.active_player_id):
		turn_state.phase = TurnEnums.MatchPhase.AWAIT_ACTION
		return TurnEnums.MatchPhase.AWAIT_ACTION

	# ADR-010 section 4: the deck is empty, so the turn ends automatically. The
	# turn boundary is applied directly here rather than through `end_turn()`:
	# this resolution still holds the phase at `RESOLVE_MOVE`, and routing it
	# through the explicit-action entry point would refuse the boundary and leave
	# the match stalled in `RESOLVE_MOVE` after the first deck was emptied.
	return _complete_turn(session)


## Ends the active player's turn (ADR-010 section 4).
##
## This is the explicit end-turn action of ADR-010 section 4. `resolve()` applies
## the same boundary automatically for a player whose last placement emptied their
## deck, so this entry point is for the player who chooses to stop. It is available
## throughout the action phase, including before any placement, so a turn may
## contain zero placements (ADR-010 section 4's deliberate relaxation of ADR-003
## section 5).
##
## Order is the one ADR-010 section 3 step 10 fixes: refill the deck at the turn
## boundary (section 5), check the end conditions (section 7), and only then hand
## play to the other player and increment the turn number.
static func end_turn(session: GameSessionState) -> int:
	if session == null:
		push_error("TurnManager.end_turn: a session is required.")
		return TurnEnums.MatchPhase.MATCH_SETUP

	var turn_state: TurnState = session.get_turn_state()
	if turn_state.is_stopped():
		return turn_state.phase
	if not turn_state.is_awaiting_action():
		push_error(
			"TurnManager.end_turn: only an open action phase can be ended; the match is at %s."
			% TurnEnums.phase_name(turn_state.phase)
		)
		return turn_state.phase
	return _complete_turn(session)


## Applies the turn boundary of ADR-010 sections 3 to 7.
##
## This is the one place a turn is closed. It is reached by the explicit end-turn
## action (`end_turn`), by `resolve` when the active player's deck was emptied by
## the placement it just committed (ADR-010 section 4), and by the application
## layer's forced handover (`end_turn_for`). Keeping the boundary in one function
## is what stops the phases of ADR-003 section 1 from having two different orders
## (AGENTS.md section 15).
##
## Order is the one ADR-010 section 3 step 10 fixes: refill the deck at the turn
## boundary (section 5), check the end conditions (section 7), and only then hand
## play to the other player and increment the turn number.
static func _complete_turn(session: GameSessionState) -> int:
	var turn_state: TurnState = session.get_turn_state()
	var player_id: StringName = turn_state.active_player_id
	if not TurnEnums.is_valid_player_id(player_id):
		push_error(
			"TurnManager: the match has no valid active player to end a turn for."
		)
		return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)

	turn_state.phase = TurnEnums.MatchPhase.TURN_END

	# ADR-010 section 5: the deck is topped back up at the turn boundary, never
	# after an individual placement, which is what bounds a turn at `deck_size`
	# placements.
	session.top_up_deck(player_id)

	# ADR-010 section 7: an end condition is checked after the refill, so a deck
	# that the pot can still supply keeps the match running.
	var reason: int = detect_end_reason(session)
	if reason != TurnEnums.EndReason.NONE:
		_finish(session, reason)
		return TurnEnums.MatchPhase.GAME_OVER

	var next_player: StringName = TurnEnums.opponent_of(player_id)
	if not TurnEnums.is_valid_player_id(next_player):
		# There is no third player, so this is an implementation error rather
		# than a game outcome (ADR-003 section 7 condition 3).
		push_error(
			"TurnManager.end_turn: '%s' has no opponent to hand the turn to."
			% String(player_id)
		)
		return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)

	turn_state.active_player_id = next_player
	turn_state.turn_number += 1
	return _enter_turn_start(session)


## Ends the active player's turn on their behalf (ADR-010 section 4).
##
## The application layer uses this when the human's turn must close while the
## rival is seated as the active player, so a stalled rival cannot leave the
## match stuck. The turn boundary itself is unchanged: `end_turn()` still owns the
## refill, the end conditions, and the handover.
static func end_turn_for(session: GameSessionState, player_id: StringName) -> int:
	if session == null:
		push_error("TurnManager.end_turn_for: a session is required.")
		return TurnEnums.MatchPhase.MATCH_SETUP
	var turn_state: TurnState = session.get_turn_state()
	if not TurnEnums.is_valid_player_id(player_id) or turn_state.active_player_id != player_id:
		return turn_state.phase
	return end_turn(session)


## Stops the match in the recoverable error state (ADR-003 section 6).
##
## ADR-003 section 7 condition 3 marks a match stopped this way as incomplete with
## no winner, so this awards no result other than `INCOMPLETE`. Development code
## uses it when a failure cannot be silently skipped.
static func fail_recovery(session: GameSessionState, reason: int) -> int:
	if session == null:
		push_error("TurnManager.fail_recovery: a session is required.")
		return TurnEnums.MatchPhase.MATCH_SETUP
	var end_reason: int = reason
	if end_reason == TurnEnums.EndReason.NONE:
		end_reason = TurnEnums.EndReason.RULES_FAILURE
	session.finish(TurnEnums.MatchOutcome.INCOMPLETE, end_reason)
	var turn_state: TurnState = session.get_turn_state()
	turn_state.phase = TurnEnums.MatchPhase.RECOVERY_ERROR
	return TurnEnums.MatchPhase.RECOVERY_ERROR


## Returns the end condition the match has reached, or `NONE` (ADR-010 section 7).
##
## This is the single definition of the end conditions, used after a resolved
## placement, at every turn boundary, and while opening a turn:
##
## 1. the board is full (all 144 cells hold a committed tile);
## 2. nothing is left to play: neither player holds a tile and the pot cannot
##    supply one.
##
## ADR-010 section 7 replaces ADR-003 section 7's two-consecutive-skip rule; no
## skip counter is read here, because a player who cannot be supplied ends their
## turn and the match continues until both players are out of tiles.
static func detect_end_reason(session: GameSessionState) -> int:
	if session == null:
		return TurnEnums.EndReason.NONE

	# Condition 1: all 144 cells hold a committed tile.
	if session.get_board().is_full():
		return TurnEnums.EndReason.BOARD_FULL

	# Condition 2: neither player holds a tile and the pot cannot supply one.
	if session.holds_any_tile():
		return TurnEnums.EndReason.NONE
	var source: TileSource = session.get_tile_source()
	var source_exhausted: bool = source != null and source.is_exhausted()
	if source_exhausted:
		return TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED

	return TurnEnums.EndReason.NONE


## Returns true when the human may act: `AWAIT_ACTION` on the human's turn.
##
## ADR-003 section 6 disables human input while the AI turn is active. ADR-010
## section 4 allows the human to end their turn, so this is the whole condition
## for accepting human input; ending the turn is a separate command.
static func is_awaiting_human_action(session: GameSessionState) -> bool:
	if session == null:
		return false
	var turn_state: TurnState = session.get_turn_state()
	return (
		turn_state.is_awaiting_action()
		and turn_state.active_player_id == TurnEnums.HUMAN_PLAYER_ID
	)


## Returns true when it is the AI's turn to supply a move.
static func is_awaiting_ai_action(session: GameSessionState) -> bool:
	if session == null:
		return false
	var turn_state: TurnState = session.get_turn_state()
	return (
		turn_state.is_awaiting_action()
		and turn_state.active_player_id == TurnEnums.AI_PLAYER_ID
	)


## Runs `TURN_START`: stocks the active player's deck and opens the action phase.
##
## ADR-010 section 3 step 2 ensures the active player's deck is stocked before the
## action phase opens. The deck was already topped up at the previous turn
## boundary (section 5), so this is a no-op except for the match's opening turn,
## which the `MATCH_SETUP` deal has already covered.
##
## ADR-010 section 4 ends a turn automatically when the active player holds no
## tiles and the pot cannot supply one, because that player has no legal
## placement. Such a turn still hands play to the other player and increments the
## turn number: it is not a pause, it is a turn that cannot be played.
##
## The loop is bounded rather than endless. With the Phase 1 two-player rules at
## most one handover can happen before end condition 2 of ADR-010 section 7
## fires, because both decks are empty by then and the pot that could not supply
## one cannot supply the other.
static func _enter_turn_start(session: GameSessionState) -> int:
	var turn_state: TurnState = session.get_turn_state()

	for _attempt: int in range(MAX_TURN_HANDOVERS):
		turn_state.phase = TurnEnums.MatchPhase.TURN_START

		var reached_end: int = detect_end_reason(session)
		if reached_end != TurnEnums.EndReason.NONE:
			_finish(session, reached_end)
			return TurnEnums.MatchPhase.GAME_OVER

		var player_id: StringName = turn_state.active_player_id
		if not TurnEnums.is_valid_player_id(player_id):
			push_error(
				"TurnManager: the match has no valid active player to start a turn for."
			)
			return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)

		# ADR-010 section 3 step 2: the deck is stocked before the action phase.
		session.top_up_deck(player_id)
		if session.has_active_tile(player_id):
			turn_state.consecutive_no_tile_skips = 0
			turn_state.last_skip_reason = TurnEnums.SkipReason.NONE
			turn_state.phase = TurnEnums.MatchPhase.AWAIT_ACTION
			return TurnEnums.MatchPhase.AWAIT_ACTION

		# ADR-010 section 4: no tile could be supplied, so this turn ends here.
		# The count is a diagnostic and a save field (ADR-003 section 9), never a
		# rule input: ADR-010 section 7 removed the two-consecutive-skip rule.
		turn_state.consecutive_no_tile_skips += 1
		turn_state.last_skip_reason = TurnEnums.SkipReason.NO_TILE_AVAILABLE

		var next_player: StringName = TurnEnums.opponent_of(player_id)
		if not TurnEnums.is_valid_player_id(next_player):
			push_error(
				"TurnManager: '%s' has no opponent to hand an empty turn to."
				% String(player_id)
			)
			return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)
		turn_state.active_player_id = next_player
		turn_state.turn_number += 1

	# Reached only when the bounded loop above is exhausted, which ADR-010
	# section 7 prevents by ending the match once neither player can be supplied.
	return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)


## Marks the match over, deriving the outcome from committed totals.
##
## ADR-003 section 8: the winner is whoever has the greater committed total, equal
## totals are a draw, and there is no bonus, penalty, multiplier, or tie-breaker.
## A deck holding unplayed tiles at the end of the match carries no penalty
## (ADR-010 section 8). The outcome is always derived here rather than supplied by
## a caller, so a result can never disagree with the ledger.
static func _finish(session: GameSessionState, reason: int) -> void:
	var outcome: int = TurnEnums.outcome_for_scores(
		session.score_for(TurnEnums.HUMAN_PLAYER_ID),
		session.score_for(TurnEnums.AI_PLAYER_ID),
		reason
	)
	session.finish(outcome, reason)
	var turn_state: TurnState = session.get_turn_state()
	turn_state.phase = TurnEnums.MatchPhase.GAME_OVER
