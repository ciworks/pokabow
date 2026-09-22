extends TestCase

## Milestone 6 difficulty tests (ADR-005 sections 4, 5, 6, 7, 8, 9, 11, and 12).
##
## Domain-level: no scene tree, no rendering, no input, no controller. Each
## difficulty is driven directly through the shared `choose_move` contract, and
## the fixtures are hand-built boards so the expected answer is derivable by hand
## rather than by trusting the search.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

const TEST_MATCH_ID: StringName = &"ai-difficulty"
const TEST_SEED: int = 20260921

## Decision seeds used for the deterministic checks.
const EASY_SEED: int = 11
const MEDIUM_SEED: int = 22
const HARD_SEED: int = 33

## The four tiles in a row that leave two completion cells open (row 5).
const ROW_OPEN_LEFT: Vector2i = Vector2i(3, 5)
const ROW_OPEN_RIGHT: Vector2i = Vector2i(8, 5)


## A hand-built board with the tile under consideration.
##
## A typed holder rather than a Dictionary, so every fixture value stays typed.
class Fixture extends RefCounted:
	var board: BoardState = null
	var snapshot: AiGameSnapshot = null
	var tile: TileDefinition = null


func test_easy_picks_a_uniform_legal_candidate() -> void:
	var fixture: Fixture = _edge_match_fixture()
	if fixture == null:
		return
	var strategy: AiEasyStrategy = AiEasyStrategy.new()
	var decision: AiDecision = strategy.choose_move(
		fixture.snapshot,
		fixture.tile,
		AiDifficultyConfig.create_default(AiEnums.Difficulty.EASY),
		EASY_SEED,
		AiCancellationToken.new()
	)
	if not check_not_null(decision, "Easy must produce a decision"):
		return
	check(decision.has_move(), "Easy must propose a move when one is legal")
	check_eq(
		int(decision.diagnostics.get("evaluated_candidates", -1)),
		0,
		"ADR-005 section 4: Easy must not evaluate score"
	)

	var request: PlacementRequest = PlacementRequest.create(
		AI, fixture.tile.tile_id, decision.cell, decision.rotation
	)
	var result: PlacementResult = PlacementValidator.validate(
		fixture.board, request, fixture.tile, true
	)
	check(
		result != null and result.accepted,
		"Easy must propose a placement the validator accepts (ADR-005 section 2)"
	)

	# ADR-005 section 4 fixes an even distribution over the legal candidates.
	var uniform: AiEasyStrategy = AiEasyStrategy.new()
	var counts: Array[int] = [0, 0, 0, 0]
	for seed: int in range(400):
		var index: int = uniform.pick_index(4, seed)
		if check(index >= 0 and index < 4, "the pick must land on a candidate"):
			counts[index] += 1
	for index: int in range(counts.size()):
		check(
			counts[index] > 60 and counts[index] < 140,
			"index %d must be picked roughly one quarter of the time (got %d)"
			% [index, counts[index]]
		)


func test_easy_spreads_across_the_legal_candidates() -> void:
	var fixture: Fixture = _edge_match_fixture()
	if fixture == null:
		return
	var strategy: AiEasyStrategy = AiEasyStrategy.new()
	var seen: Dictionary = {}
	for seed: int in range(120):
		var decision: AiDecision = strategy.choose_move(
			fixture.snapshot,
			fixture.tile,
			AiDifficultyConfig.create_default(AiEnums.Difficulty.EASY),
			seed,
			AiCancellationToken.new()
		)
		if decision != null and decision.has_move():
			seen[decision.move_key] = true
	check(
		seen.size() >= 4,
		"Easy must reach more than one candidate across seeds (got %d)" % seen.size()
	)


