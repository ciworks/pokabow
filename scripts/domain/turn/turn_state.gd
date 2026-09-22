class_name TurnState
extends RefCounted

## The mutable turn position of one match (ADR-003 section "Turn-state
## interface").
##
## ADR-003 section "Data ownership" gives `TurnManager` ownership of the active
## player, the turn number, phase transitions, and skip counting, and this type is
## the record it drives. It is deliberately a plain data holder with no
## transitions of its own: a transition here would be a second place that knows
## the turn rules, which AGENTS.md section 15 forbids.
##
## `consecutive_no_tile_skips` counts automatic `NO_TILE_AVAILABLE` skips in a
## row. It is reset when a tile is successfully supplied and ends the match at
## `TurnEnums.MAX_CONSECUTIVE_SKIPS` (ADR-003 section 5).

## `TurnEnums.MatchPhase` value.
var phase: int = TurnEnums.MatchPhase.MATCH_SETUP

## Identity of the player whose turn it is, or an empty name before setup.
var active_player_id: StringName = &""

## 1-based turn number. Turn 1 is the human's opening move (ADR-003 section 2).
var turn_number: int = 0

## Automatic no-tile skips recorded in a row (ADR-003 section 5).
var consecutive_no_tile_skips: int = 0

## `TurnEnums.SkipReason` value for the most recent automatic skip.
##
## ADR-003 section 5 requires a skipped turn to be recorded with its reason. The
## count above is the authoritative persisted field (ADR-003 section 9); this is
## the accompanying diagnostic, and it is cleared as soon as a tile is supplied.
var last_skip_reason: int = TurnEnums.SkipReason.NONE


## Builds a turn state sitting at `MATCH_SETUP` with no active player yet.
static func create() -> TurnState:
	var state: TurnState = TurnState.new()
	state.phase = TurnEnums.MatchPhase.MATCH_SETUP
	state.active_player_id = &""
	state.turn_number = 0
	state.consecutive_no_tile_skips = 0
	state.last_skip_reason = TurnEnums.SkipReason.NONE
	return state


## Returns an independent copy, so a caller cannot mutate this one by accident.
func copy() -> TurnState:
	var clone: TurnState = TurnState.new()
	clone.phase = phase
	clone.active_player_id = active_player_id
	clone.turn_number = turn_number
	clone.consecutive_no_tile_skips = consecutive_no_tile_skips
	clone.last_skip_reason = last_skip_reason
	return clone


## Returns true once gameplay has stopped, whether normally or in recovery.
##
## `RECOVERY_ERROR` counts as stopped: ADR-003 section 7 condition 3 marks such a
## match incomplete with no winner, so no further move may resolve.
func is_stopped() -> bool:
	return (
		phase == TurnEnums.MatchPhase.GAME_OVER
		or phase == TurnEnums.MatchPhase.RECOVERY_ERROR
	)


## Returns true when the active player may submit or cancel an action now.
func is_awaiting_action() -> bool:
	return phase == TurnEnums.MatchPhase.AWAIT_ACTION


## Returns a short "phase player turn N" label, for diagnostics only.
func describe() -> String:
	var player_label: String = String(active_player_id)
	if player_label.is_empty():
		player_label = "-"
	return "%s %s turn %d (skips %d)" % [
		TurnEnums.phase_name(phase),
		player_label,
		turn_number,
		consecutive_no_tile_skips,
	]
