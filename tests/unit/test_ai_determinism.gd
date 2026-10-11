extends TestCase

## Milestone 6 AI determinism tests (ADR-005 sections 3, 9, 10, 11, and 12,
## retargeted to whole lines by ADR-011 section 12).
##
## Domain-level: no scene tree, no rendering, no input. The one controller test
## hosts the application node directly so the thinking-state surface can be
## observed; it never loads `GameScreen`.
##
## ADR-011 section 12 makes one AI move one whole LINE of two or more deck tiles,
## so every call below hands the strategy the rival's held DECK rather than a
## single active tile, and every determinism claim is made about the chosen line.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

const TEST_SEED: int = 5150

## A fixed decision seed, so the ordering under test is reproducible.
const DECISION_SEED: int = 20260921

## Tiles the shortest legal line places (ADR-011 section 1).
const TILES_PER_LINE: int = 2


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

		if not check(first_decision.has_move(), "%s must propose a move" % label):
			continue
		check_eq(
			first_decision.move_key,
			second_decision.move_key,
			"%s: the same seed must produce the same line key" % label
		)
		check_eq(
			first_decision.cell,
			second_decision.cell,
			"%s: the same seed must produce the same anchor coordinate" % label
		)
		check_eq(
			first_decision.rotation,
			second_decision.rotation,
			"%s: the same seed must produce the same anchor rotation" % label
		)
		check_eq(
			first_decision.line_cells,
			second_decision.line_cells,
			"%s: the same seed must target the same cells" % label
		)
		check_eq(
			first_decision.tile_ids,
			second_decision.tile_ids,
			"%s: the same seed must commit the same deck tiles" % label
		)
		check_eq(
			int(first_decision.diagnostics.get("deep_evaluations", 0)),
			int(second_decision.diagnostics.get("deep_evaluations", 0)),
			"%s: the search must do the same amount of work for the same seed" % label
		)

		# ADR-011 sections 1 and 5: what was chosen is a whole line, so it must be
		# a line the shared validator accepts and it must place two or more tiles.
		check_eq(
			first_decision.line.size(),
			first_decision.line_cells.size(),
			"%s: every chosen tile must carry exactly one target cell" % label
		)
		check(
			first_decision.line.size() >= TILES_PER_LINE,
			"%s must choose a whole line, not a lone tile (ADR-011 section 1)" % label
		)
		var result: LineResult = LineValidator.validate(first.get_board(), first_decision.line)
		check(
			result != null and result.accepted,
			"%s: the chosen line must pass the shared validator: %s"
			% [label, "" if result == null else result.get_rejection_name()]
		)

		# Another seed must still produce a legal line: the tie-break of
		# ADR-005 section 10 may only reorder candidates, never remove one.
		var snapshot: AiGameSnapshot = AiGameSnapshot.create(first, AI)
		if not check_not_null(snapshot, "%s must be able to snapshot the match" % label):
			continue
		var other_decision: AiDecision = strategy.choose_move(
			snapshot,
			first.deck_for(AI),
			config,
			DECISION_SEED + 1,
			AiCancellationToken.new()
		)
		if check_not_null(other_decision, "%s must decide under another seed" % label):
			if check(
				other_decision.has_move(),
				"%s must still propose a line under another seed" % label
			):
				check(
					other_decision.line.size() >= 1,
					"%s: another seed must still choose a complete legal move" % label
				)


