class_name TurnManager
extends RefCounted

## The Phase 1 match lifecycle state machine (ADR-003 sections 1 to 8).
##
## ADR-003 section 1 states that the rules state machine, not UI animation, owns
## match progression, and section "Data ownership" gives `TurnManager` ownership
## of the active player, the turn number, phase transitions, and skip counting.
## This type is that state machine. It is stateless itself: every method takes the
## session and drives the session's `TurnState`, so there is exactly one mutable
## copy of the turn position.
##
## Phase flow (ADR-003 section 1):
##
##     MATCH_SETUP -> TURN_START -> AWAIT_ACTION -> RESOLVE_MOVE
##                        ^                              |
##                        +---------- TURN_END <--------+
##
##     TURN_END -> GAME_OVER when an end condition is met
##
## The human always takes the first turn (ADR-003 section 2). A tile is drawn at
## its owner's `TURN_START` and only when that player has none (ADR-003 section 3
## step 2, ADR-004 section 6), so canceling a preview or retrying an illegal
## placement never consumes a tile or a turn (ADR-003 section 5).
##
## Every method returns the phase the match now sits in, so a caller can branch
## without inspecting internals; the full details stay on the session.

## Returns the phase after setting up a fresh match and opening the first turn.
##
## Moves the match from `MATCH_SETUP` to `AWAIT_ACTION` with the human holding a
## tile. Returns the current phase unchanged, with an error, when the match is not
## sitting at `MATCH_SETUP`, so setup cannot silently restart a live match.
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

	# ADR-003 section 2: the human takes the first turn in the Phase 1 demo.
	turn_state.active_player_id = TurnEnums.HUMAN_PLAYER_ID
	turn_state.turn_number = 1
	turn_state.consecutive_no_tile_skips = 0
	turn_state.last_skip_reason = TurnEnums.SkipReason.NONE
	return _enter_turn_start(session)


