class_name PlacementValidator
extends RefCounted

## Pure placement legality reader (ADR-006 sections 3, 4, and 5, and its
## rules-layer interface).
##
## The validator reads a `BoardState` and a `PlacementRequest` and returns a
## structured `PlacementResult`. It never mutates the board, the request, the
## tile, or any scene node, and it holds no state of its own, so human input,
## AI search, preview, replay, and tests all obtain identical answers from the
## same function.
##
## Rules applied, in this fixed precedence:
## 1. `INVALID_ROTATION` - only quarter-turn indexes 0-3 are accepted
##    (ADR-006 section 5). Values are rejected, never normalized, so an
##    out-of-range request cannot silently become a legal one.
## 2. `OUT_OF_BOUNDS` - the coordinate must lie on the 12 x 12 board.
## 3. `CELL_OCCUPIED` - only empty cells may receive a tile.
## 4. `TILE_NOT_AVAILABLE` - the tile must be supplied, available, valid, and be
##    the tile the request names.
## 5. `OPENING_CELL_REQUIRED` - on an empty board the target must be one of the
##    four central cells (ADR-006 section 2).
## 6. `NOT_CONNECTED` - once a tile exists, the target must be orthogonally
##    adjacent to a committed tile; diagonal-only contact is refused
##    (ADR-006 section 3).
##
## Edge colours never appear here: they affect scoring, not legality
## (ADR-006 section 4). A tile is never required to match a neighbour.
##
## `NOT_PLAYERS_TURN` is part of the rejection vocabulary but is not applied
## here, because turn ownership is ADR-003 and is enforced in Milestone 4.


## Validates a placement without changing any state.
##
## Returns null when the caller passes a null board or request: those are
## programming errors, not game outcomes, and a structured rejection would hide
## them. `tile` may be null, which is reported as `TILE_NOT_AVAILABLE`.
static func validate(
	board: BoardState,
	request: PlacementRequest,
	tile: TileDefinition,
	tile_available: bool = true
) -> PlacementResult:
	if board == null:
		push_error("PlacementValidator.validate: a board is required.")
		return null
	if request == null:
		push_error("PlacementValidator.validate: a request is required.")
		return null

	var cell: Vector2i = request.cell

	if request.rotation < 0 or request.rotation >= TileEnums.ROTATION_COUNT:
		return PlacementResult.create_rejected(
			PlacementEnums.PlacementRejection.INVALID_ROTATION, cell
		)

	if not board.is_in_bounds(cell):
		return PlacementResult.create_rejected(
			PlacementEnums.PlacementRejection.OUT_OF_BOUNDS, cell
		)

	if board.is_occupied(cell):
		return PlacementResult.create_rejected(
			PlacementEnums.PlacementRejection.CELL_OCCUPIED, cell
		)

	if not tile_available or tile == null or not tile.is_valid():
		return PlacementResult.create_rejected(
			PlacementEnums.PlacementRejection.TILE_NOT_AVAILABLE, cell
		)
	if tile.tile_id != request.tile_id:
		# The supplied tile is not the tile the request names, so that tile
		# cannot be placed by this request.
		return PlacementResult.create_rejected(
			PlacementEnums.PlacementRejection.TILE_NOT_AVAILABLE, cell
		)

	if not board.has_any_tile():
		if not BoardEnums.is_opening_cell(cell):
			return PlacementResult.create_rejected(
				PlacementEnums.PlacementRejection.OPENING_CELL_REQUIRED, cell
			)
	elif not board.has_occupied_neighbor(cell):
		return PlacementResult.create_rejected(
			PlacementEnums.PlacementRejection.NOT_CONNECTED, cell
		)

	var snapshot: TileSnapshot = TileSnapshot.create(tile, cell, request.rotation)
	return PlacementResult.create_accepted(cell, snapshot, changed_cells_for(board, cell))


## Validates a placement and commits it to the board only when it is legal.
##
## This is the atomic board commit of Milestone 2: scoring is not evaluated yet
## (Milestone 3), and turn advancement is not applied yet (Milestone 4). A
## rejected placement leaves the board, its revision, its frontier, and its
## occupancy completely unchanged, so callers never observe a partial move.
static func apply_if_legal(
	board: BoardState,
	request: PlacementRequest,
	tile: TileDefinition,
	tile_available: bool = true
) -> PlacementResult:
	var result: PlacementResult = validate(board, request, tile, tile_available)
	if result == null or not result.accepted:
		return result

	if not board.commit_tile(result.placed_tile):
		# Validation already proved the cell is empty and in bounds, so this can
		# only happen if the board changed between validation and commit. Report
		# it as a rejection instead of exposing a partial move.
		push_error(
			"PlacementValidator.apply_if_legal: board refused a validated commit at %s."
			% BoardEnums.cell_name(result.cell)
		)
		return PlacementResult.create_rejected(
			PlacementEnums.PlacementRejection.CELL_OCCUPIED, result.cell
		)

	return result


## Returns the cells whose score contribution a placement at `cell` can change.
##
## The placed cell comes first, then its occupied orthogonal neighbours in the
## fixed up / right / down / left order (ADR-006 section 6, ADR-007 section 6).
## Read-only: it never mutates the board.
static func changed_cells_for(board: BoardState, cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if board == null or not board.is_in_bounds(cell):
		return cells
	cells.append(cell)
	for neighbor: Vector2i in board.get_occupied_neighbors(cell):
		cells.append(neighbor)
	return cells
