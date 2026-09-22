extends TestCase

## Milestone 4 match lifecycle tests (ADR-003 sections 3, 7, 8, and 9).
##
## This suite contains the Milestone 4 exit criterion: a complete match between
## two scripted players runs headlessly to a verified result, and that result is
## checked against an ordered replay of its own move history through the same
## pure rules pipeline (ADR-007 section 9).
##
## Domain-level: no scene tree, no rendering, no input.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

## A full board takes the whole bag, so this is the longest match the tests run.
const FULL_BOARD_MOVES: int = 144

## Loop guard, so a rule error shows up as a failure instead of a hang.
const MOVE_LIMIT: int = 400


func test_exit_criterion_a_full_match_runs_to_a_verified_result() -> void:
	var session: GameSessionState = _new_session(&"match-full", 20260922)
	TurnManager.setup(session)

	var outcome: Dictionary = _play_to_the_end(session)

	check_eq(outcome["rejected"], 0, "no move may be refused during a legal match")
	check_eq(
		outcome["moves"],
		FULL_BOARD_MOVES,
		"one tile per cell fills the board in exactly 144 turns"
	)
	check(session.get_board().is_full(), "the match must end with every cell filled")
	check_eq(session.move_count(), FULL_BOARD_MOVES, "every move joins the history")
	check(session.is_over(), "the match must be over")
	check_eq(
		session.get_turn_state().phase,
		TurnEnums.MatchPhase.GAME_OVER,
		"the match ends at GAME_OVER"
	)
	check_eq(
		session.get_end_reason(),
		TurnEnums.EndReason.BOARD_FULL,
		"the board filling is the end condition"
	)
	check_eq(session.remaining_tile_count(), 0, "the bag is spent exactly as the board fills")
	check_eq(
		session.get_turn_state().turn_number,
		FULL_BOARD_MOVES,
		"the 144th placement ends the match without opening a further turn"
	)

	# ADR-003 section 8: the outcome is derived from committed totals.
	var result: MatchResult = MatchResult.build(session)
	check_not_null(result, "a finished match must produce a result")
	check_eq(result.move_count, FULL_BOARD_MOVES, "the result reports every move")
	check_eq(result.board_occupied, BoardEnums.CELL_COUNT, "the result reports a full board")
	check_eq(
		result.outcome,
		TurnEnums.outcome_for_scores(
			result.human_score, result.ai_score, TurnEnums.EndReason.BOARD_FULL
		),
		"the outcome must agree with the committed totals"
	)
	check_eq(
		result.human_score + result.ai_score,
		session.get_ledger().total_points(),
		"the two totals must account for every point scored"
	)

	# The breakdown ADR-003 section 8 requires, per player.
	for player_id: StringName in TurnEnums.player_ids():
		var terms: Dictionary = result.terms_for(player_id)
		check_eq(
			int(terms.get("poker", 0)) + int(terms.get("edge", 0)) + int(terms.get("cluster", 0)),
			int(terms.get("total", -1)),
			"the category breakdown must add up to the total for '%s'" % String(player_id)
		)
		check_eq(
			int(terms.get("total", -1)),
			session.score_for(player_id),
			"the breakdown total must match the committed ledger for '%s'" % String(player_id)
		)

	# ADR-003 section 8: recalculate from committed history and compare.
	check_eq(
		MatchResult.verify_against(session),
		"",
		"a full match must replay identically from its own move history"
	)

	# The board alone must also explain every committed point (ADR-007 section 9).
	var audit: ScoringAudit.Report = ScoringAudit.audit(
		session.get_board(),
		session.get_ledger(),
		session.get_scored_hand_set(),
		session.get_rules()
	)
	check_not_null(audit, "the audit must return a report")
	check(
		audit.ok,
		"a fully played board must audit cleanly: %s" % str(audit.problems)
	)


