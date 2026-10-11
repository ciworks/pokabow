class_name ScoringCoordinator
extends RefCounted

## Orchestrates the pure calculators into preview and commit transactions
## (ADR-007 sections 2, 3, 4, and 7).
##
## ADR-007 section 2 requires the same three calculators to serve human preview,
## committed move resolution, AI evaluation, and replay verification; this class
## is the single place that calls all three and normalises their output, so no
## caller re-implements the ordering or the identifier formats.
##
## Two entry points:
## - `preview()` returns a non-authoritative `ScoreTransaction` and changes
##   nothing at all (ADR-007 section 3).
## - `commit_placement()` performs the board-plus-score half of ADR-007
##   section 4: it builds the events against the pre-move board, refuses a
##   duplicate event identifier, then commits the tile, the ledger, and the
##   scored-window set.
##
## Turn advancement is deliberately absent: ADR-003 owns it and Milestone 4
## integrates it. Until then a caller sequences validation, commit, and its own
## turn bookkeeping, which is exactly what the Milestone 3 exit criterion does.

## Preview uses a fixed placeholder move identity, because a preview must not
## consume a real move identifier (ADR-007 section 3).
const PREVIEW_MOVE_ID: StringName = &"preview"


## Returns the deterministic move identifier for one placement
## (ADR-010 section 9): `move:<match-id>:<turn-number>:<placement-index>`.
##
## ADR-010 section 9 replaces ADR-007 section 5's
## `move:<match-id>:<turn-number>` because a turn may now hold several placements
## and the shorter form is no longer unique; uniqueness is what makes
## duplicate-commit refusal idempotent under ADR-007 section 5.
##
## `placement_index` is 1-based within the turn. It defaults to 1, the first
## placement of the turn, so the two-argument ADR-007 form still names a move;
## a non-positive index is treated as 1 for the same reason. Score event
## identifiers keep their shape and inherit the whole identifier (ADR-007
## section 5).
static func move_id_for(
	match_id: StringName, turn_number: int, placement_index: int = 1
) -> StringName:
	if String(match_id).is_empty() or turn_number <= 0:
		return &""
	var index: int = placement_index
	if index <= 0:
		index = 1
	return StringName("move:%s:%d:%d" % [String(match_id), turn_number, index])


## Returns the events a placement would create, in ADR-007 section 7 order.
##
## `board` is the pre-move board and `snapshot` the tile about to be committed.
## Order is poker events by hand identifier, then edge matches by boundary
## identifier, then cluster events by colour and component key. The numeric total
## is independent of that order; ordering exists for reproducible saves, replays,
## tests, animations, and debugging.
##
## Returns an empty array rather than a partial one when the inputs are unusable,
## so a caller can never commit half a move's events.
static func build_events(
	board: BoardState,
	snapshot: TileSnapshot,
	player_id: StringName,
	move_id: StringName,
	turn_number: int,
	rules: ScoringRules,
	scored_hand_ids: ScoredHandSet
) -> Array[ScoreEvent]:
	# ADR-011 section 5 makes a move one line, so the single-tile entry point is
	# the one-tile case of the line entry point. Routing it through the same
	# function is what stops the two from drifting apart (AGENTS.md section 15);
	# a lone tile is not a legal move (ADR-011 sections 1 and 4), so callers of
	# this overload are replay and test paths, not the live commit path.
	var events: Array[ScoreEvent] = []
	if board == null or snapshot == null or not snapshot.is_valid():
		return events
	var group: Array[TileSnapshot] = [snapshot]
	return build_events_for_line(
		board, group, player_id, move_id, turn_number, rules, scored_hand_ids
	)


