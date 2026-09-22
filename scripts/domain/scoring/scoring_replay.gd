class_name ScoringReplay
extends RefCounted

## Ordered full replay (ADR-007 sections 9 and 10).
##
## ADR-007 section 9 calls replay the authoritative equivalence check, because
## player attribution and one-time poker scoring depend on move order rather than
## only on the final board. Replay rebuilds a match from an empty board by pushing
## the committed move history back through the same pure rules pipeline the live
## game uses: no separate replay-only scoring logic exists, so a divergence means
## the live path and the replay path disagree about a rule.
##
## The caller supplies a tile lookup for the tile identities the moves name. A
## replay without one cannot reconstruct tiles faithfully, so it stops at the
## first move it cannot supply and reports it as a deviation instead of guessing.
##
## Replay never mutates the caller's board, ledger, or move history: it builds its
## own copies.

## The result of one replay pass.
class Report:
	extends RefCounted

	## The board rebuilt from the move history.
	var board: BoardState = null

	## The ledger rebuilt from the move history.
	var ledger: ScoreLedger = null

	## The scored-window set rebuilt from the move history.
	var scored_hand_ids: ScoredHandSet = null

	## How many moves were applied successfully.
	var moves_applied: int = 0

	## How many moves the history contained.
	var moves_total: int = 0

	## True when every move applied and no deviation was recorded.
	var completed: bool = false

	## Human-readable description of the first point replay could not continue.
	var deviations: PackedStringArray = PackedStringArray()


	## Returns the replayed per-player totals, keyed by player name.
	func totals_by_name() -> Dictionary:
		if ledger == null:
			return {}
		return ledger.player_totals_by_name()


	## Returns a short human-readable summary, for diagnostics only.
	func describe() -> String:
		var totals: String = "none"
		if ledger != null:
			totals = str(ledger.player_totals_by_name())
		return "replay %d/%d move(s), completed=%s, totals=%s" % [
			moves_applied,
			moves_total,
			str(completed),
			totals,
		]


	## Returns a JSON-safe dictionary, for bug reports and fixtures.
	func to_dictionary() -> Dictionary:
		var scored: Array = []
		if scored_hand_ids != null:
			for hand_id: StringName in scored_hand_ids.to_array():
				scored.append(String(hand_id))
		return {
			"moves_applied": moves_applied,
			"moves_total": moves_total,
			"completed": completed,
			"deviations": Array(deviations),
			"board_revision": 0 if board == null else board.get_revision(),
			"occupied_count": 0 if board == null else board.occupied_count(),
			"totals": {} if ledger == null else ledger.player_totals_by_name(),
			"scored_hand_ids": scored,
		}


## Replays a move history and returns the rebuilt board, ledger, and window set.
##
## `tile_lookup` receives a tile identifier and returns the matching
## `TileDefinition`, or null when it cannot supply one. `board_factory` may
## override the starting board; omitting it starts from an empty 12 x 12 board.
static func replay(
	moves: Array[ScoringMove],
	rules: ScoringRules,
	tile_lookup: Callable = Callable(),
	board_factory: Callable = Callable()
) -> Report:
	var report: Report = Report.new()
	report.moves_total = moves.size()

	var board: BoardState = BoardState.create()
	if board_factory.is_valid():
		board = board_factory.call() as BoardState
		if board == null:
			board = BoardState.create()

	var ledger: ScoreLedger = ScoreLedger.create()
	var scored_hand_ids: ScoredHandSet = ScoredHandSet.create()

	report.board = board
	report.ledger = ledger
	report.scored_hand_ids = scored_hand_ids

	if rules == null or not rules.is_valid():
		report.deviations.append("a valid ScoringRules instance is required")
		return report

	for index: int in range(moves.size()):
		var move: ScoringMove = moves[index]
		if move == null:
			report.deviations.append("move %d is null" % (index + 1))
			return report
		if not move.is_valid():
			report.deviations.append("move %d is not a valid record" % (index + 1))
			return report

		# ADR-011 section 5 makes a committed move one whole line, so a replay
		# supplies every tile of the move and pushes the assembled line back
		# through the same validator and the same transaction the live path uses.
		# A one-placement record is replayed through the single-tile path, which
		# keeps ADR-007's fixtures and the pre-ADR-011 history shape replayable
		# rather than silently dropped.
		var snapshots: Array[TileSnapshot] = []
		for placement: ScoringMove.Placement in move.placements:
			var tile: TileDefinition = null
			if tile_lookup.is_valid():
				tile = tile_lookup.call(placement.tile_id) as TileDefinition
			if tile == null:
				report.deviations.append(
					"move %s: tile '%s' could not be supplied"
					% [String(move.move_id), String(placement.tile_id)]
				)
				return report
			snapshots.append(TileSnapshot.create(tile, placement.cell, placement.rotation))

		var committed: ScoreTransaction = null
		if snapshots.size() >= 2:
			var line: LineResult = LineValidator.validate(board, snapshots)
			if line == null or not line.accepted:
				var line_reason: String = "null result"
				if line != null:
					line_reason = line.get_rejection_name()
				report.deviations.append(
					"move %s was rejected on replay: %s" % [String(move.move_id), line_reason]
				)
				return report
			committed = ScoringCoordinator.commit_line(
				board,
				line.staged_tiles,
				ledger,
				scored_hand_ids,
				move.player_id,
				move.move_id,
				move.move_number,
				rules
			)
		else:
			var result: PlacementResult = PlacementValidator.validate(
				board, move.to_request(move.first_placement()), snapshots[0].get_tile(), true
			)
			if result == null or not result.accepted:
				var reason: String = "null result"
				if result != null:
					reason = result.get_rejection_name()
				report.deviations.append(
					"move %s was rejected on replay: %s" % [String(move.move_id), reason]
				)
				return report
			committed = ScoringCoordinator.commit_placement(
				board,
				result.placed_tile,
				ledger,
				scored_hand_ids,
				move.player_id,
				move.move_id,
				move.move_number,
				rules
			)
		if committed.board_revision_before != board.get_revision() - 1:
			report.deviations.append(
				"move %s did not advance the board revision" % String(move.move_id)
			)
			return report
		report.moves_applied += 1

	report.completed = report.moves_applied == report.moves_total
	return report


