class_name TurnManager
extends RefCounted

## The Phase 1 match lifecycle state machine (ADR-003 sections 1, 2, 6, and 8;
## ADR-010 sections 2, 5, 6, and 7 as ADR-011 section 8 records them; ADR-011
## sections 6, 7, and 8).
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
## ADR-010 and ADR-011 change what a turn is, not the phase names:
##
## - `MATCH_SETUP` deals each player a deck of `deck_size` tiles instead of one
##   active tile per player (ADR-010 section 2);
## - ADR-011 section 7 makes a turn EXACTLY ONE move: one committed line or one
##   swap, and that move ends the turn and passes play. The explicit end-turn
##   action of ADR-010 section 4 is removed, so `resolve()` closes the turn
##   instead of leaving it open, and there is no `end_turn()` entry point;
## - a swap is the other whole-turn move (ADR-011 section 6), resolved through
##   `resolve_swap()`, which consumes the turn and cannot score;
## - the active player's deck is refilled by the number of tiles the move used and
##   then topped back up to `deck_size` at the turn boundary, never mid-turn
##   (ADR-011 section 8, ADR-010 section 5);
## - the match ends when the board is full, or when neither player holds a tile
##   and the pot cannot supply one (ADR-010 section 7, which ADR-011 section 9
##   keeps), in place of ADR-003 section 7's two-consecutive-skip rule.
##
## The human always takes the first turn (ADR-003 section 2). A turn is skipped
## only when its player cannot be supplied a tile at `TURN_START`, so cancelling
## an assembled line or retrying an illegal one never consumes a tile or a turn
## (ADR-003 section 5, ADR-011 section 5).
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


## Resolves one committed line, which ends the turn (ADR-011 section 7).
##
## Call this after `MoveCommitter.commit_line()`. A refused line leaves the match
## at `AWAIT_ACTION` with the deck and the turn position untouched, so an illegal
## line never consumes the turn (ADR-003 section 5, ADR-011 section 5) and the
## player may reassemble.
##
## ADR-011 section 7 makes a turn exactly one move, so a committed line closes the
## turn here: the deck is refilled by the number of tiles the line used
## (section 8), the end conditions are checked (ADR-010 section 7, which
## ADR-011 section 9 keeps), and play passes to the opponent. This supersedes
## ADR-010 section 3's "one or more placements ended by an explicit End Turn
## action"; there is no end-turn entry point any more, so a caller cannot close
## the same turn twice.
static func resolve(session: GameSessionState, result: LineResult) -> int:
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

	if result == null or not result.was_committed():
		# ADR-011 section 5: a rejected line changes nothing at all, so the player
		# keeps their tiles, the turn stays open, and they may reassemble. The
		# phase is never moved into `RESOLVE_MOVE`, because no move is being
		# resolved: a refusal must not look like a move in flight (ADR-003
		# section 1), which is how `resolve_swap` already answers a refused swap.
		return TurnEnums.MatchPhase.AWAIT_ACTION

	turn_state.phase = TurnEnums.MatchPhase.RESOLVE_MOVE

	# ADR-011 section 8: a line consumes several deck tiles, so the turn boundary
	# refills by as many tiles as the line used.
	return _complete_turn(session, result.staged_count())


## Resolves one swap, which ends the turn (ADR-011 section 6).
##
## `swapped_count` is how many tiles the swapping player returned, which is the
## number the deck is refilled by (section 8). Pass 0 or a negative value for a
## refused swap: the turn is not consumed then, exactly as a rejected line leaves
## the turn open, because ADR-011 section 6 requires a refused swap to leave the
## player with their tiles.
##
## A swap cannot place a tile and cannot score (section 6): nothing is written to
## the board, the ledger, or the history by this function, and only a positive
## `swapped_count` closes the turn.
static func resolve_swap(session: GameSessionState, swapped_count: int) -> int:
	if session == null:
		push_error("TurnManager.resolve_swap: a session is required.")
		return TurnEnums.MatchPhase.MATCH_SETUP

	var turn_state: TurnState = session.get_turn_state()
	if not turn_state.is_awaiting_action():
		push_error(
			"TurnManager.resolve_swap: no move is awaiting resolution; the match is at %s."
			% TurnEnums.phase_name(turn_state.phase)
		)
		return turn_state.phase

	if swapped_count <= 0:
		# A refused swap keeps the turn and the player's tiles (section 6).
		return TurnEnums.MatchPhase.AWAIT_ACTION

	turn_state.phase = TurnEnums.MatchPhase.RESOLVE_MOVE
	return _complete_turn(session, swapped_count)


## Applies the turn boundary of ADR-010 sections 5 to 7 and ADR-011 section 8.
##
## This is the one place a turn is closed, and ADR-011 section 7 gives it exactly
## two callers: `resolve` for a committed line and `resolve_swap` for a swap.
## Keeping the boundary in one function is what stops the phases of ADR-003
## section 1 from having two different orders (AGENTS.md section 15).
##
## Order: refill the deck by the tiles the move used (ADR-011 section 8), top it
## back up to `deck_size` (ADR-010 section 5), check the end conditions
## (ADR-010 section 7), and only then hand play to the other player and increment
## the turn number.
static func _complete_turn(session: GameSessionState, consumed_tiles: int) -> int:
	var turn_state: TurnState = session.get_turn_state()
	var player_id: StringName = turn_state.active_player_id
	if not TurnEnums.is_valid_player_id(player_id):
		push_error(
			"TurnManager: the match has no valid active player to end a turn for."
		)
		return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)

	turn_state.phase = TurnEnums.MatchPhase.TURN_END

	# ADR-011 section 8: a line (or a swap) consumes several deck tiles, so the
	# deck is refilled by as many tiles as the move used, capped by the pot.
	session.refill_deck_by(player_id, consumed_tiles)

	# ADR-010 section 5: the deck is then topped back up to `deck_size` at the
	# turn boundary, never mid-turn.
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
			"TurnManager: '%s' has no opponent to hand the turn to."
			% String(player_id)
		)
		return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)

	turn_state.active_player_id = next_player
	turn_state.turn_number += 1
	return _enter_turn_start(session)


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
## ADR-003 section 6 disables human input while the AI turn is active. ADR-011
## section 7 gives the human exactly two whole-turn moves, a committed line and a
## swap, and both are submitted while this is true; there is no separate end-turn
## command, because committing or swapping ends the turn itself.
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
## tiles and the pot cannot supply one. Such a turn still hands play to the other
## player and increments the turn number: it is not a pause, it is a turn that
## cannot be played. ADR-011 section 6's swap is the ordinary way out of a hand
## that cannot form a line, so this automatic handover is reached only when the
## pot cannot supply a swap either (ADR-011 section 9).
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
