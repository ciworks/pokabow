class_name PokerHandEvaluator
extends RefCounted

## Pure poker-window evaluation (ADR-001).
##
## A hand is a contiguous, straight, orthogonal sequence of five occupied cells
## (ADR-001 section 1). Horizontal and vertical sequences count; diagonals, gaps,
## and out-of-bounds runs do not. A run longer than five is evaluated as every
## distinct five-cell window inside it.
##
## Classification uses rank *frequency* only (ADR-001 section 2), so the
## evaluator returns exactly one category per window: the highest pattern that
## matches. The face's red/black property is deliberately unused in Phase 1
## (ADR-001 section 3).
##
## This class holds no state, reads a `BoardState` without mutating it, and never
## touches a scene node, so preview, committed scoring, AI evaluation, and replay
## verification all obtain identical answers from the same functions
## (ADR-007 section 2).
##
## Incremental evaluation inspects only the windows containing the newly placed
## coordinate (ADR-001 "Incremental evaluation"); `evaluate_full_board` is the
## debug-only full scan that must agree with it.

## Face ranks indexed by frequency for one window, descending.
##
## ADR-001 section 2 lists the accepted patterns as the multiset of rank counts:
## 5, 4+1, 3+2, 3+1+1, 2+2+1, and 2+1+1+1. With five tiles drawn from four ranks
## the all-distinct pattern 1+1+1+1+1 is impossible, which is why Phase 1 has no
## High Card category.


## Returns every in-bounds five-cell window containing `cell`, bounds-only.
##
## Horizontals are produced first, ordered by starting column, then verticals,
## ordered by starting row, so the sequence is deterministic. Occupancy is NOT
## checked here: callers decide whether a window is complete.
static func candidate_windows(cell: Vector2i) -> Array:
	var windows: Array = []
	if not BoardEnums.is_in_bounds(cell):
		return windows

	var first_horizontal: int = maxi(0, cell.x - ScoringEnums.WINDOW_SIZE + 1)
	var last_horizontal: int = mini(cell.x, BoardEnums.BOARD_WIDTH - ScoringEnums.WINDOW_SIZE)
	for start_x: int in range(first_horizontal, last_horizontal + 1):
		var window: Array[Vector2i] = []
		for step: int in range(ScoringEnums.WINDOW_SIZE):
			window.append(Vector2i(start_x + step, cell.y))
		windows.append(window)

	var first_vertical: int = maxi(0, cell.y - ScoringEnums.WINDOW_SIZE + 1)
	var last_vertical: int = mini(cell.y, BoardEnums.BOARD_HEIGHT - ScoringEnums.WINDOW_SIZE)
	for start_y: int in range(first_vertical, last_vertical + 1):
		var window: Array[Vector2i] = []
		for step: int in range(ScoringEnums.WINDOW_SIZE):
			window.append(Vector2i(cell.x, start_y + step))
		windows.append(window)

	return windows


## Returns the canonical identifier of an ordered five-cell window.
##
## Orientation and origin come from the cells themselves, so the identifier does
## not depend on the direction the evaluator walked the window (ADR-001 section 1).
##
## Returns an empty name when the cells are not five contiguous straight cells.
static func window_id(cells: Array[Vector2i]) -> StringName:
	if cells.size() != ScoringEnums.WINDOW_SIZE:
		return &""

	var horizontal: bool = true
	var vertical: bool = true
	for cell: Vector2i in cells:
		if cell.y != cells[0].y:
			horizontal = false
		if cell.x != cells[0].x:
			vertical = false
	if horizontal == vertical:
		return &""

	if horizontal:
		var columns: Array[int] = []
		for cell: Vector2i in cells:
			columns.append(cell.x)
		columns.sort()
		if not _is_contiguous(columns):
			return &""
		return ScoringEnums.hand_id_for(
			ScoringEnums.HandOrientation.HORIZONTAL, Vector2i(columns[0], cells[0].y)
		)

	var rows: Array[int] = []
	for cell: Vector2i in cells:
		rows.append(cell.y)
	rows.sort()
	if not _is_contiguous(rows):
		return &""
	return ScoringEnums.hand_id_for(
		ScoringEnums.HandOrientation.VERTICAL, Vector2i(cells[0].x, rows[0])
	)


