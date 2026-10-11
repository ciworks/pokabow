extends TestCase

## Milestone 6 difficulty tests (ADR-005 sections 4, 5, 6, 7, 8, 9, 11, and 12,
## retargeted to whole lines by ADR-011 section 12).
##
## Domain-level: no scene tree, no rendering, no input, no controller. Each
## difficulty is driven directly through the shared `choose_move` contract, and
## the fixtures are hand-built boards and hands so the expected answer is
## derivable by hand rather than by trusting the search.
##
## ADR-011 section 12 changes what a candidate is - one whole LINE drawn from the
## rival's own deck - so each strategy is handed a DECK, every assertion is made
## about the chosen line, and every chosen line is re-validated through the shared
## `LineValidator` so no difficulty can propose something the human path would
## refuse.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

const TEST_MATCH_ID: StringName = &"ai-difficulty"
const TEST_SEED: int = 20260921

## Decision seeds used for the deterministic checks.
const EASY_SEED: int = 11
const MEDIUM_SEED: int = 22
const HARD_SEED: int = 33

## Turn number the hand-built fixtures are pinned to, so a preview the test
## computes and a preview the strategy computes use the same turn.
const FIXTURE_TURN: int = 7

## Tiles the shortest legal line places (ADR-011 section 1).
const TILES_PER_LINE: int = 2

## The four tiles in a column that leave two completion cells open (row 5).
const ROW_OPEN_LEFT: Vector2i = Vector2i(3, 5)
const ROW_OPEN_RIGHT: Vector2i = Vector2i(8, 5)


## A hand-built board, the hand under test, the opponent's hand, and the snapshot.
##
## A typed holder rather than a Dictionary, so every fixture value stays typed.
class Fixture extends RefCounted:
	var board: BoardState = null
	var snapshot: AiGameSnapshot = null
	var deck: Array[TileDefinition] = []
	var opponent_deck: Array[TileDefinition] = []


func test_easy_picks_a_uniform_legal_line() -> void:
	var fixture: Fixture = _edge_match_fixture()
	if fixture == null:
		return
	var strategy: AiEasyStrategy = AiEasyStrategy.new()
	var decision: AiDecision = strategy.choose_move(
		fixture.snapshot,
		fixture.deck,
		AiDifficultyConfig.create_default(AiEnums.Difficulty.EASY),
		EASY_SEED,
		AiCancellationToken.new()
	)
	if not check_not_null(decision, "Easy must produce a decision"):
		return
	if not check(decision.has_move(), "Easy must propose a move when one is legal"):
		return
	check_eq(
		int(decision.diagnostics.get("evaluated_candidates", -1)),
		0,
		"ADR-005 section 4: Easy must not evaluate score"
	)

	# ADR-011 sections 1 and 5: the move is a whole line, and the shared validator
	# must accept exactly that line on the fixture's board.
	check(
		decision.line.size() >= TILES_PER_LINE,
		"Easy must choose a line of two or more tiles, never a lone tile (ADR-011 section 1)"
	)
	var result: LineResult = LineValidator.validate(fixture.board, decision.line)
	check(
		result != null and result.accepted,
		"Easy must propose a line the shared validator accepts (ADR-005 section 2): %s"
		% ("" if result == null else result.get_rejection_name())
	)
	check_eq(
		decision.line_cells.size(),
		decision.line.size(),
		"every chosen tile must carry one target cell"
	)
	for rotation: int in decision.line_rotations:
		check(
			rotation >= 0 and rotation < TileEnums.ROTATION_COUNT,
			"Easy must choose a real quarter-turn rotation, got %d" % rotation
		)

	# ADR-005 section 4 fixes an even distribution over the legal candidates, and
	# ADR-011 section 12 makes the rotation part of the line, so the rotation
	# profile is drawn from its own seeded stream.
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

	var profiles: Array[int] = [0, 0, 0]
	for seed: int in range(300):
		var profile: int = uniform.pick_profile_index(3, seed)
		if check(profile >= 0 and profile < 3, "the profile pick must land on a profile"):
			profiles[profile] += 1
	for index: int in range(profiles.size()):
		check(
			profiles[index] > 40 and profiles[index] < 160,
			"rotation profile %d must be drawn roughly one third of the time (got %d)"
			% [index, profiles[index]]
		)


