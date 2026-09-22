class_name AiMoveCandidate
extends RefCounted

## One legal placement the AI may propose (ADR-005 sections 2, 5, 6, and 10).
##
## ADR-005 section 2 makes a candidate exactly one legal (cell, rotation) pair
## with its prospective tile snapshot, so a candidate can be committed by the
## normal ADR-007 transaction without being rebuilt. Scoring is attached here
## rather than recomputed: `apply_breakdown()` is the only place the ADR-007
## category breakdown is mapped onto candidate fields, so preview and search can
## never disagree about which number belongs to which field.
##
## The ranking fields are exactly ADR-005 section 5's tuple (total, poker,
## cluster, edge-match, distinct event count) plus section 6's Hard fields and
## section 10's deterministic tie-break value.
##
## A candidate owns no rules, no board, and no scene node; it is a plain record.

## Board coordinate of the proposed placement (ADR-006 section 1).
var cell: Vector2i = Vector2i.ZERO

## Quarter-turn index 0-3 of the proposed placement (ADR-006 section 5).
var rotation: int = 0

## The tile as it would be committed, or null when the candidate is unscored.
var snapshot: TileSnapshot = null

## Total immediate points of this placement (ADR-007 preview total).
var immediate_score: int = 0

## Points contributed by poker hands (ADR-005 section 5, field 2).
var poker_points: int = 0

## Points contributed by matching edges (ADR-005 section 5, field 4).
var edge_points: int = 0

## Points contributed by completed clusters (ADR-005 section 5, field 3).
var cluster_points: int = 0

## Number of distinct score events, used as field 5 of the ranking tuple.
var event_count: int = 0

## Canonical identifier of this placement, used for deterministic tie-breaking.
var move_key: String = ""

## Deterministic tie-break value derived from the decision seed and `move_key`
## (ADR-005 section 10). Zero until a strategy prepares the candidate.
var tie_break_value: int = 0

## True once ADR-005 section 6's two-ply evaluation has scored this candidate.
var deep_evaluated: bool = false

## Hard's ranking value (ADR-005 section 6 utility).
var utility: int = 0

## Expected best immediate score available to the opponent after this move,
## averaged over the representative sample (ADR-005 section 6).
var expected_reply_points: float = 0.0

## Opportunities retained or created for later turns (ADR-005 section 7).
var ai_open_opportunity: int = 0

## Publicly visible completion cells left to the next player (ADR-005 section 7).
var human_open_threat: int = 0

## Matching boundaries this placement creates (ADR-005 section 6 connectivity
## term). The ADR names the term without qualifying it; it is read here as the
## connectivity the candidate itself contributes, because the board-wide total
## does not differ between candidates on the same revision.
var matched_edge_count: int = 0


## Builds a candidate. `tile_id` supplies the canonical move key.
static func create(
	cell: Vector2i,
	rotation: int,
	snapshot: TileSnapshot,
	tile_id: StringName
) -> AiMoveCandidate:
	var candidate: AiMoveCandidate = AiMoveCandidate.new()
	candidate.cell = cell
	candidate.rotation = rotation
	candidate.snapshot = snapshot
	candidate.move_key = move_key_for(tile_id, cell, rotation)
	return candidate


## Returns the canonical key of one placement.
##
## ADR-005 section 10 requires ties to be resolved from stable candidate
## identity, never from iteration order or object address, so the key is built
## from the tile identity and the placement alone.
static func move_key_for(tile_id: StringName, cell: Vector2i, rotation: int) -> String:
	return "ai-move:%s:%d,%d:%d" % [
		String(tile_id), cell.x, cell.y, rotation,
	]


## Returns true when the ADR-007 preview numbers have been attached.
func is_scored() -> bool:
	return snapshot != null


## Copies an ADR-007 `ScoringCoordinator.breakdown()` report onto this candidate.
##
## The report keys are the scorer's; mapping them here keeps the field meaning in
## one place (AGENTS.md section 15).
func apply_breakdown(report: Dictionary) -> void:
	poker_points = int(report.get("poker_points", 0))
	edge_points = int(report.get("edge_points", 0))
	cluster_points = int(report.get("cluster_points", 0))
	immediate_score = int(report.get("total_points", 0))
	event_count = (
		int(report.get("poker_count", 0))
		+ int(report.get("edge_count", 0))
		+ int(report.get("cluster_count", 0))
	)


## Returns the ADR-005 section 5 ranking tuple as a readable label.
func ranking_label() -> String:
	return "total %d, poker %d, cluster %d, edge %d, events %d" % [
		immediate_score, poker_points, cluster_points, edge_points, event_count,
	]


## Returns a short description of this candidate, for diagnostics only.
func describe() -> String:
	return "%s -> %s" % [move_key, ranking_label()]
