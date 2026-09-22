class_name PlacementEnums
extends RefCounted

## Placement rejection vocabulary (ADR-006 section "Rules-layer interface").
##
## The validator returns a structured rejection reason so mobile UI can explain
## a refused placement without recreating gameplay rules (ADR-006 section 4 and
## its rules-layer interface).
##
## `NONE` means "not rejected". Every other value is an actionable reason.

enum PlacementRejection {
	## The request was legal; there is no rejection.
	NONE = 0,
	## The target coordinate is outside the 12 x 12 board (ADR-006 section 1).
	OUT_OF_BOUNDS = 1,
	## The target cell already holds a committed tile (ADR-006 section 3).
	CELL_OCCUPIED = 2,
	## The board is empty and the target is not one of the four central cells
	## (ADR-006 section 2).
	OPENING_CELL_REQUIRED = 3,
	## The board is not empty and the target touches no committed tile
	## orthogonally (ADR-006 section 3). Diagonal-only contact lands here.
	NOT_CONNECTED = 4,
	## The tile the request names cannot be supplied by the active player
	## (ADR-006 rejection list; tile supply itself is ADR-004 and Milestone 4).
	TILE_NOT_AVAILABLE = 5,
	## It is not this player's turn (ADR-003 turn flow).
	##
	## Declared so callers have the complete vocabulary, but unused by
	## `PlacementValidator`: it is a pure placement reader and does not own turn
	## state. Turn ownership is enforced in Milestone 4.
	NOT_PLAYERS_TURN = 6,
	## The rotation is not one of the four accepted quarter-turn indexes 0-3
	## (ADR-006 section 5).
	INVALID_ROTATION = 7,
	## This move identifier has already been committed (ADR-007 section 5).
	##
	## A repeated commit must be recognised rather than scored twice, and
	## ADR-006's recommended vocabulary has no reason for it, so it is declared
	## here. It refuses a placement without changing any rule about which
	## placements are legal.
	DUPLICATE_MOVE = 8,
	## The match has stopped, so gameplay input is frozen (ADR-003 section 1).
	##
	## `GAME_OVER` freezes input and `RECOVERY_ERROR` marks the match incomplete,
	## so in both cases no further move may resolve. Like `DUPLICATE_MOVE` this
	## reports an existing rule outcome rather than adding one.
	MATCH_FINISHED = 9,
}


## Returns the constant name of a rejection value, for diagnostics only.
static func rejection_name(value: int) -> String:
	if not is_valid_rejection(value):
		return "UNKNOWN_REJECTION"
	return String(PlacementRejection.find_key(value))


## Returns true when `value` is one of the defined rejection reasons.
static func is_valid_rejection(value: int) -> bool:
	return PlacementRejection.values().has(value)