func test_medium_returns_the_documented_tuple_maximum() -> void:
	var fixture: Fixture = _edge_match_fixture()
	if fixture == null:
		return
	var strategy: AiMediumStrategy = AiMediumStrategy.new()
	var decision: AiDecision = strategy.choose_move(
		fixture.snapshot,
		fixture.tile,
		AiDifficultyConfig.create_default(AiEnums.Difficulty.MEDIUM),
		MEDIUM_SEED,
		AiCancellationToken.new()
	)
	if not check_not_null(decision, "Medium must produce a decision"):
		return
	if not check(decision.has_move(), "Medium must propose a move"):
		return

	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(
		fixture.board, fixture.tile, AI
	)
	if not check(candidates.size() > 1, "the fixture must offer several candidates"):
		return

	var rules: ScoringRules = fixture.snapshot.get_rules()
	var max_total: int = 0
	for candidate: AiMoveCandidate in candidates:
		candidate.apply_breakdown(
			ScoringCoordinator.breakdown(
				fixture.board,
				candidate.snapshot,
				rules,
				fixture.snapshot.get_scored_hand_set()
			)
		)
		max_total = maxi(max_total, candidate.immediate_score)
	check(
		max_total > 0,
		"the fixture must make the choice non-trivial (a candidate must score)"
	)

	var expected: AiMoveCandidate = _medium_expected(candidates, MEDIUM_SEED, strategy)
	if not check_not_null(expected, "the fixture must yield an expected candidate"):
		return
	check_eq(
		decision.move_key,
		expected.move_key,
		"Medium must return the ADR-005 section 5 tuple maximum"
	)
	check_eq(
		String(decision.diagnostics.get("move_key", "")),
		expected.move_key,
		"the decision diagnostics must record the chosen candidate"
	)

	var chosen_score: int = -1
	for candidate: AiMoveCandidate in candidates:
		if candidate.move_key == decision.move_key:
			chosen_score = candidate.immediate_score
	check_eq(
		chosen_score,
		max_total,
		"the chosen candidate must carry the maximum immediate score"
	)


func test_hard_blocks_an_available_completion_cell() -> void:
	var fixture: Fixture = _hard_fixture()
	if fixture == null:
		return
	var rules: ScoringRules = fixture.snapshot.get_rules()

	var open_cells: Array[Vector2i] = AiFeatures.completion_cells(fixture.board, rules)
	check_eq(
		open_cells.size(),
		2,
		"the fixture must leave exactly two completion cells open: %s"
		% ScoringEnums.cells_label(open_cells)
	)
	check(
		open_cells.has(ROW_OPEN_LEFT) and open_cells.has(ROW_OPEN_RIGHT),
		"both row ends must be open"
	)

	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(
		fixture.board, fixture.tile, AI
	)
	var lowest_threat: int = 999
	var highest_threat: int = -1
	for candidate: AiMoveCandidate in candidates:
		var threat: int = AiFeatures.human_open_threat(fixture.snapshot, candidate, rules)
		lowest_threat = mini(lowest_threat, threat)
		highest_threat = maxi(highest_threat, threat)
	check(
		highest_threat > lowest_threat,
		"the fixture must let Hard reduce the threats it leaves open (%d vs %d)"
		% [lowest_threat, highest_threat]
	)

	var decision: AiDecision = AiHardStrategy.new().choose_move(
		fixture.snapshot,
		fixture.tile,
		AiDifficultyConfig.create_default(AiEnums.Difficulty.HARD),
		HARD_SEED,
		AiCancellationToken.new()
	)
	if not check_not_null(decision, "Hard must produce a decision"):
		return
	if not check(decision.has_move(), "Hard must propose a move"):
		return
	check(
		open_cells.has(decision.cell),
		"ADR-005 sections 6 and 7: Hard must take a completion cell instead of leaving it (chose %s)"
		% BoardEnums.cell_name(decision.cell)
	)
	check_eq(
		int(decision.diagnostics.get("human_open_threat", -1)),
		lowest_threat,
		"the chosen move must leave the fewest completion cells open"
	)
	check(
		int(decision.diagnostics.get("utility", 0)) > 0,
		"the chosen move must have a positive ADR-005 section 6 utility"
	)


