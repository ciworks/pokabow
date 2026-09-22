class_name ScoringAudit
extends RefCounted

## Static board audit (ADR-007 section 9, ADR-002 section 8).
##
## Unlike replay, the audit asks what the *board alone* says and compares it with
## the committed record. It enumerates every matching boundary once, builds the
## current single-colour components and their entitlements, reclassifies the
## scored poker windows from their coordinates and faces, and then checks the
## ledger against all three.
##
## Two consequences of the accepted rules make these strict equalities rather
## than bounds:
## - a matching boundary awards +1 when its second tile is committed, and the
##   board never loses tiles, so the ledger's edge points must equal the number of
##   matching boundaries on the board (ADR-002 section 1);
## - the cluster award is exactly the entitlement increase at each commit and
##   total entitlement never decreases, so the ledger's cluster points must equal
##   the board's current total entitlement (ADR-002 sections 5 and 8).
##
## The audit never mutates the board, the ledger, or the scored-window set.


## Report of one audit pass.
class Report:
	extends RefCounted

	## Board revision the audit ran against.
	var board_revision: int = 0

	## Number of cells holding a committed tile.
	var occupied_count: int = 0

	## Canonical identifier of every matching boundary on the board.
	var boundary_ids: Array[StringName] = []

	## Matching boundaries the board currently holds.
	var edges_on_board: int = 0

	## Edge-match points the ledger records.
	var edge_points_in_ledger: int = 0

	## True when the two edge counts agree.
	var edges_agree: bool = false

	## Entitlement total per colour name, including colours with no components.
	var cluster_totals: Dictionary = {}

	## Total cluster entitlement the board's components represent.
	var cluster_total_on_board: int = 0

	## Cluster points the ledger records.
	var cluster_points_in_ledger: int = 0

	## True when the two cluster totals agree.
	var clusters_agree: bool = false

	## Canonical identifier of every complete poker window on the board.
	var poker_window_ids: Array[StringName] = []

	## Window identifiers recorded as scored.
	var scored_hand_ids: Array[StringName] = []

	## True when every scored identifier still describes a real complete window.
	var poker_ids_valid: bool = false

	## True when every committed poker event's window reclassifies to the same
	## category it was awarded for.
	var poker_events_valid: bool = false

	## True when the ledger's poker points equal the points the scored windows
	## represent under the current rules.
	var poker_points_agree: bool = false

	## True when every check passed.
	var ok: bool = false

	## Human-readable description of every failed check.
	var problems: PackedStringArray = PackedStringArray()


	## Returns a short human-readable summary, for diagnostics only.
	func describe() -> String:
		return "audit r%d: edges %d/%d, clusters %d/%d, poker windows %d, scored %d, ok=%s" % [
			board_revision,
			edges_on_board,
			edge_points_in_ledger,
			cluster_total_on_board,
			cluster_points_in_ledger,
			poker_window_ids.size(),
			scored_hand_ids.size(),
			str(ok),
		]


	## Returns a JSON-safe dictionary, for bug reports and fixtures.
	func to_dictionary() -> Dictionary:
		return {
			"board_revision": board_revision,
			"occupied_count": occupied_count,
			"edges_on_board": edges_on_board,
			"edge_points_in_ledger": edge_points_in_ledger,
			"edges_agree": edges_agree,
			"cluster_totals": cluster_totals,
			"cluster_total_on_board": cluster_total_on_board,
			"cluster_points_in_ledger": cluster_points_in_ledger,
			"clusters_agree": clusters_agree,
			"poker_ids_valid": poker_ids_valid,
			"poker_events_valid": poker_events_valid,
			"poker_points_agree": poker_points_agree,
			"ok": ok,
			"problems": Array(problems),
		}


## Audits a board and its committed score record. Returns null without a board.
static func audit(
	board: BoardState,
	ledger: ScoreLedger,
	scored_hand_ids: ScoredHandSet,
	rules: ScoringRules
) -> Report:
	if board == null:
		push_error("ScoringAudit.audit: a board is required.")
		return null

	var report: Report = Report.new()
	report.board_revision = board.get_revision()
	report.occupied_count = board.occupied_count()

	if rules == null or not rules.is_valid():
		report.problems.append("a valid ScoringRules instance is required")
		return report

	_audit_edges(board, ledger, report)
	_audit_clusters(board, ledger, rules, report)
	_audit_poker(board, ledger, scored_hand_ids, rules, report)

	report.ok = (
		report.problems.is_empty()
		and report.edges_agree
		and report.clusters_agree
		and report.poker_ids_valid
		and report.poker_events_valid
		and report.poker_points_agree
	)
	return report