## Returns the cells of a canonical window identifier, or an empty array.
##
## The inverse of `window_id`. Verification uses it to check that a scored
## identifier still describes a real window on the board (ADR-007 section 9).
static func cells_for_window_id(hand_id: StringName) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var parts: PackedStringArray = String(hand_id).split(":")
	if parts.size() != 4 or parts[0] != "hand":
		return cells
	var orientation: String = parts[1]
	var first: int = int(parts[2])
	var second: int = int(parts[3])
	if orientation == "H":
		for step: int in range(ScoringEnums.WINDOW_SIZE):
			cells.append(Vector2i(second + step, first))
	elif orientation == "V":
		for step: int in range(ScoringEnums.WINDOW_SIZE):
			cells.append(Vector2i(first, second + step))
	else:
		return []
	for cell: Vector2i in cells:
		if not BoardEnums.is_in_bounds(cell):
			return []
	return cells


## Returns the highest poker category matching a multiset of face ranks.
##
## Returns `NONE` when the count of ranks is not five, when a rank is not a
## defined face, or when no pattern matches.
static func classify_ranks(ranks: Array) -> int:
	if ranks.size() != ScoringEnums.WINDOW_SIZE:
		return ScoringEnums.PokerHandCategory.NONE

	var counts: Dictionary = {}
	for rank: Variant in ranks:
		var value: int = int(rank)
		if not TileEnums.is_valid_rank(value):
			return ScoringEnums.PokerHandCategory.NONE
		counts[value] = int(counts.get(value, 0)) + 1

	var frequencies: Array[int] = []
	for key: Variant in counts.keys():
		frequencies.append(int(counts[key]))
	frequencies.sort()
	frequencies.reverse()

	if frequencies.size() == 1:
		return ScoringEnums.PokerHandCategory.FIVE_OF_A_KIND
	if frequencies.size() == 2:
		if frequencies[0] == 4:
			return ScoringEnums.PokerHandCategory.FOUR_OF_A_KIND
		if frequencies[0] == 3:
			return ScoringEnums.PokerHandCategory.FULL_HOUSE
		return ScoringEnums.PokerHandCategory.NONE
	if frequencies.size() == 3:
		if frequencies[0] == 3:
			return ScoringEnums.PokerHandCategory.THREE_OF_A_KIND
		if frequencies[0] == 2:
			return ScoringEnums.PokerHandCategory.TWO_PAIR
		return ScoringEnums.PokerHandCategory.NONE
	if frequencies.size() == 4 and frequencies[0] == 2:
		return ScoringEnums.PokerHandCategory.PAIR
	return ScoringEnums.PokerHandCategory.NONE


## Returns the category of a five-cell window on an occupied board.
##
## Returns `NONE` when any cell is off-board or empty: a gap breaks a sequence
## (ADR-001 section 1).
static func classify_window(board: BoardState, cells: Array[Vector2i]) -> int:
	if board == null or cells.size() != ScoringEnums.WINDOW_SIZE:
		return ScoringEnums.PokerHandCategory.NONE
	var ranks: Array = []
	for cell: Vector2i in cells:
		var snapshot: TileSnapshot = board.get_tile(cell)
		if snapshot == null:
			return ScoringEnums.PokerHandCategory.NONE
		ranks.append(int(snapshot.get_tile().rank))
	return classify_ranks(ranks)


## Evaluates one five-cell window, returning null when it is incomplete or
## unclassified.
##
## Points come from `rules`, never from a hard-coded table (ADR-001 section 4).
static func evaluate_window(
	board: BoardState,
	cells: Array[Vector2i],
	rules: PokerScoreRules
) -> PokerHandResult:
	if board == null or rules == null or not rules.is_valid():
		return null
	var hand_id: StringName = window_id(cells)
	if String(hand_id).is_empty():
		return null
	var category: int = classify_window(board, cells)
	if category == ScoringEnums.PokerHandCategory.NONE:
		return null
	return PokerHandResult.create(hand_id, category, rules.points_for(category), cells)


