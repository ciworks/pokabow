extends TestCase

## Milestone 6 AI determinism tests (ADR-005 sections 3, 9, 10, 11, and 12).
##
## Domain-level: no scene tree, no rendering, no input. The one controller test
## hosts the application node directly so the thinking-state surface can be
## observed; it never loads `GameScreen`.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

const TEST_SEED: int = 5150

## A fixed decision seed, so the ordering under test is reproducible.
const DECISION_SEED: int = 20260921


func test_the_same_seed_produces_the_same_decision() -> void:
	var difficulties: Array[int] = [
		AiEnums.Difficulty.EASY, AiEnums.Difficulty.MEDIUM, AiEnums.Difficulty.HARD,
	]
	for difficulty: int in difficulties:
		var label: String = AiEnums.difficulty_name(difficulty)
		# Two independently built sessions with the same identity and seed must
		# reach the same decision, because the seed stream is derived from the
		# match and not from engine iteration order (ADR-005 section 3).
		var first: GameSessionState = _ai_turn_session(&"ai-determinism", TEST_SEED)
		var second: GameSessionState = _ai_turn_session(&"ai-determinism", TEST_SEED)
		if first == null or second == null:
			continue

		var strategy: AiStrategy = _strategy_for(difficulty)
		var config: AiDifficultyConfig = AiDifficultyConfig.create_default(difficulty)
		var first_decision: AiDecision = _decide(first, strategy, config)
		var second_decision: AiDecision = _decide(second, strategy, config)
		if not check_not_null(first_decision, "%s must decide" % label):
			continue
		if not check_not_null(second_decision, "%s must decide twice" % label):
			continue

		check(first_decision.has_move(), "%s must propose a move" % label)
		check_eq(
			first_decision.move_key,
			second_decision.move_key,
			"%s: the same seed must produce the same move key" % label
		)
		check_eq(
			first_decision.cell,
			second_decision.cell,
			"%s: the same seed must produce the same coordinate" % label
		)
		check_eq(
			first_decision.rotation,
			second_decision.rotation,
			"%s: the same seed must produce the same rotation" % label
		)
		check_eq(
			int(first_decision.diagnostics.get("deep_evaluations", 0)),
			int(second_decision.diagnostics.get("deep_evaluations", 0)),
			"%s: the search must do the same amount of work for the same seed" % label
		)

		# Another seed must still produce a legal proposal: the tie-break of
		# ADR-005 section 10 may only reorder candidates, never remove one.
		var snapshot: AiGameSnapshot = AiGameSnapshot.create(first, AI)
		if not check_not_null(snapshot, "%s must be able to snapshot the match" % label):
			continue
		var other_decision: AiDecision = strategy.choose_move(
			snapshot,
			first.active_tile_for(AI),
			config,
			DECISION_SEED + 1,
			AiCancellationToken.new()
		)
		if check_not_null(other_decision, "%s must decide under another seed" % label):
			check(
				other_decision.has_move(),
				"%s must still propose a move under another seed" % label
			)


func test_the_decision_seed_derives_from_the_match_identity() -> void:
	var base: int = AiCoordinator.derive_seed(
		TEST_SEED, 7, AI, AiEnums.Difficulty.MEDIUM
	)
	check_eq(
		base,
		AiCoordinator.derive_seed(TEST_SEED, 7, AI, AiEnums.Difficulty.MEDIUM),
		"the decision seed must be a pure function of its inputs"
	)
	check(base >= 0, "the decision seed must be a non-negative value")
	check(
		base != AiCoordinator.derive_seed(TEST_SEED + 1, 7, AI, AiEnums.Difficulty.MEDIUM),
		"a different match seed must produce a different decision seed"
	)
	check(
		base != AiCoordinator.derive_seed(TEST_SEED, 8, AI, AiEnums.Difficulty.MEDIUM),
		"a different turn must produce a different decision seed"
	)
	check(
		base != AiCoordinator.derive_seed(TEST_SEED, 7, HUMAN, AiEnums.Difficulty.MEDIUM),
		"a different player must produce a different decision seed"
	)
	check(
		base != AiCoordinator.derive_seed(TEST_SEED, 7, AI, AiEnums.Difficulty.HARD),
		"a different difficulty must produce a different decision seed"
	)

	# The coordinator's own seed follows the session's turn.
	var session: GameSessionState = _ai_turn_session(&"ai-seed", TEST_SEED)
	if session == null:
		return
	var coordinator: AiCoordinator = AiCoordinator.create(AiEnums.Difficulty.MEDIUM)
	check_eq(
		coordinator.decision_seed(session),
		AiCoordinator.derive_seed(
			session.get_seed(),
			session.get_turn_state().turn_number,
			AI,
			AiEnums.Difficulty.MEDIUM
		),
		"the coordinator must derive its seed from the match, turn, player, and difficulty"
	)