func test_hard_stays_inside_the_section_8_work_budget() -> void:
	var fixture: Fixture = _hard_fixture()
	if fixture == null:
		return
	var config: AiDifficultyConfig = AiDifficultyConfig.create_default(AiEnums.Difficulty.HARD)
	check(config.is_valid(), "the Hard configuration must validate: %s" % str(config.validate()))
	check_eq(
		config.hard_candidate_beam,
		AiDifficultyConfig.DEFAULT_HARD_CANDIDATE_BEAM,
		"ADR-005 section 8 fixes the candidate beam at 24"
	)
	check_eq(
		config.hard_reply_beam,
		AiDifficultyConfig.DEFAULT_HARD_REPLY_BEAM,
		"ADR-005 section 8 fixes the reply beam at 16"
	)
	check_eq(
		config.deep_evaluation_budget,
		AiDifficultyConfig.DEFAULT_DEEP_EVALUATION_BUDGET,
		"ADR-005 section 8 fixes the deep evaluation budget at 6144"
	)

	var decision: AiDecision = AiHardStrategy.new().choose_move(
		fixture.snapshot,
		fixture.tile,
		config,
		HARD_SEED,
		AiCancellationToken.new()
	)
	if not check_not_null(decision, "Hard must produce a decision"):
		return
	var diagnostics: Dictionary = decision.diagnostics
	check(
		int(diagnostics.get("deep_evaluations", -1)) <= config.deep_evaluation_budget,
		"Hard must never exceed its deep evaluation budget"
	)
	check(
		int(diagnostics.get("candidate_beam", -1)) <= config.hard_candidate_beam,
		"Hard must never exceed its candidate beam"
	)
	check(
		int(diagnostics.get("deep_candidates", -1)) <= config.hard_candidate_beam,
		"Hard must run at most one deep pass per beamed candidate"
	)
	check_eq(
		String(diagnostics.get("sample_version", "")),
		config.sample_version(),
		"the decision diagnostics must record the sample version (ADR-005 section 12)"
	)
	check_eq(
		int(diagnostics.get("evaluation_version", -1)),
		AiDifficultyConfig.EVALUATION_VERSION,
		"the decision diagnostics must record the evaluation version"
	)


func test_a_cancelled_analysis_cannot_be_committed() -> void:
	var fixture: Fixture = _edge_match_fixture()
	if fixture == null:
		return
	var cancelled: AiCancellationToken = AiCancellationToken.new()
	cancelled.cancel()
	check(cancelled.is_cancelled(), "the token must report its own state")

	var strategies: Array[AiStrategy] = [
		AiEasyStrategy.new(), AiMediumStrategy.new(), AiHardStrategy.new()
	]
	var difficulties: Array[int] = [
		AiEnums.Difficulty.EASY, AiEnums.Difficulty.MEDIUM, AiEnums.Difficulty.HARD,
	]
	for index: int in range(strategies.size()):
		var decision: AiDecision = strategies[index].choose_move(
			fixture.snapshot,
			fixture.tile,
			AiDifficultyConfig.create_default(difficulties[index]),
			MEDIUM_SEED,
			cancelled
		)
		if not check_not_null(decision, "a cancelled analysis must still return a decision"):
			continue
		check(
			decision.is_cancelled(),
			"%s must report a cancelled analysis" % AiEnums.difficulty_name(difficulties[index])
		)
		check(
			not decision.has_move(),
			"ADR-005 section 9: a cancelled analysis must not carry a move"
		)


