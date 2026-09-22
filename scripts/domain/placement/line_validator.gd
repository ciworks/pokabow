class_name LineValidator
extends RefCounted

## Pure line legality reader (ADR-011 sections 1 to 4).
##
## ADR-011 section 1 replaces the per-tile placement model with one line per move:
## two or more tiles of the active player's deck, all in one row or one column,
## contiguous, growing from the first tile placed. Section 2 lets that line
## include tiles already committed to the board, and judges the hand over the
## whole merged line. Section 3 makes the merged line legal only when its ranks
## contain a repeated rank.
##
## The validator reads a `BoardState` and the line a player has staged and returns
## a structured `LineResult`. It never mutates the board, the tiles, or a scene
## node, and it holds no state, so staging feedback, preview, replay, and tests
## all obtain identical answers from this function.
##
## Rules applied, in this fixed precedence:
## 1. `LONE_TILE` - a move stages two or more tiles (sections 1 and 4). Checked
##    first because every later rule is about a line.
## 2. `TILE_NOT_AVAILABLE` - every staged snapshot must wrap a valid tile.
## 3. `OUT_OF_BOUNDS` / `CELL_OCCUPIED` - every staged cell must be on the board
##    and empty, and no two staged tiles may share a cell.
## 4. `MIXED_ORIENTATION` - all staged tiles lie in one row or one column
##    (section 1). A diagonal-only continuation lands here.
## 5. `LINE_GAP` - the staged tiles are contiguous and the merged line has no hole
##    (sections 1 and 2).
## 6. `OPENING_CELL_REQUIRED` / `NOT_CONNECTED` - ADR-006 sections 2 and 3 still
##    decide where a line may start and what it must touch; ADR-011 section 5
##    leaves those untouched.
## 7. `NO_REPEATED_RANK` - the merged line's ranks contain a repeated rank
##    (section 3).
##
## Step 7 is section 3's table exactly, judged by rank frequency:
## - a two-cell line is legal only as a pair (`A A`), so `A K` is refused;
## - a three- or four-cell line needs a repeated rank (`A A K`, `A A K Q`);
## - five or more cells are always legal, because four ranks cannot fill five
##    cells, which is why the check is `ranks.size() >= 5` before the count.
##
## Edge colours never appear here: ADR-011 section 10 leaves scoring rules alone,
## so a line is never required to match a neighbour's colour.


