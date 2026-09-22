class_name EdgeClusterScorer
extends RefCounted

## Reference flood-fill cluster scoring (ADR-002 sections 2, 3, 4, 5, and 8).
##
## For each edge colour, the single-colour graph is:
## - a vertex is a committed tile incident to at least one matching boundary of
##   that colour; and
## - an edge connects two orthogonally adjacent tiles whose touching edges both
##   have that colour.
##
## A cluster is one connected component of that graph, its size is the number of
## unique tiles in it, and its entitlement is a flat award per completed
## milestone (ADR-002 sections 2 to 4). Colours never mix inside one cluster and
## diagonal contact never connects tiles.
##
## ADR-002 "Incremental implementation notes" accepts a local flood fill as the
## first correct implementation on a 12 x 12 board, with union-find or caches only
## if profiling shows a real need. This is that reference implementation: it is
## deliberately simple, holds no state, and never mutates a board, so it is the
## oracle any later optimised component index must match.
##
## Only a placement's own cluster can change, so incremental evaluation touches
## the colours that form a new matching boundary at the placed coordinate
## (ADR-002 section 5, ADR-007 section 6).


## Returns true when `cell` is incident to a matching boundary of `color`.
static func is_vertex(board: BoardState, cell: Vector2i, color: int) -> bool:
	return not _matching_neighbors(board, cell, color).is_empty()


## Returns the tiles of the single-colour component containing `start`.
##
## The result is in row-major order and includes `start` itself. Returns an empty
## array when `start` is off-board, empty, or not incident to a matching boundary
## of `color`, since such a tile is not a vertex of that colour's graph.
static func component_of(board: BoardState, start: Vector2i, color: int) -> Array[Vector2i]:
	var component: Array[Vector2i] = []
	if board == null or not board.is_occupied(start):
		return component
	if not is_vertex(board, start, color):
		return component

	var visited: Dictionary = {}
	var pending: Array[Vector2i] = [start]
	visited[start] = true
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		component.append(cell)
		for neighbor: Vector2i in _matching_neighbors(board, cell, color):
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			pending.append(neighbor)

	component.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return BoardEnums.cell_index(a) < BoardEnums.cell_index(b)
	)
	return component


## Returns every component of one colour, ordered by their first cell.
static func components_for_color(board: BoardState, color: int) -> Array:
	var components: Array = []
	if board == null:
		return components

	var assigned: Dictionary = {}
	for cell: Vector2i in board.get_occupied_cells():
		if assigned.has(cell):
			continue
		if not is_vertex(board, cell, color):
			continue
		var component: Array[Vector2i] = component_of(board, cell, color)
		for member: Vector2i in component:
			assigned[member] = true
		components.append(component)

	return components


## Returns every component of every colour, ordered by colour then first cell.
static func all_components(board: BoardState) -> Array:
	var components: Array = []
	for color: int in TileEnums.EdgeColor.values():
		for component: Variant in components_for_color(board, color):
			components.append(component)
	return components


## Returns one colour's total entitlement across all of its components.
static func entitlement_for_color(board: BoardState, color: int, rules: ClusterScoreRules) -> int:
	var total: int = 0
	if board == null or rules == null or not rules.is_valid():
		return total
	for component: Variant in components_for_color(board, color):
		var cells: Array[Vector2i] = component
		total += rules.entitlement_for_size(cells.size())
	return total


## Returns every colour's entitlement total, keyed by colour name.
##
## Keyed by the lowercase colour name so a report stays readable and comparable
## across runs; colours with no components still appear, as zero.
static func entitlement_totals(board: BoardState, rules: ClusterScoreRules) -> Dictionary:
	var totals: Dictionary = {}
	for color: int in TileEnums.EdgeColor.values():
		totals[TileEnums.edge_color_name(color).to_lower()] = entitlement_for_color(
			board, color, rules
		)
	return totals


## Returns the board's total cluster entitlement across every colour.
static func total_entitlement(board: BoardState, rules: ClusterScoreRules) -> int:
	var total: int = 0
	if board == null or rules == null or not rules.is_valid():
		return total
	for color: int in TileEnums.EdgeColor.values():
		total += entitlement_for_color(board, color, rules)
	return total


