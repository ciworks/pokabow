extends TestCase

## Milestone 5 scene smoke tests (ADR-008 sections 4, 5, 7, 8, 9, and 13).
##
## ADR-008 section 13 puts scene smoke tests at level 3 and asks for few,
## focused tests covering signal wiring, responsive layout, and command routing.
## Rule correctness is already covered by the domain suites, so nothing here
## re-tests a rule; these check that the UI submits intents, renders
## authoritative state, is gated by the turn phase, and never computes a rule
## result itself.
##
## Controllers are started with an explicit match id and seed so every run is
## reproducible (ADR-004 section 9).
##
## The opponent moves on a SceneTreeTimer, and these tests never yield to the
## engine's process step, so the turn always remains with the opponent after a
## human commit. That makes the turn-phase assertions deterministic.

const GAME_SCREEN_SCENE: String = "res://scenes/game/game_screen.tscn"
const APP_ROOT_SCENE: String = "res://scenes/app/app_root.tscn"

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID

const TEST_MATCH_ID: StringName = &"ui-test"
const TEST_SEED: int = 4242


func test_game_screen_provides_the_adr_008_hierarchy() -> void:
	var screen: Node = _instantiate(GAME_SCREEN_SCENE)
	if not check_not_null(screen, "the game screen scene must instantiate"):
		return

	var expected: Dictionary = {
		"Root/Column/Body/BoardViewport/BoardView": "Control",
		"Root/Column/Body/BoardViewport/BoardView/TileLayer": "Control",
		"Root/Column/Body/BoardViewport/BoardView/PreviewLayer": "Control",
		"Root/Column/Body/BoardViewport/BoardView/HighlightLayer": "Control",
		"Root/Column/Body/BoardViewport/BoardView/EffectsLayer": "Control",
		"Root/Column/Hud/HumanScorePanel": "PanelContainer",
		"Root/Column/Hud/AiScorePanel": "PanelContainer",
		"Root/Column/Body/SidePanel/ActiveTilePanel": "PanelContainer",
	}
	for path: String in expected.keys():
		var node: Node = screen.get_node_or_null(path)
		if not check_not_null(node, "the hierarchy must provide %s" % path):
			continue
		check_eq(
			node.get_class(), expected[path], "%s must be a %s" % [path, expected[path]]
		)

	# Every unique-name reference the screen script uses at runtime must resolve,
	# otherwise the screen would fail on attach rather than on load.
	var unique_names: PackedStringArray = [
		"BoardView",
		"BoardInputController",
		"ActiveTileView",
		"RotateButton",
		"ConfirmButton",
		"CancelButton",
		"RestartButton",
		"HumanScoreValue",
		"AiScoreValue",
		"TurnIndicator",
		"RemainingTilesLabel",
		"StatusLabel",
		"FloatingScores",
		"SummaryOverlay",
		"SummaryTitle",
		"SummaryBody",
	]
	for unique_name: String in unique_names:
		check_not_null(
			screen.find_child(unique_name, true, false),
			"the screen must expose a '%s' node" % unique_name
		)

	screen.free()


func test_app_root_replaces_the_splash_with_a_playable_match() -> void:
	var root: Node = _instantiate(APP_ROOT_SCENE)
	if not check_not_null(root, "the app root scene must instantiate"):
		return
	if not _host(root):
		check(false, "the scene tree must be available to host the app root")
		root.free()
		return

	# The harness does not flush deferred `_ready` callbacks between tests, so the
	# boot is driven explicitly here. In the running game `_ready` calls the same
	# function; this only removes the timing dependency from the test.
	if root.get("game_screen") == null:
		root.call("boot_game_screen")

	# The splash is authored into the scene for the Milestone 0 bootstrap; the
	# composition root detaches it once a match can be hosted (ADR-008 section 4).
	check(
		root.get_node_or_null("SceneHost/SplashScreen") == null,
		"the splash must be replaced once the match boots"
	)
	check_not_null(
		root.get_node_or_null("SceneHost/GameScreen"),
		"the game screen must be hosted after boot"
	)
	check_not_null(root.get("game_screen"), "the app root must expose the active screen")
	check_not_null(
		root.get("session_controller"), "the app root must own the application match service"
	)

	var screen: GameScreen = root.get("game_screen")
	if screen != null:
		check(screen.controller != null, "the hosted screen must receive its controller")
		var session: GameSessionState = screen.controller.get_session()
		if check_not_null(session, "the booted match must have a session"):
			check(
				not session.get_board().has_any_tile(),
				"a booted match must start on an empty board"
			)
			check(
				screen.controller.is_human_turn(),
				"the human must hold the first action phase"
			)

	_release(root)


