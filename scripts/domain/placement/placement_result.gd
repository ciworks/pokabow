class_name PlacementResult
extends RefCounted

## The outcome of validating (and optionally committing) one placement
## (ADR-006 section "Rules-layer interface").
##
## A rejected result is still a complete, structured answer: it names the
## coordinate and the reason, so UI can give specific feedback without
## re-deriving rules.
##
## `score_events` appears in the ADR-006 interface sketch, but `ScoreEvent` does
## not exist yet. Milestone 2 commits a tile without scoring, so this type
## deliberately omits the field; Milestone 3 adds it with its concrete type
## rather than as an untyped placeholder.

## True only when the placement was accepted.
var accepted: bool = false

## `PlacementEnums.PlacementRejection` value; `NONE` when accepted.
var rejection: int = PlacementEnums.PlacementRejection.NONE

## The coordinate the request targeted (valid or not).
var cell: Vector2i = Vector2i.ZERO

## The tile placed in the committed rotation, or null when rejected.
var placed_tile: TileSnapshot = null

## Cells whose score contribution can change because of this placement:
## the placed cell first, then its occupied orthogonal neighbours in the fixed
## up / right / down / left order. Empty when rejected.
var changed_cells: Array[Vector2i] = []


## Builds an accepted result.
static func create_accepted(
	cell: Vector2i,
	placed_tile: TileSnapshot,
	changed_cells: Array[Vector2i]
) -> PlacementResult:
	var result: PlacementResult = PlacementResult.new()
	result.accepted = true
	result.rejection = PlacementEnums.PlacementRejection.NONE
	result.cell = cell
	result.placed_tile = placed_tile
	result.changed_cells = changed_cells
	return result


## Builds a rejected result carrying a structured reason.
static func create_rejected(rejection: int, cell: Vector2i) -> PlacementResult:
	var result: PlacementResult = PlacementResult.new()
	result.accepted = false
	result.rejection = rejection
	result.cell = cell
	result.placed_tile = null
	result.changed_cells = []
	return result


## Returns the constant name of the rejection reason, for diagnostics only.
func get_rejection_name() -> String:
	return PlacementEnums.rejection_name(rejection)


## Returns a short human-readable description of this result.
func describe() -> String:
	if accepted:
		return "accepted placement at %s" % BoardEnums.cell_name(cell)
	return "rejected placement at %s: %s" % [
		BoardEnums.cell_name(cell),
		get_rejection_name(),
	]
