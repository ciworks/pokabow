class_name TurnEnums
extends RefCounted

## Match lifecycle vocabulary (ADR-003 sections 1, 2, 5, 7, and 8).
##
## This script holds the match-phase names, end reasons, skip reasons, outcome
## values, and the two Phase 1 player identities. It owns no state and touches no
## scene node, so the turn manager, save schema, results screen, and tests all
## share one vocabulary instead of re-declaring strings.
##
## Authority notes:
## - The Phase 1 match phases are fixed by ADR-003 section 1. `SPLASH` is a
##   presentation state owned by the app shell, not a rules phase, so it is
##   deliberately absent here.
## - `RECOVERY_ERROR` is the unrecoverable rules failure of ADR-003 section 7
##   condition 3.
## - The human takes the first turn in the Phase 1 demo (ADR-003 section 2), and
##   `player_ids()` returns them in that order.
## - Two consecutive automatic skips end the match (ADR-003 section 5).

## Rules phases of a Phase 1 match (ADR-003 section 1).
enum MatchPhase {
	## Players, board, scores, tile source, and seed are being initialized.
	MATCH_SETUP = 0,
	## The active player's tile is assigned or retrieved.
	TURN_START = 1,
	## A human preview/confirmation or AI decision is accepted.
	AWAIT_ACTION = 2,
	## Placement and scoring commit atomically.
	RESOLVE_MOVE = 3,
	## End conditions are checked and the next player is selected.
	TURN_END = 4,
	## Gameplay input is frozen and the final result is presented.
	GAME_OVER = 5,
	## Unrecoverable rules failure: the match is incomplete and has no winner.
	RECOVERY_ERROR = 6,
}

## Why a match ended (ADR-003 section 7).
enum EndReason {
	## The match has not ended.
	NONE = 0,
	## All 144 cells hold a committed tile.
	BOARD_FULL = 1,
	## Neither player has an active tile and the source cannot supply one.
	TILE_SOURCE_EXHAUSTED = 2,
	## Development and recovery only: an implementation error stopped the match.
	RULES_FAILURE = 3,
}

## Why a turn was given up without a placement (ADR-003 section 5).
enum SkipReason {
	## The turn was not skipped.
	NONE = 0,
	## No tile could be supplied to the active player.
	NO_TILE_AVAILABLE = 1,
}

## Final result of a match (ADR-003 section 8).
enum MatchOutcome {
	## The match is still being played.
	IN_PROGRESS = 0,
	## The human's committed total is greater.
	HUMAN_WIN = 1,
	## The AI's committed total is greater.
	AI_WIN = 2,
	## Both totals are equal. Phase 1 has no tie-breaker.
	DRAW = 3,
	## The match stopped on an unrecoverable failure, so no winner is awarded.
	INCOMPLETE = 4,
}

## The human player's identity in the Phase 1 demo (ADR-003 constraint 1).
const HUMAN_PLAYER_ID: StringName = &"human"

## The AI player's identity in the Phase 1 demo (ADR-003 constraint 1).
const AI_PLAYER_ID: StringName = &"ai"

## Consecutive automatic no-tile skips that end the match (ADR-003 section 5).
const MAX_CONSECUTIVE_SKIPS: int = 2


## Returns both Phase 1 player identities, human first (ADR-003 section 2).
##
## A fresh array is returned on every call, so callers may keep or modify it.
static func player_ids() -> Array[StringName]:
	return [HUMAN_PLAYER_ID, AI_PLAYER_ID]


## Returns the other Phase 1 player.
##
## Returns an empty name when `player_id` is not one of the two Phase 1 players,
## because there is no third player to hand the turn to.
static func opponent_of(player_id: StringName) -> StringName:
	if player_id == HUMAN_PLAYER_ID:
		return AI_PLAYER_ID
	if player_id == AI_PLAYER_ID:
		return HUMAN_PLAYER_ID
	return &""


## Returns true when `value` is one of the defined match phases.
static func is_valid_phase(value: int) -> bool:
	return MatchPhase.values().has(value)


## Returns true when `value` is one of the two Phase 1 player identities.
static func is_valid_player_id(player_id: StringName) -> bool:
	return player_id == HUMAN_PLAYER_ID or player_id == AI_PLAYER_ID


## Returns true when `value` is one of the defined end reasons.
static func is_valid_end_reason(value: int) -> bool:
	return EndReason.values().has(value)


## Returns true when `value` is one of the defined outcomes.
static func is_valid_outcome(value: int) -> bool:
	return MatchOutcome.values().has(value)


## Returns the phase's constant name, for diagnostics only.
static func phase_name(value: int) -> String:
	if not is_valid_phase(value):
		return "UNKNOWN_PHASE"
	return String(MatchPhase.find_key(value))


## Returns the end reason's constant name, for diagnostics only.
static func end_reason_name(value: int) -> String:
	if not is_valid_end_reason(value):
		return "UNKNOWN_END_REASON"
	return String(EndReason.find_key(value))


## Returns the skip reason's constant name, for diagnostics only.
static func skip_reason_name(value: int) -> String:
	if not SkipReason.values().has(value):
		return "UNKNOWN_SKIP_REASON"
	return String(SkipReason.find_key(value))


## Returns the outcome's constant name, for diagnostics only.
static func outcome_name(value: int) -> String:
	if not is_valid_outcome(value):
		return "UNKNOWN_OUTCOME"
	return String(MatchOutcome.find_key(value))


## Returns the outcome that a final score comparison produces
## (ADR-003 section 8), or `INCOMPLETE` when the match was not played to an end
## condition. Phase 1 has no endgame bonus, penalty, multiplier, or tie-breaker,
## so equal totals are simply a draw.
static func outcome_for_scores(
	human_score: int, ai_score: int, reason: int
) -> int:
	if reason == EndReason.RULES_FAILURE:
		return MatchOutcome.INCOMPLETE
	if human_score > ai_score:
		return MatchOutcome.HUMAN_WIN
	if ai_score > human_score:
		return MatchOutcome.AI_WIN
	return MatchOutcome.DRAW
