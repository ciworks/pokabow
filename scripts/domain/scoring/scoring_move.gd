class_name ScoringMove
extends RefCounted

## One committed move, in the form replay needs (ADR-007 sections 4 and 9).
##
## ADR-007 section 10 lists the ordered committed move history as authoritative
## persisted input, and section 9 uses ordered replay as the authoritative
## equivalence check because player attribution and one-time poker scoring depend
## on move order rather than only on the final board.
##
## This is the rules-layer record of a move: identity, player, tile, coordinate,
## and committed rotation. It deliberately holds no points; the points a move
## earned live in the score ledger, which replay reproduces.

## Deterministic move identifier, `move:<match-id>:<turn-number>`
## (ADR-007 section 5).
var move_id: StringName = &""

## Turn number the move was committed on, 1-based.
var move_number: int = 0

## The player who committed the move.
var player_id: StringName = &""

## Deterministic identity of the tile that was placed.
var tile_id: StringName = &""

## Board coordinate the tile was committed to.
var cell: Vector2i = Vector2i.ZERO

## Committed rotation as a 0-3 quarter-turn index.
var rotation: int = 0

## True when this was the match's opening move, which is the only move exempt
## from the orthogonal-connection rule (ADR-006 sections 2 and 3).
var is_opening_move: bool = false


## Builds a move record.
static func create(
	move_id: StringName,
	move_number: int,
	player_id: StringName,
	tile_id: StringName,
	cell: Vector2i,
	rotation: int,
	is_opening_move: bool = false
) -> ScoringMove:
	var move: ScoringMove = ScoringMove.new()
	move.move_id = move_id
	move.move_number = move_number
	move.player_id = player_id
	move.tile_id = tile_id
	move.cell = cell
	move.rotation = rotation
	move.is_opening_move = is_opening_move
	return move


## Returns the committed snapshot of this move, for a supplied tile.
func to_snapshot(tile: TileDefinition) -> TileSnapshot:
	if tile == null:
		return null
	return TileSnapshot.create(tile, cell, rotation)


## Returns a placement request describing this move.
func to_request() -> PlacementRequest:
	return PlacementRequest.create(player_id, tile_id, cell, rotation)


## Returns true when the record carries the identity replay depends on.
func is_valid() -> bool:
	if String(move_id).is_empty():
		return false
	if String(player_id).is_empty():
		return false
	if String(tile_id).is_empty():
		return false
	if move_number <= 0:
		return false
	if not BoardEnums.is_in_bounds(cell):
		return false
	if rotation < 0 or rotation >= TileEnums.ROTATION_COUNT:
		return false
	return true


## Returns a short human-readable description, for diagnostics only.
func describe() -> String:
	return "%s turn %d: %s placed '%s' at %s rotation %d" % [
		String(move_id),
		move_number,
		String(player_id),
		String(tile_id),
		BoardEnums.cell_name(cell),
		rotation,
	]


## Returns a JSON-safe dictionary, for save data and bug-report fixtures.
func to_dictionary() -> Dictionary:
	return {
		"move_id": String(move_id),
		"move_number": move_number,
		"player_id": String(player_id),
		"tile_id": String(tile_id),
		"cell": [cell.x, cell.y],
		"rotation": rotation,
		"is_opening_move": is_opening_move,
	}


## Builds a move record from a dictionary produced by `to_dictionary()`.
static func from_dictionary(source: Dictionary) -> ScoringMove:
	var raw_cell: Variant = source.get("cell", [0, 0])
	var cell: Vector2i = Vector2i.ZERO
	if raw_cell is Array and raw_cell.size() >= 2:
		cell = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	return ScoringMove.create(
		StringName(String(source.get("move_id", ""))),
		int(source.get("move_number", 0)),
		StringName(String(source.get("player_id", ""))),
		StringName(String(source.get("tile_id", ""))),
		cell,
		int(source.get("rotation", 0)),
		bool(source.get("is_opening_move", false))
	)
