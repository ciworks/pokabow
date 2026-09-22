class_name PlacementRequest
extends RefCounted

## A request to place a tile in a board cell (ADR-006 section "Rules-layer
## interface").
##
## This is data only: the rules layer's input to validation. It carries no board
## reference, no scene node, and no result. `PlacementValidator` reads it and a
## `BoardState` without mutating either.
##
## `rotation` is a quarter-turn index in the range 0-3, clockwise
## (ADR-006 section 5). Presentation converts degree values before building a
## request; only indexes reach the rules layer.
##
## `player_id` identifies the requesting player for later turn ownership checks
## (ADR-003). Milestone 2 validation does not consult it.

## Requesting player identifier.
var player_id: StringName = &""

## Deterministic identity of the tile the player wants to place.
var tile_id: StringName = &""

## Target board coordinate, origin top-left (ADR-006 section 1).
var cell: Vector2i = Vector2i.ZERO

## Quarter-turn index 0-3, clockwise (ADR-006 section 5).
var rotation: int = 0


## Builds a request. The values are stored as given; validation reports an
## out-of-range rotation rather than normalizing it (ADR-006 section 5).
static func create(
	player_id: StringName,
	tile_id: StringName,
	cell: Vector2i,
	rotation: int
) -> PlacementRequest:
	var request: PlacementRequest = PlacementRequest.new()
	request.player_id = player_id
	request.tile_id = tile_id
	request.cell = cell
	request.rotation = rotation
	return request


## Returns a short human-readable description, for diagnostics only.
func describe() -> String:
	return "place tile '%s' for player '%s' at %s rotation %d" % [
		String(tile_id),
		String(player_id),
		BoardEnums.cell_name(cell),
		rotation,
	]
