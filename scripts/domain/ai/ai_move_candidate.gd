class_name AiMoveCandidate
extends RefCounted

## One legal LINE the AI may propose (ADR-011 section 12, over ADR-005 sections 2,
## 5, 6, and 10).
##
## ADR-011 section 1 makes a move one line of two or more deck tiles committed
## atomically, and section 12 retargets AI move generation to "one line per
## candidate". A candidate therefore carries the whole line: the deck tiles it
## uses, the cells they target, their rotations, and the tile snapshots that
## commit them together. Nothing here chooses the line: the snapshots are always
## the ones `LineValidator` accepted, so a candidate can never be built from an
## illegal line (sections 1 to 4).
##
## Scoring is attached rather than recomputed: `apply_transaction()` is the only
## place an ADR-007 line transaction is mapped onto candidate fields, so preview,
## search, and diagnostics can never disagree about which number belongs to which
## field (AGENTS.md section 15).
##
## The ranking fields are exactly ADR-005 section 5's tuple (total, poker,
## cluster, edge-match, distinct event count) plus section 6's Hard fields and
## section 10's deterministic tie-break value.
##
## A candidate owns no rules, no board, and no scene node; it is a plain record.

## The line as it would be committed, in line order (ADR-011 sections 2 and 5).
var snapshots: Array[TileSnapshot] = []

## The target cells, in the same order as `snapshots` (ADR-011 section 1).
var cells: Array[Vector2i] = []

## The deck tile identities, in the same order as `snapshots` (ADR-010 section 4).
var tile_ids: Array[StringName] = []

## Quarter-turn index 0-3 of each tile, in the same order as `snapshots`.
var rotations: Array[int] = []

## `ScoringEnums.HandOrientation` value of the line, never -1 for a candidate.
var orientation: int = -1

## Number of cells of the merged line the hand is judged over (ADR-011 section 2).
var merged_size: int = 0

## The merged line's face ranks, in line order (ADR-011 section 3).
var merged_ranks: Array[int] = []

## The merged line's poker category, or `NONE` when it is not five cells long.
var hand_category: int = ScoringEnums.PokerHandCategory.NONE

## True when the line joins tiles already committed to the board (section 2).
var extends_board_line: bool = false

## Total immediate points of this line (ADR-007 preview total).
var immediate_score: int = 0

## Points contributed by poker hands (ADR-005 section 5, field 2).
var poker_points: int = 0

## Points contributed by matching edges (ADR-005 section 5, field 4).
var edge_points: int = 0

## Points contributed by completed clusters (ADR-005 section 5, field 3).
var cluster_points: int = 0

## Number of distinct score events, used as field 5 of the ranking tuple.
var event_count: int = 0

## Canonical identifier of this line, used for deterministic tie-breaking.
var move_key: String = ""

## Deterministic tie-break value derived from the decision seed and `move_key`
## (ADR-005 section 10). Zero until a strategy prepares the candidate.
var tie_break_value: int = 0

## True once ADR-005 section 6's two-ply evaluation has scored this candidate.
var deep_evaluated: bool = false

## Hard's ranking value (ADR-005 section 6 utility).
var utility: int = 0

## Expected best immediate score available to the opponent after this line,
## averaged over the representative sample (ADR-005 section 6).
var expected_reply_points: float = 0.0

## Opportunities retained or created for later turns (ADR-005 section 7).
var ai_open_opportunity: int = 0

## Publicly visible completion cells left to the next player (ADR-005 section 7).
var human_open_threat: int = 0

## Matching boundaries this line creates (ADR-005 section 6 connectivity term).
## ADR-011 section 5 makes the whole line one atomic move, so the term is read
## from the line: two staged tiles can match each other, and a per-tile count
## cannot see that boundary.
var matched_edge_count: int = 0


