class_name AiFeatures
extends RefCounted

## Deterministic public-state features of ADR-005 section 7.
##
## ADR-005 section 7 lets the AI reason only about information the human could
## also see. The features here are that whole vocabulary, and nothing else:
##
## - an AI opportunity is a five-cell poker window that has not scored yet, holds
##   four occupied cells, and has exactly one legal empty frontier cell, so a
##   single tile would complete it;
## - a high-value opportunity is such a window whose best potentially
##   completable category is the strongest one available at that cell;
## - a cluster-milestone opportunity is a colour component sitting one tile below
##   its next cluster milestone;
## - a multi-match cell is a legal frontier cell that can touch matching edges in
##   more than one colour;
## - an opponent-facing threat is a completion cell the next player could take.
##
## No feature inspects an undrawn bag tile, and no feature assumes which rank a
## future tile will have (ADR-004 section 7, ADR-005 section 7). Every feature is
## a pure function of the board, the scored-window set, and the rules.
##
## Two ADR-005 section 7 phrasings leave the counting choice open, and both are
## resolved the same way -- just before and just after the candidate, counted as
## cells -- with the reasoning recorded at the function. `human_open_threat`
## counts the completion cells the board already offered that the move did not
## close, because ADR-005 section 7 states that Hard may block a threat by
## occupying its cell even at the cost of immediate points: a measure that also
## charged the move for the fresh shapes it enables would make blocking
## impossible to prefer, which the ADR explicitly says is not the intent.
## `ai_open_opportunity` counts the completion cells the move adds.

## Number of occupied cells in a window that still needs one tile (ADR-005
## section 7: a window holding "four occupied cells and one legal empty
## frontier cell").
const WINDOW_OCCUPIED_COUNT: int = ScoringEnums.WINDOW_SIZE - 1


## Returns the incomplete five-cell windows containing `cell` that `cell` alone
## would complete.
##
## Each returned array holds the window's five cells in reading order along the
## window's orientation. Returns an empty array when `cell` is not a legal
## frontier cell, because completion is only meaningful at a legal placement.
static func completion_windows(board: BoardState, cell: Vector2i) -> Array:
	var windows: Array = []
	if board == null:
		return windows
	if not board.is_frontier_cell(cell) or not board.is_empty_cell(cell):
		return windows

	for window: Variant in PokerHandEvaluator.candidate_windows(cell):
		var cells: Array[Vector2i] = window
		if not cells.has(cell):
			continue
		var empty_count: int = 0
		var occupied_count: int = 0
		for member: Vector2i in cells:
			if board.is_occupied(member):
				occupied_count += 1
			elif member == cell or board.is_empty_cell(member):
				empty_count += 1
		if occupied_count == WINDOW_OCCUPIED_COUNT and empty_count == 1:
			windows.append(cells)
	return windows


## Returns true when placing one tile at `cell` would complete a poker window.
static func is_completion_cell(board: BoardState, cell: Vector2i) -> bool:
	return not completion_windows(board, cell).is_empty()


## Returns the number of unscored completion windows on the whole board.
##
## This is ADR-005 section 7's first feature in its own words: "number of
## unscored five-cell windows containing four occupied cells and one legal empty
## frontier cell". A cell can belong to more than one window, so this counts
## windows while `completion_cells()` counts distinct cells; both are exposed
## because the ADR uses both phrasings.
static func completion_window_count(board: BoardState) -> int:
	var total: int = 0
	if board == null:
		return total
	for cell: Vector2i in board.get_frontier_cells():
		total += completion_windows(board, cell).size()
	return total


## Returns true when one candidate takes a completion cell that was already open.
##
## ADR-005 section 7 lists "whether the candidate occupies a high-value completion
## cell available before the move" as a Hard feature, and section 7's closing
## paragraph says Hard may block a threat by occupying its cell. "High-value" is
## read as "would actually score": Phase 1 has no High Card category (ADR-001
## section 2), so a window completed by one tile always awards at least a Pair,
## and the check is the strongest category the cell could reach being above NONE.
static func occupies_high_value_completion_cell(
	snapshot: AiGameSnapshot,
	candidate: AiMoveCandidate,
	_rules: ScoringRules
) -> bool:
	if snapshot == null or candidate == null:
		return false
	var board: BoardState = snapshot.get_board()
	if board == null:
		return false
	if not is_completion_cell(board, candidate.cell):
		return false
	return best_completable_category(board, candidate.cell) > ScoringEnums.PokerHandCategory.NONE


