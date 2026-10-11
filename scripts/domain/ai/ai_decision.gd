class_name AiDecision
extends RefCounted

## The result of one AI analysis (ADR-005 sections 1, 9, 11, and 12; ADR-011
## section 12).
##
## ADR-011 section 12 changes what an AI proposal is: a whole line, not one
## placement. A decision therefore carries the line's tile identities, target
## cells, and rotations (the `AiMoveCandidate` shape), and its `cell`/`rotation`
## pair is the line's FIRST tile, kept so the older placement-shaped consumers
## still have one anchor to point at.
##
## ADR-005 section 11 makes the board revision the proposal was calculated
## against part of the contract, because a proposal computed against a stale
## board must be detected and discarded rather than applied.
##
## A decision is inert data. It owns no board, no tile, and no scene node, and it
## never commits anything: the application layer commits a proposal through the
## ordinary ADR-011 whole-line transaction and nowhere else.

## `AiEnums.AiDecisionStatus` value.
var status: int = AiEnums.AiDecisionStatus.NO_LEGAL_MOVE

## Proposed board coordinate of the line's first tile; meaningful only when
## `has_move()` is true.
var cell: Vector2i = Vector2i.ZERO

## Proposed quarter-turn index of the line's first tile; meaningful only when
## `has_move()` is true.
var rotation: int = 0

## The proposed line's tile identities, in line order (ADR-011 sections 1 and 5).
## Empty on a refusal and on a swap.
var tile_ids: Array[StringName] = []

## The proposed line's target cells, in the same order as `tile_ids`.
var line_cells: Array[Vector2i] = []

## The proposed line's quarter-turn indexes, in the same order as `tile_ids`.
var line_rotations: Array[int] = []

## The proposed line as it would be committed, in line order. A whole line is
## what ADR-011 section 5 commits, so the application layer stages this directly.
var line: Array[TileSnapshot] = []

## True when the analysis decided that the rival must swap rather than play
## (ADR-011 section 6). A swap places nothing and carries no coordinate.
var is_swap: bool = false

## Board revision the proposal was calculated against (ADR-005 section 11).
var board_revision: int = 0

## Canonical key of the proposed line (ADR-005 section 10).
var move_key: String = ""

## Diagnostic record of the analysis (ADR-005 section 12).
var diagnostics: Dictionary = {}

## Elapsed analysis time in milliseconds (ADR-005 section 12).
##
## Deliberately NOT part of `diagnostics`: ADR-005 section 3 requires the same
## snapshot, deck, configuration, and decision seed to return the same decision
## and diagnostics, and a clock reading cannot satisfy both. Timing therefore
## lives beside the record rather than inside it.
var elapsed_ms: int = 0


## Builds a decision carrying a whole line.
static func create_line(
	line: Array[TileSnapshot],
	board_revision: int,
	move_key: String,
	diagnostics: Dictionary
) -> AiDecision:
	var decision: AiDecision = AiDecision.new()
	decision.status = AiEnums.AiDecisionStatus.OK
	decision.board_revision = board_revision
	decision.move_key = move_key
	decision.diagnostics = diagnostics
	if line == null:
		return decision
	for snapshot: TileSnapshot in line:
		if snapshot == null or not snapshot.is_valid():
			continue
		decision.line.append(snapshot)
		decision.line_cells.append(snapshot.get_cell())
		decision.line_rotations.append(snapshot.get_rotation())
		decision.tile_ids.append(snapshot.get_tile_id())
	if not decision.line.is_empty():
		decision.cell = decision.line[0].get_cell()
		decision.rotation = decision.line[0].get_rotation()
	return decision


## Builds a decision reporting that the rival must swap (ADR-011 section 6).
##
## The status is `OK` because a swap IS the move the analysis chose: it consumes
## the turn and passes play, which is what ADR-011 section 7 makes a turn. It
## carries no line, so nothing can be committed from it.
static func create_swap(board_revision: int, diagnostics: Dictionary) -> AiDecision:
	var decision: AiDecision = AiDecision.new()
	decision.status = AiEnums.AiDecisionStatus.OK
	decision.is_swap = true
	decision.board_revision = board_revision
	decision.diagnostics = diagnostics
	return decision


## Builds a decision reporting that no legal candidate exists.
##
## ADR-005 section 2 requires this structured answer rather than an illegal
## fallback move, and leaves the turn outcome to ADR-011 sections 6 and 7.
static func create_no_legal_move(board_revision: int, diagnostics: Dictionary) -> AiDecision:
	var decision: AiDecision = AiDecision.new()
	decision.status = AiEnums.AiDecisionStatus.NO_LEGAL_MOVE
	decision.board_revision = board_revision
	decision.diagnostics = diagnostics
	return decision


## Builds a decision reporting that the analysis was cancelled.
##
## ADR-005 section 9 forbids committing a partial result, so a cancelled
## decision deliberately carries no coordinate.
static func create_cancelled(board_revision: int, diagnostics: Dictionary) -> AiDecision:
	var decision: AiDecision = AiDecision.new()
	decision.status = AiEnums.AiDecisionStatus.CANCELLED
	decision.board_revision = board_revision
	decision.diagnostics = diagnostics
	return decision


## Builds a decision reporting that no proposal survived revalidation.
##
## ADR-005 section 11 requires the caller to stop rather than substitute an
## illegal move or silently change difficulty.
static func create_invalid(board_revision: int, diagnostics: Dictionary) -> AiDecision:
	var decision: AiDecision = AiDecision.new()
	decision.status = AiEnums.AiDecisionStatus.INVALID
	decision.board_revision = board_revision
	decision.diagnostics = diagnostics
	return decision


## Returns true when this decision carries a committable proposal.
func has_move() -> bool:
	return status == AiEnums.AiDecisionStatus.OK


## Returns true when the decision is to swap rather than to play a line.
func is_swap_move() -> bool:
	return has_move() and is_swap


## Returns true when the decision carries a whole line to commit.
func has_line() -> bool:
	return has_move() and not line.is_empty()


## Returns true when the analysis was cancelled (ADR-005 section 9).
func is_cancelled() -> bool:
	return status == AiEnums.AiDecisionStatus.CANCELLED


## Returns true when no legal candidate exists for the rival's deck.
func is_no_legal_move() -> bool:
	return status == AiEnums.AiDecisionStatus.NO_LEGAL_MOVE


## Returns the status's constant name, for diagnostics only.
func get_status_name() -> String:
	return AiEnums.status_name(status)


## Returns a short description of this decision, for diagnostics only.
func describe() -> String:
	if is_swap_move():
		return "swap (revision %d)" % board_revision
	if has_move():
		return "line %s of %d tile(s) at %s rotation %d (revision %d)" % [
			move_key, line.size(), BoardEnums.cell_name(cell), rotation, board_revision,
		]
	return "%s (revision %d)" % [get_status_name(), board_revision]
