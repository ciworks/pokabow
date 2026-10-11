class_name LegalMoveGenerator
extends RefCounted

## Deterministic legal-line candidate generation for the AI's own deck
## (ADR-005 section 2, ADR-011 section 12).
##
## ADR-011 section 12 changes move generation from "one tile per candidate" to
## "one line per candidate", so generation is:
##
##     empty runs x windows            (one orientation, contiguous, gapless)
##       -> frontier filter            (a line must join the board, ADR-006 section 3)
##       -> deck assignments           (which of the rival's tiles fill the window)
##       -> rotation profiles          (0-3 quarter turns, ADR-006 section 5)
##       -> LineValidator.validate     (the shared legality service)
##       -> de-duplicate by outcome    (identical board results collapse)
##       -> line candidates
##
## Two properties are load-bearing:
##
## - the generator applies NO rule of its own. Every survivor is confirmed by
##   `LineValidator`, the same validator the human path commits through, so the
##   AI can never see a move the rules would refuse (ADR-011 sections 3 and 12);
##   the frontier filter and the length cap only bound the search, exactly as
##   `get_frontier_cells()` bounded the single-tile generator before;
## - generation is a pure function of the board and the deck, in a fixed order:
##   shorter lines first, then orientation, then row-major window position. The
##   same inputs therefore produce the same candidate list, which is what makes
##   the strategies reproducible (ADR-005 sections 3 and 10).
##
## A single-tile candidate is legal after the opening when committed board
## tiles complete its ranked hand. The shared validator decides each candidate.
##
## This class holds no state and touches no scene node, so tests, replay, and the
## in-game AI all generate the same candidate list for the same inputs.

## Shortest candidate length. The opening still needs two newly placed tiles.
const MIN_LINE_LENGTH: int = 1

## Longest line the generator enumerates.
##
## The approved maximum hand length. Capping the enumeration keeps the
## candidate list - and therefore Medium's exhaustive preview and Hard's beam -
## bounded on an open board, which is what ADR-005 section 8 budgets assume.
const MAX_LINE_LENGTH: int = 5

## Default number of candidates generation may return.
##
## The cap is generous enough that most positions enumerate fully; when it bites
## it keeps the shorter lines, which are the ones a board can place most often.
const DEFAULT_CANDIDATE_LIMIT: int = 1024

## Orientation search order: a row first, then a column, so a tie is stable.
const ORIENTATION_ORDER: Array[int] = [
	ScoringEnums.HandOrientation.HORIZONTAL,
	ScoringEnums.HandOrientation.VERTICAL,
]


## Returns the legal line candidates for `deck`, rows first.
##
## Returns an empty array when the board is unusable or the deck cannot stage two
## tiles, which is the structured "no legal line" answer ADR-005 section 2 asks
## for. Callers that need the counts use `generate_with_report()`.
static func generate(board: BoardState, deck: Array[TileDefinition]) -> Array[AiMoveCandidate]:
	var report: Dictionary = {}
	return generate_with_report(board, deck, report)