## Validates an assembled line without changing any state.
##
## Returns null when the caller passes a null board or a null staged line: those
## are programming errors rather than game outcomes, and a structured rejection
## would hide them. An empty staged line is a game outcome (no move was made) and
## is reported as `LONE_TILE`.
static func validate(board: BoardState, staged: Array[TileSnapshot]) -> LineResult:
	if board == null:
		push_error("LineValidator.validate: a board is required.")
		return null
	if staged == null:
		push_error("LineValidator.validate: a staged line is required.")
		return null

	if staged.size() < 2:
		return LineResult.create_rejected(
			PlacementEnums.PlacementRejection.LONE_TILE, _cell_or_origin(staged)
		)

	for snapshot: TileSnapshot in staged:
		if snapshot == null or not snapshot.is_valid():
			return LineResult.create_rejected(
				PlacementEnums.PlacementRejection.TILE_NOT_AVAILABLE, _cell_or_origin(staged)
			)

	var seen: Dictionary = {}
	for snapshot: TileSnapshot in staged:
		var cell: Vector2i = snapshot.get_cell()
		if not board.is_in_bounds(cell):
			return LineResult.create_rejected(
				PlacementEnums.PlacementRejection.OUT_OF_BOUNDS, cell
			)
		if seen.has(cell) or board.is_occupied(cell):
			return LineResult.create_rejected(
				PlacementEnums.PlacementRejection.CELL_OCCUPIED, cell
			)
		seen[cell] = true

	var staged_cells: Array[Vector2i] = cells_of(staged)
	var orientation: int = orientation_of(staged_cells)
	if orientation < 0:
		return LineResult.create_rejected(
			PlacementEnums.PlacementRejection.MIXED_ORIENTATION, staged_cells[0]
		)

	if not is_contiguous_line(staged_cells, orientation):
		return LineResult.create_rejected(PlacementEnums.PlacementRejection.LINE_GAP, staged_cells[0])

	var opening_move: bool = not board.has_any_tile()
	if opening_move:
		if not _touches_opening_cell(staged_cells):
			return LineResult.create_rejected(
				PlacementEnums.PlacementRejection.OPENING_CELL_REQUIRED, staged_cells[0]
			)
	elif not _touches_committed_tile(board, staged_cells):
		return LineResult.create_rejected(
			PlacementEnums.PlacementRejection.NOT_CONNECTED, staged_cells[0]
		)

	var merged_cells: Array[Vector2i] = merged_cells_for(board, staged)
	if merged_cells.is_empty():
		return LineResult.create_rejected(PlacementEnums.PlacementRejection.LINE_GAP, staged_cells[0])

	var merged_ranks: Array[int] = merged_ranks_for(board, staged, merged_cells)
	if merged_ranks.size() != merged_cells.size():
		return LineResult.create_rejected(PlacementEnums.PlacementRejection.LINE_GAP, staged_cells[0])

	if not is_legal_hand(merged_ranks):
		return LineResult.create_rejected(
			PlacementEnums.PlacementRejection.NO_REPEATED_RANK, staged_cells[0]
		)

	var ordered: Array[TileSnapshot] = sort_into_line_order(staged, orientation)
	return LineResult.create_accepted(
		orientation,
		ordered,
		merged_cells,
		merged_ranks,
		changed_cells_for(board, ordered, merged_cells),
		hand_category_for(merged_ranks)
	)