func test_a_stale_proposal_is_refused_and_the_retry_is_bounded() -> void:
	var session: GameSessionState = _ai_turn_session(TEST_MATCH_ID, TEST_SEED)
	if session == null:
		return
	var coordinator: AiCoordinator = AiCoordinator.create(AiEnums.Difficulty.MEDIUM)
	var tile: TileDefinition = session.active_tile_for(AI)
	var decision: AiDecision = coordinator.choose_move(session, tile, AiCancellationToken.new())
	if not check_not_null(decision, "the coordinator must produce a decision"):
		return
	if not check(decision.has_move(), "the coordinator must propose a move"):
		return
	check_eq(coordinator.last_attempts(), 1, "a clean decision must not consume a retry")
	check_eq(
		AiCoordinator.MAX_ATTEMPTS,
		2,
		"ADR-005 section 11 allows exactly one retry (two attempts)"
	)
	check(not coordinator.is_thinking(), "the thinking state must clear when analysis ends")
	check_eq(
		coordinator.status(), AiCoordinator.STATUS_DECIDED, "the status must report a decision"
	)

	# Move the live board on: the proposal no longer describes the current state.
	var board: BoardState = session.get_board()
	board.commit_tile(
		TileSnapshot.create(
			_plain_tile(&"ai-fixture:tile:902"), board.get_frontier_cells()[0], 0
		)
	)
	var revalidated: AiDecision = coordinator.revalidate(session, decision)
	if not check_not_null(revalidated, "revalidation must return a decision"):
		return
	check(
		not revalidated.has_move(),
		"ADR-005 section 11: a stale proposal must be refused, never committed"
	)
	check_eq(revalidated.get_status_name(), "INVALID", "a stale proposal must report INVALID")

	# An illegal proposal at the current revision must be refused as well.
	var occupied: Vector2i = board.get_occupied_cells()[0]
	var illegal: AiDecision = AiDecision.create_move(
		occupied, 0, board.get_revision(), "ai-move:illegal:0,0:0", {}
	)
	var refused: AiDecision = coordinator.revalidate(session, illegal)
	if check_not_null(refused, "revalidation must answer for an illegal proposal"):
		check(
			not refused.has_move(),
			"a proposal the validator refuses must not survive revalidation"
		)
		check_eq(
			String(refused.diagnostics.get("reason", "")),
			"the proposal is no longer legal",
			"the refusal must name the reason"
		)


func test_the_coordinator_selects_the_configured_strategy() -> void:
	var coordinator: AiCoordinator = AiCoordinator.create(AiEnums.Difficulty.HARD)
	check(coordinator.strategy() is AiHardStrategy, "Hard must use the Hard strategy")
	check_eq(coordinator.difficulty(), AiEnums.Difficulty.HARD, "the difficulty must be recorded")
	check(
		coordinator.presentation_delay_seconds() > 0.0,
		"the configuration must supply a presentation delay"
	)

	coordinator.set_difficulty(AiEnums.Difficulty.EASY)
	check(coordinator.strategy() is AiEasyStrategy, "Easy must use the Easy strategy")
	check_eq(coordinator.difficulty(), AiEnums.Difficulty.EASY, "the difficulty must change")

	coordinator.set_difficulty(99)
	check(
		coordinator.difficulty() == AiEnums.DEFAULT_DIFFICULTY,
		"an unknown difficulty must fall back to the documented default"
	)
	check(coordinator.strategy() is AiMediumStrategy, "the fallback must use the Medium strategy")

	var config: AiDifficultyConfig = coordinator.config()
	check_not_null(config, "the coordinator must expose its configuration")
	if config != null:
		check(config.is_valid(), "the configuration must validate: %s" % str(config.validate()))


func test_each_difficulty_plays_a_short_match_through_the_committer() -> void:
	var difficulties: Array[int] = [
		AiEnums.Difficulty.EASY, AiEnums.Difficulty.MEDIUM, AiEnums.Difficulty.HARD,
	]
	for difficulty: int in difficulties:
		var session: GameSessionState = _new_session(
			StringName("ai-match-%s" % AiEnums.difficulty_slug(difficulty)),
			TEST_SEED + difficulty
		)
		if session == null:
			continue
		TurnManager.setup(session)
		var coordinator: AiCoordinator = AiCoordinator.create(difficulty)
		var ai_moves: int = _play(session, coordinator, 3)
		var label: String = AiEnums.difficulty_name(difficulty)

		check_eq(ai_moves, 3, "%s must play every turn it was given" % label)
		check_eq(
			session.get_board().occupied_count(),
			session.move_count(),
			"%s: every committed move must have placed exactly one tile" % label
		)
		check_eq(
			session.get_board().get_revision(),
			session.move_count(),
			"%s: the board revision must count the committed moves" % label
		)
		check_eq(
			session.score_for(HUMAN) + session.score_for(AI),
			session.get_ledger().total_points(),
			"%s: the two totals must account for every awarded point" % label
		)
		check_eq(
			MatchResult.verify_against(session),
			"",
			"%s: a match driven by the AI must replay identically from its own history" % label
		)


