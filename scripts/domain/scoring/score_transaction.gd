class_name ScoreTransaction
extends RefCounted

## A set of proposed score events from one placement (ADR-007 sections 3, 4, and 8).
##
## ADR-007 section 3 requires incremental calculators to evaluate a read-only
## hypothetical board: the current committed `BoardState` plus one validated
## proposed placement. The transaction is that evaluation's output. Generating it
## never updates board cells, scored window identifiers, cluster entitlements, the
## ledger, player totals, or turn state.
##
## The same transaction type serves preview and commit, which is what stops
## preview rules from drifting away from committed rules (ADR-007 section 8). A
## commit on the same board revision must produce the same events and points as
## the preview that preceded it.
##
## `board_revision_before` records the revision the transaction was calculated
## against, so a stale preview can be detected and discarded rather than applied
## to a board that has moved on.

## Deterministic move identifier this transaction belongs to.
var move_id: StringName = &""

## Board revision the transaction was calculated against.
var board_revision_before: int = 0

## The player who would be credited with these events.
var player_id: StringName = &""

## Proposed events in the deterministic order of ADR-007 section 7: poker by hand
## identifier, then edge matches by boundary identifier, then clusters by colour.
var events: Array[ScoreEvent] = []

## The coordinate the placement targets.
var placed_cell: Vector2i = Vector2i.ZERO


## Builds a transaction. The caller's event array is copied.
static func create(
	move_id: StringName,
	board_revision_before: int,
	player_id: StringName,
	events: Array[ScoreEvent],
	placed_cell: Vector2i
) -> ScoreTransaction:
	var transaction: ScoreTransaction = ScoreTransaction.new()
	transaction.move_id = move_id
	transaction.board_revision_before = board_revision_before
	transaction.player_id = player_id
	transaction.events = events.duplicate()
	transaction.placed_cell = placed_cell
	return transaction


## Returns the total points this transaction would award.
func total_points() -> int:
	var total: int = 0
	for event: ScoreEvent in events:
		total += event.points
	return total


## Returns the proposed events of one category, in order.
func events_for_category(category: int) -> Array[ScoreEvent]:
	var selected: Array[ScoreEvent] = []
	for event: ScoreEvent in events:
		if event.category == category:
			selected.append(event)
	return selected


## Returns the points this transaction would award in one category.
func points_for_category(category: int) -> int:
	var total: int = 0
	for event: ScoreEvent in events:
		if event.category == category:
			total += event.points
	return total


## Returns true when nothing would be awarded.
func is_empty() -> bool:
	return events.is_empty()


## Returns every proposed event identifier, in order.
func event_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for event: ScoreEvent in events:
		ids.append(event.event_id)
	return ids


## Returns a short human-readable summary, for diagnostics only.
func describe() -> String:
	return "move %s at %s against revision %d: %d event(s), %d point(s)" % [
		String(move_id),
		BoardEnums.cell_name(placed_cell),
		board_revision_before,
		events.size(),
		total_points(),
	]


## Returns a JSON-safe dictionary, for fixtures and diagnostics overlays.
func to_dictionary() -> Dictionary:
	var records: Array = []
	for event: ScoreEvent in events:
		records.append(event.to_dictionary())
	return {
		"move_id": String(move_id),
		"board_revision_before": board_revision_before,
		"player_id": String(player_id),
		"placed_cell": [placed_cell.x, placed_cell.y],
		"total_points": total_points(),
		"events": records,
	}