func test_human_input_is_gated_to_the_human_action_phase() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller

	check(controller.is_human_turn(), "the human opens the match")
	check(screen.board_input.enabled, "the board accepts input on the human's turn")
	check(not screen.confirm_button.disabled, "Confirm is available on the human's turn")
	check(not screen.rotate_button.disabled, "Rotate is available on the human's turn")

	# Commit a legal opening move, which hands the turn to the opponent.
	screen._on_cell_tapped(_first_frontier(controller.get_board()))
	screen._on_confirm_pressed()

	check(not controller.is_human_turn(), "the committed move passes the turn")
	check(not screen.board_input.enabled, "the board must not accept input off-turn")
	check(screen.confirm_button.disabled, "Confirm must be disabled off-turn")
	check(screen.cancel_button.disabled, "Cancel must be disabled off-turn")
	check(screen.rotate_button.disabled, "Rotate must be disabled off-turn")
	_release(screen)


func test_the_ui_previews_through_the_rules_and_commits_on_confirm() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var tile: TileDefinition = controller.human_tile()
	if not check_not_null(tile, "the human must hold a tile to place"):
		_release(screen)
		return

	# An empty board only accepts the four central cells, so (0,0) is a refusal.
	screen._on_cell_tapped(Vector2i(0, 0))
	check(controller.has_pending(), "a tap must produce a preview even when it is illegal")
	check(not controller.is_pending_valid(), "the UI must not accept an illegal placement")
	check(
		not controller.pending_reason().is_empty(),
		"an illegal preview must explain itself rather than fail silently"
	)

	# A legal opening cell, cross-checked against the rule service itself.
	var cell: Vector2i = _first_frontier(controller.get_board())
	var request: PlacementRequest = PlacementRequest.create(HUMAN, tile.tile_id, cell, 0)
	var expected: PlacementResult = PlacementValidator.validate(
		controller.get_board(), request, tile, true
	)
	screen._on_cell_tapped(cell)
	check(controller.has_pending(), "tapping a legal cell must produce a preview")
	check_eq(
		controller.is_pending_valid(),
		expected.accepted,
		"the preview verdict must come from the placement rules, not the UI"
	)

	# Rotation is a command, not a board mutation (ADR-006 section 5).
	var revision_before: int = controller.get_board().get_revision()
	screen._on_rotate_pressed()
	check_eq(
		controller.get_board().get_revision(),
		revision_before,
		"rotating a preview must not touch the board"
	)
	check_eq(controller.pending_rotation(), 1, "the rotate command advances the pending rotation")

	# Confirm commits through the same rule path and advances the turn.
	var moves_before: int = controller.get_session().move_count()
	screen._on_confirm_pressed()
	check_eq(
		controller.get_session().move_count(),
		moves_before + 1,
		"Confirm must commit exactly one move"
	)
	check(
		controller.get_board().is_occupied(cell),
		"the confirmed tile must reach the board"
	)
	check(
		screen.board_view.get_last_committed_cell() == cell,
		"the board must mark where the tile landed"
	)
	_release(screen)