## Resolves a committed move and advances the match (ADR-003 section 3).
##
## Call this after `MoveCommitter.commit()`. A refused or canceled move leaves the
## match at `AWAIT_ACTION` with the active tile intact, so an invalid action never
## consumes the turn (ADR-003 section 5). A committed move advances the turn
## number, hands over to the other player, ends the match if an end condition is
## now met (ADR-003 section 7), or opens the next turn.
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

	var reason: int = detect_end_reason(session)
	turn_state.phase = TurnEnums.MatchPhase.TURN_END
	if reason != TurnEnums.EndReason.NONE:
		_finish(session, reason)
		return TurnEnums.MatchPhase.GAME_OVER

	# ADR-003 section 3 step 11: switch active player and increment the turn.
	var next_player: StringName = TurnEnums.opponent_of(turn_state.active_player_id)
	if not TurnEnums.is_valid_player_id(next_player):
		# There is no third player, so this is an implementation error rather
		# than a game outcome (ADR-003 section 7 condition 3).
		push_error(
			"TurnManager.resolve: '%s' has no opponent to hand the turn to."
			% String(turn_state.active_player_id)
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


## Returns the end condition the match has reached, or `NONE` (ADR-003 section 7).
##
## This is the single definition of the end conditions, used both after a resolved
## move and while opening a turn.
static func detect_end_reason(session: GameSessionState) -> int:
	if session == null:
		return TurnEnums.EndReason.NONE
	var turn_state: TurnState = session.get_turn_state()

	# Condition 1: all 144 cells hold a committed tile.
	if session.get_board().is_full():
		return TurnEnums.EndReason.BOARD_FULL

	# Condition 2: neither player holds a tile, the source cannot supply one, and
	# both players have recorded consecutive automatic NO_TILE_AVAILABLE skips.
	var no_active_tiles: bool = (
		not session.has_active_tile(TurnEnums.HUMAN_PLAYER_ID)
		and not session.has_active_tile(TurnEnums.AI_PLAYER_ID)
	)
	var source: TileSource = session.get_tile_source()
	var source_exhausted: bool = source != null and source.is_exhausted()
	if (
		no_active_tiles
		and source_exhausted
		and turn_state.consecutive_no_tile_skips >= TurnEnums.MAX_CONSECUTIVE_SKIPS
	):
		return TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED

	return TurnEnums.EndReason.NONE


## Returns true when the human may act: `AWAIT_ACTION` on the human's turn.
##
## ADR-003 section 6 disables human input while the AI turn is active, and Phase 1
## has no voluntary pass, so this is the whole condition for accepting human
## input.
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


## Runs `TURN_START`: supplies the active player's tile and opens the action phase.
##
## ADR-003 section 3 step 2 and ADR-004 section 6: draw only when the active player
## has no tile, and treat drawing plus assignment as one atomic change. When no
## tile can be supplied, ADR-003 section 5 skips the turn with reason
## `NO_TILE_AVAILABLE`; two consecutive skips end the match through
## `detect_end_reason`, which is why the skip is counted before the end check.
##
## A skipped turn still increments the turn number, because it hands play to the
## other player and is only skipped because supply failed, not because the match
## paused.
##
## The loop is bounded rather than endless: ADR-003 section 5 ends the match
## after `MAX_CONSECUTIVE_SKIPS` skips, so the bound cannot be exhausted in a real
## match. It exists so this function provably returns on every path, which a
## `while true` loop does not guarantee to the static analyzer.
static func _enter_turn_start(session: GameSessionState) -> int:
	var turn_state: TurnState = session.get_turn_state()

	for _attempt: int in range(TurnEnums.MAX_CONSECUTIVE_SKIPS + 1):
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

		if session.has_active_tile(player_id):
			# ADR-003 section 4: the active tile survives cancel and resume, so a
			# player who already holds one is never dealt a replacement.
			turn_state.consecutive_no_tile_skips = 0
			turn_state.last_skip_reason = TurnEnums.SkipReason.NONE
			turn_state.phase = TurnEnums.MatchPhase.AWAIT_ACTION
			return TurnEnums.MatchPhase.AWAIT_ACTION

		var source: TileSource = session.get_tile_source()
		var drawn: TileDefinition = null
		if source != null:
			drawn = source.draw()
		if drawn != null:
			if not session.set_active_tile(player_id, drawn):
				push_error(
					"TurnManager: the drawn tile could not be assigned to '%s'."
					% String(player_id)
				)
				return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)
			turn_state.consecutive_no_tile_skips = 0
			turn_state.last_skip_reason = TurnEnums.SkipReason.NONE
			turn_state.phase = TurnEnums.MatchPhase.AWAIT_ACTION
			return TurnEnums.MatchPhase.AWAIT_ACTION

		# No tile could be supplied, so this turn is skipped (ADR-003 section 5).
		turn_state.consecutive_no_tile_skips += 1
		turn_state.last_skip_reason = TurnEnums.SkipReason.NO_TILE_AVAILABLE

		var skip_end: int = detect_end_reason(session)
		if skip_end != TurnEnums.EndReason.NONE:
			_finish(session, skip_end)
			return TurnEnums.MatchPhase.GAME_OVER

		var next_player: StringName = TurnEnums.opponent_of(player_id)
		if not TurnEnums.is_valid_player_id(next_player):
			push_error(
				"TurnManager: '%s' has no opponent to hand a skipped turn to."
				% String(player_id)
			)
			return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)
		turn_state.active_player_id = next_player
		turn_state.turn_number += 1

	# Reached only when the bounded loop above is exhausted, which ADR-003
	# section 5 prevents by ending the match after MAX_CONSECUTIVE_SKIPS skips.
	return fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE)


## Marks the match over, deriving the outcome from committed totals.
##
## ADR-003 section 8: the winner is whoever has the greater committed total, equal
## totals are a draw, and there is no bonus, penalty, multiplier, or tie-breaker.
## The outcome is always derived here rather than supplied by a caller, so a
## result can never disagree with the ledger.
static func _finish(session: GameSessionState, reason: int) -> void:
	var outcome: int = TurnEnums.outcome_for_scores(
		session.score_for(TurnEnums.HUMAN_PLAYER_ID),
		session.score_for(TurnEnums.AI_PLAYER_ID),
		reason
	)
	session.finish(outcome, reason)
	var turn_state: TurnState = session.get_turn_state()
	turn_state.phase = TurnEnums.MatchPhase.GAME_OVER
