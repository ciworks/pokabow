class_name ScoringMove
extends RefCounted

## One committed move, in the form replay needs (ADR-007 sections 4 and 9,
## ADR-011 section 5).
##
## ADR-007 section 10 lists the ordered committed move history as authoritative
## persisted input, and section 9 uses ordered replay as the authoritative
## equivalence check because player attribution and one-time poker scoring depend
## on move order rather than only on the final board.
##
## ADR-011 sections 1 and 5 change the unit of a move from one tile to one line,
## so a move record carries every tile the line placed rather than a single tile.
## `placements` is the ordered list of `Placement` records and holds at least two
## entries for every move this build can commit. The record still holds no points;
## the points a move earned live in the score ledger, which replay reproduces.
##
## ADR-011 section 5 also keeps the move identifier one per committed line, which
## is why the identifier stayed a single field while the tile fields became a
## list: `move:<match-id>:<turn-number>:1` names the whole line.


## One tile of a committed line: identity, coordinate, and committed rotation.
class Placement:
	extends RefCounted

	## Deterministic identity of the tile that was placed.
	var tile_id: StringName = &""

	## Board coordinate the tile was committed to.
	var cell: Vector2i = Vector2i.ZERO

	## Committed rotation as a 0-3 quarter-turn index.
	var rotation: int = 0


	## Builds one placement record.
	static func create(tile_id: StringName, cell: Vector2i, rotation: int) -> Placement:
		var placement: Placement = Placement.new()
		placement.tile_id = tile_id
		placement.cell = cell
		placement.rotation = rotation
		return placement


	## Returns true when the record names a tile and sits on the board.
	func is_valid() -> bool:
		if String(tile_id).is_empty():
			return false
		if not BoardEnums.is_in_bounds(cell):
			return false
		return rotation >= 0 and rotation < TileEnums.ROTATION_COUNT


	## Returns a JSON-safe dictionary, for save data and bug-report fixtures.
	func to_dictionary() -> Dictionary:
		return {
			"tile_id": String(tile_id),
			"cell": [cell.x, cell.y],
			"rotation": rotation,
		}


	## Builds a placement record from a dictionary produced by `to_dictionary()`.
	static func from_dictionary(source: Dictionary) -> Placement:
		var raw_cell: Variant = source.get("cell", [0, 0])
		var cell: Vector2i = Vector2i.ZERO
		if raw_cell is Array and raw_cell.size() >= 2:
			cell = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		return Placement.create(
			StringName(String(source.get("tile_id", ""))),
			cell,
			int(source.get("rotation", 0))
		)


## Deterministic move identifier, `move:<match-id>:<turn-number>:<placement-index>`
## (ADR-007 section 5, ADR-010 section 9). One identifier per committed line.
var move_id: StringName = &""

## Turn number the move was committed on, 1-based.
var move_number: int = 0

## The player who committed the move.
var player_id: StringName = &""

## The tiles the move placed, in line order.
var placements: Array[Placement] = []

## True when this was the match's opening move, which is the only move exempt
## from the orthogonal-connection rule (ADR-006 sections 2 and 3).
var is_opening_move: bool = false


## Builds a move record for a whole line of placements (ADR-011 section 5).
static func create(
	move_id: StringName,
	move_number: int,
	player_id: StringName,
	placements: Array[Placement],
	is_opening_move: bool = false
) -> ScoringMove:
	var move: ScoringMove = ScoringMove.new()
	move.move_id = move_id
	move.move_number = move_number
	move.player_id = player_id
	move.placements = placements.duplicate()
	move.is_opening_move = is_opening_move
	return move


## Builds a move record holding exactly one placement.
##
## Retained because replay fixtures, ADR-007's tests, and single-tile construction
## in tests still build a one-tile move; nothing in the live game commits one
## (ADR-011 sections 1 and 4).
static func create_single(
	move_id: StringName,
	move_number: int,
	player_id: StringName,
	tile_id: StringName,
	cell: Vector2i,
	rotation: int,
	is_opening_move: bool = false
) -> ScoringMove:
	var placements: Array[Placement] = [Placement.create(tile_id, cell, rotation)]
	return create(move_id, move_number, player_id, placements, is_opening_move)