## Returns the legal line candidates and fills `report` with the search shape.
##
## `report` receives the empty-run count, the window count, the raw candidate
## count, the deduplicated count, the validator-rejected count, and the final
## candidate count, so ADR-005 section 12's diagnostics report the search shape
## rather than re-deriving it. `candidate_limit` bounds the returned list; pass a
## larger value for a fixture that needs every window enumerated. `max_length`
## bounds the lines considered, which a two-ply reply search lowers to keep the
## work inside the ADR-005 section 8 budget.
static func generate_with_report(
	board: BoardState,
	deck: Array[TileDefinition],
	report: Dictionary,
	candidate_limit: int = DEFAULT_CANDIDATE_LIMIT,
	max_length: int = MAX_LINE_LENGTH
) -> Array[AiMoveCandidate]:
	var candidates: Array[AiMoveCandidate] = []
	_reset_report(report)
	if board == null:
		push_error("LegalMoveGenerator.generate: a board is required.")
		return candidates

	var tiles: Array[TileDefinition] = usable_tiles(deck)
	if tiles.size() < MIN_LINE_LENGTH:
		return candidates

	var limit: int = candidate_limit
	if limit <= 0:
		limit = DEFAULT_CANDIDATE_LIMIT
	var longest: int = max_length
	if longest < MIN_LINE_LENGTH:
		longest = MIN_LINE_LENGTH
	if longest > MAX_LINE_LENGTH:
		longest = MAX_LINE_LENGTH

	var runs: Dictionary = {}
	var run_count: int = 0
	for orientation: int in ORIENTATION_ORDER:
		var orientation_runs: Array = empty_runs(board, orientation)
		runs[orientation] = orientation_runs
		run_count += orientation_runs.size()
	report["empty_runs"] = run_count

	var seen: Dictionary = {}
	for length: int in range(MIN_LINE_LENGTH, longest + 1):
		for orientation: int in ORIENTATION_ORDER:
			var orientation_runs: Array = runs.get(orientation, [])
			for raw_run: Variant in orientation_runs:
				var run: Array[Vector2i] = raw_run
				if run.size() < length:
					continue
				for start: int in range(run.size() - length + 1):
					var window: Array[Vector2i] = window_of(run, start, length)
					if not is_joinable_window(board, window):
						continue
					report["windows"] = int(report["windows"]) + 1
					for raw_line: Variant in staged_assignments(tiles, orientation, window):
						var line: Array[TileSnapshot] = raw_line
						report["generated"] = int(report["generated"]) + 1
						var key: String = line_key(line)
						if seen.has(key):
							report["deduplicated"] = int(report["deduplicated"]) + 1
							continue
						seen[key] = true
						var result: LineResult = LineValidator.validate(board, line)
						if result == null or not result.accepted:
							report["rejected"] = int(report["rejected"]) + 1
							continue
						candidates.append(AiMoveCandidate.create(result.staged_tiles, result))
						if candidates.size() >= limit:
							report["candidates"] = candidates.size()
							report["capped"] = true
							candidates.sort_custom(compare_candidates)
							return candidates

	candidates.sort_custom(compare_candidates)
	report["candidates"] = candidates.size()
	report["capped"] = false
	return candidates


## Returns the maximal runs of empty cells in one orientation, in row-major order.
##
## Each run is the contiguous sequence of empty in-bounds cells of one row (or
## one column) that lies between committed tiles or board edges, so every window
## taken from it is a gapless line in exactly one orientation (ADR-011 section 1).
static func empty_runs(board: BoardState, orientation: int) -> Array:
	var runs: Array = []
	if board == null or not ScoringEnums.is_valid_orientation(orientation):
		return runs
	var horizontal: bool = orientation == ScoringEnums.HandOrientation.HORIZONTAL
	var line_count: int = BoardEnums.BOARD_HEIGHT if horizontal else BoardEnums.BOARD_WIDTH
	var line_length: int = BoardEnums.BOARD_WIDTH if horizontal else BoardEnums.BOARD_HEIGHT
	for fixed: int in range(line_count):
		var run: Array[Vector2i] = []
		for axis: int in range(line_length):
			var cell: Vector2i = cell_for(horizontal, fixed, axis)
			if board.is_empty_cell(cell):
				run.append(cell)
				continue
			if run.size() >= MIN_LINE_LENGTH:
				runs.append(run)
			run = [] as Array[Vector2i]
		if run.size() >= MIN_LINE_LENGTH:
			runs.append(run)
	return runs


## Returns the contiguous window of `length` cells starting at `start`.
static func window_of(run: Array[Vector2i], start: int, length: int) -> Array[Vector2i]:
	var window: Array[Vector2i] = []
	if run == null or start < 0 or length < 1:
		return window
	for index: int in range(start, start + length):
		if index >= run.size():
			break
		window.append(run[index])
	return window


## Returns true when a window could legally receive a line.
##
## ADR-006 section 3 still decides where a move may connect: a staged cell must
## touch a committed tile, and before the first move it must be one of the four
## central cells. `BoardState` already exposes exactly that set as its frontier,
## so requiring one frontier cell per window is the same bound the single-tile
## generator used. The validator re-checks connectivity independently, so this is
## a search bound and never the legality decision.
static func is_joinable_window(board: BoardState, window: Array[Vector2i]) -> bool:
	if board == null:
		return false
	for cell: Vector2i in window:
		if board.is_frontier_cell(cell):
			return true
	return false