## Plays `ai_turns` opponent turns, with the human side taking the first frontier
## cell.
##
## Returns how many opponent moves were committed, so a caller can tell a
## completed run from one the AI could not finish.
func _play(session: GameSessionState, coordinator: AiCoordinator, ai_turns: int) -> int:
	var ai_moves: int = 0
	var guard: int = 0
	while ai_moves < ai_turns and not session.is_over() and guard < 64:
		guard += 1
		var turn_state: TurnState = session.get_turn_state()
		if not turn_state.is_awaiting_action():
			break
		var result: PlacementResult = null
		if turn_state.active_player_id == HUMAN:
			var frontier: Array[Vector2i] = session.get_board().get_frontier_cells()
			if frontier.is_empty():
				break
			result = MoveCommitter.commit(session, HUMAN, frontier[0], 0)
		else:
			var tile: TileDefinition = session.active_tile_for(AI)
			if tile == null:
				break
			var decision: AiDecision = coordinator.choose_move(
				session, tile, AiCancellationToken.new()
			)
			if decision == null or not decision.has_move():
				check(false, "the AI must always have a legal move while the frontier is open")
				break
			result = MoveCommitter.commit(session, AI, decision.cell, decision.rotation)
			if result != null and result.was_committed():
				ai_moves += 1
			else:
				check(false, "an AI proposal must commit through MoveCommitter")
				break
		if result == null or not result.was_committed():
			check(false, "every resolved move in this fixture must commit")
			break
		TurnManager.resolve(session, result)
	return ai_moves


## Returns the candidate the ADR-005 section 5 tuple selects.
func _medium_expected(
	candidates: Array[AiMoveCandidate], decision_seed: int, strategy: AiMediumStrategy
) -> AiMoveCandidate:
	var best: AiMoveCandidate = null
	for candidate: AiMoveCandidate in candidates:
		candidate.tie_break_value = strategy.tie_break_value_for(decision_seed, candidate.move_key)
		if best == null:
			best = candidate
			continue
		if _medium_is_stronger(candidate, best):
			best = candidate
	return best


## Returns true when `a` outranks `b` under the ADR-005 section 5 tuple.
##
## Fields are compared in the documented precedence, then the deterministic
## tie-break value of section 10 (lower wins), then the canonical move key.
func _medium_is_stronger(a: AiMoveCandidate, b: AiMoveCandidate) -> bool:
	if a.immediate_score != b.immediate_score:
		return a.immediate_score > b.immediate_score
	if a.poker_points != b.poker_points:
		return a.poker_points > b.poker_points
	if a.cluster_points != b.cluster_points:
		return a.cluster_points > b.cluster_points
	if a.edge_points != b.edge_points:
		return a.edge_points > b.edge_points
	if a.event_count != b.event_count:
		return a.event_count > b.event_count
	if a.tie_break_value != b.tie_break_value:
		return a.tie_break_value > b.tie_break_value
	return a.move_key < b.move_key


## Builds a board with one all-green tile and a tile that matches on one side.
##
## The fixture is small on purpose: the expected maximum is derivable by hand, so
## the test does not simply repeat the search it is checking.
func _edge_match_fixture() -> Fixture:
	var board: BoardState = BoardState.create()
	board.commit_tile(
		TileSnapshot.create(
			_all_edges_tile(&"ai-fixture:tile:700", TileEnums.EdgeColor.GREEN),
			Vector2i(5, 5),
			0
		)
	)
	var tile: TileDefinition = _tile_with_edges(
		&"ai-fixture:tile:701",
		TileEnums.TileRank.ACE,
		[
			TileEnums.EdgeColor.GREEN,
			TileEnums.EdgeColor.BLUE,
			TileEnums.EdgeColor.BLUE,
			TileEnums.EdgeColor.BLUE,
		]
	)
	return _fixture(board, tile)