## Returns the events a whole line of tiles would create, in ADR-007 section 7
## order (ADR-011 sections 5 and 10).
##
## ADR-011 section 5 commits an assembled line as one atomic move and section 10
## leaves scoring untouched, so this is `build_events` with the unit changed: the
## event identifiers still carry the move identity, and every calculator is the
## same one the single-tile path used. `board` is the pre-move board and
## `snapshots` the tiles the move writes.
##
## A move may complete several five-cell windows, including windows that span its
## staged tiles and the committed tiles it joins (ADR-011 section 2), so the
## candidate windows are the windows of every contiguous run through the staged
## cells rather than of a single coordinate. The poker results are then ordered by
## canonical window identifier, exactly as before.
##
## Returns an empty array rather than a partial one when the inputs are unusable,
## so a caller can never commit half a move's events.
static func build_events_for_line(
	board: BoardState,
	snapshots: Array[TileSnapshot],
	player_id: StringName,
	move_id: StringName,
	turn_number: int,
	rules: ScoringRules,
	scored_hand_ids: ScoredHandSet
) -> Array[ScoreEvent]:
	var events: Array[ScoreEvent] = []
	if board == null or snapshots == null or snapshots.is_empty():
		return events
	var staged_cells: Array[Vector2i] = []
	for snapshot: TileSnapshot in snapshots:
		if snapshot == null or not snapshot.is_valid():
			return events
		if not board.is_empty_cell(snapshot.get_cell()):
			return events
		staged_cells.append(snapshot.get_cell())
	if not _inputs_are_usable(rules, player_id, move_id):
		return events

	var rules_version: String = rules.version_key()
	var hypothetical: BoardState = board.with_tiles(snapshots)

	var poker_results: Array[PokerHandResult] = []
	for window: Variant in PokerHandEvaluator.hands_through_cells(hypothetical, staged_cells):
		var cells: Array[Vector2i] = window
		var result: PokerHandResult = PokerHandEvaluator.evaluate_window(
			hypothetical, cells, rules.poker
		)
		if result == null:
			continue
		if scored_hand_ids != null and scored_hand_ids.has(result.hand_id):
			continue
		poker_results.append(result)
	poker_results.sort_custom(
		func(a: PokerHandResult, b: PokerHandResult) -> bool:
			return String(a.hand_id) < String(b.hand_id)
	)

	for result: PokerHandResult in poker_results:
		var boundary_ids: Array[StringName] = HandMultiplierScorer.new_boundary_ids(
			hypothetical, result.cells, staged_cells
		)
		var card_points: int = HandMultiplierScorer.card_points(hypothetical, result.cells)
		var card_multiplier: int = HandMultiplierScorer.card_multiplier(hypothetical, result.cells)
		var edge_multiplier: int = HandMultiplierScorer.edge_multiplier_from_ids(
			hypothetical, result.cells, boundary_ids
		)
		var hand_points: int = (result.points + card_points) * card_multiplier * edge_multiplier
		var boundary_labels: Array[String] = []
		for boundary_id: StringName in boundary_ids:
			boundary_labels.append(String(boundary_id))
		var evidence: Dictionary = {
			"hand_id": String(result.hand_id),
			"category": result.get_category_name(),
			"cells": ScoringEnums.cells_label(result.cells),
			"category_points": result.points,
			"card_points": card_points,
			"card_multiplier": card_multiplier,
			"edge_multiplier": edge_multiplier,
			"new_hand_boundaries": boundary_labels,
		}
		events.append(
			ScoreEvent.create(
				ScoringEnums.event_id_for(
					move_id,
					ScoringEnums.ScoreCategory.POKER_HAND,
					String(result.hand_id)
				),
				move_id,
				player_id,
				ScoringEnums.ScoreCategory.POKER_HAND,
				hand_points,
				result.cells,
				evidence,
				turn_number,
				rules_version
			)
		)

	# ADR-011 section 5 makes the whole line one move and section 10 leaves
	# ADR-002 section 1's +1 per new matching boundary unchanged, so the boundary
	# set is read ONCE over the whole line. The line form is what sees a boundary
	# between two staged tiles, which a per-tile evaluation against the pre-move
	# board cannot see; it de-duplicates by canonical boundary identifier itself,
	# so a boundary is never credited twice.
	var edge_results: Array[EdgeMatchResult] = EdgeMatchScorer.evaluate_line(board, snapshots)

	for result: EdgeMatchResult in edge_results:
		var evidence: Dictionary = {
			"boundary_id": String(result.boundary_id),
			"color": result.get_color_name(),
		}
		events.append(
			ScoreEvent.create(
				ScoringEnums.event_id_for(
					move_id,
					ScoringEnums.ScoreCategory.EDGE_MATCH,
					String(result.boundary_id)
				),
				move_id,
				player_id,
				ScoringEnums.ScoreCategory.EDGE_MATCH,
				result.points,
				result.cells,
				evidence,
				turn_number,
				rules_version
			)
		)

	# ADR-007 section 5 documents the cluster identifier as
	# `score:<move-id>:cluster:<color>:<ordinal>`. The ordinal is 1-based within
	# this move and counts per colour, so it is deterministic because the scorer
	# returns clusters ordered by colour and then component key. The canonical
	# component key travels in the event evidence instead, where ADR-002 section 7
	# places it.
	var cluster_ordinals: Dictionary = {}
	for result: ClusterScoreResult in EdgeClusterScorer.evaluate_line(
		board, snapshots, rules.cluster
	):
		var color_key: String = result.get_color_name().to_lower()
		var ordinal: int = int(cluster_ordinals.get(color_key, 0)) + 1
		cluster_ordinals[color_key] = ordinal
		var evidence: Dictionary = {
			"color": result.get_color_name(),
			"component_key": String(result.component_key),
			"previous_entitlement": result.previous_entitlement,
			"current_entitlement": result.current_entitlement,
			"delta": result.points,
		}
		events.append(
			ScoreEvent.create(
				ScoringEnums.event_id_for(
					move_id,
					ScoringEnums.ScoreCategory.EDGE_CLUSTER,
					"%s:%d" % [color_key, ordinal]
				),
				move_id,
				player_id,
				ScoringEnums.ScoreCategory.EDGE_CLUSTER,
				result.points,
				result.cells,
				evidence,
				turn_number,
				rules_version
			)
		)

	# The append order above IS the ADR-007 section 7 order: poker by hand
	# identifier, then edge matches by boundary identifier, then clusters by colour
	# and component evidence. Each calculator already returns its own events in
	# canonical order, so re-sorting here would break the required category order
	# (sorting by event identifier would put "cluster" before "edge" before
	# "poker").
	return events