## Returns the clusters a placement completes, ordered by colour then key.
##
## `board` is the pre-move board and `snapshot` the tile about to be committed.
## For each colour forming a new matching boundary at the placed coordinate, the
## award is `max(0, post_entitlement - sum(pre_entitlements))` over the distinct
## pre-move components the new tile touches (ADR-002 section 5). Zero-point
## deltas produce no result, because a growing or merging cluster may correctly
## award nothing.
##
## This is the one-tile case of `evaluate_line`, which ADR-011 section 5 makes the
## unit of a commit, so the two forms cannot disagree about what a move completes
## (AGENTS.md section 15). With one staged tile the line form measures exactly
## this: the entry's own tile, the same distinct pre-move regions the tile
## touched, and the same post-move component.
##
## Never mutates the board or the rules.
static func evaluate_placement(
	board: BoardState,
	snapshot: TileSnapshot,
	rules: ClusterScoreRules
) -> Array[ClusterScoreResult]:
	var results: Array[ClusterScoreResult] = []
	if board == null or snapshot == null or not snapshot.is_valid():
		return results
	if rules == null or not rules.is_valid():
		return results
	var staged: Array[TileSnapshot] = [snapshot]
	return evaluate_line(board, staged, rules)


## Returns the cluster entitlement deltas a whole line creates, ordered by colour
## then key (ADR-011 sections 5 and 10).
##
## A whole-line commit introduces several tiles at once, so the delta is measured
## over the components the LINE changes rather than over one tile's four sides:
##
## - the colours examined are exactly those the move forms a matching boundary of,
##   whether to a committed neighbour or between two staged tiles of the line,
##   because those are the colours whose component structure the move can change;
## - the pre side is every distinct pre-move region of that colour the line
##   touched, de-duplicated by canonical component key, so a line that joins one
##   region twice cannot award the pre-entitlement twice;
## - the post side is every distinct post-move component of that colour which now
##   contains a staged tile, de-duplicated by canonical component key, because two
##   staged tiles can end up in the same component and counting it twice would
##   invent entitlement the board does not hold;
## - the awarded points stay the entitlement formula of ADR-002 section 5,
##   `max(0, post - pre)` over the current rules, so the values are unchanged.
##
## That keeps the ledger's cluster points equal to the board's total entitlement
## the way `ScoringAudit` independently checks it, which is what ADR-002 section 8
## requires of any incremental implementation.
##
## Never mutates the board or the rules. Returns an empty array when the inputs
## are unusable, and a zero-point delta produces no result.
static func evaluate_line(
	board: BoardState,
	snapshots: Array[TileSnapshot],
	rules: ClusterScoreRules
) -> Array[ClusterScoreResult]:
	var results: Array[ClusterScoreResult] = []
	if board == null or snapshots == null or snapshots.is_empty():
		return results
	for snapshot: TileSnapshot in snapshots:
		if snapshot == null or not snapshot.is_valid():
			return results
		if not board.is_empty_cell(snapshot.get_cell()):
			return results
	if rules == null or not rules.is_valid():
		return results

	var staged_cells: Array[Vector2i] = []
	for snapshot: TileSnapshot in snapshots:
		staged_cells.append(snapshot.get_cell())
	var hypothetical: BoardState = board.with_tiles(snapshots)

	# The colours the move forms a boundary of, keyed by colour, with the
	# committed partners that matched it.
	var touched: Dictionary = {}
	for snapshot: TileSnapshot in snapshots:
		var placed_cell: Vector2i = snapshot.get_cell()
		for offset: Vector2i in BoardEnums.neighbor_offsets():
			var neighbor: Vector2i = placed_cell + offset
			var position: int = BoardEnums.edge_position_toward(offset)
			var placed_color: int = snapshot.get_edge_at(position)
			if placed_color < 0:
				continue
			if staged_cells.has(neighbor):
				# A boundary between two staged tiles: the colour is in play even
				# with no committed neighbour.
				var other: TileSnapshot = _staged_at(snapshots, neighbor)
				if other == null:
					continue
				if other.get_edge_at(BoardEnums.opposite_edge_position(position)) != placed_color:
					continue
				if not touched.has(placed_color):
					touched[placed_color] = [] as Array[Vector2i]
				continue
			var neighbor_tile: TileSnapshot = board.get_tile(neighbor)
			if neighbor_tile == null:
				continue
			var neighbor_color: int = neighbor_tile.get_edge_at(
				BoardEnums.opposite_edge_position(position)
			)
			if neighbor_color != placed_color:
				continue
			if not touched.has(placed_color):
				touched[placed_color] = [] as Array[Vector2i]
			var neighbors: Array[Vector2i] = touched[placed_color]
			if not neighbors.has(neighbor):
				neighbors.append(neighbor)

	var colors: Array[int] = []
	for key: Variant in touched.keys():
		colors.append(int(key))
	colors.sort()

	for color: int in colors:
		var neighbors: Array[Vector2i] = touched[color]
		var seen_pre_keys: Dictionary = {}
		var previous_entitlement: int = 0
		for neighbor: Vector2i in neighbors:
			var region: Array[Vector2i] = _pre_move_region(board, neighbor, color)
			var key: StringName = ScoringEnums.component_key_for(color, region)
			if seen_pre_keys.has(key):
				continue
			seen_pre_keys[key] = true
			previous_entitlement += rules.entitlement_for_size(region.size())

		var seen_post_keys: Dictionary = {}
		var current_entitlement: int = 0
		var cluster_cells: Array[Vector2i] = []
		for cell: Vector2i in staged_cells:
			var component: Array[Vector2i] = component_of(hypothetical, cell, color)
			if component.is_empty():
				continue
			var component_key: StringName = ScoringEnums.component_key_for(color, component)
			if seen_post_keys.has(component_key):
				continue
			seen_post_keys[component_key] = true
			current_entitlement += rules.entitlement_for_size(component.size())
			for member: Vector2i in component:
				if not cluster_cells.has(member):
					cluster_cells.append(member)

		if cluster_cells.is_empty():
			continue
		var points: int = maxi(0, current_entitlement - previous_entitlement)
		if points <= 0:
			continue
		results.append(
			ClusterScoreResult.create(
				color,
				ScoringEnums.sort_cells(cluster_cells),
				previous_entitlement,
				current_entitlement,
				points
			)
		)

	results.sort_custom(
		func(a: ClusterScoreResult, b: ClusterScoreResult) -> bool:
			if a.color != b.color:
				return a.color < b.color
			return String(a.component_key) < String(b.component_key)
	)
	return results