func test_easy_spreads_across_the_legal_lines() -> void:
	var fixture: Fixture = _edge_match_fixture()
	if fixture == null:
		return
	var strategy: AiEasyStrategy = AiEasyStrategy.new()
	var seen: Dictionary = {}
	for seed: int in range(120):
		var decision: AiDecision = strategy.choose_move(
			fixture.snapshot,
			fixture.deck,
			AiDifficultyConfig.create_default(AiEnums.Difficulty.EASY),
			seed,
			AiCancellationToken.new()
		)
		if decision != null and decision.has_move():
			seen[decision.move_key] = true
	check(
		seen.size() >= 4,
		"Easy must reach more than one legal line across seeds (got %d)" % seen.size()
	)


func test_medium_returns_the_documented_tuple_maximum() -> void:
	var fixture: Fixture = _medium_fixture()
	if fixture == null:
		return
	var strategy: AiMediumStrategy = AiMediumStrategy.new()
	var decision: AiDecision = strategy.choose_move(
		fixture.snapshot,
		fixture.deck,
		AiDifficultyConfig.create_default(AiEnums.Difficulty.MEDIUM),
		MEDIUM_SEED,
		AiCancellationToken.new()
	)
	if not check_not_null(decision, "Medium must produce a decision"):
		return
	if not check(decision.has_move(), "Medium must propose a move"):
		return

	var candidates: Array[AiMoveCandidate] = _scored_candidates(fixture, MEDIUM_SEED)
	if not check(candidates.size() > 1, "the fixture must offer several candidates"):
		return

	var max_total: int = 0
	for candidate: AiMoveCandidate in candidates:
		max_total = maxi(max_total, candidate.immediate_score)
	# The fixture leaves a five-cell window one line away from completion at its
	# left end - the only end ADR-012 section 1 as amended allows - so a line that
	# completes it must beat the lines that only match their own neighbour. A zero
	# maximum would make the choice trivial and prove nothing.
	check(
		max_total > 1,
		"the fixture must make the choice non-trivial (best line scores %d)" % max_total
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
		"the decision diagnostics must record the chosen line"
	)

	var chosen: AiMoveCandidate = null
	for candidate: AiMoveCandidate in candidates:
		if candidate.move_key == decision.move_key:
			chosen = candidate
	if not check_not_null(chosen, "the chosen line must be one of the enumerated candidates"):
		return
	check_eq(
		chosen.immediate_score,
		max_total,
		"the chosen line must carry the maximum immediate score"
	)
	check(
		chosen.immediate_score > 0,
		"Medium must prefer a line that scores over one that does not"
	)
	# Completing the fixture's five-cell window is what earns the maximum, so the
	# chosen line must be the one that does it.
	check_eq(
		chosen.merged_size,
		5,
		"the chosen line must complete the five-cell window (ADR-011 section 2)"
	)
	check_eq(
		chosen.hand_category,
		ScoringEnums.PokerHandCategory.FULL_HOUSE,
		"the completed window must be the fixture's Full House (ADR-012 section 1)"
	)
	check_eq(
		int(decision.diagnostics.get("merged_size", -1)),
		5,
		"the decision diagnostics must record the merged line length"
	)