## Builds four tiles in a row, leaving two completion cells open on row 5.
##
## Their ranks differ, so the five-tile window a completion cell would close is a
## pair rather than a stronger hand (ADR-001 section 2).
func _hard_fixture() -> Fixture:
	var board: BoardState = BoardState.create()
	var columns: Array[int] = [4, 5, 6, 7]
	var ranks: Array[int] = [
		TileEnums.TileRank.ACE,
		TileEnums.TileRank.KING,
		TileEnums.TileRank.QUEEN,
		TileEnums.TileRank.JACK,
	]
	for index: int in range(columns.size()):
		var tile: TileDefinition = _tile_with_edges(
			StringName("ai-fixture:tile:%d" % (710 + index)),
			ranks[index],
			[
				TileEnums.EdgeColor.GREEN,
				TileEnums.EdgeColor.GREEN,
				TileEnums.EdgeColor.GREEN,
				TileEnums.EdgeColor.GREEN,
			]
		)
		board.commit_tile(TileSnapshot.create(tile, Vector2i(columns[index], 5), 0))

	# The opponent holds a tile whose edges never match the fixture's green row,
	# so the immediate score cannot mask the difference in open threats.
	var held: TileDefinition = _all_edges_tile(&"ai-fixture:tile:720", TileEnums.EdgeColor.BLUE)
	return _fixture(board, held)


## Pairs a fixture board with its tile into a detached snapshot.
func _fixture(board: BoardState, tile: TileDefinition) -> Fixture:
	var snapshot: AiGameSnapshot = AiGameSnapshot.from_parts(
		board,
		ScoredHandSet.create(),
		ScoringRules.create_default(),
		AI,
		HUMAN,
		0,
		0,
		7,
		&"ai-fixture",
		TEST_SEED
	)
	if not check_not_null(snapshot, "the fixture snapshot must build"):
		return null
	check(
		snapshot.is_valid(),
		"the fixture snapshot must be valid: %s" % str(snapshot.validate())
	)
	var fixture: Fixture = Fixture.new()
	fixture.board = board
	fixture.snapshot = snapshot
	fixture.tile = tile
	return fixture


## Builds a session and advances it to the opponent's action phase.
func _ai_turn_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = _new_session(match_id, seed)
	if session == null:
		return null
	TurnManager.setup(session)
	var frontier: Array[Vector2i] = session.get_board().get_frontier_cells()
	var result: PlacementResult = MoveCommitter.commit(session, HUMAN, frontier[0], 0)
	if not check(result != null and result.was_committed(), "the human move must commit"):
		return null
	TurnManager.resolve(session, result)
	if not check(
		TurnManager.is_awaiting_ai_action(session),
		"the fixture must reach the opponent's action phase"
	):
		return null
	return session


## Builds a standard-rules session.
func _new_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = GameSessionState.create(
		match_id, seed, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(session, "the session must be constructible")
	return session


## Builds a valid tile with the given visible edges.
func _tile_with_edges(
	tile_id: StringName, rank: int, edges: Array[TileEnums.EdgeColor]
) -> TileDefinition:
	return TileDefinition.create(tile_id, rank, TileEnums.FaceColor.RED, edges.duplicate())


## Builds a valid tile with one colour on every edge.
func _all_edges_tile(tile_id: StringName, color: TileEnums.EdgeColor) -> TileDefinition:
	return _tile_with_edges(tile_id, TileEnums.TileRank.ACE, [color, color, color, color])


## Builds a valid tile whose edges never match an all-green fixture.
func _plain_tile(tile_id: StringName) -> TileDefinition:
	return _all_edges_tile(tile_id, TileEnums.EdgeColor.BLUE)
