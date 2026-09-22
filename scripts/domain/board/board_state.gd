class_name BoardState
extends RefCounted

## Authoritative board storage (ADR-006 sections 1, 2, 3, and 7; GAME_SPEC
## section 4).
##
## Owns exactly three things:
## 1. the 12 x 12 array of committed `TileSnapshot`s;
## 2. the legal-placement frontier index, which is derived data; and
## 3. a revision counter that increments on every committed placement.
##
## It deliberately owns no scoring, no turn state, no presentation, and no
## legality opinion: legality is `PlacementValidator`'s job (ADR-006 section
## "Data ownership"). Committing a tile here is the board half of the atomic
## move transaction defined by ADR-006 section 6; scoring is added on top of it
## in Milestone 3 and the full transaction in Milestone 4.
##
## Board size is fixed at 12 x 12 (ADR-006 constraint 1, GAME_SPEC section 4.1).
## ADR-008 section 12 allows board dimensions to become a versioned rules
## resource; until that is needed, `BoardEnums` holds the approved constants.
##
## Presentation converts cells to pixels. Nothing here knows about pixels, scene
## nodes, or screen sizes.

## Flat row-major storage of committed tiles; empty cells hold null.
var _cells: Array[TileSnapshot] = []

## Derived set of playable empty cells: cell -> true.
var _frontier: Dictionary = {}

## Number of cells holding a committed tile.
var _occupied_count: int = 0

## Increments once per committed placement. Preview never changes it.
var _revision: int = 0


## Creates an empty standard 12 x 12 board with the opening frontier in place.
static func create() -> BoardState:
	var board: BoardState = BoardState.new()
	board._cells = []
	board._cells.resize(BoardEnums.CELL_COUNT)
	board._frontier = {}
	board._occupied_count = 0
	board._revision = 0
	board._reset_frontier_for_empty_board()
	return board


## Returns the number of board columns.
func get_width() -> int:
	return BoardEnums.BOARD_WIDTH


## Returns the number of board rows.
func get_height() -> int:
	return BoardEnums.BOARD_HEIGHT


## Returns the number of cells on the board.
func cell_count() -> int:
	return BoardEnums.CELL_COUNT


## Returns the board revision. It changes only when a tile is committed.
func get_revision() -> int:
	return _revision


## Returns how many cells hold a committed tile.
func occupied_count() -> int:
	return _occupied_count


## Returns true when every cell holds a tile.
func is_full() -> bool:
	return _occupied_count >= BoardEnums.CELL_COUNT


## Returns true once at least one tile is committed.
##
## This is what distinguishes the opening move from later moves
## (ADR-006 sections 2 and 3).
func has_any_tile() -> bool:
	return _occupied_count > 0


## Returns true when `cell` lies on the board (ADR-006 section 1).
func is_in_bounds(cell: Vector2i) -> bool:
	return BoardEnums.is_in_bounds(cell, BoardEnums.BOARD_WIDTH, BoardEnums.BOARD_HEIGHT)