func test_hard_blocks_an_available_completion_cell() -> void:
	var fixture: Fixture = _hard_fixture()
	if fixture == null:
		return
	var rules: ScoringRules = fixture.snapshot.get_rules()

	# AiFeatures reads completion from occupancy alone, so both row ends count here
	# even though only one grouped rank completes the window legally (ADR-012
	# section 1 as amended). The checks below are about the threats the rival
	# leaves open and the blocks it can take, not about which rank would complete a
	# window, so the order-agnostic count is the right input for them.
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
		fixture.board, fixture.deck
	)
	var lowest_threat: int = 999
	var highest_threat: int = -1
	var blockers: int = 0
	for candidate: AiMoveCandidate in candidates:
		var threat: int = AiFeatures.human_open_threat(fixture.snapshot, candidate, rules)
		lowest_threat = mini(lowest_threat, threat)
		highest_threat = maxi(highest_threat, threat)
		for cell: Vector2i in candidate.cells:
			if open_cells.has(cell):
				blockers += 1
				break
	check(
		highest_threat > lowest_threat,
		"the fixture must let Hard reduce the threats it leaves open (%d vs %d)"
		% [lowest_threat, highest_threat]
	)
	check(
		blockers > 0,
		"the fixture must offer at least one legal line that occupies a completion cell"
	)

	var decision: AiDecision = AiHardStrategy.new().choose_move(
		fixture.snapshot,
		fixture.deck,
		_hard_config(),
		HARD_SEED,
		AiCancellationToken.new()
	)
	if not check_not_null(decision, "Hard must produce a decision"):
		return
	if not check(decision.has_move(), "Hard must propose a move"):
		return
	var result: LineResult = LineValidator.validate(fixture.board, decision.line)
	check(
		result != null and result.accepted,
		"Hard must propose a line the shared validator accepts: %s"
		% ("" if result == null else result.get_rejection_name())
	)

	# The multiplied hand score can outweigh a block. Hard must still evaluate
	# the open-threat feature consistently for its chosen legal move.
	check(
		int(decision.diagnostics.get("human_open_threat", -1)) >= lowest_threat
		and int(decision.diagnostics.get("human_open_threat", -1)) <= highest_threat,
		"Hard must report a threat count from the candidate range"
	)
	check_eq(
		int(decision.diagnostics.get("human_open_threat", -1)),
		AiFeatures.human_open_threat(fixture.snapshot, AiMoveCandidate.create(decision.line, result), rules),
		"the chosen line's threat diagnostic must match the shared feature"
	)
	check(
		int(decision.diagnostics.get("utility", 0)) > 0,
		"the chosen move must have a positive ADR-005 section 6 utility"
	)


func test_hard_stays_inside_the_section_8_work_budget() -> void:
	var fixture: Fixture = _hard_fixture()
	if fixture == null:
		return
	var config: AiDifficultyConfig = _hard_config()
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
		fixture.deck,
		AiDifficultyConfig.create_default(AiEnums.Difficulty.HARD),
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
	check_eq(
		String(diagnostics.get("search", "")),
		"legal-line-generation",
		"the diagnostics must name the line-shaped search ADR-011 section 12 requires"
	)