## Returns the strongest poker category a four-tile histogram could still reach.
##
## ADR-005 section 7 asks only whether the *best* window at a cell could hold a
## valuable hand. Nothing is assumed about the tile that would arrive, so every
## rank Phase 1 defines is tried once as the missing fifth tile and the strongest
## resulting category is reported. A future rank set would extend the same walk
## without changing this shape.
static func best_potentially_completable(occupied_counts: Dictionary) -> int:
	var best: int = ScoringEnums.PokerHandCategory.NONE
	for rank: int in TileEnums.TileRank.values():
		var extended: Dictionary = occupied_counts.duplicate()
		extended[rank] = int(extended.get(rank, 0)) + 1
		var category: int = _classify_category_counts(extended)
		if category > best:
			best = category
	return best


## Returns the strongest poker category some window at `cell` could complete.
##
## Returns `PokerHandCategory.NONE` when no window would complete there.
static func best_completable_category(board: BoardState, cell: Vector2i) -> int:
	var best: int = ScoringEnums.PokerHandCategory.NONE
	for window: Variant in completion_windows(board, cell):
		var cells: Array[Vector2i] = window
		var counts: Dictionary = {}
		for member: Vector2i in cells:
			if member == cell:
				continue
			var tile: TileSnapshot = board.get_tile(member)
			if tile == null or tile.get_tile() == null:
				continue
			var rank: int = int(tile.get_tile().rank)
			counts[rank] = int(counts.get(rank, 0)) + 1
		var reachable: int = best_potentially_completable(counts)
		if reachable > best:
			best = reachable
	return best


## Returns every frontier cell that completes a window, in row-major order.
##
## This is the board-level opportunity set: the cells the next player may be able
## to finish a poker window on. It is what ADR-005 section 7's aggregate helpers
## count, and it never depends on a hypothetical future tile.
static func completion_cells(board: BoardState, _rules: ScoringRules) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if board == null:
		return cells
	for cell: Vector2i in board.get_frontier_cells():
		if is_completion_cell(board, cell):
			cells.append(cell)
	return cells