## Returns every staged line the deck can build in one window.
##
## ADR-011 section 3 makes a merged line legal only when its ranks repeat, and
## section 2 lets a window join committed tiles whose ranks may already repeat.
## The generator therefore offers two shapes per window and lets `LineValidator`
## decide between them:
##
## - one assignment per rank the deck holds twice or more, so the line itself can
##   carry the repeated rank; and
## - one assignment in the deck's own order, which is legal when the committed
##   part of the merged line repeats a rank, or when the merged line is five or
##   more cells long (section 3's table);
##
## each under every rotation profile of the window's orientation.
static func staged_assignments(
	tiles: Array[TileDefinition], orientation: int, window: Array[Vector2i]
) -> Array:
	var lines: Array = []
	if window.is_empty() or tiles.size() < window.size():
		return lines
	if window.size() == 1:
		for tile: TileDefinition in tiles:
			lines.append_array(lines_for_assignment(tiles, [tile], orientation, window))
		return lines
	var ranks: Array[int] = ranks_with_multiple(tiles)
	for rank: int in ranks:
		lines.append_array(
			lines_for_assignment(
				tiles, fill_assignment(tiles, window.size(), rank), orientation, window
			)
		)
	lines.append_array(
		lines_for_assignment(tiles, fill_assignment(tiles, window.size(), -1), orientation, window)
	)
	return lines


## Returns the staged lines of one tile assignment under every rotation profile.
static func lines_for_assignment(
	tiles: Array[TileDefinition], assignment: Array, orientation: int, window: Array[Vector2i]
) -> Array:
	var lines: Array = []
	if assignment.size() < window.size():
		return lines
	for raw_profile: Variant in rotation_profiles(orientation, window.size()):
		var profile: Array[int] = raw_profile
		if profile.size() < window.size():
			continue
		var line: Array[TileSnapshot] = []
		for index: int in range(window.size()):
			var tile: TileDefinition = assignment[index]
			line.append(TileSnapshot.create(tile, window[index], profile[index]))
		if line.size() == window.size():
			lines.append(line)
	return lines


## Returns `length` deck tiles, starting with two of `repeated_rank` when given.
##
## A repeated rank can only come from the deck: two tiles of one rank are chosen
## in deal order, and the rest of the line is filled in deal order as well, so
## the assignment is deterministic. A negative rank skips the repeated pair.
static func fill_assignment(
	tiles: Array[TileDefinition], length: int, repeated_rank: int
) -> Array:
	var chosen: Array = []
	var used: Dictionary = {}
	if repeated_rank >= 0:
		for tile: TileDefinition in tiles:
			if chosen.size() >= 2:
				break
			if tile == null or not tile.is_valid() or int(tile.rank) != repeated_rank:
				continue
			if used.has(tile.tile_id):
				continue
			chosen.append(tile)
			used[tile.tile_id] = true
	for tile: TileDefinition in tiles:
		if chosen.size() >= length:
			break
		if tile == null or not tile.is_valid() or used.has(tile.tile_id):
			continue
		chosen.append(tile)
		used[tile.tile_id] = true
	return chosen


## Returns every rotation profile tried for one orientation and line length.
##
## ADR-006 section 5 accepts the four quarter turns, and ADR-011 section 12 lets
## one candidate carry a rotation per tile. The profiles are the four uniform
## rotations plus the alternating planar pair (`0/2` for a row, `1/3` for a
## column), which keeps the rotation search bounded while still offering both
## planar orientations and one mixed arrangement per window.
static func rotation_profiles(orientation: int, length: int) -> Array:
	var profiles: Array = []
	for rotation: int in range(TileEnums.ROTATION_COUNT):
		profiles.append(uniform_profile(rotation, length))
	profiles.append(alternating_profile(planar_rotations(orientation), length))
	return profiles


## Returns the two quarter turns a line's tiles take when laid along an axis.
static func planar_rotations(orientation: int) -> Array[int]:
	if orientation == ScoringEnums.HandOrientation.VERTICAL:
		return [1, 3]
	return [0, 2]


