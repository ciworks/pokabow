class_name AiDecision
extends RefCounted

## The result of one AI analysis (ADR-005 sections 1, 9, 11, and 12).
##
## ADR-005 section 1 fixes the request/response shape: a decision carries a
## proposed coordinate, a rotation, the board revision it was calculated against,
## and diagnostics. ADR-005 section 11 makes the revision part of the contract,
## because a proposal computed against a stale board must be detected and
## discarded rather than applied.
##
## A decision is inert data. It owns no board, no tile, and no scene node, and it
## never commits anything: the application layer commits a proposal through the
## ordinary ADR-007 transaction and nowhere else.

## `AiEnums.AiDecisionStatus` value.
var status: int = AiEnums.AiDecisionStatus.NO_LEGAL_MOVE

## Proposed board coordinate; meaningful only when `has_move()` is true.
var cell: Vector2i = Vector2i.ZERO

## Proposed quarter-turn index; meaningful only when `has_move()` is true.
var rotation: int = 0

## Board revision the proposal was calculated against (ADR-005 section 11).
var board_revision: int = 0

## Canonical key of the proposed placement (ADR-005 section 10).
var move_key: String = ""

## Diagnostic record of the analysis (ADR-005 section 12).
var diagnostics: Dictionary = {}

## Elapsed analysis time in milliseconds (ADR-005 section 12).
##
## Deliberately NOT part of `diagnostics`: ADR-005 section 3 requires the same
## snapshot, tile, configuration, and decision seed to return the same decision
## and diagnostics, and a clock reading cannot satisfy both. Timing therefore
## lives beside the record rather than inside it.
var elapsed_ms: int = 0


## Builds a decision carrying a legal proposal.
static func create_move(
	cell: Vector2i,
	rotation: int,
	board_revision: int,
	move_key: String,
	diagnostics: Dictionary
) -> AiDecision:
	var decision: AiDecision = AiDecision.new()
	decision.status = AiEnums.AiDecisionStatus.OK
	decision.cell = cell
	decision.rotation = rotation
	decision.board_revision = board_revision
	decision.move_key = move_key
	decision.diagnostics = diagnostics
	return decision


## Builds a decision reporting that no legal candidate exists.
##
## ADR-005 section 2 requires this structured answer rather than an illegal
## fallback move, and leaves the turn outcome to ADR-003.
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


## Returns true when the analysis was cancelled (ADR-005 section 9).
func is_cancelled() -> bool:
	return status == AiEnums.AiDecisionStatus.CANCELLED


## Returns true when no legal candidate exists for the active tile.
func is_no_legal_move() -> bool:
	return status == AiEnums.AiDecisionStatus.NO_LEGAL_MOVE


## Returns the status's constant name, for diagnostics only.
func get_status_name() -> String:
	return AiEnums.status_name(status)


## Returns a short description of this decision, for diagnostics only.
func describe() -> String:
	if has_move():
		return "move %s at %s rotation %d (revision %d)" % [
			move_key, BoardEnums.cell_name(cell), rotation, board_revision,
		]
	return "%s (revision %d)" % [get_status_name(), board_revision]
