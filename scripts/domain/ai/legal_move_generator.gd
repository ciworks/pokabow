class_name LegalMoveGenerator
extends RefCounted

## Deterministic legal-candidate generation for one active tile
## (ADR-005 section 2).
##
## ADR-005 section 2 defines a legal move as an empty in-bounds cell, paired with
## rotation 0-3, that `PlacementValidator` accepts, and describes generation as:
##
##     legal moves = frontier cells x rotations -> rotate tile
##                 -> validate        (PlacementValidator)
##                 -> deduplicate     (identical visible edge tuples)
##                 -> placement candidates
##
## Read the frontier from the board, not by scanning the whole board: ADR-006
## section 7 makes the frontier exactly the cells a tile may legally occupy, so
## generation stays proportional to the frontier and stays deterministic in
## row-major order.
##
## Two properties are load-bearing:
##
## - the generator applies NO rule of its own. Every survivor is confirmed by
##   `PlacementValidator.validate()` with the tile marked available, so the AI
##   can never see a move a human could not make (ADR-005 section 2);
## - deduplication compares the visible rotated edge tuples, so rotationally
##   equivalent candidates collapse to their lowest rotation and the search does
##   not waste budget re-evaluating identical positions.
##
## This class holds no state and touches no scene node, so tests, replay, and the
## in-game AI all generate the same candidate list for the same inputs.

## Number of rotations tried per frontier cell (ADR-006 section 5).
const ROTATIONS_PER_CELL: int = TileEnums.ROTATION_COUNT


## Returns the deduplicated legal candidates, row-major by cell then rotation.
##
## Returns an empty array when the board, the tile, or the player identity is
## unusable. Callers distinguish "no candidate" from "bad input" by the
## diagnostics report, which is why `generate_with_report()` exists.
static func generate(
	board: BoardState,
	tile: TileDefinition,
	player_id: StringName
) -> Array[AiMoveCandidate]:
	var report: Dictionary = {}
	return generate_with_report(board, tile, player_id, report)


## Returns the deduplicated legal candidates and fills `report` with counts.
##
## `report` receives the raw candidate count, the deduplicated count, and the
## validator-rejected count, so ADR-005 section 12's diagnostics can report the
## search shape without re-deriving it.
static func generate_with_report(
	board: BoardState,
	tile: TileDefinition,
	player_id: StringName,
	report: Dictionary
) -> Array[AiMoveCandidate]:
	var candidates: Array[AiMoveCandidate] = []
	report["frontier_cells"] = 0
	report["generated"] = 0
	report["deduplicated"] = 0
	report["rejected"] = 0
	report["candidates"] = 0

	if board == null or tile == null or not tile.is_valid():
		return candidates

	var frontier: Array[Vector2i] = board.get_frontier_cells()
	report["frontier_cells"] = frontier.size()

	for cell: Vector2i in frontier:
		# Rotations whose visible edge tuple is already present at this cell can
		# never produce a different board state, so they are dropped before
		# validation (ADR-005 section 2).
		var seen_edge_keys: Dictionary = {}
		for rotation: int in range(ROTATIONS_PER_CELL):
			report["generated"] = int(report["generated"]) + 1
			var edge_key: String = visible_edge_key(tile, rotation)
			if seen_edge_keys.has(edge_key):
				report["deduplicated"] = int(report["deduplicated"]) + 1
				continue
			seen_edge_keys[edge_key] = true

			var request: PlacementRequest = PlacementRequest.create(
				player_id, tile.tile_id, cell, rotation
			)
			var result: PlacementResult = PlacementValidator.validate(
				board, request, tile, true
			)
			if result == null or not result.accepted or result.placed_tile == null:
				report["rejected"] = int(report["rejected"]) + 1
				continue
			candidates.append(
				AiMoveCandidate.create(cell, rotation, result.placed_tile, tile.tile_id)
			)

	candidates.sort_custom(compare_candidates)
	report["candidates"] = candidates.size()
	return candidates


## Returns a comparable key for a tile's visible edges in one rotation.
##
## The key is the visible edge tuple (ADR-004 section 4), so two rotations with
## the same colours across all four positions are recognised as equivalent.
static func visible_edge_key(tile: TileDefinition, rotation: int) -> String:
	if tile == null:
		return ""
	var edges: Array[TileEnums.EdgeColor] = tile.get_rotated_edges(rotation)
	if edges.size() != TileEnums.EDGE_COUNT:
		return ""
	return "%d-%d-%d-%d" % [int(edges[0]), int(edges[1]), int(edges[2]), int(edges[3])]


## Returns true when `a` sorts before `b`: cell row-major, then rotation.
##
## The fixed order is what makes generation reproducible, and it is the order
## the diagnostics and tests quote (ADR-005 sections 2 and 10).
static func compare_candidates(a: AiMoveCandidate, b: AiMoveCandidate) -> bool:
	var index_a: int = BoardEnums.cell_index(a.cell)
	var index_b: int = BoardEnums.cell_index(b.cell)
	if index_a != index_b:
		return index_a < index_b
	return a.rotation < b.rotation


## Returns true when every candidate is accepted by the placement validator.
##
## Verification helper for tests and debugging (ADR-005 "Required tests"): it
## re-runs the authoritative validator over a candidate list and reports whether
## generation and legality still agree.
static func all_candidates_are_legal(
	board: BoardState,
	candidates: Array[AiMoveCandidate],
	tile: TileDefinition,
	player_id: StringName
) -> bool:
	if board == null or tile == null:
		return false
	for candidate: AiMoveCandidate in candidates:
		if candidate == null:
			return false
		var request: PlacementRequest = PlacementRequest.create(
			player_id, tile.tile_id, candidate.cell, candidate.rotation
		)
		var result: PlacementResult = PlacementValidator.validate(board, request, tile, true)
		if result == null or not result.accepted:
			return false
	return true