## Returns a non-authoritative preview of what a whole line would score
## (ADR-011 section 5).
##
## ADR-007 section 3's guarantees are unchanged: preview never updates board
## cells, scored window identifiers, cluster indexes, the ledger, player totals,
## or turn state, and the transaction carries the revision it was calculated
## against. The unit is the line, so the transaction's `placed_cell` is the line's
## first staged cell and every event belongs to the one provisional move identity.
static func preview_line(
	board: BoardState,
	snapshots: Array[TileSnapshot],
	player_id: StringName,
	rules: ScoringRules,
	scored_hand_ids: ScoredHandSet = null,
	turn_number: int = 0
) -> ScoreTransaction:
	var no_events: Array[ScoreEvent] = []
	if board == null or snapshots == null or snapshots.is_empty():
		return ScoreTransaction.create(
			PREVIEW_MOVE_ID, 0, player_id, no_events, Vector2i.ZERO
		)

	var events: Array[ScoreEvent] = build_events_for_line(
		board, snapshots, player_id, PREVIEW_MOVE_ID, turn_number, rules, scored_hand_ids
	)
	return ScoreTransaction.create(
		PREVIEW_MOVE_ID,
		board.get_revision(),
		player_id,
		events,
		snapshots[0].get_cell()
	)


## Commits a whole line's board and score changes as one prepared batch
## (ADR-007 section 4, ADR-011 section 5).
##
## The transaction is the one ADR-007 section 4 describes with the unit changed
## from a tile to a line: build the hypothetical post-move board, generate the
## proposed events, refuse a duplicate identifier, then write the board, the
## ledger, and the scored-window set together. The whole line is written by the
## board's own batch commit, so a refusal leaves the board exactly as it was --
## a half-written line is not reachable.
##
## Returns an empty transaction, with nothing mutated, when any precondition
## fails.
static func commit_line(
	board: BoardState,
	snapshots: Array[TileSnapshot],
	ledger: ScoreLedger,
	scored_hand_ids: ScoredHandSet,
	player_id: StringName,
	move_id: StringName,
	turn_number: int,
	rules: ScoringRules
) -> ScoreTransaction:
	var no_events: Array[ScoreEvent] = []
	if board == null or ledger == null or scored_hand_ids == null:
		push_error(
			"ScoringCoordinator.commit_line: a board, ledger, and scored-hand set are required."
		)
		return ScoreTransaction.create(move_id, 0, player_id, no_events, Vector2i.ZERO)
	if snapshots == null or snapshots.is_empty():
		return ScoreTransaction.create(
			move_id, board.get_revision(), player_id, no_events, Vector2i.ZERO
		)

	var anchor: Vector2i = snapshots[0].get_cell()
	var revision: int = board.get_revision()
	for snapshot: TileSnapshot in snapshots:
		if snapshot == null or not snapshot.is_valid() or not board.is_empty_cell(snapshot.get_cell()):
			return ScoreTransaction.create(move_id, revision, player_id, no_events, anchor)

	var events: Array[ScoreEvent] = build_events_for_line(
		board, snapshots, player_id, move_id, turn_number, rules, scored_hand_ids
	)

	# Reject a repeated event identifier before anything is mutated, so a commit
	# retry can never award the same points twice (ADR-007 sections 5 and 11).
	for event: ScoreEvent in events:
		if ledger.has_event(event.event_id):
			push_error(
				"ScoringCoordinator.commit_line: event '%s' is already committed; refusing to score twice."
				% String(event.event_id)
			)
			return ScoreTransaction.create(move_id, revision, player_id, no_events, anchor)

	# Window identifiers are recorded only for windows that actually scored, which
	# is what makes each window score once for the whole match (ADR-001 section 5).
	var pending_hand_ids: Array[StringName] = []
	for event: ScoreEvent in events:
		if event.category != ScoringEnums.ScoreCategory.POKER_HAND:
			continue
		pending_hand_ids.append(StringName(String(event.evidence.get("hand_id", ""))))

	if not board.commit_tiles(snapshots):
		push_error(
			"ScoringCoordinator.commit_line: the board refused a validated line commit at %s."
			% BoardEnums.cell_name(anchor)
		)
		return ScoreTransaction.create(move_id, revision, player_id, no_events, anchor)

	for event: ScoreEvent in events:
		if not ledger.add(event):
			push_error(
				"ScoringCoordinator.commit_line: the ledger refused event '%s' after the board commit; board and ledger now disagree."
				% String(event.event_id)
			)
			return ScoreTransaction.create(move_id, revision, player_id, no_events, anchor)
	for hand_id: StringName in pending_hand_ids:
		scored_hand_ids.add(hand_id)

	return ScoreTransaction.create(move_id, revision, player_id, events, anchor)


