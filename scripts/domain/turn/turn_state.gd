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
## `consecutive_no_tile_skips` counts automatic `NO_TILE_AVAILABLE` turn ends in
## a row, which ADR-010 section 4 uses when the active player holds no tiles and
## the pot cannot supply one. ADR-010 section 7 removes the two-consecutive-skip
## end condition, so the count is now a diagnostic and a save field rather than a
## rule input: the match ends only when the board is full or when neither player
## holds a tile and the pot is empty. It is still reset whenever a turn proceeds
## with a stocked deck.

## `TurnEnums.MatchPhase` value.
var phase: int = TurnEnums.MatchPhase.MATCH_SETUP

## Identity of the player whose turn it is, or an empty name before setup.
##
## Seating an active player starts that player's turn, so the turn's placement
## index restarts at 1 (ADR-010 section 9). Every turn boundary in `TurnManager`
## seats a player (`setup`, `end_turn`, and the automatic handover of
## `_enter_turn_start`), so the sequence `move:<match>:<turn>:1`, `:2`, ... is
## maintained by construction rather than by a second counter a caller could
## forget to reset.
##
## Re-seating the active player is what makes the refusal of ADR-007 section 5
## idempotent for a retried placement: restoring the turn position restores the
## index too, so a replay of an already-committed placement reproduces its
## identifier and is refused as `DUPLICATE_MOVE` instead of being scored twice.
var active_player_id: StringName:
	get:
		return _active_player_id
	set(value):
		_active_player_id = value
		placements_this_turn = 0

## Storage for `active_player_id`.
var _active_player_id: StringName = &""

## Placements committed since the active player was seated (ADR-010 section 9).
##
## `MoveCommitter` advances this once per committed placement, and
## `GameSessionState.next_placement_index()` reads it, so the 1-based index of
## the next placement is the count plus one. It is deliberately not derived from
## the committed history: a retry must reproduce the identifier of the placement
## it repeats (ADR-007 section 5), which only a turn-position counter can do.
var placements_this_turn: int = 0

## 1-based turn number. Turn 1 is the human's opening move (ADR-003 section 2).
var turn_number: int = 0

## Legacy save fields. New turns have no move deadline.
var remaining_seconds: float = 0.0
var deadline_unix_seconds: float = 0.0

## Automatic no-tile turn ends recorded in a row (ADR-010 section 4).
var consecutive_no_tile_skips: int = 0

## `TurnEnums.SkipReason` value for the most recent automatic turn end.
##
## ADR-010 section 4 requires a turn ended for want of a tile to be recorded with
## its reason. The count above is the persisted field (ADR-003 section 9); this is
## the accompanying diagnostic, and it is cleared as soon as a turn proceeds.
var last_skip_reason: int = TurnEnums.SkipReason.NONE


## Builds a turn state sitting at `MATCH_SETUP` with no active player yet.
static func create() -> TurnState:
	var state: TurnState = TurnState.new()
	state.phase = TurnEnums.MatchPhase.MATCH_SETUP
	state.active_player_id = &""
	state.turn_number = 0
	state.consecutive_no_tile_skips = 0
	state.last_skip_reason = TurnEnums.SkipReason.NONE
	state.placements_this_turn = 0
	return state


## Returns an independent copy, so a caller cannot mutate this one by accident.
func copy() -> TurnState:
	var clone: TurnState = TurnState.new()
	clone.phase = phase
	# Seating the player first, because that assignment restarts the turn's
	# placement index; the counter is restored afterwards.
	clone.active_player_id = active_player_id
	clone.turn_number = turn_number
	clone.remaining_seconds = remaining_seconds
	clone.deadline_unix_seconds = deadline_unix_seconds
	clone.consecutive_no_tile_skips = consecutive_no_tile_skips
	clone.last_skip_reason = last_skip_reason
	clone.placements_this_turn = placements_this_turn
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