## Enumerates matching boundaries and compares the count with edge points.
static func _audit_edges(board: BoardState, ledger: ScoreLedger, report: Report) -> void:
	report.boundary_ids = EdgeMatchScorer.boundary_ids(board)
	report.edges_on_board = report.boundary_ids.size()
	report.edge_points_in_ledger = 0
	if ledger != null:
		report.edge_points_in_ledger = ledger.total_for_category(
			ScoringEnums.ScoreCategory.EDGE_MATCH
		)
	report.edges_agree = report.edges_on_board == report.edge_points_in_ledger
	if not report.edges_agree:
		report.problems.append(
			"the board holds %d matching boundaries but the ledger records %d edge point(s)"
			% [report.edges_on_board, report.edge_points_in_ledger]
		)


## Builds colour components and compares total entitlement with cluster points.
static func _audit_clusters(
	board: BoardState,
	ledger: ScoreLedger,
	rules: ScoringRules,
	report: Report
) -> void:
	report.cluster_totals = EdgeClusterScorer.entitlement_totals(board, rules.cluster)
	report.cluster_total_on_board = EdgeClusterScorer.total_entitlement(board, rules.cluster)
	report.cluster_points_in_ledger = 0
	if ledger != null:
		report.cluster_points_in_ledger = ledger.total_for_category(
			ScoringEnums.ScoreCategory.EDGE_CLUSTER
		)
	report.clusters_agree = report.cluster_total_on_board == report.cluster_points_in_ledger
	if not report.clusters_agree:
		report.problems.append(
			"the board's clusters represent %d entitlement point(s) but the ledger records %d"
			% [report.cluster_total_on_board, report.cluster_points_in_ledger]
		)


## Reclassifies scored windows from the board and compares them with the events.
static func _audit_poker(
	board: BoardState,
	ledger: ScoreLedger,
	scored_hand_ids: ScoredHandSet,
	rules: ScoringRules,
	report: Report
) -> void:
	report.poker_window_ids = PokerHandEvaluator.full_board_hand_ids(board)
	report.scored_hand_ids = []
	if scored_hand_ids != null:
		report.scored_hand_ids = scored_hand_ids.to_array()

	report.poker_ids_valid = true
	var recomputed_points: int = 0
	for hand_id: StringName in report.scored_hand_ids:
		var cells: Array[Vector2i] = PokerHandEvaluator.cells_for_window_id(hand_id)
		if cells.is_empty():
			report.poker_ids_valid = false
			report.problems.append(
				"scored window '%s' is not a valid canonical window identifier"
				% String(hand_id)
			)
			continue
		var category: int = PokerHandEvaluator.classify_window(board, cells)
		if category == ScoringEnums.PokerHandCategory.NONE:
			report.poker_ids_valid = false
			report.problems.append(
				"scored window '%s' no longer describes five occupied cells"
				% String(hand_id)
			)
			continue
		recomputed_points += rules.points_for_hand(category)

	report.poker_events_valid = true
	var committed_points: int = 0
	if ledger != null:
		committed_points = ledger.total_for_category(
			ScoringEnums.ScoreCategory.POKER_HAND
		)
		for event: ScoreEvent in ledger.events_for_category(
			ScoringEnums.ScoreCategory.POKER_HAND
		):
			var hand_id: StringName = StringName(String(event.evidence.get("hand_id", "")))
			if String(hand_id).is_empty() or not report.scored_hand_ids.has(hand_id):
				report.poker_events_valid = false
				report.problems.append(
					"poker event '%s' has no recorded window on the board" % String(event.event_id)
				)
				continue
			var cells: Array[Vector2i] = PokerHandEvaluator.cells_for_window_id(hand_id)
			var category: int = PokerHandEvaluator.classify_window(board, cells)
			var awarded: String = String(event.evidence.get("category", ""))
			if ScoringEnums.poker_hand_name(category) != awarded:
				report.poker_events_valid = false
				report.problems.append(
					"poker event '%s' was awarded as %s but its window is now %s"
					% [String(event.event_id), awarded, ScoringEnums.poker_hand_name(category)]
				)

	report.poker_points_agree = recomputed_points == committed_points
	if not report.poker_points_agree:
		report.problems.append(
			"the scored windows are worth %d point(s) but the ledger records %d poker point(s)"
			% [recomputed_points, committed_points]
		)