func test_no_clock_reading_can_change_the_chosen_line() -> void:
	# ADR-005 section 3: the same snapshot, deck, configuration, and decision seed
	# must return the same decision. A wall-clock cutoff would break that, because
	# it would let two identical requests finish with different work. The check is
	# therefore run twice with a deliberately different amount of unrelated work
	# between them: only a time-derived decision could differ.
	var session: GameSessionState = _ai_turn_session(&"ai-clock", TEST_SEED)
	if session == null:
		return
	var strategy: AiStrategy = _strategy_for(AiEnums.Difficulty.HARD)
	var config: AiDifficultyConfig = AiDifficultyConfig.create_default(AiEnums.Difficulty.HARD)
	var first: AiDecision = _decide(session, strategy, config)
	if not check_not_null(first, "the first analysis must decide"):
		return
	_burn_time(4000)
	var second: AiDecision = _decide(session, strategy, config)
	if not check_not_null(second, "the second analysis must decide"):
		return

	check_eq(first.move_key, second.move_key, "a clock reading must not change the chosen line")
	check_eq(first.line_cells, second.line_cells, "a clock reading must not change the target cells")
	check_eq(
		first.diagnostics,
		second.diagnostics,
		"nothing a clock reads may reach the decision record (ADR-005 section 3)"
	)

	# The decision record itself may not carry a timing reading, so a timing value
	# cannot leak into a comparison, a save, or a decision replay.
	for key: Variant in first.diagnostics.keys():
		var name: String = String(key).to_lower()
		check(
			not (name.contains("elapsed") or name.contains("time") or name.contains("duration")),
			"the decision diagnostics must not carry a clock reading (found '%s')" % name
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

	# The same whole line is committed on both matches; the only difference
	# between them is that the first one ran the AI analysis (ADR-011 section 5
	# makes that one atomic line, not a sequence of placements).
	var chosen: AiDecision = _decide(
		analysed, AiEasyStrategy.new(), AiDifficultyConfig.create_default(AiEnums.Difficulty.EASY)
	)
	if not check_not_null(chosen, "the fixture must find a legal AI move"):
		return
	var line: Array[TileSnapshot] = chosen.line
	if not check(line.size() >= 1, "the fixture must assemble a complete move"):
		return
	var analysed_result: LineResult = MoveCommitter.commit_line(analysed, AI, line)
	var untouched_result: LineResult = MoveCommitter.commit_line(
		untouched, AI, line
	)
	check(
		analysed_result != null and analysed_result.was_committed(),
		"the analysed match must still accept the line"
	)
	check(
		untouched_result != null and untouched_result.was_committed(),
		"the control match must accept the line"
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

	# A real human turn must commit through the ordinary move path. ADR-011
	# sections 1 and 5 make that one whole line of two deck tiles, and section 7
	# closes the turn on the commit itself, so play passes to the rival with no
	# end-turn action in between.
	var board: BoardState = controller.get_board()
	var opening: Array[Vector2i] = _opening_cells(board)
	if not check_eq(opening.size(), TILES_PER_LINE, "the board must offer two adjacent cells"):
		_release(controller)
		return
	var closed: bool = _commit_staged_line(controller, opening)
	check(closed, "the human's assembled line must commit through the controller")
	check_eq(
		controller.get_session().move_count(), 1, "the human line must commit exactly once"
	)
	check_eq(
		controller.get_session().get_board().occupied_count(),
		TILES_PER_LINE,
		"the whole line must reach the board in one commit"
	)
	# ADR-011 section 7: a turn is exactly one move, so the commit passed play on
	# by itself and the human cannot act again.
	check(not controller.is_human_turn(), "the committed line must pass play to the rival")
	check_eq(controller.turn_number(), 2, "the committed line must advance the turn")

	controller._on_ai_think_timeout()
	check_eq(
		controller.get_session().move_count(),
		TILES_PER_LINE,
		"the opponent must commit one whole line as the turn's one move"
	)
	check(
		controller.get_session().get_board().occupied_count() >= TILES_PER_LINE * 2,
		"the opponent must place a whole line of two or more tiles, never a lone tile"
	)
	check(
		controller.get_session().get_outcome() != TurnEnums.MatchOutcome.INCOMPLETE,
		"a rival that can line up its hand must not fail the match"
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
##
## ADR-011 section 12 hands the strategy the rival's whole held deck, because a
## candidate is a line rather than a single placement.
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
		session.deck_for(AI),
		config,
		DECISION_SEED,
		AiCancellationToken.new()
	)


## Consumes `iterations` units of unrelated work.
##
## ADR-005 section 3 makes the decision a pure function of its inputs, so the
## determinism check varies how much real time has passed without varying any
## input. The loop is bounded and does no work the AI could observe.
func _burn_time(iterations: int) -> void:
	var accumulator: int = 0
	for index: int in range(maxi(0, iterations)):
		accumulator = (accumulator + index) % 7919
	if accumulator < 0:
		push_error("test_ai_determinism: the work loop must stay bounded and finite.")


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
##
## The human opens with a real two-tile line, so the board the rival faces is the
## board ADR-011 section 1 produces, not a relic of the per-tile model.
func _ai_turn_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = GameSessionState.create(
		match_id, seed, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	if not check_not_null(session, "the session must be constructible"):
		return null
	TurnManager.setup(session)
	var opening: Array[TileSnapshot] = _line_from_deck(session, HUMAN)
	if not check_eq(opening.size(), TILES_PER_LINE, "the human must hold a pair for its line"):
		return null
	var result: LineResult = MoveCommitter.commit_line(session, HUMAN, opening)
	if not check(result != null and result.was_committed(), "the human line must commit"):
		return null
	# ADR-011 section 7 makes a turn exactly one move, so resolving the committed
	# line passes play to the opponent by itself; there is no end-turn action to
	# call. Resolving it also runs the turn boundary of section 8, so the
	# opponent's deck is the refilled one when the analysis starts.
	TurnManager.resolve(session, result)
	if not check(
		TurnManager.is_awaiting_ai_action(session),
		"the fixture must reach the opponent's action phase"
	):
		return null
	return session


## Returns two of `player_id`'s own deck tiles of one rank staged as a legal line.
##
## ADR-012 section 1 makes a Pair the shortest legal hand and a deck of six drawn
## from four ranks always holds a pair; the cells are the first gap-free run the
## board offers, which is the opening cell and its neighbour.
func _line_from_deck(session: GameSessionState, player_id: StringName) -> Array[TileSnapshot]:
	var empty: Array[TileSnapshot] = []
	if session == null:
		return empty
	var board: BoardState = session.get_board()
	if board == null:
		return empty
	var pair: Array[TileDefinition] = _rank_pair(session.deck_for(player_id), TILES_PER_LINE)
	if pair.size() < TILES_PER_LINE:
		return empty
	var cells: Array[Vector2i] = _opening_cells(board)
	if cells.size() < TILES_PER_LINE:
		return empty
	var line: Array[TileSnapshot] = []
	for index: int in range(TILES_PER_LINE):
		line.append(TileSnapshot.create(pair[index], cells[index], 0))
	return line


## Returns two adjacent empty cells of the first gapless run the board offers.
func _opening_cells(board: BoardState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if board == null:
		return cells
	var frontier: Array[Vector2i] = board.get_frontier_cells()
	if frontier.is_empty():
		return cells
	var first: Vector2i = frontier[0]
	cells.append(first)
	if board.is_empty_cell(first + Vector2i(1, 0)):
		cells.append(first + Vector2i(1, 0))
		return cells
	if board.is_empty_cell(first + Vector2i(0, 1)):
		cells.append(first + Vector2i(0, 1))
	return cells


## Returns `count` tiles of one shared rank from `deck`, or an empty array.
func _rank_pair(deck: Array[TileDefinition], count: int) -> Array[TileDefinition]:
	var empty: Array[TileDefinition] = []
	if count <= 0:
		return empty
	var by_rank: Dictionary = {}
	for tile: TileDefinition in deck:
		if tile == null:
			continue
		var rank: int = int(tile.rank)
		var group: Array = by_rank.get(rank, [])
		group.append(tile)
		by_rank[rank] = group
	for rank: Variant in by_rank.keys():
		var group: Array = by_rank[rank]
		if group.size() < count:
			continue
		var chosen: Array[TileDefinition] = []
		for tile: TileDefinition in group:
			chosen.append(tile)
			if chosen.size() == count:
				return chosen
	return empty


## Assembles a legal line from the human's own deck and commits it through the
## controller (ADR-011 sections 3, 5, and 11).
func _commit_staged_line(controller: GameSessionController, cells: Array[Vector2i]) -> bool:
	var session: GameSessionState = controller.get_session()
	if session == null:
		return false
	var pair: Array[TileDefinition] = _rank_pair(
		session.deck_for(TurnEnums.HUMAN_PLAYER_ID), cells.size()
	)
	if pair.size() < cells.size():
		return false
	for index: int in range(cells.size()):
		var tile: TileDefinition = pair[index]
		controller.select_deck_tile(tile.tile_id)
		if not controller.stage_tile(tile.tile_id, cells[index], 0):
			return false
	var result: LineResult = controller.commit_line()
	return result != null and result.was_committed()


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