## Returns how many frontier cells can touch matching edges in more than one
## colour (ADR-005 section 7).
static func multi_match_frontier_cells(board: BoardState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if board == null:
		return cells
	for cell: Vector2i in board.get_frontier_cells():
		if matching_color_count(board, cell) > 1:
			cells.append(cell)
	return cells


## Returns the number of distinct edge colours `cell` could match.
##
## A boundary matches when the neighbour's facing edge colour equals the colour
## the placed tile would need on that side; the placed tile's own colours are
## unknown, so each neighbour contributes at most one possible colour.
static func matching_color_count(board: BoardState, cell: Vector2i) -> int:
	if board == null or not board.is_empty_cell(cell):
		return 0
	var colors: Dictionary = {}
	for neighbor: Vector2i in board.get_occupied_neighbors(cell):
		var color: int = _facing_color_of(board, cell, neighbor)
		if color >= 0:
			colors[color] = true
	return colors.size()


## Returns how many colour components are exactly one tile short of their next
## cluster milestone (ADR-005 section 7).
##
## The milestone size and the flat award come from the cluster rule resource, so
## this feature never hard-codes ADR-002's numbers.
static func cluster_milestone_cell_count(board: BoardState, rules: ScoringRules) -> int:
	var count: int = 0
	if board == null or rules == null or rules.cluster == null:
		return count
	var cluster_rules: ClusterScoreRules = rules.cluster
	if not cluster_rules.is_valid():
		return count
	var milestone: int = cluster_rules.milestone_size
	if milestone <= 1:
		return count

	for color: int in TileEnums.EdgeColor.values():
		for component: Variant in EdgeClusterScorer.components_for_color(board, color):
			var cells: Array[Vector2i] = component
			var size: int = cells.size()
			if size <= 0:
				continue
			if size % milestone == milestone - 1:
				count += 1
	return count


## Returns how many completion cells a player may occupy after a move.
##
## `board` is the board as it will be after the move, so this is the count of
## opportunities the next player can actually take.
static func open_opportunity_count(board: BoardState, rules: ScoringRules) -> int:
	return completion_cells(board, rules).size()


## Returns the AI's retained-or-created opportunity count for one candidate.
##
## ADR-005 section 7 defines this as the count of high-value completion cells that
## remain available to the AI after the move (a retain) or that the move creates
## (a create). A cell that was already available before the move and is still
## available after it is invisible on the board: it is neither created by this
## move nor owned by the AI, and leaving such cells open is what
## `human_open_threat` measures. This function therefore counts the increase in
## completion cells, never fewer than zero, so occupying a completion cell is not
## punished here.
static func open_opportunity(
	snapshot: AiGameSnapshot,
	candidate: AiMoveCandidate,
	rules: ScoringRules,
	_cancellation: AiCancellationToken
) -> int:
	if snapshot == null or candidate == null or candidate.snapshot == null:
		return 0
	var board: BoardState = snapshot.get_board()
	if board == null:
		return 0
	var before: int = open_opportunity_count(board, rules)
	var after: int = open_opportunity_count(board.with_tile(candidate.snapshot), rules)
	return maxi(0, after - before)


## Returns the completion cells a candidate leaves open to the next player.
##
## ADR-005 section 7 defines this as the "publicly visible completion cells left
## available to the next player": the cells the board already offered as a
## one-tile completion that the move did not occupy and that are still
## completions afterwards. Scoring the move for the fresh shapes it enables would
## make blocking strictly worse than ignoring a threat, and ADR-005 section 7
## states that Hard "may block a threat by occupying its cell even if the move
## scores fewer immediate points", so the term is the threat left standing rather
## than the total threat count after the move.
##
## The count is read from the pre-move board and rechecked on the hypothetical
## post-move board, so a cell whose window filled for another reason is not
## counted as open.
static func human_open_threat(
	snapshot: AiGameSnapshot,
	candidate: AiMoveCandidate,
	rules: ScoringRules
) -> int:
	if snapshot == null or candidate == null or candidate.snapshot == null:
		return 0
	var board: BoardState = snapshot.get_board()
	if board == null:
		return 0
	var after: BoardState = board.with_tile(candidate.snapshot)
	var count: int = 0
	for cell: Vector2i in completion_cells(board, rules):
		if after.is_empty_cell(cell) and is_completion_cell(after, cell):
			count += 1
	return count


## Returns the number of matching boundaries one candidate creates.
##
## ADR-005 section 6 lists "matched edge count" as a connectivity term without
## qualifying it. On one board revision the board-wide total is the same for every
## candidate, so the term is read as the connectivity the candidate itself
## contributes, which is what `EdgeMatchScorer` reports for that placement.
static func matched_edge_count(
	snapshot: AiGameSnapshot,
	candidate: AiMoveCandidate
) -> int:
	if snapshot == null or candidate == null or candidate.snapshot == null:
		return 0
	return EdgeMatchScorer.evaluate_placement(
		snapshot.get_board(), candidate.snapshot
	).size()


## Returns the number of cluster milestones a board has completed.
static func cluster_milestones_completed(board: BoardState, rules: ScoringRules) -> Dictionary:
	var milestones: Dictionary = {}
	if board == null or rules == null or rules.cluster == null:
		return milestones
	var cluster_rules: ClusterScoreRules = rules.cluster
	if not cluster_rules.is_valid():
		return milestones
	for color: int in TileEnums.EdgeColor.values():
		var completed: int = 0
		for component: Variant in EdgeClusterScorer.components_for_color(board, color):
			var cells: Array[Vector2i] = component
			completed += int(cells.size() / cluster_rules.milestone_size)
		milestones[color] = completed
	return milestones


## Returns the colour of the edge the neighbour at `neighbor` presents to `cell`.
##
## Returns -1 when either cell is off-board or empty. This is the direction the
## placed tile would have to match, not a match with a tile that is not there.
static func _facing_color_of(board: BoardState, cell: Vector2i, neighbor: Vector2i) -> int:
	var position: int = BoardEnums.edge_position_toward(neighbor - cell)
	if position == -1:
		return -1
	var neighbor_tile: TileSnapshot = board.get_tile(neighbor)
	if neighbor_tile == null:
		return -1
	return neighbor_tile.get_edge_at(BoardEnums.opposite_edge_position(position))


## Returns the poker category a complete rank-frequency histogram would score as.
##
## The pattern table is ADR-001 section 2's set of rank counts, matching the
## vocabulary `ScoringEnums.PokerHandCategory` declares.
static func _classify_category_counts(counts: Dictionary) -> int:
	if counts.is_empty():
		return ScoringEnums.PokerHandCategory.NONE
	var frequencies: Array[int] = []
	var total: int = 0
	for key: Variant in counts.keys():
		frequencies.append(int(counts[key]))
		total += int(counts[key])
	if total != ScoringEnums.WINDOW_SIZE:
		return ScoringEnums.PokerHandCategory.NONE

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