## Returns how many tiles the move placed.
func placement_count() -> int:
	return placements.size()


## Returns the first placement, or null when the record holds none.
func first_placement() -> Placement:
	if placements.is_empty():
		return null
	return placements[0]


## Returns the identity of the first placed tile, or an empty name.
func tile_id() -> StringName:
	var placement: Placement = first_placement()
	if placement == null:
		return &""
	return placement.tile_id


## Returns the first placed cell, for the one-cell convenience the presentation
## layer and older diagnostics still read. `Vector2i.ZERO` when empty.
func cell() -> Vector2i:
	var placement: Placement = first_placement()
	if placement == null:
		return Vector2i.ZERO
	return placement.cell


## Returns the first placement's rotation, or 0 when the record holds none.
func rotation() -> int:
	var placement: Placement = first_placement()
	if placement == null:
		return 0
	return placement.rotation


## Returns the committed snapshot of one placement, for a supplied tile.
func to_snapshot(placement: Placement, tile: TileDefinition) -> TileSnapshot:
	if placement == null or tile == null:
		return null
	return TileSnapshot.create(tile, placement.cell, placement.rotation)


## Returns a placement request describing one placement.
func to_request(placement: Placement) -> PlacementRequest:
	if placement == null:
		return null
	return PlacementRequest.create(
		player_id, placement.tile_id, placement.cell, placement.rotation
	)


## Returns a placement request describing the move's first placement.
##
## Retained for the one-tile replay path; the live line path builds a request per
## placement.
func to_first_request() -> PlacementRequest:
	return to_request(first_placement())


## Returns true when the record carries the identity replay depends on.
func is_valid() -> bool:
	if String(move_id).is_empty():
		return false
	if String(player_id).is_empty():
		return false
	if move_number <= 0:
		return false
	if placements.is_empty():
		return false
	var seen: Dictionary = {}
	for placement: Placement in placements:
		if placement == null or not placement.is_valid():
			return false
		if seen.has(placement.cell):
			return false
		seen[placement.cell] = true
	return true


## Returns a short human-readable description, for diagnostics only.
func describe() -> String:
	var cells: PackedStringArray = PackedStringArray()
	for placement: Placement in placements:
		cells.append(BoardEnums.cell_name(placement.cell))
	return "%s turn %d: %s placed %d tile(s) at %s" % [
		String(move_id),
		move_number,
		String(player_id),
		placements.size(),
		", ".join(cells),
	]


## Returns a JSON-safe dictionary, for save data and bug-report fixtures.
func to_dictionary() -> Dictionary:
	var records: Array = []
	for placement: Placement in placements:
		records.append(placement.to_dictionary())
	return {
		"move_id": String(move_id),
		"move_number": move_number,
		"player_id": String(player_id),
		"placements": records,
		"is_opening_move": is_opening_move,
	}


## Builds a move record from a dictionary produced by `to_dictionary()`.
##
## A record written before ADR-011 carried one `tile_id`, `cell`, and `rotation`,
## so that shape is still read as a one-placement record rather than rejected:
## the fields are read, never guessed.
static func from_dictionary(source: Dictionary) -> ScoringMove:
	var placements: Array[Placement] = []
	var raw_placements: Variant = source.get("placements", null)
	if raw_placements is Array:
		for entry: Variant in raw_placements:
			if entry is Dictionary:
				placements.append(Placement.from_dictionary(entry))
	elif source.has("tile_id"):
		placements.append(Placement.from_dictionary(source))
	return ScoringMove.create(
		StringName(String(source.get("move_id", ""))),
		int(source.get("move_number", 0)),
		StringName(String(source.get("player_id", ""))),
		placements,
		bool(source.get("is_opening_move", false))
	)