## Evaluates the windows created by one placement (ADR-001 "Incremental
## evaluation").
##
## `board` is the pre-move board and `snapshot` the tile about to be committed.
## Only windows containing the placed cell are candidates, and a window whose
## canonical identifier is already in `scored_hand_ids` is skipped, which is what
## makes each window score exactly once (ADR-001 section 5).
##
## Returns results ordered by canonical identifier. It never mutates `board` or
## `scored_hand_ids`; the caller records identifiers when the move commits.
static func evaluate_placement(
	board: BoardState,
	snapshot: TileSnapshot,
	rules: PokerScoreRules,
	scored_hand_ids: ScoredHandSet = null
) -> Array[PokerHandResult]:
	var results: Array[PokerHandResult] = []
	if board == null or snapshot == null or not snapshot.is_valid():
		return results
	if not board.is_empty_cell(snapshot.get_cell()):
		return results

	var hypothetical: BoardState = board.with_tile(snapshot)
	for window: Variant in candidate_windows(snapshot.get_cell()):
		var cells: Array[Vector2i] = window
		var result: PokerHandResult = evaluate_window(hypothetical, cells, rules)
		if result == null:
			continue
		if scored_hand_ids != null and scored_hand_ids.has(result.hand_id):
			continue
		results.append(result)

	_sort_by_hand_id(results)
	return results


## Returns every complete five-cell window on the board, row-major.
##
## This is the debug-only full scan of ADR-001 "Incremental evaluation": it must
## produce the same set of canonical windows as incremental evaluation.
static func enumerate_windows(board: BoardState) -> Array:
	var windows: Array = []
	if board == null:
		return windows

	for y: int in range(BoardEnums.BOARD_HEIGHT):
		for start_x: int in range(
			BoardEnums.BOARD_WIDTH - ScoringEnums.WINDOW_SIZE + 1
		):
			var window: Array[Vector2i] = []
			for step: int in range(ScoringEnums.WINDOW_SIZE):
				window.append(Vector2i(start_x + step, y))
			if _is_complete(board, window):
				windows.append(window)

	for x: int in range(BoardEnums.BOARD_WIDTH):
		for start_y: int in range(
			BoardEnums.BOARD_HEIGHT - ScoringEnums.WINDOW_SIZE + 1
		):
			var window: Array[Vector2i] = []
			for step: int in range(ScoringEnums.WINDOW_SIZE):
				window.append(Vector2i(x, start_y + step))
			if _is_complete(board, window):
				windows.append(window)

	return windows


## Returns the classified windows of a whole board, ordered by identifier.
##
## Full-board scanning is for validation, replay, and testing; normal play uses
## `evaluate_placement` (AGENTS.md section 5, ADR-007 section 9).
static func evaluate_full_board(
	board: BoardState,
	rules: PokerScoreRules,
	scored_hand_ids: ScoredHandSet = null
) -> Array[PokerHandResult]:
	var results: Array[PokerHandResult] = []
	if board == null or rules == null or not rules.is_valid():
		return results

	for window: Variant in enumerate_windows(board):
		var cells: Array[Vector2i] = window
		var result: PokerHandResult = evaluate_window(board, cells, rules)
		if result == null:
			continue
		if scored_hand_ids != null and scored_hand_ids.has(result.hand_id):
			continue
		results.append(result)

	_sort_by_hand_id(results)
	return results


## Returns the canonical identifiers of every complete window on the board.
static func full_board_hand_ids(board: BoardState) -> Array[StringName]:
	var ids: Array[StringName] = []
	for window: Variant in enumerate_windows(board):
		var cells: Array[Vector2i] = window
		ids.append(window_id(cells))
	return ids


## Returns true when an ascending list holds five consecutive integers.
static func _is_contiguous(values: Array[int]) -> bool:
	if values.size() != ScoringEnums.WINDOW_SIZE:
		return false
	for index: int in range(1, values.size()):
		if values[index] != values[index - 1] + 1:
			return false
	return true


## Returns true when every cell of a window holds a committed tile.
static func _is_complete(board: BoardState, cells: Array[Vector2i]) -> bool:
	for cell: Vector2i in cells:
		if not board.is_occupied(cell):
			return false
	return true


## Sorts results by canonical identifier, for deterministic event ordering.
static func _sort_by_hand_id(results: Array[PokerHandResult]) -> void:
	results.sort_custom(
		func(a: PokerHandResult, b: PokerHandResult) -> bool:
			return String(a.hand_id) < String(b.hand_id)
	)