## Returns a non-authoritative preview of what a placement would score.
##
## ADR-007 section 3: preview never updates board cells, scored window
## identifiers, cluster indexes, the ledger, player totals, or turn state. The
## transaction records the board revision it was calculated against, so a stale
## preview can be detected and discarded rather than applied
## (ADR-007 section 8).
static func preview(
	board: BoardState,
	snapshot: TileSnapshot,
	player_id: StringName,
	rules: ScoringRules,
	scored_hand_ids: ScoredHandSet = null,
	turn_number: int = 0
) -> ScoreTransaction:
	var no_events: Array[ScoreEvent] = []
	if board == null or snapshot == null:
		return ScoreTransaction.create(
			PREVIEW_MOVE_ID, 0, player_id, no_events, Vector2i.ZERO
		)

	var events: Array[ScoreEvent] = build_events(
		board,
		snapshot,
		player_id,
		PREVIEW_MOVE_ID,
		turn_number,
		rules,
		scored_hand_ids
	)
	return ScoreTransaction.create(
		PREVIEW_MOVE_ID, board.get_revision(), player_id, events, snapshot.get_cell()
	)


## Commits a placement's board and score changes as one prepared batch.
##
## This is ADR-007 section 4 steps 3 to 7 for the in-memory half of a move:
## build the hypothetical post-placement board, generate proposed events,
## validate them, prepare the board, ledger, and scored-window updates, then
## commit them together. Turn advancement (step 9) is ADR-003 and Milestone 4.
##
## Returns an empty transaction, with nothing mutated, when any precondition
## fails. The one failure that cannot be undone after the board write is a ledger
## refusal, so duplicate event identifiers are rejected before the board is
## touched; a post-write refusal would mean the ledger and the board disagree, and
## is reported as an internal error (ADR-007 section 11).
static func commit_placement(
	board: BoardState,
	snapshot: TileSnapshot,
	ledger: ScoreLedger,
	scored_hand_ids: ScoredHandSet,
	player_id: StringName,
	move_id: StringName,
	turn_number: int,
	rules: ScoringRules
) -> ScoreTransaction:
	var no_events: Array[ScoreEvent] = []
	if board == null or ledger == null or scored_hand_ids == null:
		push_error(
			"ScoringCoordinator.commit_placement: a board, ledger, and scored-hand set are required."
		)
		return ScoreTransaction.create(move_id, 0, player_id, no_events, Vector2i.ZERO)
	if snapshot == null or not snapshot.is_valid():
		return ScoreTransaction.create(
			move_id, board.get_revision(), player_id, no_events, Vector2i.ZERO
		)

	var cell: Vector2i = snapshot.get_cell()
	var revision: int = board.get_revision()
	if not board.is_empty_cell(cell):
		return ScoreTransaction.create(move_id, revision, player_id, no_events, cell)

	var events: Array[ScoreEvent] = build_events(
		board, snapshot, player_id, move_id, turn_number, rules, scored_hand_ids
	)

	# Reject a repeated event identifier before anything is mutated, so a commit
	# retry can never award the same points twice (ADR-007 sections 5 and 11).
	for event: ScoreEvent in events:
		if ledger.has_event(event.event_id):
			push_error(
				"ScoringCoordinator.commit_placement: event '%s' is already committed; refusing to score twice."
				% String(event.event_id)
			)
			return ScoreTransaction.create(move_id, revision, player_id, no_events, cell)

	# Window identifiers are recorded only for windows that actually scored, which
	# is what makes each window score once for the whole match (ADR-001 section 5).
	var pending_hand_ids: Array[StringName] = []
	for event: ScoreEvent in events:
		if event.category != ScoringEnums.ScoreCategory.POKER_HAND:
			continue
		pending_hand_ids.append(StringName(String(event.evidence.get("hand_id", ""))))

	if not board.commit_tile(snapshot):
		push_error(
			"ScoringCoordinator.commit_placement: the board refused a validated commit at %s."
			% BoardEnums.cell_name(cell)
		)
		return ScoreTransaction.create(move_id, revision, player_id, no_events, cell)

	for event: ScoreEvent in events:
		if not ledger.add(event):
			push_error(
				"ScoringCoordinator.commit_placement: the ledger refused event '%s' after the board commit; board and ledger now disagree."
				% String(event.event_id)
			)
			return ScoreTransaction.create(move_id, revision, player_id, no_events, cell)
	for hand_id: StringName in pending_hand_ids:
		scored_hand_ids.add(hand_id)

	return ScoreTransaction.create(move_id, revision, player_id, events, cell)