func test_a_partial_match_survives_save_and_resume() -> void:
	var original: GameSessionState = _new_session(&"match-save", 4242)
	TurnManager.setup(original)
	_play_moves(original, 20)
	check(
		original.get_turn_state().is_awaiting_action(),
		"a save must be taken at a transaction boundary"
	)

	var snapshot: MatchSnapshotDto = original.to_snapshot()
	check(snapshot.is_valid(), "a snapshot taken between turns must be restorable")

	var restored: GameSessionState = GameSessionState.from_snapshot(
		snapshot, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(restored, "the match must restore")

	_compare_sessions(original, restored, "after restore")

	# The restored match must be playable, not merely readable.
	var original_next: Dictionary = _play_moves(original, 5)
	var restored_next: Dictionary = _play_moves(restored, 5)

	check_eq(restored_next["rejected"], 0, "the restored match must accept legal moves")
	check_eq(
		restored_next["moves"],
		original_next["moves"],
		"both matches must commit the same number of further moves"
	)
	_compare_sessions(original, restored, "after playing on")
	check_eq(
		MatchResult.verify_against(restored),
		"",
		"the resumed match must still replay identically"
	)


func test_a_match_resumes_mid_preview_without_a_committed_tile() -> void:
	var session: GameSessionState = _new_session(&"match-preview", 77)
	TurnManager.setup(session)

	# The human holds an uncommitted tile and the board is still empty: exactly
	# the state an interrupted preview leaves behind (ADR-003 section 9).
	var held_id: StringName = session.active_tile_for(HUMAN).tile_id
	var snapshot: MatchSnapshotDto = session.to_snapshot()

	check_eq(snapshot.board.size(), 0, "a preview must never be saved as board state")

	var restored: GameSessionState = GameSessionState.from_snapshot(
		snapshot, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(restored, "a match interrupted during a preview must restore")

	check_eq(restored.get_board().occupied_count(), 0, "the restored board must still be empty")
	check_eq(
		restored.get_turn_state().phase,
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"resume must return to the action phase"
	)
	check_eq(
		restored.get_turn_state().active_player_id,
		HUMAN,
		"resume must restore whose turn it was"
	)
	check_eq(
		restored.active_tile_for(HUMAN).tile_id,
		held_id,
		"resume must restore the uncommitted active tile"
	)
	check_eq(restored.remaining_tile_count(), 143, "resume must restore the draw position")

	var cell: Vector2i = _first_frontier(restored.get_board())
	var resumed_move: PlacementResult = MoveCommitter.commit(restored, HUMAN, cell, 0)
	check(resumed_move.was_committed(), "the restored active tile must still be placeable")
	check_eq(
		String(resumed_move.move_id),
		"move:match-preview:1",
		"the resumed match must commit the opening move it was about to make"
	)


func test_tiles_are_conserved_across_a_save_and_resume() -> void:
	var session: GameSessionState = _new_session(&"match-tiles", 515)
	TurnManager.setup(session)
	_play_moves(session, 30)

	check_eq(
		session.verify_tile_conservation().size(),
		0,
		"every tile must sit in exactly one place before saving: %s"
		% str(session.verify_tile_conservation())
	)

	var restored: GameSessionState = GameSessionState.from_snapshot(
		session.to_snapshot(), ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(restored, "the match must restore")
	check_eq(
		restored.verify_tile_conservation().size(),
		0,
		"every tile must still sit in exactly one place after restoring: %s"
		% str(restored.verify_tile_conservation())
	)

	# The bag is one tile per cell, and every tile is bag, hand, or board.
	check_eq(restored.get_tile_source().get_bag_size(), BoardEnums.CELL_COUNT, "144 tiles exist")
	check_eq(
		restored.get_tile_source().get_bag_size(),
		restored.remaining_tile_count()
			+ restored.get_board().occupied_count()
			+ restored.players_with_active_tiles().size(),
		"remaining bag, committed tiles, and held tiles must account for the whole bag"
	)


func test_a_snapshot_of_a_move_in_flight_is_refused() -> void:
	var session: GameSessionState = _new_session(&"match-inflight", 808)
	TurnManager.setup(session)

	# RESOLVE_MOVE is a state the match passes through, not a boundary to resume on.
	session.get_turn_state().phase = TurnEnums.MatchPhase.RESOLVE_MOVE

	var snapshot: MatchSnapshotDto = session.to_snapshot()
	check(not snapshot.is_valid(), "a snapshot taken mid-resolution must be rejected")
	check_not_null(
		GameSessionState.from_snapshot(
			snapshot, ScoringRules.create_default(), TileGenerationRules.create_default()
		) == null,
		"a rejected snapshot must not restore"
	)


func test_a_snapshot_from_other_rules_is_refused() -> void:
	var session: GameSessionState = _new_session(&"match-rules", 909)
	TurnManager.setup(session)
	var snapshot: MatchSnapshotDto = session.to_snapshot()

	# A save written under a different scoring rules version must not be restored
	# against the rules in force now (ADR-007 section 11).
	var other_rules: ScoringRules = ScoringRules.create_default()
	other_rules.schema_version = 99

	check(
		GameSessionState.from_snapshot(
			snapshot, other_rules, TileGenerationRules.create_default()
		) == null,
		"a save written under other rules must be refused"
	)
	check_not_null(
		GameSessionState.from_snapshot(
			snapshot, ScoringRules.create_default(), TileGenerationRules.create_default()
		),
		"the same save must restore against the rules it was written with"
	)


## Plays legal moves until the match ends or the guard trips.
##
## Every move takes the first frontier cell in row-major order at rotation 0.
## ADR-006 section 8 guarantees every frontier cell accepts every available tile,
## so this always commits and never needs a fallback pick.
func _play_moves(session: GameSessionState, count: int) -> Dictionary:
	var committed: int = 0
	var rejected: int = 0
	var guard: int = 0
	while committed < count and not session.is_over() and guard < MOVE_LIMIT:
		guard += 1
		var turn_state: TurnState = session.get_turn_state()
		if not turn_state.is_awaiting_action():
			break
		var frontier: Array[Vector2i] = session.get_board().get_frontier_cells()
		if frontier.is_empty():
			break
		var result: PlacementResult = MoveCommitter.commit(
			session, turn_state.active_player_id, frontier[0], 0
		)
		if not result.was_committed():
			rejected += 1
			break
		TurnManager.resolve(session, result)
		committed += 1
	return {"moves": committed, "rejected": rejected}


## Plays until the match reaches an end condition.
func _play_to_the_end(session: GameSessionState) -> Dictionary:
	return _play_moves(session, BoardEnums.CELL_COUNT)


## Checks that two sessions agree on every authoritative and derived value.
func _compare_sessions(a: GameSessionState, b: GameSessionState, label: String) -> void:
	check_eq(
		b.get_board().get_revision(),
		a.get_board().get_revision(),
		"board revision must agree %s" % label
	)
	check_eq(
		b.get_board().occupied_count(),
		a.get_board().occupied_count(),
		"board occupancy must agree %s" % label
	)
	check_eq(
		b.get_board().to_debug_string(),
		a.get_board().to_debug_string(),
		"board layout must agree %s" % label
	)
	check_eq(
		b.get_ledger().event_ids(),
		a.get_ledger().event_ids(),
		"committed score events must agree %s" % label
	)
	check_eq(
		b.get_scored_hand_set().to_array(),
		a.get_scored_hand_set().to_array(),
		"scored windows must agree %s" % label
	)
	check_eq(b.move_count(), a.move_count(), "move history length must agree %s" % label)
	var a_history: Array[ScoringMove] = a.get_history()
	var b_history: Array[ScoringMove] = b.get_history()
	var history_matches: bool = a_history.size() == b_history.size()
	if history_matches:
		for index: int in range(a_history.size()):
			if a_history[index].move_id != b_history[index].move_id:
				history_matches = false
				break
	check(history_matches, "move history order must agree %s" % label)

	check_eq(
		b.get_turn_state().phase,
		a.get_turn_state().phase,
		"turn phase must agree %s" % label
	)
	check_eq(
		b.get_turn_state().active_player_id,
		a.get_turn_state().active_player_id,
		"active player must agree %s" % label
	)
	check_eq(
		b.get_turn_state().turn_number,
		a.get_turn_state().turn_number,
		"turn number must agree %s" % label
	)
	check_eq(
		b.get_turn_state().consecutive_no_tile_skips,
		a.get_turn_state().consecutive_no_tile_skips,
		"skip count must agree %s" % label
	)
	check_eq(
		b.remaining_tile_count(),
		a.remaining_tile_count(),
		"remaining tile count must agree %s" % label
	)
	check_eq(
		b.score_for(HUMAN),
		a.score_for(HUMAN),
		"the human total must agree %s" % label
	)
	check_eq(b.score_for(AI), a.score_for(AI), "the AI total must agree %s" % label)

	for player_id: StringName in TurnEnums.player_ids():
		var a_active: TileDefinition = a.active_tile_for(player_id)
		var b_active: TileDefinition = b.active_tile_for(player_id)
		var a_id: StringName = &"" if a_active == null else a_active.tile_id
		var b_id: StringName = &"" if b_active == null else b_active.tile_id
		check_eq(
			b_id, a_id, "the active tile of '%s' must agree %s" % [String(player_id), label]
		)


## Builds a standard-rules session.
func _new_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = GameSessionState.create(
		match_id, seed, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(session, "the session must be constructible")
	return session


## Returns the first legal frontier cell in row-major order.
func _first_frontier(board: BoardState) -> Vector2i:
	var frontier: Array[Vector2i] = board.get_frontier_cells()
	if frontier.is_empty():
		return Vector2i(-1, -1)
	return frontier[0]
