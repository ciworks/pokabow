class_name PokerHandEvaluator
extends RefCounted

## Pure poker-hand evaluation (ADR-012, superseding ADR-001 section 2).
##
## A hand is a contiguous, straight, orthogonal sequence of two to five occupied
## cells (ADR-001 section 1, ADR-011 section 1). Horizontal and vertical
## sequences count; diagonals, gaps, and out-of-bounds runs do not.
##
## Classification returns exactly one category per hand, drawn from the closed
## seven-item list of ADR-012 section 1: Pair, Two Pair, 3-straight,
## Three-of-a-Kind, 4-straight, Full House, and 4-of-a-Kind. Anything else is
## `NONE`, which the placement validator refuses as a move, so an unranked line
## never reaches the board. Five identical ranks are no longer a hand.
##
## Rank *frequency* decides every repeated-rank hand, while a sequence hand is
## decided by the order the faces sit along the line (ADR-012 sections 2 and 3).
## The two families are disjoint, so no precedence between them is needed. The
## face's red/black property is deliberately unused (ADR-001 section 3).
##
## This class holds no state, reads a `BoardState` without mutating it, and never
## touches a scene node, so preview, committed scoring, AI evaluation, and replay
## verification all obtain identical answers from the same functions
## (ADR-007 section 2).
##
## Incremental evaluation inspects only the windows containing the newly placed
## coordinate (ADR-001 "Incremental evaluation"); `evaluate_full_board` is the
## debug-only full scan that must agree with it.

## Valid rank-frequency shapes by hand length (ADR-012 section 1).
##
## Length 2 accepts 2. Length 3 accepts 3 or 2+1. Length 4 accepts 4, 3+1, 2+2,
## or 2+1+1. Length 5 accepts only 3+2, which is the Full House; every other
## five-tile shape is refused even though four ranks make five distinct faces
## impossible, because a five-tile hand must be a three plus a pair.

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


## Returns the canonical identifier of an ordered two- to five-cell hand.
##
## Orientation and origin come from the cells themselves, so the identifier does
## not depend on the direction the evaluator walked the window (ADR-001 section 1).
##
## Returns an empty name when the cells are not two to five contiguous straight cells.
static func window_id(cells: Array[Vector2i]) -> StringName:
	if cells.size() < 2 or cells.size() > ScoringEnums.WINDOW_SIZE:
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
		var base: StringName = ScoringEnums.hand_id_for(
			ScoringEnums.HandOrientation.HORIZONTAL, Vector2i(columns[0], cells[0].y)
		)
		return base if cells.size() == ScoringEnums.WINDOW_SIZE else StringName(
			"%s:%d" % [String(base), cells.size()]
		)

	var rows: Array[int] = []
	for cell: Vector2i in cells:
		rows.append(cell.y)
	rows.sort()
	if not _is_contiguous(rows):
		return &""
	var base: StringName = ScoringEnums.hand_id_for(
		ScoringEnums.HandOrientation.VERTICAL, Vector2i(cells[0].x, rows[0])
	)
	return base if cells.size() == ScoringEnums.WINDOW_SIZE else StringName(
		"%s:%d" % [String(base), cells.size()]
	)


## Returns the cells of a canonical window identifier, or an empty array.
##
## The inverse of `window_id`. Verification uses it to check that a scored
## identifier still describes a real window on the board (ADR-007 section 9).
static func cells_for_window_id(hand_id: StringName) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var parts: PackedStringArray = String(hand_id).split(":")
	if (parts.size() != 4 and parts.size() != 5) or parts[0] != "hand":
		return cells
	var length: int = ScoringEnums.WINDOW_SIZE
	if parts.size() == 5:
		if not parts[4].is_valid_int():
			return cells
		length = int(parts[4])
		if length < 2 or length >= ScoringEnums.WINDOW_SIZE:
			return cells
	var orientation: String = parts[1]
	var first: int = int(parts[2])
	var second: int = int(parts[3])
	if orientation == "H":
		for step: int in range(length):
			cells.append(Vector2i(second + step, first))
	elif orientation == "V":
		for step: int in range(length):
			cells.append(Vector2i(first, second + step))
	else:
		return []
	for cell: Vector2i in cells:
		if not BoardEnums.is_in_bounds(cell):
			return []
	return cells