## Returns the cells of a staged line, in the order the snapshots are given.
static func cells_of(staged: Array[TileSnapshot]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for snapshot: TileSnapshot in staged:
		if snapshot != null:
			cells.append(snapshot.get_cell())
	return cells


## Returns the single orientation of a set of cells, or -1 when there is none.
##
## A pair of cells is one orientation unless they differ in both axes, which is
## the diagonal case ADR-011 section 1 refuses. A single cell has no orientation.
static func orientation_of(cells: Array[Vector2i]) -> int:
	if cells.is_empty():
		return -1
	var horizontal: bool = true
	var vertical: bool = true
	for cell: Vector2i in cells:
		if cell.y != cells[0].y:
			horizontal = false
		if cell.x != cells[0].x:
			vertical = false
	if horizontal and vertical:
		return -1
	if horizontal:
		return ScoringEnums.HandOrientation.HORIZONTAL
	if vertical:
		return ScoringEnums.HandOrientation.VERTICAL
	return -1


## Returns true when the cells form a gapless run in the given orientation.
static func is_contiguous_line(cells: Array[Vector2i], orientation: int) -> bool:
	if cells.size() < 2:
		return false
	if not ScoringEnums.is_valid_orientation(orientation):
		return false
	var horizontal: bool = orientation == ScoringEnums.HandOrientation.HORIZONTAL
	var values: Array[int] = []
	for cell: Vector2i in cells:
		values.append(_axis_of(cell, horizontal))
	values.sort()
	for index: int in range(1, values.size()):
		if values[index] != values[index - 1] + 1:
			return false
	return true


## Returns the merged line's cells, in line order, or an empty array.
##
## The merged line is the staged tiles plus every committed tile they join in the
## same row or column (ADR-011 section 2). It is grown outward from the staged
## range through adjacent committed tiles and then verified to be gapless, so a
## staged line that would leave a hole next to committed tiles far away on the
## same row is reported rather than silently judged over a partial line.
static func merged_cells_for(board: BoardState, staged: Array[TileSnapshot]) -> Array[Vector2i]:
	var merged: Array[Vector2i] = []
	if board == null or staged.is_empty():
		return merged
	var staged_cells: Array[Vector2i] = cells_of(staged)
	if staged_cells.size() != staged.size():
		return merged
	var orientation: int = orientation_of(staged_cells)
	if orientation < 0 or not is_contiguous_line(staged_cells, orientation):
		return merged

	var horizontal: bool = orientation == ScoringEnums.HandOrientation.HORIZONTAL
	var fixed: int = staged_cells[0].y if horizontal else staged_cells[0].x
	var limit: int = BoardEnums.BOARD_WIDTH if horizontal else BoardEnums.BOARD_HEIGHT
	var low: int = _axis_extreme(staged_cells, horizontal, true)
	var high: int = _axis_extreme(staged_cells, horizontal, false)

	# The two scans are written with the bound as the loop condition and the
	# cell test as an explicit break, so every path out of them is a return the
	# static analyzer can see. The bound alone terminates them: `low` stops at 0
	# and `high` stops at `limit - 1`.
	while low - 1 >= 0:
		if not board.is_occupied(_cell_for(horizontal, fixed, low - 1)):
			break
		low -= 1
	while high + 1 < limit:
		if not board.is_occupied(_cell_for(horizontal, fixed, high + 1)):
			break
		high += 1

	for axis: int in range(low, high + 1):
		var cell: Vector2i = _cell_for(horizontal, fixed, axis)
		if not _is_filled(board, staged_cells, cell):
			return [] as Array[Vector2i]
		merged.append(cell)
	return merged


## Returns the merged line's face ranks in the same order as `merged_cells`.
static func merged_ranks_for(
	board: BoardState,
	staged: Array[TileSnapshot],
	merged_cells: Array[Vector2i]
) -> Array[int]:
	var ranks: Array[int] = []
	if board == null:
		return ranks
	var staged_by_cell: Dictionary = {}
	for snapshot: TileSnapshot in staged:
		if snapshot != null and snapshot.get_tile() != null:
			staged_by_cell[snapshot.get_cell()] = snapshot
	for cell: Vector2i in merged_cells:
		if staged_by_cell.has(cell):
			var staged_snapshot: TileSnapshot = staged_by_cell[cell]
			ranks.append(int(staged_snapshot.get_tile().rank))
			continue
		var committed: TileSnapshot = board.get_tile(cell)
		if committed == null or committed.get_tile() == null:
			return [] as Array[int]
		ranks.append(int(committed.get_tile().rank))
	return ranks


## Returns true when any rank occurs more than once (ADR-011 section 3).
static func contains_repeated_rank(ranks: Array[int]) -> bool:
	var counts: Dictionary = {}
	for rank: int in ranks:
		var seen: int = int(counts.get(rank, 0)) + 1
		if seen >= 2:
			return true
		counts[rank] = seen
	return false


## Returns true when the merged ranks are a legal hand (ADR-011 section 3).
##
## Five or more cells are always legal: with four ranks, at least one rank must
## repeat (section 3's table). Shorter lines must contain a repeated rank, so a
## two-cell line is legal only as a pair.
static func is_legal_hand(ranks: Array[int]) -> bool:
	if ranks.size() >= ScoringEnums.WINDOW_SIZE:
		return true
	return contains_repeated_rank(ranks)


## Returns the merged line's poker category, or `NONE` when it is not five cells.
##
## ADR-001 section 2 classifies exactly the five-cell windows, and ADR-011
## section 10 leaves that vocabulary unchanged, so this delegates to the existing
## evaluator rather than defining a second set of categories for short lines.
static func hand_category_for(ranks: Array[int]) -> int:
	if ranks.size() != ScoringEnums.WINDOW_SIZE:
		return ScoringEnums.PokerHandCategory.NONE
	return PokerHandEvaluator.classify_ranks(ranks)


## Returns the cells whose score contribution the move can change.
##
## The merged line comes first in row-major order, then the occupied orthogonal
## neighbours of those cells, also row-major and de-duplicated. Read-only.
static func changed_cells_for(
	board: BoardState,
	staged: Array[TileSnapshot],
	merged_cells: Array[Vector2i]
) -> Array[Vector2i]:
	var ordered: Array[Vector2i] = []
	if board == null:
		return ordered
	for cell: Vector2i in ScoringEnums.sort_cells(merged_cells):
		if not ordered.has(cell):
			ordered.append(cell)
	var neighbors: Array[Vector2i] = []
	for cell: Vector2i in merged_cells:
		for neighbor: Vector2i in board.get_occupied_neighbors(cell):
			if not neighbors.has(neighbor):
				neighbors.append(neighbor)
	for neighbor: Vector2i in ScoringEnums.sort_cells(neighbors):
		if not ordered.has(neighbor):
			ordered.append(neighbor)
	# The staged snapshots are validated elsewhere; this keeps the parameter
	# meaningful for callers that build the list themselves and documents that
	# every staged cell is part of the line.
	for snapshot: TileSnapshot in staged:
		if snapshot == null:
			continue
		var cell: Vector2i = snapshot.get_cell()
		if not ordered.has(cell):
			ordered.append(cell)
	return ordered


## Returns the staged tiles ordered along the line, row-major.
static func sort_into_line_order(
	staged: Array[TileSnapshot], orientation: int
) -> Array[TileSnapshot]:
	var ordered: Array[TileSnapshot] = []
	for snapshot: TileSnapshot in staged:
		if snapshot != null:
			ordered.append(snapshot)
	var horizontal: bool = orientation == ScoringEnums.HandOrientation.HORIZONTAL
	ordered.sort_custom(
		func(a: TileSnapshot, b: TileSnapshot) -> bool:
			return _axis_of(a.get_cell(), horizontal) < _axis_of(b.get_cell(), horizontal)
	)
	return ordered


## Returns the coordinate of a staged line's first cell, or the origin.
static func _cell_or_origin(staged: Array[TileSnapshot]) -> Vector2i:
	for snapshot: TileSnapshot in staged:
		if snapshot != null:
			return snapshot.get_cell()
	return Vector2i.ZERO


## Returns the axis coordinate a line walks: x for a row, y for a column.
static func _axis_of(cell: Vector2i, horizontal: bool) -> int:
	return cell.x if horizontal else cell.y


## Builds a cell on a line from its fixed coordinate and its axis coordinate.
static func _cell_for(horizontal: bool, fixed: int, axis: int) -> Vector2i:
	return Vector2i(axis, fixed) if horizontal else Vector2i(fixed, axis)


## Returns the smallest (`smallest` true) or largest axis coordinate of a line.
static func _axis_extreme(cells: Array[Vector2i], horizontal: bool, smallest: bool) -> int:
	var value: int = _axis_of(cells[0], horizontal)
	for cell: Vector2i in cells:
		var axis: int = _axis_of(cell, horizontal)
		if smallest and axis < value:
			value = axis
		elif not smallest and axis > value:
			value = axis
	return value


## Returns true when a staged tile or a committed tile fills a merged line cell.
static func _is_filled(
	board: BoardState, staged_cells: Array[Vector2i], cell: Vector2i
) -> bool:
	return staged_cells.has(cell) or board.is_occupied(cell)


## Returns true when any staged cell is one of the four central opening cells.
static func _touches_opening_cell(staged_cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in staged_cells:
		if BoardEnums.is_opening_cell(cell):
			return true
	return false


## Returns true when any staged cell has a committed orthogonal neighbour.
static func _touches_committed_tile(board: BoardState, staged_cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in staged_cells:
		if board.has_occupied_neighbor(cell):
			return true
	return false