func test_every_difficulty_swaps_when_no_legal_line_exists() -> void:
	# ADR-011 section 6: a player who holds tiles but cannot form ONE legal line
	# swaps rather than stalling or placing an illegal tile. The hand below holds
	# two tiles of different ranks that repeat nothing, and under ADR-012 section 1
	# a hand must either repeat a rank or step along the Jack-to-Ace ladder in
	# sequence order: neither held rank sits one step from the committed ACE, so
	# no merged line of one or two of them is a hand.
	var fixture: Fixture = _no_line_fixture()
	if fixture == null:
		return
	var board: BoardState = fixture.snapshot.get_board()
	check_eq(
		LegalMoveGenerator.generate(board, fixture.deck).size(),
		0,
		"the fixture's hand must be unable to form a legal line"
	)
	var single: Array[TileSnapshot] = [
		TileSnapshot.create(fixture.deck[0], board.get_frontier_cells()[0], 0)
	]
	var lone: LineResult = LineValidator.validate(board, single)
	check(
		lone != null and not lone.accepted,
		"ADR-011 section 4: a lone tile must not be a legal move"
	)

	var strategies: Array[AiStrategy] = [
		AiEasyStrategy.new(), AiMediumStrategy.new(), AiHardStrategy.new()
	]
	var difficulties: Array[int] = [
		AiEnums.Difficulty.EASY, AiEnums.Difficulty.MEDIUM, AiEnums.Difficulty.HARD,
	]
	for index: int in range(strategies.size()):
		var label: String = AiEnums.difficulty_name(difficulties[index])
		var decision: AiDecision = strategies[index].choose_move(
			fixture.snapshot,
			fixture.deck,
			AiDifficultyConfig.create_default(difficulties[index]),
			HARD_SEED,
			AiCancellationToken.new()
		)
		if not check_not_null(decision, "%s must still answer with an unplayable hand" % label):
			continue
		check(decision.has_move(), "%s must report the swap as its move" % label)
		check(decision.is_swap_move(), "%s must swap when no legal line exists" % label)
		check(not decision.has_line(), "%s must not carry a line in a swap" % label)
		check_eq(decision.line.size(), 0, "%s's swap must place no tile" % label)
		check_eq(
			String(decision.diagnostics.get("policy_outcome", "")),
			"swap",
			"%s must record that the turn was taken by the swap" % label
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
			fixture.deck,
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
		check(
			not decision.has_line(),
			"ADR-005 section 9: a cancelled analysis must carry no line"
		)


func test_a_stale_proposal_is_refused_and_the_retry_is_bounded() -> void:
	var session: GameSessionState = _ai_turn_session(TEST_MATCH_ID, TEST_SEED)
	if session == null:
		return
	var coordinator: AiCoordinator = AiCoordinator.create(AiEnums.Difficulty.MEDIUM)
	var deck: Array[TileDefinition] = session.deck_for(AI)
	var decision: AiDecision = coordinator.choose_move(session, deck, AiCancellationToken.new())
	if not check_not_null(decision, "the coordinator must produce a decision"):
		return
	if not check(decision.has_move(), "the coordinator must propose a move"):
		return
	check(
		decision.line.size() >= 1,
		"the coordinator must decide a complete legal move"
	)
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

	# A lone tile at the current revision must be refused as well: ADR-011
	# section 4 makes it no move at all, whatever the board says.
	var occupied: Vector2i = board.get_occupied_cells()[0]
	var lone: Array[TileSnapshot] = [
		TileSnapshot.create(_plain_tile(&"ai-fixture:tile:903"), occupied, 0)
	]
	var illegal: AiDecision = AiDecision.create_line(
		lone, board.get_revision(), "ai-line:illegal", {}
	)
	var refused: AiDecision = coordinator.revalidate(session, illegal)
	if check_not_null(refused, "revalidation must answer for an illegal proposal"):
		check(
			not refused.has_move(),
			"a proposal the validator refuses must not survive revalidation"
		)
		check_eq(
			String(refused.diagnostics.get("reason", "")),
			"the proposal has no tiles",
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
	check(coordinator.strategy() is AiEasyStrategy, "the fallback must use the Easy strategy")

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
		# ADR-011 sections 1 and 5: every committed move is one whole line of two
		# or more tiles, so the board can never be a tile ahead of the history.
		check(
			session.get_board().occupied_count() >= ai_moves * TILES_PER_LINE,
			"%s: every committed move must place a whole line of two or more tiles" % label
		)
		check_eq(
			session.get_board().get_revision(),
			session.move_count(),
			"%s: the board revision must count the committed moves, not the tiles" % label
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


## Plays `ai_turns` opponent turns, with the human side taking the first legal line
## its own deck can form.
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
		var committed: LineResult = null
		if turn_state.active_player_id == HUMAN:
			committed = MoveCommitter.commit_line(session, HUMAN, _human_line(session))
		else:
			var decision: AiDecision = coordinator.choose_move(
				session, session.deck_for(AI), AiCancellationToken.new()
			)
			if decision == null or not decision.has_line():
				check(false, "the AI must always hold a legal line while the board is open")
				break
			committed = MoveCommitter.commit_line(session, AI, decision.line)
			if committed != null and committed.was_committed():
				ai_moves += 1
			else:
				check(false, "an AI line must commit through MoveCommitter")
				break
		if committed == null or not committed.was_committed():
			check(false, "every scripted move in this fixture must form a legal line")
			break
		# ADR-011 section 7 makes a turn exactly one move, so the resolved line
		# ends the turn and there is no separate end-turn step.
		TurnManager.resolve(session, committed)
	return ai_moves


## Returns a legal opening line from the human's deck, or an empty array.
##
## ADR-012 sections 1 and 2 make a hand legal when it repeats a rank or steps
## along the Jack-to-Ace ladder, and a deck of six drawn from four ranks always
## holds a pair, so the first legal candidate the shared generator finds is the
## line this fixture plays.
func _human_line(session: GameSessionState) -> Array[TileSnapshot]:
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(
		session.get_board(), session.deck_for(HUMAN)
	)
	if candidates.is_empty():
		return [] as Array[TileSnapshot]
	return candidates[0].snapshots


## Returns the candidate the ADR-005 section 5 tuple selects.
##
## The candidates are scored through the SAME ADR-007 preview and the SAME seed
## derivation the strategy uses, but the comparison is written out here, so this
## is an independent statement of the expected answer rather than a second call
## to the code under test.
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
## tie-break value of section 10 (higher wins), then the canonical move key.
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


## Returns the fixture's legal line candidates with their ADR-007 preview attached.
func _scored_candidates(fixture: Fixture, decision_seed: int) -> Array[AiMoveCandidate]:
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(
		fixture.board, fixture.deck
	)
	if fixture.snapshot == null:
		return candidates
	var rules: ScoringRules = fixture.snapshot.get_rules()
	var strategy: AiMediumStrategy = AiMediumStrategy.new()
	for candidate: AiMoveCandidate in candidates:
		candidate.apply_transaction(
			ScoringCoordinator.preview_line(
				fixture.board,
				candidate.snapshots,
				AI,
				rules,
				fixture.snapshot.get_scored_hand_set(),
				FIXTURE_TURN
			)
		)
		candidate.tie_break_value = strategy.tie_break_value_for(decision_seed, candidate.move_key)
	return candidates


## Returns the Hard configuration the blocking fixture is scored with.
##
## The deep ply is pinned to the opponent's own held hand (`hard_reply_sample_size`
## of 1) so the fixture isolates the blocking term of ADR-005 section 6: the
## representative sample is a different term, and letting its tiles into this
## fixture would let one candidate's reply outscore the threat difference the
## check is about. The sample's own contract is asserted by
## `test_hard_stays_inside_the_section_8_work_budget`.
func _hard_config() -> AiDifficultyConfig:
	var config: AiDifficultyConfig = AiDifficultyConfig.create_default(AiEnums.Difficulty.HARD)
	config.hard_reply_sample_size = 1
	return config


## Builds a board with one committed pair of tiles and a hand that can line up.
##
## The pair gives the hand a rank to merge with, so lines both in the row and in
## the columns around it are legal, which is what the uniformity checks need.
func _edge_match_fixture() -> Fixture:
	var board: BoardState = BoardState.create()
	board.commit_tile(
		TileSnapshot.create(
			_all_edges_tile(&"ai-fixture:tile:700", TileEnums.EdgeColor.GREEN),
			Vector2i(5, 5),
			0
		)
	)
	board.commit_tile(
		TileSnapshot.create(
			_tile_with_edges(
				&"ai-fixture:tile:701",
				TileEnums.TileRank.KING,
				[
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
				]
			),
			Vector2i(6, 5),
			0
		)
	)
	return _fixture(board, _line_hand(), _opponent_hand())


## Builds a board with a five-cell window one line away from completion.
##
## Columns 5, 6, and 7 of row 5 hold ACE, KING, and KING, so a line of two ACE
## tiles at the left end (columns 3 and 4) completes a five-cell window whose
## ranks are ACE, ACE, ACE, KING, KING - the Full House of ADR-012 section 1, the
## only shape a five-tile line may take now that a five-tile Three-of-a-Kind and
## Five-of-a-Kind are both refused. ADR-012 section 1 as amended additionally
## requires each rank's tiles to be adjacent along the line, so the right end
## (columns 8 and 9) reads ACE, KING, KING, ACE, ACE with the ACE group split: it
## is interleaved and refused, and it is not a completion the fixture offers.
## Every other legal line scores only the edge match between the two tiles it
## stages, so the maximum is derivable by hand and the chosen line must be the
## left-end one that completes the window.
func _medium_fixture() -> Fixture:
	var board: BoardState = BoardState.create()
	board.commit_tile(
		TileSnapshot.create(
			_all_edges_tile(&"ai-fixture:tile:730", TileEnums.EdgeColor.GREEN),
			Vector2i(5, 5),
			0
		)
	)
	board.commit_tile(
		TileSnapshot.create(
			_tile_with_edges(
				&"ai-fixture:tile:731",
				TileEnums.TileRank.KING,
				_green_edges()
			),
			Vector2i(6, 5),
			0
		)
	)
	board.commit_tile(
		TileSnapshot.create(
			_tile_with_edges(
				&"ai-fixture:tile:732",
				TileEnums.TileRank.KING,
				_green_edges()
			),
			Vector2i(7, 5),
			0
		)
	)
	var hand: Array[TileDefinition] = [
		_all_edges_tile(&"ai-fixture:tile:733", TileEnums.EdgeColor.BLUE),
		_all_edges_tile(&"ai-fixture:tile:734", TileEnums.EdgeColor.BLUE),
	]
	return _fixture(board, hand, _opponent_hand())


## Builds four tiles in a row that one more tile can complete as a Full House.
##
## Row 5 holds ACE, ACE, KING, and KING at columns 4 to 7, so the five-cell
## window has an open end at column 3 and at column 8. ADR-012 section 1 as
## amended requires each rank's tiles to be adjacent along the line, so only two
## of the four one-tile completions are legal: an ACE at column 3 reads
## ACE, ACE, ACE, KING, KING and a KING at column 8 reads ACE, ACE, KING, KING,
## KING, while a KING at column 3 and an ACE at column 8 split both groups and
## are refused. Those two grouped ends are the fixture's high-value completion
## cells, and both keep the shape 3+2, the only five-tile shape still legal. The
## hand under test
## holds two tiles of one rank whose edges cannot match the row, so the choice
## turns on which completion cell the line occupies (ADR-005 sections 6 and 7).
## The opponent's hand is colour-disjoint from the board and from the tiles under
## test, so no reply can score either.
func _hard_fixture() -> Fixture:
	var board: BoardState = BoardState.create()
	var columns: Array[int] = [4, 5, 6, 7]
	var ranks: Array[int] = [
		TileEnums.TileRank.ACE,
		TileEnums.TileRank.ACE,
		TileEnums.TileRank.KING,
		TileEnums.TileRank.KING,
	]
	for index: int in range(columns.size()):
		board.commit_tile(
			TileSnapshot.create(
				_tile_with_edges(
					StringName("ai-fixture:tile:%d" % (710 + index)),
					ranks[index],
					_green_edges()
				),
				Vector2i(columns[index], 5),
				0
			)
		)
	var hand: Array[TileDefinition] = [
		_all_edges_tile(&"ai-fixture:tile:720", TileEnums.EdgeColor.BLUE),
		_all_edges_tile(&"ai-fixture:tile:721", TileEnums.EdgeColor.BLUE),
	]
	return _fixture(board, hand, _colour_disjoint_hand())


## Builds a board with room to line up and a hand that cannot form any legal line.
##
## ADR-012 section 1 makes a hand legal only when it repeats a rank or steps along
## the Jack-to-Ace ladder in sequence order (section 2). The committed ACE and the
## two held ranks here (JACK and QUEEN) therefore repeat nothing, and neither held
## rank sits one ladder step from the ACE, so no line the hand can stage is a
## hand - which is the state ADR-011 section 6's swap exists for. The board still
## has open cells, so "no legal line" is a property of the hand, not of the board.
func _no_line_fixture() -> Fixture:
	var board: BoardState = BoardState.create()
	board.commit_tile(
		TileSnapshot.create(
			_tile_with_edges(
				&"ai-fixture:tile:740", TileEnums.TileRank.ACE, _green_edges()
			),
			Vector2i(5, 5),
			0
		)
	)
	var hand: Array[TileDefinition] = [
		_tile_with_edges(&"ai-fixture:tile:741", TileEnums.TileRank.JACK, _blue_edges()),
		_tile_with_edges(
			&"ai-fixture:tile:742",
			TileEnums.TileRank.QUEEN,
			[
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
			]
		),
	]
	return _fixture(board, hand, _opponent_hand())


## Pairs a fixture board with a hand under test into a detached snapshot.
func _fixture(
	board: BoardState, hand: Array[TileDefinition], opponent_hand: Array[TileDefinition]
) -> Fixture:
	var snapshot: AiGameSnapshot = AiGameSnapshot.from_parts(
		board,
		ScoredHandSet.create(),
		ScoringRules.create_default(),
		AI,
		HUMAN,
		0,
		0,
		FIXTURE_TURN,
		&"ai-fixture",
		TEST_SEED,
		hand,
		opponent_hand
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
	fixture.deck = hand
	fixture.opponent_deck = opponent_hand
	return fixture


## Builds a session and advances it to the opponent's action phase.
func _ai_turn_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = _new_session(match_id, seed)
	if session == null:
		return null
	TurnManager.setup(session)
	var opening: Array[TileSnapshot] = _human_line(session)
	if not check(
		opening.size() >= TILES_PER_LINE,
		"the fixture's opening hand must be able to form a line"
	):
		return null
	var result: LineResult = MoveCommitter.commit_line(session, HUMAN, opening)
	if not check(result != null and result.was_committed(), "the human line must commit"):
		return null
	# ADR-011 section 7 makes a turn exactly one move, so resolving the committed
	# line passes play to the opponent; ADR-010's explicit end-turn action is
	# gone. Resolving it also runs the turn boundary of section 8, so the
	# opponent's deck is the refilled one when the analysis starts.
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


## Returns the six-tile hand the line-shaped checks are driven with.
##
## Two ACE tiles give the hand a rank to merge with the committed pair, and the
## colours are chosen so a line never matches the committed GREEN tiles, which
## keeps the uniformity checks about the candidate list rather than about score.
func _line_hand() -> Array[TileDefinition]:
	return [
		_tile_with_edges(
			&"ai-fixture:tile:750",
			TileEnums.TileRank.ACE,
			[
				TileEnums.EdgeColor.GREEN,
				TileEnums.EdgeColor.GREEN,
				TileEnums.EdgeColor.BLUE,
				TileEnums.EdgeColor.BLUE,
			]
		),
		_all_edges_tile(&"ai-fixture:tile:751", TileEnums.EdgeColor.BLUE),
		_tile_with_edges(&"ai-fixture:tile:752", TileEnums.TileRank.QUEEN, _blue_edges()),
		_tile_with_edges(
			&"ai-fixture:tile:753",
			TileEnums.TileRank.QUEEN,
			[
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
			]
		),
		_tile_with_edges(&"ai-fixture:tile:754", TileEnums.TileRank.JACK, _blue_edges()),
		_all_edges_tile(&"ai-fixture:tile:755", TileEnums.EdgeColor.RED),
	]


## Returns the opponent's hand for the fixtures whose reply ply does not matter.
func _opponent_hand() -> Array[TileDefinition]:
	return [
		_tile_with_edges(&"ai-fixture:tile:760", TileEnums.TileRank.ACE, _blue_edges()),
		_tile_with_edges(
			&"ai-fixture:tile:761",
			TileEnums.TileRank.KING,
			[
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
			]
		),
	]


## Returns an opponent hand whose colours appear nowhere on the blocking fixture.
func _colour_disjoint_hand() -> Array[TileDefinition]:
	return [
		_tile_with_edges(
			&"ai-fixture:tile:770",
			TileEnums.TileRank.ACE,
			[
				TileEnums.EdgeColor.YELLOW,
				TileEnums.EdgeColor.YELLOW,
				TileEnums.EdgeColor.YELLOW,
				TileEnums.EdgeColor.YELLOW,
			]
		),
		_tile_with_edges(
			&"ai-fixture:tile:771",
			TileEnums.TileRank.KING,
			[
				TileEnums.EdgeColor.YELLOW,
				TileEnums.EdgeColor.YELLOW,
				TileEnums.EdgeColor.YELLOW,
				TileEnums.EdgeColor.YELLOW,
			]
		),
	]


## Builds a valid tile with the given visible edges.
func _tile_with_edges(
	tile_id: StringName, rank: int, edges: Array[TileEnums.EdgeColor]
) -> TileDefinition:
	return TileDefinition.create(tile_id, rank, TileEnums.FaceColor.RED, edges.duplicate())


## Builds a valid tile with one colour on every edge.
func _all_edges_tile(tile_id: StringName, color: TileEnums.EdgeColor) -> TileDefinition:
	return _tile_with_edges(tile_id, TileEnums.TileRank.ACE, _edges_of(color))


## Returns four edges of one colour, as the tile factory expects them.
func _edges_of(color: TileEnums.EdgeColor) -> Array[TileEnums.EdgeColor]:
	return [color, color, color, color]


## Returns four GREEN edges.
func _green_edges() -> Array[TileEnums.EdgeColor]:
	return _edges_of(TileEnums.EdgeColor.GREEN)


## Returns four BLUE edges.
func _blue_edges() -> Array[TileEnums.EdgeColor]:
	return _edges_of(TileEnums.EdgeColor.BLUE)


## Builds a valid tile whose edges never match the GREEN fixtures.
func _plain_tile(tile_id: StringName) -> TileDefinition:
	return _all_edges_tile(tile_id, TileEnums.EdgeColor.BLUE)