## Compares a live match with a replay of its move history.
##
## ADR-007 section 9 lists what must match: board state, score events and their
## identifiers, per-player totals, scored poker windows, matching boundaries, and
## cluster entitlements. Returns the first mismatch as a human-readable string, or
## an empty string when everything agrees.
static func compare(
	live_board: BoardState,
	live_ledger: ScoreLedger,
	live_scored_hand_ids: ScoredHandSet,
	replayed: Report,
	rules: ScoringRules
) -> String:
	if live_board == null or live_ledger == null or live_scored_hand_ids == null:
		return "a live board, ledger, and scored-hand set are required to compare"
	if replayed == null or replayed.board == null or replayed.ledger == null:
		return "a completed replay report is required to compare"
	if not replayed.completed:
		return "replay did not complete: %s" % ", ".join(replayed.deviations)

	if live_board.get_revision() != replayed.board.get_revision():
		return "board revision differs: live %d, replay %d" % [
			live_board.get_revision(), replayed.board.get_revision()
		]
	if live_board.to_debug_string() != replayed.board.to_debug_string():
		return "board layout differs between live play and replay"

	var live_ids: Array[StringName] = live_ledger.event_ids()
	var replayed_ids: Array[StringName] = replayed.ledger.event_ids()
	if live_ids != replayed_ids:
		return "score events differ: live %s, replay %s" % [str(live_ids), str(replayed_ids)]

	if live_ledger.player_totals_by_name() != replayed.ledger.player_totals_by_name():
		return "player totals differ: live %s, replay %s" % [
			str(live_ledger.player_totals_by_name()), str(replayed.ledger.player_totals_by_name())
		]

	var live_hands: Array[StringName] = live_scored_hand_ids.to_array()
	var replayed_hands: Array[StringName] = replayed.scored_hand_ids.to_array()
	if live_hands != replayed_hands:
		return "scored poker windows differ: live %s, replay %s" % [
			str(live_hands), str(replayed_hands)
		]

	var live_boundaries: Array[StringName] = EdgeMatchScorer.boundary_ids(live_board)
	var replayed_boundaries: Array[StringName] = EdgeMatchScorer.boundary_ids(replayed.board)
	if live_boundaries != replayed_boundaries:
		return "matching boundaries differ between live play and replay"

	if rules == null or not rules.is_valid():
		return "a valid ScoringRules instance is required to compare cluster entitlements"
	var live_entitlement: Dictionary = EdgeClusterScorer.entitlement_totals(live_board, rules.cluster)
	var replayed_entitlement: Dictionary = EdgeClusterScorer.entitlement_totals(
		replayed.board, rules.cluster
	)
	if live_entitlement != replayed_entitlement:
		return "cluster entitlements differ: live %s, replay %s" % [
			str(live_entitlement), str(replayed_entitlement)
		]

	return ""