## Builds a candidate from a line the shared validator accepted.
##
## The line is taken from `result.staged_tiles`, which `LineValidator` returns in
## line order, so a caller cannot influence the committed cell order.
static func create(line: Array[TileSnapshot], result: LineResult) -> AiMoveCandidate:
	var candidate: AiMoveCandidate = AiMoveCandidate.new()
	if line == null:
		return candidate
	for snapshot: TileSnapshot in line:
		if snapshot == null or not snapshot.is_valid():
			return candidate
		candidate.snapshots.append(snapshot)
		candidate.cells.append(snapshot.get_cell())
		candidate.tile_ids.append(snapshot.get_tile_id())
		candidate.rotations.append(snapshot.get_rotation())
	candidate.move_key = move_key_for(candidate.cells, candidate.rotations, candidate.tile_ids)
	if result != null:
		candidate.orientation = result.orientation
		candidate.merged_size = result.merged_size()
		candidate.merged_ranks = result.merged_ranks.duplicate()
		candidate.hand_category = result.hand_category
		candidate.extends_board_line = result.is_extending_a_board_line()
	return candidate


## Returns the canonical key of one line.
##
## ADR-005 section 10 requires ties to be resolved from stable candidate
## identity, never from iteration order or object address, so the key is built
## from the line's cells, rotations, and tile identities alone.
static func move_key_for(
	cells: Array[Vector2i], rotations: Array[int], tile_ids: Array[StringName]
) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if cells == null:
		return ""
	for index: int in range(cells.size()):
		var cell: Vector2i = cells[index]
		var rotation: int = 0
		if rotations != null and index < rotations.size():
			rotation = rotations[index]
		var tile_id: String = ""
		if tile_ids != null and index < tile_ids.size():
			tile_id = String(tile_ids[index])
		parts.append("%d,%d:%d:%s" % [cell.x, cell.y, rotation, tile_id])
	return "ai-line:%s" % "|".join(parts)


## Returns how many tiles the line stages, which is the move's tile count.
func length() -> int:
	return snapshots.size()


## Returns the first tile of the line in line order, or null.
func anchor_snapshot() -> TileSnapshot:
	if snapshots.is_empty():
		return null
	return snapshots[0]


## Returns the first cell of the line in line order, or the origin.
func anchor_cell() -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	return cells[0]


## Returns true when the line can be committed as a move.
##
## ADR-011 sections 1 and 4 make a single tile illegal, so a one-tile candidate
## is never committable even though it is representable.
func is_committable() -> bool:
	return not snapshots.is_empty()


## Returns true when the ADR-007 preview numbers have been attached.
func is_scored() -> bool:
	return not snapshots.is_empty() and (immediate_score != 0 or event_count > 0)


## Copies an ADR-007 line transaction onto this candidate.
##
## The categories are the scorer's; mapping them here keeps the field meaning in
## one place, and the total is derived from them so the four numbers can never
## disagree (AGENTS.md section 15).
func apply_transaction(transaction: ScoreTransaction) -> void:
	poker_points = 0
	edge_points = 0
	cluster_points = 0
	event_count = 0
	immediate_score = 0
	if transaction == null or transaction.events == null:
		return
	for event: ScoreEvent in transaction.events:
		if event == null:
			continue
		match event.category:
			ScoringEnums.ScoreCategory.POKER_HAND:
				poker_points += event.points
			ScoringEnums.ScoreCategory.EDGE_MATCH:
				edge_points += event.points
			ScoringEnums.ScoreCategory.EDGE_CLUSTER:
				cluster_points += event.points
	event_count = transaction.events.size()
	immediate_score = poker_points + edge_points + cluster_points


## Returns the ADR-005 section 5 ranking tuple as a readable label.
func ranking_label() -> String:
	return "total %d, poker %d, cluster %d, edge %d, events %d" % [
		immediate_score, poker_points, cluster_points, edge_points, event_count,
	]


## Returns the line's cells as a readable label, for diagnostics only.
func cells_label() -> String:
	return ScoringEnums.cells_label(cells)


## Returns a short description of this candidate, for diagnostics only.
func describe() -> String:
	return "%s (%d tile(s) %s) -> %s" % [
		move_key,
		snapshots.size(),
		ScoringEnums.orientation_name(orientation),
		ranking_label(),
	]