## Returns the staged snapshot at `cell`, or null when none is staged there.
static func _staged_at(snapshots: Array[TileSnapshot], cell: Vector2i) -> TileSnapshot:
	for snapshot: TileSnapshot in snapshots:
		if snapshot != null and snapshot.get_cell() == cell:
			return snapshot
	return null


## Returns the pre-move colour region containing `cell`.
##
## `cell` is a neighbour that matches the incoming tile, so it is a vertex of the
## post-move graph. Before the placement it may or may not have been a vertex: if
## it was, its region is its pre-move component; if it was isolated in that
## colour, its region is the single tile. Either way the region's tile count is
## what the entitlement delta is measured against (ADR-002 section 5).
static func _pre_move_region(board: BoardState, cell: Vector2i, color: int) -> Array[Vector2i]:
	if is_vertex(board, cell, color):
		return component_of(board, cell, color)
	var region: Array[Vector2i] = [cell]
	return region


## Returns the orthogonally adjacent tiles connected to `cell` by `color`.
static func _matching_neighbors(board: BoardState, cell: Vector2i, color: int) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	if board == null:
		return neighbors
	for offset: Vector2i in BoardEnums.neighbor_offsets():
		var neighbor: Vector2i = cell + offset
		if matching_color_of(board, cell, neighbor) == color:
			neighbors.append(neighbor)
	return neighbors


## Returns the shared colour of a matching boundary, or -1.
##
## Delegates to `EdgeMatchScorer` so cluster connection and edge-match scoring can
## never disagree about what a matching boundary is.
static func matching_color_of(board: BoardState, a: Vector2i, b: Vector2i) -> int:
	return EdgeMatchScorer.matching_color(board, a, b)