## Returns the valid hand category matching an ordered list of face ranks.
##
## `ranks` must be in the order the tiles sit along the line, because a sequence
## hand is legal only when the faces step along the ladder (ADR-012 section 2).
## Pass `ordered = false` only when the caller genuinely holds a multiset and
## sequence hands cannot apply; that can never award `STRAIGHT_3`/`STRAIGHT_4`.
##
## Returns `NONE` when the count of ranks is outside two to five, when a rank is
## not a defined face, or when the shape is not one of ADR-012 section 1's seven
## valid hands. `NONE` means "not a legal hand", not "a weak hand".
static func classify_ranks(ranks: Array, ordered: bool = true) -> int:
	var size: int = ranks.size()
	if size < 2 or size > ScoringEnums.WINDOW_SIZE:
		return ScoringEnums.PokerHandCategory.NONE

	var counts: Dictionary = {}
	for rank: Variant in ranks:
		var value: int = int(rank)
		if not TileEnums.is_valid_rank(value):
			return ScoringEnums.PokerHandCategory.NONE
		counts[value] = int(counts.get(value, 0)) + 1

	# Sequence hands first: they are the only valid hands with all-distinct
	# ranks, so they cannot collide with the frequency shapes below. A two-tile
	# line is never a sequence hand: ADR-012 section 2 defines only 3- and
	# 4-straights, and the shortest hand is a Pair. Without this lower bound a
	# two-tile J-Q line would satisfy the ladder and be misread as a 4-straight.
	if ordered and size >= 3 and size <= 4 and TileEnums.is_sequence_order(ranks):
		if size == 3:
			return ScoringEnums.PokerHandCategory.STRAIGHT_3
		return ScoringEnums.PokerHandCategory.STRAIGHT_4

	# ADR-012 section 3: equal ranks must sit together along the line, so a hand
	# whose ranks interleave is refused however many of each rank it holds.
	# `Q J Q Q J` is three Queens and two Jacks by count, but it is not a Full
	# House. Every straight has all-distinct ranks and already returned above.
	if ordered and not is_grouped(ranks):
		return ScoringEnums.PokerHandCategory.NONE

	var frequencies: Array = []
	for key: Variant in counts.keys():
		frequencies.append(int(counts[key]))
	frequencies.sort()
	frequencies.reverse()

	# ADR-012 section 1's list is EXACT, so each valid shape occupies one fixed
	# length and every shape carrying an unmatched tile falls through to `NONE`.
	# That is why `2 + 1` at three tiles, and `3 + 1` and `2 + 1 + 1` at four
	# tiles, are deliberately absent: `A A K`, `A A A K` and `K J Q Q` are all
	# refused, even though each contains a smaller valid hand.
	match size:
		2:
			if frequencies == [2]:
				return ScoringEnums.PokerHandCategory.PAIR
		3:
			if frequencies == [3]:
				return ScoringEnums.PokerHandCategory.THREE_OF_A_KIND
		4:
			if frequencies == [4]:
				return ScoringEnums.PokerHandCategory.FOUR_OF_A_KIND
			if frequencies == [2, 2]:
				return ScoringEnums.PokerHandCategory.TWO_PAIR
		5:
			if frequencies == [3, 2]:
				return ScoringEnums.PokerHandCategory.FULL_HOUSE
	return ScoringEnums.PokerHandCategory.NONE


## Returns true when each rank's occurrences are contiguous in `ranks`.
##
## ADR-012 section 3: a hand reads as its groups, so equal ranks must sit
## together along the line. `A A K K` and `K K A A` are grouped; `A K A K`,
## `Q J Q Q J` and `K A A K K` are not. Fewer than two entries is trivially
## grouped. `ranks` must be in the order the tiles sit along the line.
static func is_grouped(ranks: Array) -> bool:
	if ranks.size() < 2:
		return true
	var blocks: int = 0
	var distinct: Dictionary = {}
	var previous: int = -1
	for rank: Variant in ranks:
		var value: int = int(rank)
		if value != previous:
			blocks += 1
			previous = value
		distinct[value] = true
	return blocks == distinct.size()


## Returns the category of a two- to five-cell hand on an occupied board.
##
## Returns `NONE` when any cell is off-board or empty: a gap breaks a sequence
## (ADR-001 section 1).
static func classify_window(board: BoardState, cells: Array[Vector2i]) -> int:
	if board == null or cells.size() < 2 or cells.size() > ScoringEnums.WINDOW_SIZE:
		return ScoringEnums.PokerHandCategory.NONE
	var ranks: Array = []
	for cell: Vector2i in cells:
		var snapshot: TileSnapshot = board.get_tile(cell)
		if snapshot == null:
			return ScoringEnums.PokerHandCategory.NONE
		ranks.append(int(snapshot.get_tile().rank))
	return classify_ranks(ranks)


## Evaluates one two- to five-cell hand, returning null when it is incomplete or
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
	for window: Variant in hands_through_cells(hypothetical, [snapshot.get_cell()]):
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

	for window: Variant in hands_through_cells(board, board.get_occupied_cells()):
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
	if board == null:
		return ids
	for window: Variant in hands_through_cells(board, board.get_occupied_cells()):
		var cells: Array[Vector2i] = window
		if classify_window(board, cells) != ScoringEnums.PokerHandCategory.NONE:
			ids.append(window_id(cells))
	return ids