## Returns one rotation repeated `length` times.
static func uniform_profile(rotation: int, length: int) -> Array[int]:
	var profile: Array[int] = []
	for _index: int in range(length):
		profile.append(TileEnums.normalize_rotation(rotation))
	return profile


## Returns the two planar rotations alternating along the line.
static func alternating_profile(planar: Array[int], length: int) -> Array[int]:
	var profile: Array[int] = []
	if planar.is_empty():
		return profile
	for index: int in range(length):
		profile.append(planar[index % planar.size()])
	return profile


## Returns the ranks the deck holds at least twice, in first-seen order.
static func ranks_with_multiple(tiles: Array[TileDefinition]) -> Array[int]:
	var counts: Dictionary = {}
	var order: Array[int] = []
	if tiles == null:
		return order
	for tile: TileDefinition in tiles:
		if tile == null or not tile.is_valid():
			continue
		var rank: int = int(tile.rank)
		if not counts.has(rank):
			counts[rank] = 0
			order.append(rank)
		counts[rank] = int(counts[rank]) + 1
	var repeated: Array[int] = []
	for rank: int in order:
		if int(counts[rank]) >= 2:
			repeated.append(rank)
	return repeated


## Returns the deck without unusable entries, preserving deal order.
static func usable_tiles(deck: Array[TileDefinition]) -> Array[TileDefinition]:
	var tiles: Array[TileDefinition] = []
	if deck == null:
		return tiles
	for tile: TileDefinition in deck:
		if tile != null and tile.is_valid():
			tiles.append(tile)
	return tiles


## Returns a key for the board state one line produces.
##
## Two assignments that place the same ranks with the same visible edges at the
## same cells in the same rotations produce an identical board and score, so they
## collapse to one candidate. Tile identities are deliberately not part of the
## key: that is what makes the collapse possible, and the first assignment in deal
## order is the one kept (ADR-005 section 2 de-duplication).
static func line_key(line: Array[TileSnapshot]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for snapshot: TileSnapshot in line:
		var cell: Vector2i = snapshot.get_cell()
		var tile: TileDefinition = snapshot.get_tile()
		var rank: int = -1 if tile == null else int(tile.rank)
		var edges: String = ""
		for edge: TileEnums.EdgeColor in snapshot.get_rotated_edges():
			edges += "%d," % int(edge)
		parts.append("%d,%d:%d:%s:%s" % [cell.x, cell.y, snapshot.get_rotation(), rank, edges])
	return "|".join(parts)


## Returns true when `a` sorts before `b` in the generator's fixed order.
static func compare_candidates(a: AiMoveCandidate, b: AiMoveCandidate) -> bool:
	if a == null or b == null:
		return a != null
	var index_a: int = BoardEnums.cell_index(a.anchor_cell())
	var index_b: int = BoardEnums.cell_index(b.anchor_cell())
	if index_a != index_b:
		return index_a < index_b
	if a.orientation != b.orientation:
		return a.orientation < b.orientation
	if a.length() != b.length():
		return a.length() < b.length()
	return a.move_key < b.move_key


## Returns true when every candidate is accepted by the shared validator.
##
## Verification helper for tests and debugging (ADR-011 "Required tests": the AI
## must never propose an illegal line). It re-runs `LineValidator` over a
## candidate list and reports whether generation and legality still agree.
static func all_candidates_are_legal(
	board: BoardState, candidates: Array[AiMoveCandidate]
) -> bool:
	if board == null:
		return false
	for candidate: AiMoveCandidate in candidates:
		if candidate == null or not candidate.is_committable():
			return false
		var result: LineResult = LineValidator.validate(board, candidate.snapshots)
		if result == null or not result.accepted:
			return false
	return true


## Fills `report` with the zeroed search-shape counts.
static func _reset_report(report: Dictionary) -> void:
	report["empty_runs"] = 0
	report["windows"] = 0
	report["generated"] = 0
	report["deduplicated"] = 0
	report["rejected"] = 0
	report["candidates"] = 0
	report["capped"] = false
	report["max_line_length"] = MAX_LINE_LENGTH


## Builds a cell on a line from its fixed coordinate and its axis coordinate.
static func cell_for(horizontal: bool, fixed: int, axis: int) -> Vector2i:
	return Vector2i(axis, fixed) if horizontal else Vector2i(fixed, axis)