## Returns true when `cell` holds a committed tile.
func is_occupied(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	return _cells[_index_of(cell)] != null


## Returns true when `cell` is in bounds and empty, which is the only state that
## can receive a tile (GAME_SPEC section 4.2).
func is_empty_cell(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and _cells[_index_of(cell)] == null


## Returns the committed tile in `cell`, or null when the cell is empty or out
## of bounds.
func get_tile(cell: Vector2i) -> TileSnapshot:
	if not is_in_bounds(cell):
		return null
	return _cells[_index_of(cell)]


## Returns true when `cell` holds at least one orthogonally adjacent tile.
##
## Diagonal contact does not count (ADR-006 section 3).
func has_occupied_neighbor(cell: Vector2i) -> bool:
	return not get_occupied_neighbors(cell).is_empty()


## Returns every occupied cell in row-major order, for deterministic iteration.
func get_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(BoardEnums.BOARD_HEIGHT):
		for x: int in range(BoardEnums.BOARD_WIDTH):
			var cell: Vector2i = Vector2i(x, y)
			if _cells[_index_of(cell)] != null:
				cells.append(cell)
	return cells


## Returns the in-bounds orthogonal neighbours of `cell`.
##
## Order is fixed at up, right, down, left so callers and tests see a stable
## sequence regardless of Dictionary or engine iteration order.
func get_orthogonal_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for offset: Vector2i in BoardEnums.neighbor_offsets():
		var neighbor: Vector2i = cell + offset
		if is_in_bounds(neighbor):
			neighbors.append(neighbor)
	return neighbors


## Returns the occupied orthogonal neighbours of `cell`, in the same fixed
## up / right / down / left order.
func get_occupied_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for offset: Vector2i in BoardEnums.neighbor_offsets():
		var neighbor: Vector2i = cell + offset
		if is_occupied(neighbor):
			neighbors.append(neighbor)
	return neighbors


## Returns true when `cell` is currently a legal-placement frontier cell.
func is_frontier_cell(cell: Vector2i) -> bool:
	return _frontier.has(cell)


## Returns the frontier in row-major order, for deterministic iteration.
##
## Before the first move this is the four central opening cells; afterwards it
## is every empty cell orthogonally adjacent to a committed tile
## (ADR-006 section 7).
func get_frontier_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y: int in range(BoardEnums.BOARD_HEIGHT):
		for x: int in range(BoardEnums.BOARD_WIDTH):
			var cell: Vector2i = Vector2i(x, y)
			if _frontier.has(cell):
				cells.append(cell)
	return cells


## Recomputes the frontier from the board array alone.
##
## Pure: it neither reads nor writes the incremental index. ADR-006 section 7
## requires this independent rebuild for verification, and it is the oracle the
## incremental updates are checked against.
func compute_frontier() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not has_any_tile():
		return BoardEnums.opening_cells()
	for y: int in range(BoardEnums.BOARD_HEIGHT):
		for x: int in range(BoardEnums.BOARD_WIDTH):
			var cell: Vector2i = Vector2i(x, y)
			if _cells[_index_of(cell)] != null:
				continue
			if has_occupied_neighbor(cell):
				cells.append(cell)
	return cells


## Replaces the incremental index with a value rebuilt from the board array.
##
## Returns the rebuilt frontier in row-major order. Debug, test, and recovery
## paths use this; normal play uses the incremental updates in `commit_tile`.
func rebuild_frontier() -> Array[Vector2i]:
	var cells: Array[Vector2i] = compute_frontier()
	var rebuilt: Dictionary = {}
	for cell: Vector2i in cells:
		rebuilt[cell] = true
	_frontier = rebuilt
	return cells


## Returns true when the incremental frontier and a full rebuild agree.
func frontier_matches_rebuild() -> bool:
	var rebuilt: Array[Vector2i] = compute_frontier()
	if rebuilt.size() != _frontier.size():
		return false
	for cell: Vector2i in rebuilt:
		if not _frontier.has(cell):
			return false
	return true


## Commits one tile to the board, without scoring.
##
## Returns false and changes nothing when the snapshot is null, invalid, out of
## bounds, or targets an occupied cell. On success it writes the snapshot,
## updates the occupancy count, updates the frontier incrementally, and
## increments the board revision. This is the board half of ADR-006 section 6;
## the caller performs it only after validation succeeded.
func commit_tile(snapshot: TileSnapshot) -> bool:
	if snapshot == null or not snapshot.is_valid():
		return false
	var cell: Vector2i = snapshot.get_cell()
	if not is_empty_cell(cell):
		return false

	var was_empty_board: bool = not has_any_tile()
	_cells[_index_of(cell)] = snapshot
	_occupied_count += 1
	_revision += 1
	_apply_frontier_after_commit(cell, was_empty_board)
	return true


## Returns an independent copy of this board, including its frontier index.
##
## The revision is copied, not incremented: a copy is not a commit.
func copy() -> BoardState:
	var board: BoardState = BoardState.new()
	var cells: Array[TileSnapshot] = []
	cells.resize(_cells.size())
	for index: int in range(_cells.size()):
		cells[index] = _cells[index]
	board._cells = cells
	board._frontier = _frontier.duplicate()
	board._occupied_count = _occupied_count
	board._revision = _revision
	return board


## Returns a copy of this board with one hypothetical tile added.
##
## This is the read-only post-placement view required by ADR-007 section 3 for
## previews and scoring. It never mutates this board, never increments the board
## revision, and returns the unchanged copy when `snapshot` is null or targets a
## cell that is not empty and in bounds. Callers validate first; the guards keep
## an illegal preview from corrupting the hypothetical view.
func with_tile(snapshot: TileSnapshot) -> BoardState:
	var hypothetical: BoardState = copy()
	if snapshot == null or not snapshot.is_valid():
		return hypothetical
	var cell: Vector2i = snapshot.get_cell()
	if not hypothetical.is_empty_cell(cell):
		return hypothetical
	hypothetical._cells[hypothetical._index_of(cell)] = snapshot
	hypothetical._occupied_count += 1
	hypothetical._apply_frontier_after_commit(cell, not has_any_tile())
	return hypothetical


## Returns a compact board description, for diagnostics overlays and tests.
func to_debug_string() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for y: int in range(BoardEnums.BOARD_HEIGHT):
		var row: String = ""
		for x: int in range(BoardEnums.BOARD_WIDTH):
			var cell: Vector2i = Vector2i(x, y)
			if _cells[_index_of(cell)] == null:
				row += "."
			elif _frontier.has(cell):
				row += "f"
			else:
				row += "t"
		lines.append(row)
	return "\n".join(lines)


## Applies the incremental frontier update after a successful commit.
##
## Before the first move the frontier is the four central cells; that set is a
## pre-first-move state, not a permanent superset, so the first commit rebuilds
## the neighbourhood from the committed tile (ADR-006 section 7). Later commits
## only erase the committed cell and add its empty in-bounds neighbours, which
## keeps the index equal to `compute_frontier()`.
func _apply_frontier_after_commit(cell: Vector2i, was_empty_board: bool) -> void:
	if was_empty_board:
		_frontier.clear()
	else:
		_frontier.erase(cell)
	for neighbor: Vector2i in get_orthogonal_neighbors(cell):
		if is_empty_cell(neighbor):
			_frontier[neighbor] = true


## Sets the pre-first-move frontier: the four central opening cells.
func _reset_frontier_for_empty_board() -> void:
	var opening: Dictionary = {}
	for cell: Vector2i in BoardEnums.opening_cells():
		opening[cell] = true
	_frontier = opening


## Returns the flat row-major storage index of an in-bounds cell.
func _index_of(cell: Vector2i) -> int:
	return BoardEnums.cell_index(cell, BoardEnums.BOARD_WIDTH)