## Returns each maximal two- to five-tile run touched by this move once.
## Longer runs yield distinct five-tile windows containing a changed cell.
static func hands_through_cells(board: BoardState, cells: Array[Vector2i]) -> Array:
	var hands: Array = []
	if board == null:
		return hands
	var seen: Dictionary = {}
	for cell: Vector2i in cells:
		if not board.is_occupied(cell):
			continue
		for horizontal: bool in [true, false]:
			var step: Vector2i = Vector2i.RIGHT if horizontal else Vector2i.DOWN
			var start: Vector2i = cell
			while board.is_in_bounds(start - step) and board.is_occupied(start - step):
				start -= step
			var run: Array[Vector2i] = []
			var cursor: Vector2i = start
			while board.is_in_bounds(cursor) and board.is_occupied(cursor):
				run.append(cursor)
				cursor += step
			if run.size() < 2:
				continue
			var candidates: Array = [run]
			if run.size() > ScoringEnums.WINDOW_SIZE:
				candidates = []
				for offset: int in range(run.size() - ScoringEnums.WINDOW_SIZE + 1):
					var window: Array[Vector2i] = []
					for index: int in range(offset, offset + ScoringEnums.WINDOW_SIZE):
						window.append(run[index])
					candidates.append(window)
			for candidate: Variant in candidates:
				var hand: Array[Vector2i] = candidate
				if not hand.has(cell):
					continue
				var id: StringName = window_id(hand)
				if String(id).is_empty() or seen.has(id):
					continue
				seen[id] = true
				hands.append(hand)
	hands.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return String(window_id(a)) < String(window_id(b))
	)
	return hands


## Returns every in-bounds five-cell window that contains at least one of `cells`
## on the post-move board (ADR-011 sections 2, 5, and 10).
##
## ADR-011 section 5 commits a whole line at once and section 2 judges the hand
## over the merged line, so the candidate windows are no longer "windows through
## one coordinate": they are the windows through any of the move's staged cells,
## including windows that mix staged and committed tiles. ADR-001 section 1's
## definition of a window is unchanged, and each window is still identified by its
## canonical identifier, so ADR-001 section 5's score-once rule is unchanged.
##
## `board` is the hypothetical post-move board and `cells` the staged coordinates.
## Returns windows ordered by identifier. A run shorter than five cells yields no
## window, which is correct: only a complete five-cell window scores.
static func windows_through_cells(board: BoardState, cells: Array[Vector2i]) -> Array:
	var windows: Array = []
	if board == null or cells.is_empty():
		return windows

	var staged: Dictionary = {}
	for cell: Vector2i in cells:
		if BoardEnums.is_in_bounds(cell):
			staged[cell] = true
	if staged.is_empty():
		return windows

	var rows: Array[int] = []
	var columns: Array[int] = []
	for key: Variant in staged.keys():
		var cell: Vector2i = key
		if not rows.has(cell.y):
			rows.append(cell.y)
		if not columns.has(cell.x):
			columns.append(cell.x)
	rows.sort()
	columns.sort()

	var seen: Dictionary = {}
	var candidates: Array = []
	candidates.append_array(_windows_along(board, staged, true, rows))
	candidates.append_array(_windows_along(board, staged, false, columns))
	for candidate: Variant in candidates:
		var window: Array[Vector2i] = candidate
		var id: StringName = window_id(window)
		if String(id).is_empty() or seen.has(id):
			continue
		seen[id] = true
		windows.append(window)

	windows.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			return String(window_id(a)) < String(window_id(b))
	)
	return windows


## Returns the windows through staged cells along every listed line.
##
## `lines` holds the fixed coordinates to walk: row indices for horizontals and
## column indices for verticals.
static func _windows_along(
	board: BoardState, staged: Dictionary, horizontal: bool, lines: Array[int]
) -> Array:
	var windows: Array = []
	var limit: int = BoardEnums.BOARD_WIDTH if horizontal else BoardEnums.BOARD_HEIGHT
	for fixed: int in lines:
		var run_start: int = -1
		for axis: int in range(limit + 1):
			var filled: bool = false
			if axis < limit:
				filled = _is_line_cell_filled(board, staged, horizontal, fixed, axis)
			if filled:
				if run_start < 0:
					run_start = axis
				continue
			if run_start >= 0:
				_append_run_windows(windows, staged, horizontal, fixed, run_start, axis - 1)
				run_start = -1
	return windows


## Returns true when a line cell holds a staged tile or a committed tile.
static func _is_line_cell_filled(
	board: BoardState, staged: Dictionary, horizontal: bool, fixed: int, axis: int
) -> bool:
	var cell: Vector2i = Vector2i(axis, fixed) if horizontal else Vector2i(fixed, axis)
	return staged.has(cell) or board.is_occupied(cell)


## Appends every five-cell window inside one run that contains a staged cell.
static func _append_run_windows(
	windows: Array,
	staged: Dictionary,
	horizontal: bool,
	fixed: int,
	low: int,
	high: int
) -> void:
	var last_start: int = high - ScoringEnums.WINDOW_SIZE + 1
	if last_start < low:
		return
	for start: int in range(low, last_start + 1):
		var window: Array[Vector2i] = []
		var holds_staged: bool = false
		for step: int in range(ScoringEnums.WINDOW_SIZE):
			var axis: int = start + step
			var cell: Vector2i = Vector2i(axis, fixed) if horizontal else Vector2i(fixed, axis)
			window.append(cell)
			if staged.has(cell):
				holds_staged = true
		if holds_staged:
			windows.append(window)


## Returns true when an ascending list holds five consecutive integers.
static func _is_contiguous(values: Array[int]) -> bool:
	if values.size() < 2 or values.size() > ScoringEnums.WINDOW_SIZE:
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