func test_ai_analysis_never_changes_the_draw_order() -> void:
	# ADR-004 section 7: the AI decision interface must not be able to disturb the
	# tile bag. Two identical matches are compared: one analyses with all three
	# difficulties first, the other does not.
	var analysed: GameSessionState = _ai_turn_session(&"ai-draw-order", TEST_SEED)
	var untouched: GameSessionState = _ai_turn_session(&"ai-draw-order", TEST_SEED)
	if analysed == null or untouched == null:
		return

	var difficulties: Array[int] = [
		AiEnums.Difficulty.EASY, AiEnums.Difficulty.MEDIUM, AiEnums.Difficulty.HARD,
	]
	for difficulty: int in difficulties:
		var decision: AiDecision = _decide(
			analysed, _strategy_for(difficulty), AiDifficultyConfig.create_default(difficulty)
		)
		check_not_null(decision, "analysis must run without a scene tree")

	var bag_before: Array[StringName] = _bag_ids(analysed)
	var cell: Vector2i = analysed.get_board().get_frontier_cells()[0]

	# The same move is committed on both matches; the only difference between them
	# is that the first one ran the AI analysis.
	var analysed_result: PlacementResult = MoveCommitter.commit(analysed, AI, cell, 0)
	var untouched_result: PlacementResult = MoveCommitter.commit(untouched, AI, cell, 0)
	check(
		analysed_result != null and analysed_result.was_committed(),
		"the analysed match must still accept the move"
	)
	check(
		untouched_result != null and untouched_result.was_committed(),
		"the control match must accept the move"
	)

	check_eq(
		_bag_ids(analysed),
		bag_before,
		"AI analysis must not reorder the bag"
	)
	check_eq(
		_bag_ids(analysed),
		_bag_ids(untouched),
		"both matches must still hold the same bag in the same order"
	)
	check_eq(
		analysed.get_tile_source().get_draw_index(),
		untouched.get_tile_source().get_draw_index(),
		"AI analysis must not consume a draw"
	)
	check_eq(
		analysed.remaining_tile_count(),
		untouched.remaining_tile_count(),
		"AI analysis must not change how many tiles remain"
	)
	check_eq(
		analysed.get_board().to_debug_string(),
		untouched.get_board().to_debug_string(),
		"both matches must reach the same board"
	)
	check_eq(
		analysed.get_ledger().event_ids(),
		untouched.get_ledger().event_ids(),
		"both matches must award the same events"
	)
	if check(
		analysed.get_tile_source().get_draw_index() < analysed.get_tile_source().get_bag_size(),
		"the fixture must leave a tile to peek at"
	):
		check_eq(
			_next_bag_tile_id(analysed),
			_next_bag_tile_id(untouched),
			"the next tile to be drawn must be the same in both matches"
		)
	check_eq(
		analysed.get_turn_state().turn_number,
		untouched.get_turn_state().turn_number,
		"both matches must sit at the same turn"
	)