func test_a_cancel_discards_the_preview_without_consuming_the_turn() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var revision_before: int = controller.get_board().get_revision()

	screen._on_cell_tapped(_first_frontier(controller.get_board()))
	check(controller.has_pending(), "the tap must have produced a preview")
	screen._on_cancel_pressed()

	check(not controller.has_pending(), "Cancel must discard the preview")
	check_eq(
		controller.get_board().get_revision(),
		revision_before,
		"Cancel must leave the board untouched"
	)
	check(
		controller.get_session().move_count() == 0,
		"Cancel must not record a move"
	)
	check(controller.is_human_turn(), "Cancel must not consume the turn")
	check(
		controller.human_tile() != null,
		"Cancel must keep the active tile in hand"
	)
	_release(screen)


func test_each_committed_event_plays_one_popup_in_order() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return

	var events: Array[ScoreEvent] = [
		_make_event(
			&"score:move:m1:poker:hand:H:5:5",
			ScoringEnums.ScoreCategory.POKER_HAND,
			4,
			"TWO_PAIR"
		),
		_make_event(
			&"score:move:m1:edge:edge:5,5-6,5", ScoringEnums.ScoreCategory.EDGE_MATCH, 1, ""
		),
		_make_event(
			&"score:move:m1:cluster:blue:1", ScoringEnums.ScoreCategory.EDGE_CLUSTER, 3, ""
		),
	]
	screen._on_score_awarded(events, Vector2i(5, 5))

	check_eq(
		screen.floating_scores.active_count(),
		3,
		"one committed event must produce exactly one popup"
	)
	var first: Label = screen.floating_scores.get_child(0) as Label
	if check_not_null(first, "a popup must be a label"):
		check(
			first.text.begins_with("+4"),
			"popups must follow the committed event order (got '%s')" % first.text
		)
	_release(screen)


func test_the_summary_panel_shows_the_final_breakdown_and_restarts() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var session: GameSessionState = controller.get_session()
	if not check_not_null(session, "the match must have a session"):
		_release(screen)
		return

	# Finish the match directly rather than playing 144 moves: the lifecycle
	# suite already covers reaching an end condition by play.
	session.finish(TurnEnums.MatchOutcome.DRAW, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))

	check(screen.summary_overlay.visible, "the summary must appear when the match ends")
	check_eq(screen.summary_title.text, "It's a draw", "a draw must be reported as one")
	check(
		screen.summary_body.text.contains("poker"),
		"the summary must break the score down by category"
	)
	check(not screen.board_input.enabled, "a finished match must stop accepting input")

	# Restarting must clear the summary and start a fresh board.
	screen._on_restart_pressed()
	check(not screen.summary_overlay.visible, "a new match must hide the summary")
	var restarted: GameSessionState = controller.get_session()
	if check_not_null(restarted, "restarting must produce a session"):
		check(
			not restarted.get_board().has_any_tile(),
			"a new match must start on an empty board"
		)
		check(
			restarted.get_board().get_revision() == 0,
			"a new match must start at revision zero"
		)
	_release(screen)


## Hosts a game screen with a started match and returns it, or null on failure.
func _host_screen() -> GameScreen:
	var screen: GameScreen = _instantiate(GAME_SCREEN_SCENE) as GameScreen
	if not check_not_null(screen, "the game screen must instantiate as a GameScreen"):
		return null
	if not _host(screen):
		check(false, "the scene tree must be available to host the game screen")
		screen.free()
		return null

	var controller: GameSessionController = GameSessionController.create()
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.start_new_match(TEST_MATCH_ID, TEST_SEED)
	return screen


## Returns the first legal frontier cell in row-major order.
func _first_frontier(board: BoardState) -> Vector2i:
	var frontier: Array[Vector2i] = board.get_frontier_cells()
	if frontier.is_empty():
		return BoardMetrics.NO_CELL
	return frontier[0]


## Builds a committed score event for popup tests.
func _make_event(
	event_id: StringName, category: int, points: int, hand_name: String
) -> ScoreEvent:
	var evidence: Dictionary = {}
	if not hand_name.is_empty():
		evidence["category"] = hand_name
	return ScoreEvent.create(
		event_id, &"move:m1", HUMAN, category, points, [Vector2i(5, 5)], evidence, 1, "scoring:1"
	)


## Loads and instantiates a scene, or returns null when it cannot be loaded.
func _instantiate(scene_path: String) -> Node:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()


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
