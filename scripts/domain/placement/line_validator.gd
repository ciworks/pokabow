class_name LineValidator
extends RefCounted

## Pure line legality reader (ADR-011 sections 1 to 4).
##
## ADR-011 section 1 replaces the per-tile placement model with one line per move:
## two or more tiles of the active player's deck, all in one row or one column.
## Section 2 lets that line include tiles already committed to the board, and
## judges the hand over the whole merged line. Section 1's no-gap rule is judged
## over that merged line too (owner amendment, 2026-09-23), so the staged tiles may
## sit on both sides of a committed tile as long as the merged line is gapless.
## Section 3 makes the merged line legal only when it is a ranked hand.
##
## The validator reads a `BoardState` and the line a player has staged and returns
## a structured `LineResult`. It never mutates the board, the tiles, or a scene
## node, and it holds no state, so staging feedback, preview, replay, and tests
## all obtain identical answers from this function.
##
## Rules applied, in this fixed precedence:
## 1. `LONE_TILE` - a move stages at least one tile, and an opening stages two
##    or more (sections 1 and 4).
## 2. `TILE_NOT_AVAILABLE` - every staged snapshot must wrap a valid tile.
## 3. `OUT_OF_BOUNDS` / `CELL_OCCUPIED` - every staged cell must be on the board
##    and empty, and no two staged tiles may share a cell.
## 4. `MIXED_ORIENTATION` - all staged tiles lie in one row or one column
##    (section 1). A diagonal-only continuation lands here.
## 5. `LINE_GAP` - the merged line has no hole once the staged tiles are joined to
##    the committed tiles they touch (sections 1 and 2, as amended).
## 6. `OPENING_CELL_REQUIRED` / `NOT_CONNECTED` - ADR-006 sections 2 and 3 still
##    decide where a line may start and what it must touch; ADR-011 section 5
##    leaves those untouched.
## 7. `HAND_TOO_LONG` - no connected run through a staged tile may exceed five.
## 8. `NO_REPEATED_RANK` - the merged line must classify as a ranked hand.
##
## Hand classification is the exact closed list of ADR-012 section 1, judged over
## the merged line in the order its tiles sit along it:
## - a two-cell line is legal only as a pair (`A A`), so `A K` is refused;
## - a three-cell line is a three-of-a-kind (`A A A`) or a 3-straight (`J Q K`);
## - a four-cell line is a four-of-a-kind, a two pair, or a 4-straight;
## - a five-cell line is legal only as a full house (`A A A K K`).
## A hand carrying an unmatched tile, or one whose equal ranks interleave, is
## refused, and `is_legal_hand` below is the single reader of that rule.
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

	if staged.is_empty() or (staged.size() == 1 and not board.has_any_tile()):
		return LineResult.create_rejected(
			PlacementEnums.PlacementRejection.LONE_TILE, _cell_or_origin(staged)
		)
	if staged.size() > ScoringEnums.WINDOW_SIZE:
		return LineResult.create_rejected(
			PlacementEnums.PlacementRejection.HAND_TOO_LONG, _cell_or_origin(staged)
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
	if staged.size() == 1:
		orientation = _single_tile_orientation(board, staged)
	if orientation < 0:
		return LineResult.create_rejected(
			PlacementEnums.PlacementRejection.MIXED_ORIENTATION, staged_cells[0]
		)

	# The no-gap rule is judged over the MERGED line, not over the staged tiles
	# alone (ADR-011 section 1 as amended by the owner's 2026-09-23 note). A move
	# may place tiles on both sides of a committed tile: the staged set then holds
	# a hole, but the committed tile fills that hole and the merged line is still
	# gapless. `merged_cells_for` below walks the whole span and rejects it when
	# any cell in it is empty, so a genuinely gapped line is still refused.

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

	var merged_cells: Array[Vector2i] = merged_cells_for(board, staged, orientation)
	if merged_cells.is_empty():
		return LineResult.create_rejected(PlacementEnums.PlacementRejection.LINE_GAP, staged_cells[0])
	if merged_cells.size() > ScoringEnums.WINDOW_SIZE:
		return LineResult.create_rejected(
			PlacementEnums.PlacementRejection.HAND_TOO_LONG, staged_cells[0]
		)
	for cell: Vector2i in staged_cells:
		if (
			_run_length_through(board, staged_cells, cell, Vector2i.RIGHT) > ScoringEnums.WINDOW_SIZE
			or _run_length_through(board, staged_cells, cell, Vector2i.DOWN) > ScoringEnums.WINDOW_SIZE
		):
			return LineResult.create_rejected(
				PlacementEnums.PlacementRejection.HAND_TOO_LONG, cell
			)

	var merged_ranks: Array[int] = merged_ranks_for(board, staged, merged_cells)
	if merged_ranks.size() != merged_cells.size():
		return LineResult.create_rejected(PlacementEnums.PlacementRejection.LINE_GAP, staged_cells[0])

	if not is_legal_hand(merged_ranks):
		return LineResult.create_rejected(
			PlacementEnums.PlacementRejection.NO_REPEATED_RANK, staged_cells[0]
		)
	var hypothetical: BoardState = board.with_tiles(staged)
	for cell: Vector2i in staged_cells:
		for horizontal: bool in [true, false]:
			var run: Array[Vector2i] = _occupied_run_through(
				hypothetical, cell, Vector2i.RIGHT if horizontal else Vector2i.DOWN
			)
			if run.size() >= 2 and PokerHandEvaluator.classify_window(
				hypothetical, run
			) == ScoringEnums.PokerHandCategory.NONE:
				return LineResult.create_rejected(
					PlacementEnums.PlacementRejection.NO_REPEATED_RANK, cell
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
	if cells.is_empty():
		return false
	if not ScoringEnums.is_valid_orientation(orientation):
		return false
	if cells.size() == 1:
		return true
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
## range through adjacent committed tiles, and then every cell across the span
## must be filled by a staged or a committed tile, so a span holding a real hole
## is reported rather than silently judged over a partial line.
##
## The staged cells themselves need not be contiguous (ADR-011 section 1 as
## amended): placing tiles on both sides of a committed tile leaves a hole in the
## staged set that the committed tile fills, and that is a legal flanking move.
static func merged_cells_for(
	board: BoardState, staged: Array[TileSnapshot], chosen_orientation: int = -1
) -> Array[Vector2i]:
	var merged: Array[Vector2i] = []
	if board == null or staged.is_empty():
		return merged
	var staged_cells: Array[Vector2i] = cells_of(staged)
	if staged_cells.size() != staged.size():
		return merged
	var orientation: int = chosen_orientation
	if orientation < 0:
		orientation = orientation_of(staged_cells)
	if orientation < 0:
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
## Only two- to five-tile ranked hands are legal. The validator rejects longer
## runs before calling this helper.
static func is_legal_hand(ranks: Array[int]) -> bool:
	return PokerHandEvaluator.classify_ranks(ranks) != ScoringEnums.PokerHandCategory.NONE


## Chooses a ranked merged hand for a one-tile move, horizontal before vertical.
static func _single_tile_orientation(board: BoardState, staged: Array[TileSnapshot]) -> int:
	for orientation: int in [
		ScoringEnums.HandOrientation.HORIZONTAL,
		ScoringEnums.HandOrientation.VERTICAL,
	]:
		var cells: Array[Vector2i] = merged_cells_for(board, staged, orientation)
		if is_legal_hand(merged_ranks_for(board, staged, cells)):
			return orientation
	# Continue through normal connectivity and hand rejection with a stable axis.
	return ScoringEnums.HandOrientation.HORIZONTAL


## Counts the post-move connected run through a staged cell on one axis.
static func _run_length_through(
	board: BoardState, staged_cells: Array[Vector2i], cell: Vector2i, step: Vector2i
) -> int:
	var count: int = 1
	for direction: Vector2i in [step, -step]:
		var cursor: Vector2i = cell + direction
		while board.is_in_bounds(cursor) and _is_filled(board, staged_cells, cursor):
			count += 1
			cursor += direction
	return count


## Returns the complete occupied run through a cell on one axis.
static func _occupied_run_through(
	board: BoardState, cell: Vector2i, step: Vector2i
) -> Array[Vector2i]:
	var run: Array[Vector2i] = []
	var start: Vector2i = cell
	while board.is_in_bounds(start - step) and board.is_occupied(start - step):
		start -= step
	var cursor: Vector2i = start
	while board.is_in_bounds(cursor) and board.is_occupied(cursor):
		run.append(cursor)
		cursor += step
	return run


## Returns the merged line's poker category, or `NONE` when invalid.
##
## The evaluator classifies every scored hand length from two through five.
static func hand_category_for(ranks: Array[int]) -> int:
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