func test_the_decision_diagnostics_identify_the_analysis() -> void:
	var session: GameSessionState = _ai_turn_session(&"ai-diagnostics", TEST_SEED)
	if session == null:
		return
	var config: AiDifficultyConfig = AiDifficultyConfig.create_default(AiEnums.Difficulty.HARD)
	var decision: AiDecision = _decide(session, AiHardStrategy.new(), config)
	if not check_not_null(decision, "the analysis must produce a decision"):
		return
	var diagnostics: Dictionary = decision.diagnostics

	check_eq(
		String(diagnostics.get("difficulty", "")),
		AiEnums.difficulty_name(AiEnums.Difficulty.HARD),
		"the diagnostics must name the difficulty (ADR-005 section 12)"
	)
	check_eq(
		int(diagnostics.get("evaluation_version", -1)),
		AiDifficultyConfig.EVALUATION_VERSION,
		"the diagnostics must name the evaluation version"
	)
	check_eq(
		int(diagnostics.get("turn_number", -1)),
		session.get_turn_state().turn_number,
		"the diagnostics must name the turn the decision was made on"
	)
	check_eq(
		int(diagnostics.get("board_revision", -1)),
		session.get_board().get_revision(),
		"the diagnostics must name the board revision"
	)
	check_eq(
		String(diagnostics.get("match_id", "")),
		String(session.get_match_id()),
		"the diagnostics must name the match"
	)
	check_eq(
		decision.board_revision,
		session.get_board().get_revision(),
		"the decision must carry the revision it was computed against (ADR-005 section 11)"
	)
	check(
		String(diagnostics.get("config_version", "")).begins_with("ai-difficulty:"),
		"the diagnostics must carry a versioned configuration key"
	)


func test_the_controller_reports_an_ai_thinking_state() -> void:
	var controller: GameSessionController = GameSessionController.create()
	if not check_not_null(controller, "the controller must be constructible"):
		return
	if not _host(controller):
		check(false, "the scene tree must be available to host the controller")
		controller.free()
		return

	var seen: Array[bool] = []
	controller.ai_thinking_changed.connect(
		func(thinking: bool) -> void:
			seen.append(thinking)
	)

	check(not controller.is_ai_thinking(), "a fresh controller must not report thinking")
	check_eq(
		controller.ai_difficulty(),
		AiEnums.DEFAULT_DIFFICULTY,
		"the opponent must start at the documented default difficulty"
	)
	check(
		controller.start_new_match(&"ai-controller", TEST_SEED),
		"the controller must start a match without a scene tree"
	)
	check(not controller.is_ai_thinking(), "starting a match must not report thinking")

	controller.set_ai_difficulty(AiEnums.Difficulty.EASY)
	check_eq(
		controller.ai_difficulty(),
		AiEnums.Difficulty.EASY,
		"the opponent difficulty must be selectable"
	)

	# The state, not the turn owner, drives the rival-turn message, so it must be
	# observable on its own (ADR-005 section 9).
	controller._set_ai_thinking(true)
	check(controller.is_ai_thinking(), "the controller must report the thinking state")
	controller._set_ai_thinking(false)
	check(not controller.is_ai_thinking(), "the thinking state must clear")
	if check_eq(seen.size(), 2, "one signal must be emitted per state change"):
		check_eq(seen[0], true, "the first signal must report the start of the analysis")
		check_eq(seen[1], false, "the second signal must report the end of the analysis")

	# A real opponent turn must commit through the ordinary move path.
	var board: BoardState = controller.get_board()
	var cell: Vector2i = board.get_frontier_cells()[0]
	controller.preview_placement(cell)
	controller.confirm_pending()
	check_eq(
		controller.get_session().move_count(), 1, "the human move must commit exactly once"
	)
	# ADR-010 section 3 step 9: a committed placement leaves the turn open, so
	# the human closes it explicitly before the rival may answer (section 4).
	check(controller.is_human_turn(), "a committed move must leave the turn open")
	controller.end_human_turn()
	check(not controller.is_human_turn(), "ending the turn must pass play to the rival")

	controller._on_ai_think_timeout()
	check_eq(
		controller.get_session().move_count(),
		2,
		"the opponent must commit one move through the same path as the human"
	)
	check(
		controller.get_session().get_board().occupied_count() >= 2,
		"the opponent's tile must reach the board"
	)
	check(not controller.is_ai_thinking(), "the thinking state must clear once the move is played")

	_release(controller)