## Returns a category-by-category breakdown of what a placement would score.
##
## Intended for preview UI, AI heuristics, and tests that need the parts rather
## than the total. Nothing is mutated: the placement is evaluated against a
## hypothetical board.
static func breakdown(
	board: BoardState,
	snapshot: TileSnapshot,
	rules: ScoringRules,
	scored_hand_ids: ScoredHandSet = null
) -> Dictionary:
	var report: Dictionary = {
		"valid": false,
		"poker_points": 0,
		"poker_count": 0,
		"poker_ids": [],
		"edge_points": 0,
		"edge_count": 0,
		"boundary_ids": [],
		"cluster_points": 0,
		"cluster_count": 0,
		"total_points": 0,
	}
	if board == null or snapshot == null or not snapshot.is_valid():
		return report
	if rules == null or not rules.is_valid():
		return report
	if not board.is_empty_cell(snapshot.get_cell()):
		return report

	report["valid"] = true

	var poker_points: int = 0
	var poker_ids: Array = []
	for result: PokerHandResult in PokerHandEvaluator.evaluate_placement(
		board, snapshot, rules.poker, scored_hand_ids
	):
		poker_points += result.points
		poker_ids.append(String(result.hand_id))
	report["poker_points"] = poker_points
	report["poker_count"] = poker_ids.size()
	report["poker_ids"] = poker_ids

	var edge_points: int = 0
	var boundary_ids: Array = []
	for result: EdgeMatchResult in EdgeMatchScorer.evaluate_placement(board, snapshot):
		edge_points += result.points
		boundary_ids.append(String(result.boundary_id))
	report["edge_points"] = edge_points
	report["edge_count"] = boundary_ids.size()
	report["boundary_ids"] = boundary_ids

	var cluster_points: int = 0
	var cluster_count: int = 0
	for result: ClusterScoreResult in EdgeClusterScorer.evaluate_placement(
		board, snapshot, rules.cluster
	):
		cluster_points += result.points
		cluster_count += 1
	report["cluster_points"] = cluster_points
	report["cluster_count"] = cluster_count

	report["total_points"] = poker_points + edge_points + cluster_points
	return report


## Returns true when the rule set, player, and move identity can produce events.
static func _inputs_are_usable(
	rules: ScoringRules, player_id: StringName, move_id: StringName
) -> bool:
	if rules == null or not rules.is_valid():
		push_error("ScoringCoordinator: a valid ScoringRules instance is required.")
		return false
	if String(player_id).is_empty():
		push_error("ScoringCoordinator: a player identifier is required to attribute points.")
		return false
	if String(move_id).is_empty():
		push_error("ScoringCoordinator: a move identifier is required for deterministic event ids.")
		return false
	return true