## Returns the strategy for one difficulty.
func _strategy_for(difficulty: int) -> AiStrategy:
	match difficulty:
		AiEnums.Difficulty.EASY:
			return AiEasyStrategy.new()
		AiEnums.Difficulty.HARD:
			return AiHardStrategy.new()
	return AiMediumStrategy.new()


## Runs one strategy over the session's current opponent turn.
func _decide(
	session: GameSessionState, strategy: AiStrategy, config: AiDifficultyConfig
) -> AiDecision:
	if session == null or strategy == null or config == null:
		return null
	var snapshot: AiGameSnapshot = AiGameSnapshot.create(session, AI)
	if snapshot == null:
		return null
	return strategy.choose_move(
		snapshot,
		session.active_tile_for(AI),
		config,
		DECISION_SEED,
		AiCancellationToken.new()
	)


## Returns true when the tie-break value is a pure function of its inputs.
##
## ADR-005 section 10 requires the tie-break to come from the seeded value and
## the candidate's canonical identity rather than from iteration order, object
## address, or frame time, so it must be reproducible and independent per key.
func test_the_tie_break_value_is_a_pure_function_of_the_seed_and_key() -> void:
	var strategy: AiEasyStrategy = AiEasyStrategy.new()
	var key_a: String = AiMoveCandidate.move_key_for(&"ai-fixture:tile:1", Vector2i(5, 4), 0)
	var key_b: String = AiMoveCandidate.move_key_for(&"ai-fixture:tile:1", Vector2i(5, 4), 1)
	check(key_a != key_b, "different placements must produce different move keys")

	var value: int = strategy.tie_break_value_for(DECISION_SEED, key_a)
	check(value >= 0, "the tie-break value must be a non-negative integer")
	check_eq(
		value,
		strategy.tie_break_value_for(DECISION_SEED, key_a),
		"the same seed and move key must produce the same tie-break value"
	)
	check(
		value != strategy.tie_break_value_for(DECISION_SEED, key_b),
		"a different candidate must produce a different tie-break value"
	)
	check(
		value != strategy.tie_break_value_for(DECISION_SEED + 1, key_a),
		"a different seed must produce a different tie-break value"
	)


## Returns the whole bag's identities, in bag order.
func _bag_ids(session: GameSessionState) -> Array[StringName]:
	var ids: Array[StringName] = []
	for tile: TileDefinition in session.get_tile_source().debug_bag_snapshot():
		ids.append(tile.tile_id)
	return ids


## Returns the identity of the tile that would be drawn next.
func _next_bag_tile_id(session: GameSessionState) -> StringName:
	return session.get_tile_source().debug_bag_snapshot()[
		session.get_tile_source().get_draw_index()
	].tile_id


## Builds a session and advances it to the opponent's action phase.
func _ai_turn_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = GameSessionState.create(
		match_id, seed, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	if not check_not_null(session, "the session must be constructible"):
		return null
	TurnManager.setup(session)
	var frontier: Array[Vector2i] = session.get_board().get_frontier_cells()
	if not check(frontier.size() > 0, "the fixture must offer a frontier cell"):
		return null
	var result: PlacementResult = MoveCommitter.commit(session, HUMAN, frontier[0], 0)
	if not check(result != null and result.was_committed(), "the human move must commit"):
		return null
	TurnManager.resolve(session, result)
	# ADR-010 section 3 makes a turn one or more placements, so one committed
	# tile does not pass play: the human ends the turn explicitly (section 4)
	# before the opponent can reach its action phase and be topped up at the
	# turn boundary (section 5).
	TurnManager.end_turn(session)
	if not check(
		TurnManager.is_awaiting_ai_action(session),
		"the fixture must reach the opponent's action phase"
	):
		return null
	return session


## Adds a node to the live scene tree so `_ready` runs. Returns false on failure.
func _host(node: Node) -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	tree.root.add_child(node)
	return true


## Detaches and frees a hosted node, so one test cannot leak into the next.
func _release(node: Node) -> void:
	if node == null:
		return
	var parent: Node = node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()
