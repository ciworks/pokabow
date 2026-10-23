extends TestCase

## Milestone 5 scene smoke tests (ADR-008 sections 4, 5, 7, 8, 9, and 13),
## retargeted to the line-staging screen of ADR-011 sections 1, 3, 5, 6, 7, and
## 11.
##
## ADR-008 section 13 puts scene smoke tests at level 3 and asks for few,
## focused tests covering signal wiring, responsive layout, and command routing.
## Rule correctness is already covered by the domain suites, so nothing here
## re-tests a rule; these check that the UI submits intents, renders
## authoritative state, is gated by the turn phase, and never computes a rule
## result itself.
##
## ADR-011 section 11 replaces per-tile placement with a staging state. The flow
## these tests fix is: a deck tap names the tile the next board tap stages, a
## second tap on that same tile turns it a quarter-turn and the deck row draws it
## turned, board taps build the pending line and it is drawn whole with one
## validity verdict, a tap on a staged tile turns that staged tile instead of
## taking it out of the line, dragging a staged tile off the board is what takes it
## out, repeated taps rotate selected and staged tiles without writing to the board,
## Cancel returns every staged tile to the deck, and one Confirm commits the whole
## line as one move. Swapping (section 6) returns deck tiles for equal
## replacements and consumes the whole turn.
##
## ADR-011 section 7 makes a turn exactly one move, which removed the explicit
## End Turn action: the hierarchy test asserts the control is gone rather than
## wired, and the gating test asserts a committed line is what freezes input.
##
## Controllers are started with an explicit match id and seed so every run is
## reproducible (ADR-004 section 9).
##
## The opponent moves on a SceneTreeTimer, and these tests never yield to the
## engine's process step, so the turn always remains with the opponent after a
## human commit. That makes the turn-phase assertions deterministic.

const GAME_SCREEN_SCENE: String = "res://scenes/game/game_screen.tscn"
const APP_ROOT_SCENE: String = "res://scenes/app/app_root.tscn"
const TABLETOP_THEME: Script = preload("res://scripts/presentation/modern_tabletop_theme.gd")

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID

const TEST_MATCH_ID: StringName = &"ui-test"
const TEST_SEED: int = 4242

## Tiles a legal move places at minimum (ADR-011 sections 1 and 4).
const TILES_PER_LINE: int = 2

## The Phase 1 deck size every deck is filled to (ADR-010 section 1).
const DECK_SIZE: int = DeckRules.DEFAULT_DECK_SIZE

## Tiles the pot still holds once both decks are dealt (ADR-010 section 2).
##
## The screen drives the real controller, which loads the real generation rules,
## so the bag holds 52 tiles (ADR-004 section 1, amended 2026-09-23) and the deal
## leaves 40.
const POT_AFTER_SETUP: int = TileGenerationRules.DEFAULT_BAG_SIZE - DECK_SIZE * 2

## Gap that must be refused as a hole in a line (ADR-011 section 1).
const LINE_GAP: int = PlacementEnums.PlacementRejection.LINE_GAP

## Diagonal continuation that must be refused as a mixed orientation.
const MIXED_ORIENTATION: int = PlacementEnums.PlacementRejection.MIXED_ORIENTATION


func test_a_human_with_no_valid_move_sees_a_board_notice_and_loses_the_turn() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var session: GameSessionState = controller.get_session()
	var board: BoardState = controller.get_board()
	# A queen cannot extend this full house or pair with either of its ranks.
	var tile: TileDefinition = TileDefinition.create(
		&"test-no-move-queen", TileEnums.TileRank.QUEEN, TileEnums.FaceColor.RED,
		[TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.BLUE]
	)
	var snapshots: Array[TileSnapshot] = []
	for index: int in range(5):
		var filler: TileDefinition = TileDefinition.create(
			StringName("test-no-move-filler-%d" % index),
			TileEnums.TileRank.ACE if index < 3 else TileEnums.TileRank.KING,
			TileEnums.FaceColor.RED,
			[TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.BLUE]
		)
		snapshots.append(TileSnapshot.create(filler, Vector2i(BoardEnums.OPENING_MIN + index, BoardEnums.OPENING_MIN), 0))
	if not check(LineValidator.validate(board, snapshots).accepted, "fixture line must be legal"):
		_release(screen)
		return
	board.commit_tiles(snapshots)
	# Automatic passing applies only when the pot can no longer fund a swap.
	while not session.get_tile_source().is_exhausted():
		session.get_tile_source().draw()
	var turn_state: TurnState = session.get_turn_state()
	turn_state.active_player_id = HUMAN
	turn_state.phase = TurnEnums.MatchPhase.AWAIT_ACTION
	var human_deck: Array[TileDefinition] = session._deck(HUMAN)
	human_deck.clear()
	human_deck.append(tile)
	var notices: Array[String] = []
	controller.notice.connect(func(message: String) -> void: notices.append(message))
	controller._after_state_change()
	check(not controller.is_human_turn(), "a hand with no legal move must pass the turn")
	check_eq(turn_state.active_player_id, TurnEnums.AI_PLAYER_ID, "play passes to the opponent")
	check_eq(turn_state.turn_number, 2, "the skipped turn advances the turn number")
	check_eq(notices.back() if not notices.is_empty() else "", GameSessionController.NO_VALID_MOVE_NOTICE, "the exact no-move notice is emitted")
	check_eq(screen.get_node("%BoardMessageLabel").text, GameSessionController.NO_VALID_MOVE_NOTICE, "the no-move notice appears below the board")
	check_eq(screen.turn_indicator.text, "Rival's turn", "the command drawer retains current turn status")
	_release(screen)


## One scoring move must reveal the tiles in its poker hand, not merely announce
## a number (AGENTS.md section 8, Milestone 8: score feedback).
##
## The cells and the colour arrive on the events, so the board marks what really
## scored rather than re-deriving it from the board - which is what keeps the
## reveal and the ledger from ever disagreeing (ADR-008 section 4).
func test_a_scoring_move_reveals_its_edges_and_clusters() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return

	# One matching boundary, one poker hand, and one paying cluster, in the order
	# ADR-007 section 7 records them.
	var events: Array[ScoreEvent] = [
		ScoreEvent.create(
			&"score:move:m1:edge:edge:5,5-6,5",
			&"move:m1",
			&"human",
			ScoringEnums.ScoreCategory.EDGE_MATCH,
			1,
			[Vector2i(5, 5), Vector2i(6, 5)],
			{"boundary_id": "edge:5,5-6,5", "color": "BLUE"}
		),
		ScoreEvent.create(
			&"score:move:m1:poker:hand:H:5:5",
			&"move:m1",
			&"human",
			ScoringEnums.ScoreCategory.POKER_HAND,
			10,
			[
				Vector2i(5, 5),
				Vector2i(6, 5),
				Vector2i(7, 5),
				Vector2i(8, 5),
				Vector2i(9, 5),
			],
			{"hand_id": "hand:H:5:5", "category": "FULL_HOUSE"}
		),
		ScoreEvent.create(
			&"score:move:m1:cluster:blue:1",
			&"move:m1",
			&"human",
			ScoringEnums.ScoreCategory.EDGE_CLUSTER,
			3,
			[Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)],
			{"color": "BLUE", "component_key": "blue:5,5|6,5|7,5"}
		),
	]
	screen._on_score_awarded(events, Vector2i(5, 5))

	if not check_not_null(screen.board_view, "the screen must expose its board view"):
		_release(screen)
		return
	if not check_not_null(
		screen.board_view.reveal_layer,
		"the board must have a reveal layer to draw the marks on"
	):
		_release(screen)
		return

	check(
		screen.board_view.reveal_layer.has_marks(),
		"a move that scored a hand, an edge match, and a cluster must reveal them"
	)
	check_eq(
		screen.board_view.reveal_layer.group_count(),
		1,
		"the poker hand gets one overlay group; an edge cluster does not outline tiles"
	)
	check(
		screen.board_view.reveal_layer.ripple_duration() > 0.0,
		"the scored hand shows a tactile ripple before online Gems travel"
	)
	check_eq(
		screen.board_view.reveal_layer.wave_cells().size(),
		5,
		"the poker hand's five tiles are the ones that bounce"
	)
	screen.board_view.reveal_layer._process(4.0)
	check(
		screen.board_view.reveal_layer.has_marks(),
		"the hand trace remains after the ripple finishes"
	)
	check_eq(
		screen.board_view.reveal_layer.modulate.a,
		1.0,
		"the hand trace starts fully visible"
	)
	var reveal: ScoreRevealLayer = screen.board_view.reveal_layer
	if reveal._fade != null and reveal._fade.is_valid():
		reveal._fade.custom_step(ScoreRevealLayer.FADE * 0.5)
	check(reveal.has_marks(), "the hand trace remains during its fade")
	check(reveal.modulate.a > 0.0, "the hand trace is still visible halfway through the fade")
	if reveal._fade != null and reveal._fade.is_valid():
		reveal._fade.custom_step(ScoreRevealLayer.FADE)
	check(not reveal.has_marks(), "the hand trace clears when its two-second fade finishes")
	screen._on_score_awarded([] as Array, Vector2i(5, 5))
	check(
		not screen.board_view.reveal_layer.has_marks(),
		"a move with no hand leaves no hand trace"
	)
	_release(screen)


func test_game_screen_provides_the_adr_008_hierarchy() -> void:
	var screen: Node = _instantiate(GAME_SCREEN_SCENE)
	if not check_not_null(screen, "the game screen scene must instantiate"):
		return

	var expected: Dictionary = {
		"Root/Column/Body/BoardViewport/BoardView": "Control",
		"Root/Column/Body/BoardViewport/BoardView/BoardCanvas/TileLayer": "Control",
		"Root/Column/Body/BoardViewport/BoardView/BoardCanvas/PreviewLayer": "Control",
		"Root/Column/Body/BoardViewport/BoardView/BoardCanvas/HighlightLayer": "Control",
		"Root/Column/Body/BoardViewport/BoardView/BoardCanvas/ScoreRevealLayer": "Control",
		"Root/Column/Body/BoardViewport/BoardView/BoardCanvas/EffectsLayer": "Control",
		"Root/Column/Hud/HumanScorePanel": "PanelContainer",
		"Root/Column/Hud/AiScorePanel": "PanelContainer",
		"Root/Column/Hud/PotPanel": "PanelContainer",
		"Root/Column/TurnInfoPanel": "PanelContainer",
		"Root/Column/TurnInfoPanel/TurnInfoRow": "HBoxContainer",
		"Root/Column/TurnInfoPanel/TurnInfoRow/TurnStatusLabel": "Label",
		"Root/Column/TurnInfoPanel/TurnInfoRow/OpponentRack": "Control",
		"Root/Column/TurnInfoPanel/TurnInfoRow/TurnClockLabel": "Label",
		"Root/Column/DeckBar/DeckPanel/RackColumn/DeckRow/DeckView": "Control",
		"BottomNavigation": "PanelContainer",
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
		"DeckView",
		"BottomNavigation",
		"SwapConfirmButton",
		"SwapCancelButton",
		"RestartButton",
		"HumanScoreValue",
		"AiScoreValue",
		"TurnIndicator",
		"TurnInfoRow",
		"TurnInfoPanel",
		"TurnStatusLabel",
		"TurnClockLabel",
		"AvailableTilesLabel",
		"TilePileView",
		"DealLayer",
		"StatusLabel",
		"FloatingScores",
		"ScoreRevealLayer",
		"SummaryOverlay",
		"SummaryTitle",
		"SummaryBody",
	]
	for unique_name: String in unique_names:
		check_not_null(
			screen.find_child(unique_name, true, false),
			"the screen must expose a '%s' node" % unique_name
		)

	# ADR-011 section 7 supersedes ADR-010 section 3's explicit end-turn action, so
	# the control that used to close a turn must not exist at all: a leftover
	# button would be a second way to end a turn that no rule authorises.
	check(
		screen.find_child("EndTurnButton", true, false) == null,
		"ADR-011 section 7 removes the End Turn control from the screen"
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
		(root.get_node("OverlayLayer/TransitionOverlay") as CanvasItem).show()
		(root.get_node("OverlayLayer/ErrorDialog") as CanvasItem).show()
		root.call("boot_game_screen")
		check(not (root.get_node("OverlayLayer/TransitionOverlay") as CanvasItem).visible,
			"game boot must clear a stale full-screen transition cover")
		check(not (root.get_node("OverlayLayer/ErrorDialog") as CanvasItem).visible,
			"game boot must clear a stale shell error cover")

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
			check(
				not screen.controller.has_pending(),
				"a booted match must start with no staged line (ADR-011 section 11)"
			)

	_release(root)


## Regression: leaving a match from the "Back to hub" control must not free the
## screen while the press that asked for it is still unwinding.
##
## The shell used to free the screen outright from inside the control's own signal
## emission, which fails with "Attempted to free a locked object" and leaves the
## screen alive but hosted nowhere. The screen is detached at once and released at
## the end of the frame instead, so the host is clear in this call and the nodes go
## once the emission has unwound.
func test_back_to_hub_releases_the_screen_without_freeing_a_locked_object() -> void:
	var root: Node = _instantiate(APP_ROOT_SCENE)
	if not check_not_null(root, "the app root scene must instantiate"):
		return
	if not _host(root):
		check(false, "the scene tree must be available to host the app root")
		root.free()
		return

	# Booted explicitly, as in the splash test above: the splash hold is a timer
	# and the harness does not process frames.
	root.call("boot_game_screen")
	var screen: GameScreen = root.get("game_screen") as GameScreen
	if not check_not_null(screen, "the booted match must be hosted"):
		_release(root)
		return
	var hub_button: Button = screen.find_child("MenuHubButton", true, false) as Button
	if not check_not_null(hub_button, "the drawer must offer the Back to hub control"):
		_release(root)
		return

	# Emitted rather than `pressed.emit` on the screen, because the press handler
	# is what is still on the stack when the shell reacts: that is the situation
	# that locked the screen and made the free fail.
	hub_button.pressed.emit()

	check_eq(root.get("game_screen"), null, "the shell must forget the released screen")
	check(root.get("session_controller") == null, "the shell must release the match service")
	check(not screen.is_inside_tree(), "the released screen must leave the scene host")
	check(
		is_instance_valid(screen) and screen.is_queued_for_deletion(),
		"the released screen must be queued for release, not freed while the press unwound"
	)
	check_not_null(root.get("hub_screen"), "the hub must be back on screen after the match")

	_release(root)


func test_player_panel_always_shows_you() -> void:
	var root: AppRoot = _instantiate(APP_ROOT_SCENE) as AppRoot
	if not check_not_null(root, "the app root scene must instantiate"):
		return
	root.user_state = {"token": "api-token", "user": {"displayName": "Player_123456789"}}
	if not _host(root):
		check(false, "the scene tree must host the app root")
		root.free()
		return
	root.boot_game_screen()
	var title: Label = root.game_screen.get_node_or_null("%HumanScoreTitle") as Label
	if check_not_null(title, "the player score panel must have a title"):
		check_eq(title.text, "You", "the panel must show You even for an authenticated player")
		root.game_screen.set_player_display_name("")
		check_eq(title.text, "You", "the panel must still show You when no name is available")
	_release(root)


func test_human_input_is_gated_to_the_human_action_phase() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller

	check(controller.is_human_turn(), "the human opens the match")
	check(screen.board_input.enabled, "the board accepts input on the human's turn")
	check(screen.bottom_navigation.buttons[&"Play"].disabled, "Play waits for a staged hand")
	check(not screen.bottom_navigation.buttons[&"Pot"].disabled, "Pot is available before staging")
	check(not screen.bottom_navigation.buttons[&"Swap"].disabled, "Swap is available on the human's turn")
	check(not screen.deck_view.is_locked(), "the deck row is selectable on the human's turn")

	# ADR-011 sections 5 and 7: the committed line is atomic and ends the turn, so
	# the commit itself is what freezes the human's input. There is no end-turn
	# action left to test, only the commit that closes the move.
	var result: LineResult = _stage_and_commit_opening_line(screen)
	if not check(
		result != null and result.was_committed(),
		"the opening line must commit: %s" % (result.describe() if result != null else "no result")
	):
		_release(screen)
		return

	check_eq(controller.get_session().move_count(), 1, "the line must be recorded as one move")
	check(not controller.is_human_turn(), "the committed line hands play to the rival")
	check(not screen.board_input.enabled, "the board must not accept input off-turn")
	check(screen.bottom_navigation.buttons[&"Play"].disabled, "Play must be disabled off-turn")
	check(not screen.bottom_navigation.buttons[&"Pot"].disabled, "Pot remains available off-turn")
	check(screen.bottom_navigation.buttons[&"Swap"].disabled, "Swap must be disabled off-turn")
	check(screen.deck_view.is_locked(), "the deck row must not be selectable off-turn")
	check(
		screen.deck_view.deck_size() == DECK_SIZE,
		"the player's refilled tiles are still shown after the commit"
	)
	_release(screen)


func test_a_fresh_deck_draws_no_tile_as_selected() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var deck: Array[TileDefinition] = controller.human_deck()
	if not check(deck.size() > 0, "the human must hold a deck to draw"):
		_release(screen)
		return

	# A dealt hand is the player's own to choose from. Nothing has been picked
	# yet, so no tile is armed and the row draws no tile as selected: the first
	# tap is always a selection the player made rather than one that was made for
	# them.
	check_eq(
		String(controller.selected_deck_tile_id()),
		"",
		"a freshly dealt deck must have nothing armed"
	)
	check_eq(
		String(screen.deck_view.selected_tile_id()),
		"",
		"a freshly dealt deck must draw no tile as selected"
	)
	check_eq(
		controller.human_tile(),
		deck[0],
		"the controller keeps its documented first-tile fallback without selecting it in the view"
	)

	# The first tap is then a real selection, and it works from that empty state.
	_tap_deck_fully(screen, 0)
	check_eq(
		String(controller.selected_deck_tile_id()),
		String(deck[0].tile_id),
		"the first tap on a freshly dealt deck must select the tile it names"
	)
	_release(screen)


func test_a_deck_tap_names_the_tile_the_next_staging_command_places() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var deck: Array[TileDefinition] = controller.human_deck()
	if not check(deck.size() >= TILES_PER_LINE, "the human must hold a deck to stage from"):
		_release(screen)
		return

	# ADR-010 section 12 keeps choosing a deck tile as the player's own choice, so
	# the tap names which held tile the next staging command takes. It must not
	# place, commit, or touch the board.
	var revision_before: int = controller.get_board().get_revision()
	var chosen: TileDefinition = deck[deck.size() - 1]
	_tap_deck(screen, deck.size() - 1)

	check_eq(
		String(controller.selected_deck_tile_id()),
		String(chosen.tile_id),
		"the tapped deck tile is the tile the next board tap stages"
	)
	check_eq(
		String(controller.human_tile().tile_id),
		String(chosen.tile_id),
		"the tapped deck tile is the tile the staging commands place"
	)
	check(
		not screen.deck_view.is_marked(chosen.tile_id),
		"a staging tap must not mark a tile for the swap (ADR-011 section 6)"
	)
	check_eq(controller.staged_count(), 0, "selecting a deck tile stages nothing by itself")
	check_eq(
		controller.get_board().get_revision(),
		revision_before,
		"selecting a deck tile must not touch the board"
	)
	check(controller.is_human_turn(), "selecting a deck tile must not consume the turn")
	_release(screen)


func test_a_second_tap_on_the_selected_deck_tile_turns_it_in_the_row() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var deck: Array[TileDefinition] = controller.human_deck()
	if not check(deck.size() >= TILES_PER_LINE, "the human must hold a deck to select from"):
		_release(screen)
		return

	# Aimed at a tile the row is not already drawing as selected, so the first tap
	# is unambiguously the existing selection gesture.
	var chosen: int = 0
	if String(screen.deck_view.selected_tile_id()) == String(deck[0].tile_id):
		chosen = 1
	var revision_before: int = controller.get_board().get_revision()

	# The first tap is the existing selection, unchanged: it names the tile the
	# next board tap stages.
	_tap_deck_fully(screen, chosen)
	check_eq(
		String(controller.selected_deck_tile_id()),
		String(deck[chosen].tile_id),
		"the first tap must select the deck tile it names"
	)
	check_eq(
		controller.pending_rotation(), 0, "a fresh selection starts at the base orientation"
	)
	check_eq(
		screen.deck_view.selected_rotation(),
		0,
		"the row must draw a fresh selection at the base orientation"
	)

	# Every further tap on that same tile is one quarter-turn, and the rotation
	# the row draws is the rotation the controller reports, so a tap on the tile
	# visibly turns it in the row (AGENTS.md section 19).
	for expected: int in range(1, TileEnums.ROTATION_COUNT + 1):
		_tap_deck_fully(screen, chosen)
		check_eq(
			controller.pending_rotation(),
			expected % TileEnums.ROTATION_COUNT,
			"tapping the selected tile must turn it one quarter-turn per tap"
		)
		check_eq(
			screen.deck_view.selected_rotation(),
			controller.pending_rotation(),
			"the deck row must draw the selected tile at its current rotation"
		)
		check_eq(
			String(controller.selected_deck_tile_id()),
			String(deck[chosen].tile_id),
			"turning the selected tile must not re-select or clear it"
		)

	check_eq(controller.staged_count(), 0, "turning a deck tile must stage nothing")
	check_eq(
		controller.get_board().get_revision(),
		revision_before,
		"turning a deck tile must not touch the board"
	)
	check(controller.is_human_turn(), "turning a deck tile must not consume the turn")
	_release(screen)


func test_staging_builds_a_pending_line_without_writing_to_the_board() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if not check_eq(
		pair.size(), TILES_PER_LINE, "a deck of six from four ranks must hold a pair"
	):
		_release(screen)
		return
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if not check_eq(cells.size(), TILES_PER_LINE, "the opening board must offer a two-cell line"):
		_release(screen)
		return

	var revision_before: int = board.get_revision()

	# One staged tile is drawn on the board and is not yet a legal move
	# (ADR-011 sections 1 and 11).
	_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[0].tile_id))
	screen.stage_at(cells[0])

	check_eq(controller.staged_count(), 1, "the stage command must place one tile into the line")
	check(controller.has_pending(), "staging must leave a pending line")
	check_eq(controller.staged_cells()[0], cells[0], "the tile must be staged at the cell it was given")
	check_eq(
		screen.board_view.get_pending_count(),
		1,
		"the board must draw the staged tile as the pending line"
	)
	check(
		not controller.is_line_valid(),
		"ADR-011 section 1: one staged tile is not a legal whole move"
	)
	check(
		not screen.board_view.is_pending_valid(),
		"the board must draw the pending line as not yet legal"
	)
	check(
		not controller.line_reason().is_empty(),
		"an illegal pending line must explain itself rather than fail silently"
	)
	check_eq(
		screen.board_view.get_pending_reason(),
		controller.line_reason(),
		"the board must render the controller's verdict instead of deciding one"
	)
	check_eq(board.occupied_count(), 0, "staging must not write a tile to the board")
	check_eq(board.get_revision(), revision_before, "staging must not touch the board")
	check_eq(controller.get_session().move_count(), 0, "staging must not record a move")
	check(controller.is_human_turn(), "staging must not consume the turn")
	check_eq(
		screen.deck_view.deck_size(),
		DECK_SIZE - 1,
		"the staged tile must leave the visible deck before commit"
	)
	check_eq(
		screen.board_view.get_pending_line()[0].get_tile_id(),
		pair[0].tile_id,
		"the board preview must show the selected deck tile"
	)
	check_eq(controller.human_deck_count(), DECK_SIZE, "staging keeps match state unchanged")

	# The second tile of the pair completes a legal line, still without writing to
	# the board (ADR-011 sections 3 and 5).
	_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[1].tile_id))
	screen.stage_at(cells[1])

	check_eq(controller.staged_count(), TILES_PER_LINE, "the second tap must extend the line")
	check(
		controller.is_line_valid(),
		"a contiguous pair of one rank is a legal line: %s" % controller.line_reason()
	)
	check(screen.board_view.is_pending_valid(), "a legal pending line must be drawn as legal")
	check_eq(
		screen.board_view.get_pending_count(),
		TILES_PER_LINE,
		"the board must draw every tile of the pending line"
	)
	check_eq(
		screen.board_view.get_pending_line()[1].get_cell(),
		cells[1],
		"the board must draw the line at the staged cells"
	)
	check_eq(board.occupied_count(), 0, "a complete staged line still must not reach the board")
	check_eq(board.get_revision(), revision_before, "a staged line must not touch the board")
	check_eq(screen.deck_view.deck_size(), DECK_SIZE - TILES_PER_LINE, "both staged tiles leave the visible deck")
	check_eq(controller.get_session().move_count(), 0, "a staged line must not record a move")
	check(controller.is_human_turn(), "a staged line must not consume the turn")

	# Tapping a staged cell turns that tile instead of taking it out of the line: the
	# tile stays staged, on the same cell, at a new orientation, and the board is
	# still untouched (ADR-011 section 11). Taking a tile out is a drag off the
	# board, and moving it is a release elsewhere, both separate tests.
	#
	# The whole gesture is driven, because a board gesture is resolved on release:
	# pressed on the staged tile and released on the same cell is the turn
	# (AGENTS.md section 8).
	var staged_rotation: int = controller.staged_snapshots()[1].get_rotation()
	screen.board_input._handle_press(_board_point_for(screen, cells[1]), true)
	screen.board_input._handle_press(_board_point_for(screen, cells[1]), false)
	check_eq(
		controller.staged_count(),
		TILES_PER_LINE,
		"tapping a staged cell must keep its tile in the line"
	)
	check_eq(controller.staged_cells()[1], cells[1], "tapping a staged cell must not move its tile")
	check_eq(
		controller.staged_snapshots()[1].get_rotation(),
		(staged_rotation + 1) % TileEnums.ROTATION_COUNT,
		"tapping a staged cell must turn that tile one quarter-turn"
	)
	check_eq(
		screen.board_view.get_pending_line()[1].get_rotation(),
		controller.staged_snapshots()[1].get_rotation(),
		"the board must draw the staged tile at the orientation the tap gave it"
	)
	check_eq(
		screen.deck_view.deck_size(),
		DECK_SIZE - TILES_PER_LINE,
		"tapping a staged cell must not return its tile to the deck"
	)
	check_eq(board.get_revision(), revision_before, "turning a staged tile must not touch the board")
	check_eq(
		controller.get_session().move_count(), 0, "turning a staged tile must not record a move"
	)
	check(controller.is_human_turn(), "turning a staged tile must not consume the turn")
	_release(screen)


func test_a_press_on_a_staged_tile_released_off_the_board_takes_that_tile_out() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if not check_eq(
		pair.size(), TILES_PER_LINE, "a deck of six from four ranks must hold a pair"
	):
		_release(screen)
		return
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if not check_eq(cells.size(), TILES_PER_LINE, "the opening board must offer a two-cell line"):
		_release(screen)
		return

	_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[0].tile_id))
	screen.stage_at(cells[0])
	_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[1].tile_id))
	screen.stage_at(cells[1])
	if not check_eq(
		controller.staged_count(), TILES_PER_LINE, "the whole line must be staged before one tile leaves it"
	):
		_release(screen)
		return

	var revision_before: int = board.get_revision()
	var deck_before: PackedStringArray = _deck_ids(controller)
	var moves_before: int = controller.get_session().move_count()

	# The board gesture is driven through the input controller's own handler,
	# because the harness never runs a layout pass: a press on the staged tile and
	# then a release off the board, which is the gesture that takes it back out
	# (ADR-011 section 11). The press only picks the tile up; the release is what
	# decides, and a release off the board removes it without turning it.
	screen.board_input._handle_press(_board_point_for(screen, cells[1]), true)
	screen.board_input._handle_press(_off_board_point(screen), false)

	check_eq(
		controller.staged_count(),
		TILES_PER_LINE - 1,
		"a press on a staged tile released off the board must remove exactly that one tile"
	)
	check_eq(
		controller.staged_cells()[0],
		cells[0],
		"the removal must leave the rest of the line on the cells it held"
	)
	check(
		_index_of_tile(controller.unstaged_human_deck(), pair[1].tile_id) >= 0,
		"the removed tile must be selectable from the deck again"
	)
	check(
		_index_of_tile(controller.unstaged_human_deck(), pair[0].tile_id) < 0,
		"the removal must not return the tiles the line still holds"
	)
	check_eq(
		_deck_ids(controller),
		deck_before,
		"the removal must not change the tiles the player holds"
	)
	check_eq(board.get_revision(), revision_before, "the removal must not touch the board")
	check_eq(board.occupied_count(), 0, "the removal must not write to the board")
	check_eq(
		controller.get_session().move_count(), moves_before, "the removal must not record a move"
	)
	check(controller.is_human_turn(), "the removal must not consume the turn")
	_release(screen)


func test_a_board_tap_on_a_committed_cell_never_turns_a_committed_tile() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if not check_eq(
		pair.size(), TILES_PER_LINE, "a deck of six from four ranks must hold a pair"
	):
		_release(screen)
		return
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if not check_eq(cells.size(), TILES_PER_LINE, "the opening board must offer a two-cell line"):
		_release(screen)
		return

	_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[0].tile_id))
	screen.stage_at(cells[0])
	_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[1].tile_id))
	screen.stage_at(cells[1])
	screen._on_confirm_pressed()
	if not check_eq(
		board.occupied_count(),
		TILES_PER_LINE,
		"the opening line must be committed, or there is no committed tile to test"
	):
		_release(screen)
		return

	var revision_before: int = board.get_revision()

	# A committed cell holds no pending snapshot, so the rotate command has
	# nothing to turn there, and the commit has also passed the turn to the rival
	# (ADR-011 section 5: committed play is immutable; ADR-008 section 8: input is
	# gated to the human action phase).
	check_eq(
		controller.rotate_staged_at(cells[1]),
		-1,
		"a committed cell must have no staged tile to turn"
	)
	check(
		not screen.rotate_staged_at(cells[1]),
		"the screen must report no rotation for a committed cell"
	)

	# A tap there still stages nothing: a board tap no longer stages at all, and the
	# cell is occupied in any case (ADR-006 section 3). The committed tiles stay put.
	screen._on_cell_tapped(cells[1])
	check_eq(controller.staged_count(), 0, "a tap on a committed cell must stage nothing")
	check_eq(
		board.occupied_count(),
		TILES_PER_LINE,
		"a tap on a committed cell must leave the committed tiles where they are"
	)
	check_eq(
		board.get_revision(),
		revision_before,
		"a tap on a committed cell must not write to the board"
	)
	_release(screen)


func test_a_board_tap_on_an_empty_cell_stages_nothing() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()

	# The removal this pins: a tile reaches the board only by being dragged there
	# from the hand. A board tap used to stage whichever deck tile was selected,
	# which spent a tile the player had never chosen.
	if not check_eq(
		String(controller.selected_deck_tile_id()),
		"",
		"nothing may be armed before the player chooses a tile"
	):
		_release(screen)
		return

	var deck_before: int = controller.human_deck().size()
	var revision_before: int = board.get_revision()
	var cells: Array[Vector2i] = board.get_frontier_cells()
	if not check(cells.size() > 0, "the opening board must offer a legal cell"):
		_release(screen)
		return

	screen._on_cell_tapped(cells[0])

	check_eq(controller.staged_count(), 0, "a board tap must not stage a tile")
	check(not controller.has_pending(), "a board tap must leave no pending line")
	check_eq(
		screen.board_view.get_pending_count(), 0, "the board must draw no pending line"
	)
	check_eq(
		controller.human_deck().size(),
		deck_before,
		"a board tap must not take a tile out of the hand"
	)
	check_eq(board.get_revision(), revision_before, "a board tap must not touch the board")
	check_eq(board.occupied_count(), 0, "a board tap must not place a tile")
	check(controller.is_human_turn(), "a board tap must not consume the turn")
	_release(screen)


## Moving an unconfirmed tile to another cell by dragging it there.
##
## The pending line is an uncommitted assembly, so where its tiles sit is the
## player's to adjust until they confirm (ADR-011 section 11). The move keeps the
## tile, its rotation, and its membership of the line, and touches nothing else.
func test_a_press_on_a_staged_tile_released_on_another_cell_moves_it_there() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if not check_eq(
		pair.size(), TILES_PER_LINE, "a deck of six from four ranks must hold a pair"
	):
		_release(screen)
		return
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if not check_eq(cells.size(), TILES_PER_LINE, "the opening board must offer a two-cell line"):
		_release(screen)
		return

	_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[0].tile_id))
	screen.stage_at(cells[0])
	if not check_eq(controller.staged_count(), 1, "the tile must be staged before it is moved"):
		_release(screen)
		return

	# A destination the line does not hold and the board has committed nothing to.
	var target: Vector2i = _free_cell_beside(board, cells[0])
	if not check(
		target != BoardMetrics.NO_CELL, "the board must offer a free destination"
	):
		_release(screen)
		return

	var revision_before: int = board.get_revision()
	var deck_before: PackedStringArray = _deck_ids(controller)
	var rotation_before: int = controller.staged_snapshots()[0].get_rotation()

	# Pressed on the staged tile, released on another cell: the gesture that moves it.
	screen.board_input._handle_press(_board_point_for(screen, cells[0]), true)
	screen.board_input._handle_press(_board_point_for(screen, target), false)

	check_eq(controller.staged_count(), 1, "a move must keep the tile in the line")
	check_eq(
		controller.staged_cells()[0],
		target,
		"the released-on cell must be where the tile now stands"
	)
	check(
		not controller.staged_cells().has(cells[0]),
		"the cell the tile was moved from must no longer hold it"
	)
	check_eq(
		controller.staged_snapshots()[0].get_rotation(),
		rotation_before,
		"a move must carry the tile's rotation with it"
	)
	check_eq(
		screen.board_view.get_pending_line()[0].get_cell(),
		target,
		"the board must draw the tile on the cell it was moved to"
	)
	check_eq(
		_deck_ids(controller),
		deck_before,
		"a move must not change which tiles the deck holds"
	)
	check_eq(board.get_revision(), revision_before, "a move must not touch the board")
	check_eq(controller.get_session().move_count(), 0, "a move must not record a move")
	check(controller.is_human_turn(), "a move must not consume the turn")
	_release(screen)


## Returns a cell next to `cell` that holds no committed tile, or `NO_CELL`.
func _free_cell_beside(board: BoardState, cell: Vector2i) -> Vector2i:
	for offset: Vector2i in BoardEnums.neighbor_offsets():
		var candidate: Vector2i = cell + offset
		if BoardEnums.is_in_bounds(candidate) and board.is_empty_cell(candidate):
			return candidate
	return BoardMetrics.NO_CELL


func test_a_cancel_returns_every_staged_tile_to_the_deck() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if not check_eq(
		pair.size(), TILES_PER_LINE, "a deck of six from four ranks must hold a pair"
	):
		_release(screen)
		return
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if not check_eq(cells.size(), TILES_PER_LINE, "the opening board must offer a two-cell line"):
		_release(screen)
		return

	var deck_before: PackedStringArray = _deck_ids(controller)
	var revision_before: int = board.get_revision()

	_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[0].tile_id))
	screen.stage_at(cells[0])
	_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[1].tile_id))
	screen.stage_at(cells[1])
	if not check_eq(
		controller.staged_count(),
		TILES_PER_LINE,
		"the whole line must be staged before it can be cancelled"
	):
		_release(screen)
		return

	screen._on_cancel_pressed()

	check(not controller.has_pending(), "Cancel must discard the pending line")
	check_eq(controller.staged_count(), 0, "Cancel must leave nothing staged")
	check_eq(screen.deck_view.deck_size(), DECK_SIZE, "Cancel must restore every tile to the visible deck")
	check_eq(
		screen.board_view.get_pending_count(), 0, "Cancel must clear the board's pending line"
	)
	check_eq(
		_deck_ids(controller),
		deck_before,
		"Cancel must return every staged tile to the deck, in deck order"
	)
	check_eq(board.occupied_count(), 0, "Cancel must leave the board untouched")
	check_eq(board.get_revision(), revision_before, "Cancel must leave the board untouched")
	check_eq(controller.get_session().move_count(), 0, "Cancel must not record a move")
	check(controller.is_human_turn(), "Cancel must not consume the turn")
	check_eq(
		controller.pending_rotation(), 0, "Cancel must return rotation to the base orientation"
	)
	_release(screen)


func test_an_illegal_pending_line_is_refused_and_changes_nothing() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if not check_eq(
		pair.size(), TILES_PER_LINE, "a deck of six from four ranks must hold a pair"
	):
		_release(screen)
		return

	# Two cells of one rank that are collinear with a hole between them, and two
	# that only meet diagonally: ADR-011 section 1 refuses both, so neither may
	# commit anything at all (section 5).
	var opening: Vector2i = Vector2i(BoardEnums.OPENING_MIN, BoardEnums.OPENING_MIN)
	var gapped: Array[Vector2i] = [opening, opening + Vector2i(2, 0)]
	var diagonal: Array[Vector2i] = [opening, opening + Vector2i(1, 1)]

	_run_refused_line(screen, pair, gapped, LINE_GAP)
	_run_refused_line(screen, pair, diagonal, MIXED_ORIENTATION)

	# The refusals changed nothing at all, which is what section 5 requires.
	var deck_before: PackedStringArray = _deck_ids(controller)
	check_eq(controller.get_session().move_count(), 0, "a refused line must record no move")
	check(controller.is_human_turn(), "a refused line must not consume the turn")
	check_eq(board.occupied_count(), 0, "a refused line must not write to the board")
	check_eq(board.get_revision(), 0, "a refused line must not touch the board")
	check_eq(_deck_ids(controller), deck_before, "a refused line must keep the player's tiles")
	_release(screen)


func test_confirm_commits_the_whole_line_as_one_move() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var session: GameSessionState = controller.get_session()
	var board: BoardState = controller.get_board()

	# Confirming with nothing staged must not commit anything.
	screen._on_confirm_pressed()
	check_eq(session.move_count(), 0, "Confirm with no pending line must commit nothing")
	check(controller.is_human_turn(), "Confirm with no pending line must not consume the turn")

	var pot_before: int = controller.remaining_tiles()
	var result: LineResult = _stage_and_commit_opening_line(screen)
	if not check(
		result != null and result.was_committed(),
		"the assembled line must commit as one move (ADR-011 section 5)"
	):
		_release(screen)
		return

	# One line, one transaction, one move identifier, one history entry.
	check_eq(session.move_count(), 1, "the whole line is one history entry")
	check_eq(
		session.last_move().placement_count(),
		TILES_PER_LINE,
		"the history entry must carry every tile of the line"
	)
	check_eq(
		result.staged_count(),
		TILES_PER_LINE,
		"the committed move must report the tiles it placed"
	)
	check(
		session.has_move_id(ScoringCoordinator.move_id_for(TEST_MATCH_ID, 1, 1)),
		"the line of turn 1 is that turn's one move, at placement index 1 (ADR-011 section 7)"
	)
	check_eq(board.occupied_count(), TILES_PER_LINE, "every tile of the line must reach the board")

	var committed_cells: Array[Vector2i] = result.staged_cells()
	for cell: Vector2i in committed_cells:
		check(board.is_occupied(cell), "the whole line must be on the board at once")
	check(
		screen.board_view.get_last_committed_cells().has(committed_cells[0]),
		"the board must mark the line it committed"
	)
	check_eq(
		screen.board_view.get_last_committed_cells().size(),
		TILES_PER_LINE,
		"the board must mark every cell of the committed line"
	)

	check(not controller.has_pending(), "a committed line clears the staging state")
	check_eq(screen.board_view.get_pending_count(), 0, "a committed line clears the board preview")

	# ADR-011 sections 7 and 8: the commit ends the turn and refills the deck by
	# exactly the tiles the line used.
	check(not controller.is_human_turn(), "the committed line hands play to the rival")
	check(
		TurnManager.is_awaiting_ai_action(session),
		"the turn boundary must reach the opponent's action phase"
	)
	check_eq(session.get_turn_state().turn_number, 2, "the committed line advances the turn number")
	check_eq(
		pot_before - controller.remaining_tiles(),
		TILES_PER_LINE,
		"the refill takes exactly the tiles the line consumed"
	)
	check_eq(
		session.deck_count(HUMAN), DECK_SIZE, "the human's deck is refilled to deck_size"
	)
	check_eq(
		session.verify_tile_conservation().size(),
		0,
		"the commit must keep every tile in exactly one place: %s"
		% str(session.verify_tile_conservation())
	)
	_release(screen)


func test_the_swap_returns_tiles_for_equal_replacements_and_consumes_the_turn() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var session: GameSessionState = controller.get_session()
	var board: BoardState = controller.get_board()
	var deck: Array[TileDefinition] = controller.human_deck()
	if not check_eq(deck.size(), DECK_SIZE, "the human must hold a full deck to swap from"):
		_release(screen)
		return

	# ADR-011 section 6: a swap cannot place a tile, so opening it must clear the
	# pending line rather than leave it staged behind the swap.
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if cells.size() >= 1:
		screen.stage_at(cells[0])
	var revision_before: int = board.get_revision()
	var pot_before: int = controller.remaining_tiles()

	screen._on_swap_pressed()

	if not check(screen.is_swap_mode(), "the Swap control must open the swap set"):
		_release(screen)
		return
	check(
		not controller.has_pending(),
		"opening the swap must clear the pending line: a swap cannot place a tile"
	)
	check(screen.deck_view.is_mark_mode(), "the deck row must collect the tiles to return")
	check_eq(
		_deck_ids(controller).size(), DECK_SIZE, "opening the swap must not change the deck"
	)
	check(controller.is_human_turn(), "opening the swap must not consume the turn")

	# The player marks the tile to return; nothing is returned until it is
	# submitted as a whole.
	var returned_id: StringName = deck[0].tile_id
	_tap_deck(screen, 0)
	check_eq(screen.swap_tiles().size(), 1, "a tap must mark one tile for the swap")
	check_eq(
		String(screen.swap_tiles()[0]), String(returned_id), "the marked tile must be the tapped one"
	)
	check_eq(screen.deck_view.marked_count(), 1, "the row must draw the marked tile")
	check(
		session.holds_deck_tile(HUMAN, returned_id),
		"a marked tile is still held until the swap is submitted"
	)
	check_eq(session.move_count(), 0, "marking a swap tile must not record a move")
	check_eq(board.get_revision(), revision_before, "marking a swap tile must not touch the board")

	screen._on_swap_confirm_pressed()

	check(not screen.is_swap_mode(), "submitting the swap must close the swap set")
	check_eq(screen.swap_tiles().size(), 0, "a submitted swap must leave no marks behind")
	check_eq(screen.deck_view.marked_count(), 0, "the row must clear every swap mark")
	check(
		not session.holds_deck_tile(HUMAN, returned_id),
		"the swapped tile must have left the deck"
	)
	check_eq(session.deck_count(HUMAN), DECK_SIZE, "the deck is refilled with equal replacements")
	check_eq(
		controller.remaining_tiles(),
		POT_AFTER_SETUP,
		"a swap returns as many tiles as it drew, so the pot holds the same total"
	)

	# ADR-011 section 6: a swap consumes the whole turn and cannot score.
	check(not controller.is_human_turn(), "a swap consumes the player's whole turn")
	check(TurnManager.is_awaiting_ai_action(session), "a swap passes play to the opponent")
	check_eq(session.move_count(), 0, "a swap cannot place a tile and cannot score")
	check_eq(board.occupied_count(), 0, "a swap must not commit the cleared pending line")
	check_eq(board.get_revision(), revision_before, "a swap must not touch the board")
	_release(screen)


func test_a_swap_is_refused_when_it_cannot_be_supplied_and_keeps_the_turn() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var session: GameSessionState = controller.get_session()
	var deck_before: PackedStringArray = _deck_ids(controller)

	screen._on_swap_pressed()
	if not check(screen.is_swap_mode(), "the Swap control must open the swap set"):
		_release(screen)
		return

	# An empty swap set is nothing to swap: it must not be submitted as a swap.
	screen._on_swap_confirm_pressed()
	check(screen.is_swap_mode(), "an empty swap set must leave the swap open")
	check(controller.is_human_turn(), "an empty swap set must not consume the turn")
	check_eq(session.move_count(), 0, "an empty swap set must record no move")

	# A swap the player cannot supply is refused (ADR-011 section 6): the player
	# keeps their tiles and the turn stays open.
	var swapped: int = controller.request_swap([&"ui-test:not-a-held-tile"] as Array[StringName])
	check_eq(swapped, -1, "a swap that cannot be supplied must be refused")
	check(controller.is_human_turn(), "a refused swap must leave the turn open")
	check_eq(_deck_ids(controller), deck_before, "a refused swap must leave the player's tiles alone")

	# Closing the swap set without submitting it keeps the player's tiles too.
	screen._on_swap_cancel_pressed()
	check(not screen.is_swap_mode(), "cancelling the swap must close the swap set")
	check_eq(_deck_ids(controller), deck_before, "cancelling the swap must keep the player's tiles")
	check(controller.is_human_turn(), "cancelling the swap must not consume the turn")
	_release(screen)


func test_the_deck_row_is_not_selectable_off_turn() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()

	var result: LineResult = _stage_and_commit_opening_line(screen)
	if not check(
		result != null and result.was_committed(),
		"the opening line must commit so the rival holds the turn"
	):
		_release(screen)
		return
	if not check(not controller.is_human_turn(), "the committed line must pass play to the rival"):
		_release(screen)
		return

	var revision_before: int = board.get_revision()
	var armed_before: StringName = controller.selected_deck_tile_id()
	var cells: Array[Vector2i] = board.get_frontier_cells()

	# ADR-008 section 8: off-turn the screen freezes every gameplay control, and
	# the deck row is where a staging gesture starts, so it is the one that must
	# refuse taps first.
	check(screen.deck_view.is_locked(), "the deck row must be locked off-turn")
	check(not screen.board_input.enabled, "the board must not accept input off-turn")
	check(screen.bottom_navigation.buttons[&"Swap"].disabled, "Swap must be disabled off-turn")
	check(not screen.is_swap_mode(), "no swap set may be open off-turn")

	_tap_deck(screen, 0)
	check_eq(
		String(controller.selected_deck_tile_id()),
		String(armed_before),
		"a tap on a locked deck row must not change the armed tile"
	)

	screen.stage_at(cells[0] if not cells.is_empty() else Vector2i.ZERO)
	check_eq(controller.staged_count(), 0, "a board tap off-turn must stage nothing")
	check(not controller.has_pending(), "off-turn staging must leave no pending line")
	check_eq(board.get_revision(), revision_before, "off-turn staging must not touch the board")

	# The swap set belongs to the player's own turn, so it cannot be opened while
	# the rival holds the turn.
	screen._on_swap_pressed()
	check(not screen.is_swap_mode(), "the swap set must not open off-turn")
	check(not screen.deck_view.is_mark_mode(), "the deck row must not collect marks off-turn")
	check_eq(
		controller.get_session().move_count(),
		1,
		"off-turn commands must record no further move"
	)
	_release(screen)


func test_committed_move_shows_one_total_popup() -> void:
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
		_make_event(
			&"score:move:m1:poker:hand:V:5:5", ScoringEnums.ScoreCategory.POKER_HAND, 6, "THREE_OF_A_KIND"
		),
	]
	screen._on_score_awarded(events, Vector2i(5, 5))

	check_eq(
		screen.floating_scores.active_count(),
		1,
		"all awards from a played move must produce exactly one popup"
	)
	var first: Label = screen.floating_scores.get_child(0) as Label
	if check_not_null(first, "a popup must be a label"):
		check_eq(first.text, "14", "the popup sums every award without a plus prefix")
		check_eq(first.get_theme_font_size("font_size"), 55, "the score is half its former 110-point size")
		check_eq(first.get_theme_color("font_color"), Color.WHITE, "the score is white")
		check_eq(first.get_theme_color("font_outline_color"), Color.BLACK, "the score outline is black")
		check(first.get_theme_constant("outline_size") > 0, "the outline is visible")
	screen._on_score_awarded([
		_make_event(&"score:move:m2:edge", ScoringEnums.ScoreCategory.EDGE_MATCH, 2, "")
	], Vector2i(6, 5))
	check_eq(screen.floating_scores.active_count(), 2, "a subsequent move gets its own popup")
	check_eq((screen.floating_scores.get_child(1) as Label).text, "2", "totals do not accumulate across moves")
	_release(screen)


func test_empty_awards_show_no_total_popup() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	screen._on_score_awarded([], Vector2i(5, 5))
	check_eq(screen.floating_scores.active_count(), 0, "no points means no score popup")
	_release(screen)


func test_results_mark_the_winner_without_sweeping_panels() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var session: GameSessionState = screen.controller.get_session()
	session.finish(TurnEnums.MatchOutcome.AI_WIN, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))
	check(not screen.summary_overlay.visible, "rival result leaves the final board visible briefly")
	screen._on_final_board_pause_finished()
	var presentation: MatchEndPresentation = screen.summary_overlay as MatchEndPresentation
	presentation._stop_animation()
	presentation.seek(0.5)
	check_eq(screen.summary_title.text, "Rival wins", "rival win uses the neutral result heading")
	check(presentation._accents[1].winner and not presentation._accents[0].winner, "only the rival gets the winner ring")
	check_eq(presentation._accents[1].sparkle_alpha, 0.0, "rival win has no celebratory sparkles")
	check(not screen.summary_hub_button.disabled, "hub remains available during the entrance")
	check(presentation.find_child("BluePattern", true, false) == null, "old sweeping pattern is absent")
	screen._on_restart_pressed()
	session = screen.controller.get_session()
	session.finish(TurnEnums.MatchOutcome.HUMAN_WIN, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))
	screen._on_final_board_pause_finished()
	presentation._stop_animation()
	presentation.seek(0.5)
	check(presentation._accents[0].winner and not presentation._accents[1].winner, "only the player gets the winner ring")
	if not AccessibilitySettings.reduced_motion():
		check(presentation._accents[0].sparkle_alpha > 0, "player win has a brief sparkle")
	presentation.seek(MatchEndPresentation.DURATION)
	check(presentation._accents[0].sparkle_alpha < 0.001, "entrance sparkles finish before the repeating accent")
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

	# Finish the match directly rather than playing one out: the lifecycle
	# suite already covers reaching an end condition by play, and the live 52-tile
	# bag (ADR-004 section 1, amended 2026-09-23) cannot fill all 144 cells.
	session.finish(TurnEnums.MatchOutcome.DRAW, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))
	check(not screen.summary_overlay.visible, "player result leaves the final board visible briefly")
	screen._on_final_board_pause_finished()

	check(screen.summary_overlay.visible, "the summary must appear when the match ends")
	check(not (screen.get_node("%PotPanel") as Control).visible,
		"game over must hide the pot, count plate and count")
	check(not screen.tile_pile_view.is_visible_in_tree(), "game over must hide the pot artwork")
	check(not screen.turn_info_panel.visible, "game over hides the turn information panel")
	check_eq(screen.turn_clock_label.text, "", "game over clears the text timer")
	check(not screen.available_tiles_label.is_visible_in_tree(), "game over must hide the tile count")
	check(not screen.summary_body.text.contains("tiles left"), "the summary must omit the tile count")
	check_eq(screen.summary_title.text, "It's a draw", "a draw must be reported as one")
	check(
		(screen.summary_overlay as MatchEndPresentation)._terms.has("poker"),
		"the summary must break the score down by category"
	)
	check(not screen.board_input.enabled, "a finished match must stop accepting input")

	# Restarting must clear the summary and start a fresh board.
	screen._on_restart_pressed()
	check(not screen.summary_overlay.visible, "a new match must hide the summary")
	check((screen.get_node("%PotPanel") as Control).visible,
		"a new match must restore the pot and tile count")
	check(not screen.is_swap_mode(), "a new match must start with no swap set")
	check_eq(screen.turn_clock_label.text, "1:00", "a new match restores the text timer")
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
		check(not controller.has_pending(), "a new match must start with no staged line")
	_release(screen)


# --- Deck drag onto the board (AGENTS.md section 8) ------------------------


func test_the_difficulty_picker_selects_the_opponent_policy() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	if not check_not_null(
		screen.difficulty_picker, "the HUD must expose the rival difficulty control"
	):
		_release(screen)
		return

	# ADR-005 sections 4 to 6 define exactly three Phase 1 difficulties, so the
	# control must offer all three and nothing else.
	check_eq(
		screen.difficulty_picker.item_count,
		AiEnums.Difficulty.size(),
		"the control must offer one entry per Phase 1 difficulty"
	)

	# The control must open on the policy actually in force.
	check_eq(
		screen.difficulty_picker.get_item_id(screen.difficulty_picker.selected),
		controller.ai_difficulty(),
		"the control must start by showing the difficulty in force"
	)

	# This is the exit criterion's missing half (Milestone 6): Human vs Easy has
	# to be startable, and until now nothing in the game could select it.
	var easy_index: int = screen.difficulty_picker.get_item_index(AiEnums.Difficulty.EASY)
	if not check(easy_index >= 0, "Easy must be offered"):
		_release(screen)
		return
	screen.difficulty_picker.select(easy_index)
	screen._on_difficulty_selected(easy_index)
	check_eq(
		controller.ai_difficulty(),
		AiEnums.Difficulty.EASY,
		"choosing Easy must put the Easy policy in force"
	)

	# Hard too, so all three are reachable rather than only the first entry.
	var hard_index: int = screen.difficulty_picker.get_item_index(AiEnums.Difficulty.HARD)
	if not check(hard_index >= 0, "Hard must be offered"):
		_release(screen)
		return
	screen.difficulty_picker.select(hard_index)
	screen._on_difficulty_selected(hard_index)
	check_eq(
		controller.ai_difficulty(),
		AiEnums.Difficulty.HARD,
		"choosing Hard must put the Hard policy in force"
	)
	check_eq(
		screen.difficulty_picker.get_item_id(screen.difficulty_picker.selected),
		AiEnums.Difficulty.HARD,
		"the control must show the difficulty it just put in force"
	)

	# And the choice must outlive a new match rather than silently reverting.
	controller.start_new_match(TEST_MATCH_ID, TEST_SEED)
	check_eq(
		controller.ai_difficulty(),
		AiEnums.Difficulty.HARD,
		"a new match must keep the chosen difficulty"
	)
	_release(screen)


func test_deck_surrounding_space_can_drag_a_tile_onto_the_board() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var row: DeckView = screen.deck_view
	row.size = Vector2(720, 96)
	var tile_id: StringName = screen.controller.unstaged_human_deck()[0].tile_id
	var grab := Vector2(1, 1)
	check(not row.tile_rect_at(0).has_point(grab), "press starts outside the tile artwork")
	_send_press(row, grab)
	_send_motion(row, grab + Vector2(0, -DeckView.DRAG_THRESHOLD - 4))
	check(row.is_dragging(), "surrounding deck space starts a drag")
	var cell := Vector2i(5, 5)
	var destination: Vector2 = _drag_point_for(screen, cell)
	_send_motion(row, destination)
	_send_release(row, destination)
	check_eq(screen.controller.staged_count(), 1, "release stages one tile")
	if screen.controller.staged_count() == 1:
		check_eq(screen.controller.staged_snapshots()[0].get_tile_id(), tile_id, "drop stages the nearest tile")
		check_eq(screen.controller.staged_cells()[0], cell, "drop reaches the chosen cell")
	check(not row.is_dragging(), "release finishes the drag")
	_release(screen)


func test_deck_drag_continues_after_pointer_leaves_the_deck_control() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var row: DeckView = screen.deck_view
	row.size = Vector2(720.0, 96.0)
	var cell: Vector2i = screen.controller.get_board().get_frontier_cells()[0]
	var start: Vector2 = row.tile_rect_at(0).get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	row._gui_input(press)
	var threshold_point: Vector2 = start + Vector2(0.0, -DeckView.DRAG_THRESHOLD - 4.0)
	_send_viewport_motion(row, threshold_point)
	check(row.is_dragging(), "viewport motion must start a drag outside the deck control")
	var destination: Vector2 = _drag_point_for(screen, cell)
	_send_viewport_motion(row, destination)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = row.get_global_transform_with_canvas() * destination
	row._input(release)
	check_eq(screen.controller.staged_count(), 1, "release outside the deck must stage the tile on the board")
	check_eq(screen.controller.staged_cells()[0], cell, "the tracked release must land on its board cell")
	check(not row.is_dragging(), "viewport release must finish the deck drag")
	_release(screen)


func test_hud_refresh_preserves_a_held_deck_drag() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var row: DeckView = screen.deck_view
	if not check(_begin_deck_drag(screen, 0), "deck drag starts before HUD refresh"):
		_release(screen)
		return
	var dragged_id: StringName = screen._drag_tile_id
	screen._refresh_all()
	check(row.is_dragging(), "unchanged HUD redraw keeps the held deck gesture")
	check_eq(screen._drag_tile_id, dragged_id, "screen keeps the tile identity until release")
	check(screen._deck_drag_preview.visible, "drag preview remains visible after refresh")
	row.cancel_drag()
	check(not row.is_dragging() and String(screen._drag_tile_id).is_empty(), "explicit cancellation still ends both views")
	_release(screen)


func test_a_dragged_tile_is_staged_at_the_cell_it_is_dropped_on() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if not check_eq(
		pair.size(), TILES_PER_LINE, "a deck of six from four ranks must hold a pair"
	):
		_release(screen)
		return
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if not check_eq(cells.size(), TILES_PER_LINE, "the opening board must offer a two-cell line"):
		_release(screen)
		return

	var revision_before: int = board.get_revision()
	var deck_before: PackedStringArray = _deck_ids(controller)

	# The player turns the tile in the deck row first. A drag stages the tile, it
	# never turns it, so the drop must use exactly this rotation. Whichever tap is
	# the one that arms the tile, the following taps turn it, so the turns are made
	# until the row reports an orientation that is off the base.
	var first_tile: int = _index_of_tile(controller.human_deck(), pair[0].tile_id)
	_tap_deck_fully(screen, first_tile)
	var chosen_rotation: int = controller.pending_rotation()
	for _step: int in range(TileEnums.ROTATION_COUNT):
		if chosen_rotation != 0:
			break
		_tap_deck_fully(screen, first_tile)
		chosen_rotation = controller.pending_rotation()
	if not check(
		chosen_rotation != 0, "tapping the selected deck tile must turn it in the row"
	):
		_release(screen)
		return
	check_eq(
		screen.deck_view.selected_rotation(),
		chosen_rotation,
		"the row must draw the tile at the rotation the player chose"
	)

	# The drag runs through the row's own input handler and the screen's own
	# handlers: the press, the move past the threshold, the move over the board,
	# and the release are synthesized events, so this exercises the real path.
	if not check(
		_drag_deck_tile(screen, first_tile, cells[0]),
		"a drag must start through the deck row's own input handler"
	):
		_release(screen)
		return

	check_eq(
		controller.staged_count(), 1, "a drop on a legal cell must stage the dragged tile"
	)
	check_eq(
		controller.staged_snapshots()[0].get_rotation(),
		chosen_rotation,
		"a drop must stage the tile at the rotation the player chose in the deck row"
	)
	check_eq(
		controller.staged_cells()[0],
		cells[0],
		"the tile must be staged at the cell it was dropped on"
	)
	check_eq(
		controller.get_session().move_count(), 0, "a drop must not record a move by itself"
	)
	check_eq(board.get_revision(), revision_before, "a drop must not write to the board")
	check_eq(_deck_ids(controller), deck_before, "a drop must keep the player's tiles")
	check(controller.is_human_turn(), "a drop must not consume the turn")
	check(
		not screen.board_view.has_drag(),
		"a released drag must leave no ghost behind on the board"
	)
	check(not screen.deck_view.is_dragging(), "a released drag must leave the row idle")

	# A second dragged tile extends the pending line exactly as a second tap
	# does: one tile is never a legal move (ADR-011 sections 1 and 3).
	if not check(
		_drag_deck_tile(
			screen, _index_of_tile(controller.unstaged_human_deck(), pair[1].tile_id), cells[1]
		),
		"a second drag must start through the deck row's own input handler"
	):
		_release(screen)
		return

	check_eq(
		controller.staged_count(),
		TILES_PER_LINE,
		"a second dragged tile must extend the pending line"
	)
	check(
		controller.is_line_valid(),
		"a dropped contiguous pair of one rank is a legal line: %s" % controller.line_reason()
	)
	check_eq(
		screen.board_view.get_pending_count(),
		TILES_PER_LINE,
		"the board must draw every tile the drags staged"
	)
	check_eq(board.get_revision(), revision_before, "two drops must still not touch the board")
	check_eq(
		controller.get_session().move_count(), 0, "two drops must still not record a move"
	)
	_release(screen)


func test_deal_tracks_live_pot_and_rack_geometry_without_restarting() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var row: DeckView = screen.deck_view
	row.size = Vector2(720, 96)
	var layer: DealLayer = screen.deal_layer
	check_eq(layer._tiles.size(), row.deck_size(), "opening deal includes the visible deck")
	layer._elapsed = DealLayer.FLIGHT + 0.1
	var elapsed: float = layer._elapsed
	var deck_parent: Control = row.get_parent() as Control
	deck_parent.position += Vector2(17, -146)
	row.size = Vector2(600, 84)
	row.scale = Vector2(0.9, 0.9)
	screen.tile_pile_view.position += Vector2(7, 13)
	layer.position = Vector2(11, 19)
	layer.scale = Vector2(0.8, 0.8)
	layer._refresh_geometry()
	check((layer.get_global_transform() * layer._from).is_equal_approx(screen.tile_pile_view.stack_origin_global()), "flight still begins at the pot opening")
	for index: int in range(layer._tiles.size()):
		var expected: Rect2 = row.tile_global_rect_for(layer._tiles[index].tile_id)
		var actual: Rect2 = layer.get_global_transform() * layer._to[index]
		check(actual.position.is_equal_approx(expected.position), "landing follows the moved rack slot")
		check(actual.size.is_equal_approx(expected.size), "landing uses the scaled tile size")
	check_eq(layer._elapsed, elapsed, "layout updates do not restart the deal")
	layer._process(layer._total_duration())
	check(not layer.is_playing(), "deal finishes normally after layout changes")
	check(row._concealed.is_empty(), "finished tiles are revealed in the deck")
	_release(screen)


func test_deal_signals_tile_flip_sound_at_half_turn() -> void:
	var layer := DealLayer.new()
	layer._tiles = [TileDefinition.new()]
	layer._playing = true
	var sound_at: float = DealLayer.FLIGHT + DealLayer.HOLD + layer.flip_duration * 0.25
	layer._elapsed = sound_at - 0.01
	var flips: Array[int] = []
	layer.tile_flip_sound_due.connect(func() -> void: flips.append(1))
	layer._process(0.005)
	check(flips.is_empty(), "the sound cue must wait until halfway through the turn")
	layer._process(0.01)
	check_eq(flips.size(), 1, "the sound cue must fire halfway into the turn")
	layer.free()


func test_tile_flip_depth_peaks_at_twenty_percent_of_tile_width() -> void:
	var bounds := Rect2(30.0, 40.0, 200.0, 100.0)
	var edge_on: Rect2 = TilePainter.flip_depth_rect(bounds, 0.5)
	check_eq(edge_on.size.x, 40.0, "edge-on depth reaches twenty percent of tile width")
	check_eq(edge_on.size.y, bounds.size.y, "depth spans the tile's full height")
	check(edge_on.get_center().is_equal_approx(bounds.get_center()), "depth stays centered on the flipping tile")
	check_eq(TilePainter.flip_depth_rect(bounds, 0.25).size.x, 20.0, "depth grows smoothly toward the midpoint")
	check(not TilePainter.flip_depth_rect(bounds, 0.0).has_area(), "no side face is visible before the flip")
	check(not TilePainter.flip_depth_rect(bounds, 1.0).has_area(), "no side face remains after the flip")
	check_eq(TilePainter.FLIP_EDGE_COLOR, Color(0.20, 0.20, 0.22, 1.0), "the temporary side is dark gray")


func test_tile_flip_sound_loads_at_quarter_amplitude() -> void:
	var adapter := FeedbackAdapter.new()
	var stream: AudioStream = adapter._load_cue_stream(
		String(FeedbackAdapter.CUE_SOUNDS[FeedbackAdapter.CUE_TILE_FLIP])
	)
	check_not_null(stream, "the tile-flip MP3 must load even before an import artifact exists")
	check_eq(
		float(FeedbackAdapter.CUE_VOLUMES_DB[FeedbackAdapter.CUE_TILE_FLIP]),
		-18.0,
		"tile-pop playback must use a 75% intensity reduction"
	)
	if stream != null:
		check(stream.get_length() > 0.0, "the loaded tile-flip clip must have a usable duration")
	adapter.free()


func test_deck_drag_shrinks_preview_and_tracks_nearest_cell() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var row: DeckView = screen.deck_view
	row.size = Vector2(720, 96)
	var cell := Vector2i(5, 5)
	var destination: Vector2 = _drag_point_for(screen, cell)
	_send_press(row, row.tile_rect_at(0).get_center())
	_send_motion(row, destination)
	check_eq(screen.board_view.get_drop_cell(), cell, "first drag motion immediately highlights the nearest cell")
	var preview: BoardPreviewLayer = screen.board_view.get_node("%PreviewLayer") as BoardPreviewLayer
	var overlay: Control = screen._deck_drag_preview
	check_eq(screen._deck_drag_preview.DRAG_TILE_ALPHA, 1.0, "a tile dragged from the deck stays fully opaque")
	var to_screen: Transform2D = screen.get_global_transform().affine_inverse() * row.get_global_transform()
	var deck_rect: Rect2 = to_screen * row.tile_rect_at(row.dragging_index())
	check(overlay.size.is_equal_approx(deck_rect.size * 0.9), "drag preview is ten percent smaller than its deck tile")
	check(overlay.get_rect().get_center().is_equal_approx(to_screen * destination), "smaller tile follows the pointer")
	check(not preview.state.drag_tile_visible, "board draws no duplicate snapped tile")
	check_eq(preview._target_frame.border_color, Color("#F4C86A"), "drop target uses the Modern Tabletop honey outline")
	check(not preview._target_frame.draw_center, "highlight frame leaves the target tile visible")
	var next_cell := Vector2i(6, 5)
	_send_motion(row, _drag_point_for(screen, next_cell))
	check_eq(screen.board_view.get_drop_cell(), next_cell, "target follows the nearest cell")
	_send_release(row, _drag_point_for(screen, next_cell))
	check_eq(screen.controller.staged_count(), 1, "shrinking does not change placement")
	check(not screen.board_view.has_drag(), "drop clears the target frame and drag preview")
	check_eq(preview.state.drag_scale, 1.0, "drop restores normal render scale")
	check(not overlay.visible, "drop hides the free-moving tile")
	check(preview.drag_tile_rect().size == Vector2.ZERO, "no small drag tile remains after release")
	_release(screen)


func test_deck_glimmer_only_runs_on_resting_unselected_tiles() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	_finish_opening_deal(screen)
	var row: DeckView = screen.deck_view
	var tile_id: StringName = screen.controller.human_deck()[0].tile_id
	check(is_equal_approx(DeckView.GLIMMER_DURATION, 1.0 / 3.0), "a glimmer takes one third of a second at three times speed")
	check(
		TilePainter.warmable_art_paths().has(TilePainter.TILE_GLIMMER_TEXTURE),
		"the deck glimmer image is included in the startup warm-up"
	)
	row._selected_index = -1
	row._drag_index = -1
	row.set_concealed([] as Array[StringName])
	check(row._can_glimmer(tile_id), "an unselected tile at rest may glimmer")
	row._selected_index = 0
	check(not row._can_glimmer(tile_id), "a selected tile does not glimmer")
	row._selected_index = -1
	row._drag_index = 0
	check(not row._can_glimmer(tile_id), "a lifted tile does not glimmer")
	row._drag_index = -1
	row.set_concealed([tile_id])
	check(not row._can_glimmer(tile_id), "a concealed tile in flight does not glimmer")
	_release(screen)


func test_deck_drag_moves_smoothly_within_cells_and_outside_board() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	check(_begin_deck_drag(screen, 0), "deck drag starts")
	var row: DeckView = screen.deck_view
	var overlay: Control = screen._deck_drag_preview
	var to_screen: Transform2D = screen.get_global_transform().affine_inverse() * row.get_global_transform()
	var drawn_size: Vector2 = overlay.size
	var cell := Vector2i(5, 5)
	var center: Vector2 = _drag_point_for(screen, cell)
	for offset: Vector2 in [Vector2(-3.25, 2.5), Vector2.ZERO, Vector2(4.5, -1.75)]:
		_send_motion(row, center + offset)
		check(overlay.get_rect().get_center().is_equal_approx(to_screen * (center + offset)), "preview follows fractional pointer motion without grid jumps")
		check_eq(screen.board_view.get_drop_cell(), cell, "target stays on the nearest cell while tile moves")
		check_eq(screen.controller.staged_count(), 0, "moving the preview never stages a tile")
	var outside: Vector2 = row.get_global_transform().affine_inverse() * _off_board_point(screen)
	_send_motion(row, outside)
	check(overlay.visible, "tile remains visible between deck and board")
	check(overlay.get_rect().get_center().is_equal_approx(to_screen * outside), "off-board tile follows the pointer")
	check(not screen.board_view.has_drag(), "off-board pointer clears only the grid target")
	check_eq(overlay.size, drawn_size, "drag size stays constant outside the board")
	row.cancel_drag()
	check(not overlay.visible, "cancellation hides the overlay")
	check_eq(screen.controller.staged_count(), 0, "cancellation places no tile")
	_release(screen)


func test_a_drag_highlights_the_cell_under_the_pointer_as_legal_or_illegal() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if not check_eq(
		pair.size(), TILES_PER_LINE, "a deck of six from four ranks must hold a pair"
	):
		_release(screen)
		return
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if not check_eq(cells.size(), TILES_PER_LINE, "the opening board must offer a two-cell line"):
		_release(screen)
		return

	var row: DeckView = screen.deck_view
	var first: int = _index_of_tile(controller.human_deck(), pair[0].tile_id)
	if not check(_begin_deck_drag(screen, first), "the drag gesture must start"):
		_release(screen)
		return

	# Over the board: the tile snaps to the cell under the pointer and that cell
	# is marked as a target the controller would accept.
	_send_motion(row, _drag_point_for(screen, cells[0]))
	check(screen.board_view.has_drag(), "a drag over the board must draw a target")
	check_eq(
		screen.board_view.get_drop_cell(),
		cells[0],
		"the target must be the cell under the pointer, read from the board's metrics"
	)
	var ghost: TileSnapshot = screen.board_view.get_drag_snapshot()
	if check_not_null(ghost, "a drag over the board must draw the tile being dragged"):
		check_eq(
			ghost.get_cell(),
			cells[0],
			"the dragged tile must snap to the cell under the pointer"
		)
	check(
		screen.board_view.is_drop_legal(),
		"an empty cell on the board must be marked as a legal drop"
	)

	# Off the board: there is no cell, so nothing is drawn to promise a landing.
	_send_motion(row, _drag_point_for(screen, cells[0]) + Vector2(-100000.0, -100000.0))
	check_eq(
		screen.board_view.get_drop_cell(),
		BoardMetrics.NO_CELL,
		"a pointer off the board must report no target cell"
	)
	check(
		not screen.board_view.has_drag(),
		"a pointer off the board must leave no ghost on the board"
	)

	# Drop the first tile legally, then drag a second over the cell the pending
	# line already holds: that cell cannot take it, so it must be marked illegal
	# while an empty cell stays legal.
	_send_motion(row, _drag_point_for(screen, cells[0]))
	_send_release(row, _drag_point_for(screen, cells[0]))
	if not check_eq(controller.staged_count(), 1, "the legal drop must have staged a tile"):
		_release(screen)
		return

	var second: int = _index_of_tile(controller.human_deck(), pair[1].tile_id)
	if not check(_begin_deck_drag(screen, second), "the second drag gesture must start"):
		_release(screen)
		return
	_send_motion(row, _drag_point_for(screen, cells[0]))
	check_eq(
		screen.board_view.get_drop_cell(),
		cells[0],
		"the highlight must follow the pointer onto a cell the line already holds"
	)
	check(
		not screen.board_view.is_drop_legal(),
		"a cell the pending line already holds must be marked as an illegal drop"
	)
	_send_motion(row, _drag_point_for(screen, cells[1]))
	check(
		screen.board_view.is_drop_legal(),
		"an empty cell must be marked as a legal drop even after an illegal one"
	)
	_send_release(row, _drag_point_for(screen, cells[1]))
	check_eq(controller.staged_count(), TILES_PER_LINE, "the second drop must extend the line")
	check(not screen.board_view.has_drag(), "a released drag must leave no ghost behind")
	_release(screen)


func test_a_drop_on_an_illegal_cell_or_off_the_board_changes_nothing() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if not check_eq(
		pair.size(), TILES_PER_LINE, "a deck of six from four ranks must hold a pair"
	):
		_release(screen)
		return
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if not check_eq(cells.size(), TILES_PER_LINE, "the opening board must offer a two-cell line"):
		_release(screen)
		return

	var first: int = _index_of_tile(controller.human_deck(), pair[0].tile_id)
	if not check(
		_drag_deck_tile(screen, first, cells[0]), "the setup drop must stage one tile"
	):
		_release(screen)
		return

	var revision_before: int = board.get_revision()
	var deck_before: PackedStringArray = _deck_ids(controller)
	var moves_before: int = controller.get_session().move_count()
	var staged_before: int = controller.staged_count()
	var second: int = _index_of_tile(controller.human_deck(), pair[1].tile_id)

	# The cell the pending line already holds cannot take a second tile, so a
	# release there must leave the board, the deck, the history, and the pending
	# line exactly as they were (ADR-011 section 5).
	if not check(
		_drag_deck_tile(screen, second, cells[0]), "the illegal drag must still run its gesture"
	):
		_release(screen)
		return
	check_eq(
		controller.staged_count(),
		staged_before,
		"a drop on a cell the line already holds must stage nothing"
	)
	check_eq(board.get_revision(), revision_before, "an illegal drop must not touch the board")
	check_eq(_deck_ids(controller), deck_before, "an illegal drop must leave the deck unchanged")
	check_eq(
		controller.get_session().move_count(),
		moves_before,
		"an illegal drop must record no move"
	)
	check(controller.is_human_turn(), "an illegal drop must not consume the turn")
	check(not screen.board_view.has_drag(), "an illegal drop must leave no ghost behind")

	# A release off the board entirely is the same case: nothing to land on, so
	# nothing changes.
	var off_board: Vector2 = _drag_point_for(screen, cells[1]) + Vector2(-100000.0, -100000.0)
	if not check(
		_drag_deck_tile_to_point(screen, second, off_board),
		"the off-board drag must still run its gesture"
	):
		_release(screen)
		return
	check_eq(
		controller.staged_count(), staged_before, "a drop off the board must stage nothing"
	)
	check_eq(
		board.get_revision(), revision_before, "a drop off the board must not touch the board"
	)
	check_eq(
		_deck_ids(controller), deck_before, "a drop off the board must leave the deck unchanged"
	)
	check_eq(
		controller.get_session().move_count(),
		moves_before,
		"a drop off the board must record no move"
	)
	check(
		not screen.board_view.has_drag(),
		"a drop off the board must leave no ghost behind"
	)
	check(
		not screen.deck_view.is_dragging(),
		"a drop off the board must leave the row idle"
	)
	_release(screen)


func test_a_drag_off_turn_is_refused() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()

	var result: LineResult = _stage_and_commit_opening_line(screen)
	if not check(
		result != null and result.was_committed(),
		"the opening line must commit so the rival holds the turn"
	):
		_release(screen)
		return
	if not check(not controller.is_human_turn(), "the committed line must pass play to the rival"):
		_release(screen)
		return

	var revision_before: int = board.get_revision()
	var deck_before: PackedStringArray = _deck_ids(controller)
	var moves_before: int = controller.get_session().move_count()
	var cells: Array[Vector2i] = board.get_frontier_cells()

	# The row is locked off-turn, so the gesture never even leaves the row
	# (ADR-008 section 8).
	check(
		not _begin_deck_drag(screen, 0),
		"a locked deck row must not start a drag"
	)
	check(not screen.deck_view.is_dragging(), "a locked deck row must leave no drag in flight")

	# And if a drag report reaches the screen anyway, the screen refuses it: no
	# ghost, no target, and nothing staged.
	var tile_id: StringName = controller.human_deck()[0].tile_id
	var point: Vector2 = _drag_point_for(
		screen, cells[0] if not cells.is_empty() else Vector2i.ZERO
	)
	screen._on_deck_tile_drag_started(tile_id, Vector2.ZERO)
	screen._on_deck_tile_dragged(tile_id, point)
	check(not screen.board_view.has_drag(), "an off-turn drag must draw no ghost")
	check_eq(
		screen.board_view.get_drop_cell(),
		BoardMetrics.NO_CELL,
		"an off-turn drag must mark no target cell"
	)
	screen._on_deck_tile_drop_requested(tile_id, point)

	check_eq(controller.staged_count(), 0, "an off-turn drop must stage nothing")
	check(not controller.has_pending(), "an off-turn drop must leave no pending line")
	check_eq(board.get_revision(), revision_before, "an off-turn drop must not touch the board")
	check_eq(_deck_ids(controller), deck_before, "an off-turn drop must leave the deck unchanged")
	check_eq(
		controller.get_session().move_count(),
		moves_before,
		"an off-turn drop must record no move"
	)
	_release(screen)


# --- Helpers ---------------------------------------------------------------


## Stages a legal opening line through the screen and confirms it with the
## screen's own Confirm command.
##
## ADR-011 sections 1, 3, and 11: a legal move is a contiguous line of two or
## more deck tiles of one rank, staged on the board as a whole and confirmed once.
## Returns the committed line result, or null when this hand cannot supply the
## pair or the line was refused. The result is captured from `line_committed` -
## the signal the screen itself renders from - so the fixture and the screen are
## driven by the same commit path (ADR-011 section 5).
func _stage_and_commit_opening_line(screen: GameScreen) -> LineResult:
	if screen == null or screen.controller == null:
		return null
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	if board == null:
		return null
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if pair.size() < TILES_PER_LINE:
		return null
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if cells.size() < TILES_PER_LINE:
		return null

	var captured: Array[LineResult] = []
	var capture: Callable = func(result: LineResult, _phase: int) -> void: captured.append(result)
	controller.line_committed.connect(capture)
	for index: int in range(cells.size()):
		_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[index].tile_id))
		if not screen.stage_at(cells[index]):
			controller.line_committed.disconnect(capture)
			return null
	screen._on_confirm_pressed()
	controller.line_committed.disconnect(capture)
	if captured.is_empty():
		return null
	return captured[0]


## Assembles one illegal line through the screen and requires it to be refused.
##
## The expected verdict is taken from `LineValidator` itself and compared with
## what the controller reports, so the test proves the screen renders the rule
## result rather than deriving one (AGENTS.md section 19).
func _run_refused_line(
	screen: GameScreen,
	pair: Array[TileDefinition],
	cells: Array[Vector2i],
	expected_rejection: int
) -> void:
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	var revision_before: int = board.get_revision()
	var deck_before: PackedStringArray = _deck_ids(controller)

	screen._on_cancel_pressed()
	for index: int in range(cells.size()):
		if index >= pair.size():
			break
		_tap_deck(screen, _index_of_tile(controller.unstaged_human_deck(), pair[index].tile_id))
		if not screen.stage_at(cells[index]):
			check(
				false,
				"the illegal line %s must still stage so its verdict can be reported"
				% str(cells)
			)
			return

	var expected: LineResult = LineValidator.validate(board, controller.staged_snapshots())
	check_not_null(expected, "the line rules must answer for a staged line")
	if expected == null:
		return
	check_eq(
		expected.rejection,
		expected_rejection,
		"the fixture must be the refusal it claims to be: %s" % expected.describe()
	)
	check(not expected.accepted, "the staged line must be illegal")
	check_eq(
		controller.is_line_valid(),
		expected.accepted,
		"the pending verdict must come from the line rules, not the UI"
	)
	check(
		not controller.line_reason().is_empty(),
		"an illegal pending line must explain itself"
	)
	check_eq(
		screen.board_view.get_pending_reason(),
		controller.line_reason(),
		"the board must render the controller's reason verbatim"
	)
	check_eq(
		screen.board_view.get_pending_count(),
		cells.size(),
		"the board must still draw every staged tile of a refused line"
	)

	# ADR-011 section 5: a rejected line changes nothing at all, and the player
	# keeps their tiles and may reassemble.
	screen._on_confirm_pressed()
	check_eq(
		controller.get_session().move_count(),
		0,
		"a refused line must record no move"
	)
	check(controller.is_human_turn(), "a refused line must not consume the turn")
	check_eq(board.get_revision(), revision_before, "a refused line must not touch the board")
	check_eq(board.occupied_count(), 0, "a refused line must not write to the board")
	check_eq(
		controller.staged_count(),
		cells.size(),
		"a refused line must be kept so the player can reassemble it"
	)
	check_eq(_deck_ids(controller), deck_before, "a refused line must keep the player's tiles")


## Taps one deck tile through the row's own input handler.
##
## The screen's layout gives the row a real rectangle in the running game, and
## the smoke tests never wait for a layout pass, so the rectangle is set here
## before the tap is aimed. `tile_rect_at` resolves the tile's current rack slot,
## draws and hit-tests with, so the tap lands on the tile it names.
func _tap_deck(screen: GameScreen, index: int) -> void:
	if screen == null or screen.deck_view == null:
		return
	var row: DeckView = screen.deck_view
	row.size = Vector2(720.0, 96.0)
	var count: int = row.deck_size()
	if count <= 0 or index < 0 or index >= count:
		return
	var rect: Rect2 = row.tile_rect_at(index)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = rect.get_center()
	row._gui_input(event)


## Taps one deck tile the way a finger does, as a press and a release on the same
## spot, through the row's own input handler.
##
## A tap that names a tile the row does not draw as selected is reported on the
## press. A tap on the tile it already draws as selected is the rotation gesture,
## which is reported on the release, so both halves of the gesture are synthesized
## here.
func _tap_deck_fully(screen: GameScreen, index: int) -> void:
	_tap_deck(screen, index)
	if screen == null or screen.deck_view == null:
		return
	var row: DeckView = screen.deck_view
	var count: int = row.deck_size()
	if count <= 0 or index < 0 or index >= count:
		return
	_send_release(row, row.tile_rect_at(index).get_center())


## Returns the global point at the centre of one board cell.
##
## `BoardInputController` converts a global pointer position through the board
## view's own metrics, so a test that drives its handler has to move in the same
## global space the board does.
func _board_point_for(screen: GameScreen, cell: Vector2i) -> Vector2:
	if screen == null or screen.board_view == null:
		return Vector2.ZERO
	screen.board_view.size = Vector2(640.0, 640.0)
	var board_rect: Rect2 = screen.board_view.global_board_rect()
	return BoardMetrics.cell_center(board_rect, cell, BoardEnums.BOARD_WIDTH)


## Returns a global point that is off the board entirely.
func _off_board_point(screen: GameScreen) -> Vector2:
	if screen == null or screen.board_view == null:
		return Vector2(-100000.0, -100000.0)
	screen.board_view.size = Vector2(640.0, 640.0)
	return screen.board_view.global_board_rect().position + Vector2(-50.0, -50.0)


## Sends a synthesized left-button press to the deck row.
##
## The row is given the rectangle its layout would produce, because the smoke
## tests never wait for a layout pass, and the press is aimed with
## `tile_rect_at`, the same geometry the row draws and hit-tests with, so it
## lands on the tile it names.
func _send_press(row: DeckView, position: Vector2) -> void:
	_send_button(row, position, true)


## Sends a synthesized left-button release to the deck row.
func _send_release(row: DeckView, position: Vector2) -> void:
	_send_button(row, position, false)


## Sends one synthesized left-button event to the deck row.
func _send_button(row: DeckView, position: Vector2, pressed: bool) -> void:
	if row == null:
		return
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = position
	row._gui_input(event)


## Sends a synthesized pointer move to the deck row, which is what carries a drag
## from the row to the board.
func _send_motion(row: DeckView, position: Vector2) -> void:
	if row == null:
		return
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = position
	row._gui_input(event)


## Sends a viewport-space motion into the in-progress drag path.
func _send_viewport_motion(row: DeckView, local_point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = row.get_global_transform_with_canvas() * local_point
	row._input(event)


## Starts a drag of one deck tile through the row's own input handler.
##
## A press alone is a tap; the drag only begins once the pointer has travelled
## past `DeckView.DRAG_THRESHOLD`, which is exactly what this synthesizes. Returns
## false when the gesture could not start, which is how an off-turn refusal shows.
func _begin_deck_drag(screen: GameScreen, index: int) -> bool:
	if screen == null or screen.deck_view == null or screen.board_view == null:
		return false
	var row: DeckView = screen.deck_view
	row.size = Vector2(720.0, 96.0)
	screen.board_view.size = Vector2(640.0, 640.0)
	var count: int = row.deck_size()
	if count <= 0 or index < 0 or index >= count:
		return false
	var grab: Vector2 = row.tile_rect_at(index).get_center()
	_send_press(row, grab)
	_send_motion(row, grab + Vector2(DeckView.DRAG_THRESHOLD + 4.0, 0.0))
	return row.is_dragging()


## Returns the row-local pointer position that aims at one board cell.
##
## The screen converts a row-local point to a cell by mapping it through the row's
## own transform and then reading the board's metrics, so a test aiming at a cell
## has to invert exactly that mapping. `BoardMetrics.cell_center` is the board's
## own definition of where that cell is, so a drop lands on the cell the board
## draws the tile on.
func _drag_point_for(screen: GameScreen, cell: Vector2i) -> Vector2:
	if screen == null or screen.deck_view == null or screen.board_view == null:
		return Vector2.ZERO
	screen.board_view.size = Vector2(640.0, 640.0)
	var board_rect: Rect2 = screen.board_view.global_board_rect()
	var center: Vector2 = BoardMetrics.cell_center(board_rect, cell, BoardEnums.BOARD_WIDTH)
	return screen.deck_view.get_global_transform().affine_inverse() * center


## Drags one deck tile through the row's own handlers and releases it on `cell`.
##
## Returns false when the gesture could not start. Whether the drop is accepted is
## not part of the answer: a refused drop is exactly what some tests are checking.
func _drag_deck_tile(screen: GameScreen, index: int, cell: Vector2i) -> bool:
	return _drag_deck_tile_to_point(screen, index, _drag_point_for(screen, cell))


## Drags one deck tile through the row's own handlers and releases it at a raw
## row-local point, which is how a drop off the board is expressed.
func _drag_deck_tile_to_point(screen: GameScreen, index: int, point: Vector2) -> bool:
	if not _begin_deck_drag(screen, index):
		return false
	var row: DeckView = screen.deck_view
	_send_motion(row, point)
	_send_release(row, point)
	return true


## Returns the index of a tile identity in a deck, or -1.
func _index_of_tile(deck: Array[TileDefinition], tile_id: StringName) -> int:
	for index: int in range(deck.size()):
		if deck[index] != null and deck[index].tile_id == tile_id:
			return index
	return -1


## Returns one player's deck as a list of tile identities, in deal order.
func _deck_ids(controller: GameSessionController) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	if controller == null:
		return ids
	for tile: TileDefinition in controller.human_deck():
		if tile != null:
			ids.append(String(tile.tile_id))
	return ids


## Returns `count` cells of the first legal line the frontier offers, in
## row-major order, or as many as the board can supply.
func _line_cells(board: BoardState, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var first: Vector2i = _first_frontier(board)
	if first == BoardMetrics.NO_CELL:
		return cells
	cells.append(first)
	for offset: Vector2i in BoardEnums.neighbor_offsets():
		if cells.size() >= count:
			break
		var neighbor: Vector2i = first + offset
		if board.is_empty_cell(neighbor):
			cells.append(neighbor)
	return cells


## Returns `count` tiles of one rank from a deck, or an empty array.
##
## ADR-012 section 1 makes a Pair the shortest legal hand, so a line is staged
## from held tiles of one rank. Six tiles drawn from four ranks cannot all differ,
## so any dealt deck supplies a pair.
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


## Hosts a game screen with a started match and returns it, or null on failure.
func test_bottom_navigation_menu_and_play_use_existing_commands() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var background: ColorRect = screen.get_node("%Background") as ColorRect
	check_not_null(background, "the ivory canvas uses a ColorRect so it renders without a texture")
	if background != null:
		check_eq(background.color, Color("#F6F2E9"), "the game screen canvas uses the approved ivory")
	check_eq(screen.turn_indicator.text, "Your turn", "the command drawer shows the active turn")
	check(screen.get_node_or_null("%HeaderTurnStatus") == null, "the top message label is removed")
	var opponent_rack: OpponentRackView = screen.get_node("%OpponentRack") as OpponentRackView
	check_eq(opponent_rack._tile_count, DECK_SIZE, "rival tiles reflect the starting hand count")
	opponent_rack.size = Vector2(420, 62)
	screen._fit_opponent_rack_cell_size()
	var overview_cell_side: float = screen.board_view.overview_cell_size()
	check(overview_cell_side > 0.0, "zoomed-out board cell size is available to the rival rack")
	check(is_equal_approx(opponent_rack.tile_rect(0).size.x, overview_cell_side), "rival tiles exactly match a zoomed-out board cell")
	check(is_equal_approx(opponent_rack.tile_rect(0).size.x, opponent_rack.tile_rect(1).size.x), "rival tiles do not shrink to fit as more tiles are shown")
	var gap: float = opponent_rack.tile_rect(1).position.x - opponent_rack.tile_rect(0).end.x
	check(is_equal_approx(gap, overview_cell_side * OpponentRackView.TILE_GAP_RATIO), "rival tiles use even compact gaps from the concept")
	opponent_rack.size.x = 300.0
	check(is_equal_approx(opponent_rack.tile_rect(0).size.x, overview_cell_side), "narrow rack spacing preserves exact board-cell tile size")
	check(opponent_rack.tile_rect(0).position.x >= 0.0 and opponent_rack.tile_rect(DECK_SIZE - 1).end.x <= opponent_rack.size.x, "board-cell rival tiles remain inside a narrow rack")
	check(TilePainter.warmable_art_paths().has(TilePainter.OPPONENT_TILE_BACK_TEXTURE), "the teal opponent back participates in startup preloading")
	check(ResourceLoader.exists(TilePainter.OPPONENT_TILE_BACK_TEXTURE), "the supplied teal opponent back asset is available")
	var nav: GameBottomNavigation = screen.bottom_navigation
	check_eq(nav.buttons.size(), 5, "the bottom bar offers five options")
	check(nav.buttons[&"Play"].disabled, "Play waits for a staged hand")
	check(nav.buttons[&"Undo"].disabled, "Undo waits for staged tiles")
	check_eq(nav.get_node("Actions").get_child(1), nav.buttons[&"Play"], "Play hand stays in the thumb zone")
	for action: StringName in [&"Undo", &"Swap", &"Resign", &"Pot"]:
		var icon_surface: PanelContainer = nav.buttons[action].get_node("Content/IconSurface") as PanelContainer
		var icon_style: StyleBoxFlat = icon_surface.get_theme_stylebox("panel") as StyleBoxFlat
		check_eq(icon_style.bg_color, TABLETOP_THEME.canvas_alt(), "%s icon uses the soft-ivory rounded surface" % action)
		check_eq(icon_surface.custom_minimum_size, Vector2(52, 52), "%s icon has the rounded concept-sized surface" % action)
	var play_button: Button = nav.buttons[&"Play"]
	var play_label: Label = play_button.get_node("Content/Label") as Label
	var play_surface: StyleBoxFlat = play_button.get_theme_stylebox("normal") as StyleBoxFlat
	var disabled_play_surface: StyleBoxFlat = play_button.get_theme_stylebox("disabled") as StyleBoxFlat
	check_eq(play_surface.bg_color, TABLETOP_THEME.honey(), "Play hand uses the concept's honey primary-action fill")
	check_eq(disabled_play_surface.bg_color, TABLETOP_THEME.honey(), "Play hand keeps its honey fill while unavailable")
	check_eq(play_label.get_theme_font("font"), TABLETOP_THEME.SEMIBOLD, "Play hand uses Fredoka Semibold")
	check_eq(play_label.get_theme_color("font_color"), TABLETOP_THEME.ink(), "Play hand label uses deep-teal ink")
	check_eq(play_button.get_node("Content").modulate, Color.WHITE, "disabled Play hand content stays untinted so its text remains deep teal")
	check_eq(play_label.get_theme_font_size("font_size"), 30, "Play hand label matches 22px at the 390px reference width")
	check(is_equal_approx(play_button.custom_minimum_size.y, 78.0), "Play hand height matches the concept proportion")
	check_eq(play_button.size_flags_vertical, Control.SIZE_SHRINK_CENTER, "Play hand keeps its concept height centered in the footer")
	check(is_equal_approx(play_button.size_flags_stretch_ratio, 2.0), "Play hand is wider than secondary actions as in the concept")
	check_eq(nav.get_node("Actions").get_child(4), nav.buttons[&"Pot"], "Pot occupies the right edge")
	check(screen.get_node_or_null("%HeaderSpacer") is Button, "top-right settings remain available")
	check_eq(nav.get_node("Actions").get_child(3), nav.buttons[&"Resign"], "Resign follows Swap")
	check(not nav.buttons.has(&"Share"), "the redundant gameplay Share action is absent")
	check(not nav.buttons[&"Resign"].disabled, "Resign is available during an active match")
	var resign_label: Label = nav.buttons[&"Resign"].get_node("Content/Label") as Label
	check_eq(resign_label.text, "Resign", "the resign action has a clear label")
	check_eq(nav.buttons[&"Resign"].tooltip_text, "Resign this match", "the resign action has a concise tooltip")
	check_eq(nav.buttons[&"Resign"].accessibility_name, "Resign this match", "the resign action has an accessible name")
	check(ResourceLoader.exists("res://assets/ui/modern_tabletop/flag.svg"), "Resign uses a local flag icon")
	check(screen.get_node_or_null("%Share") is Share, "the results screen retains the configured Share plugin node")
	check(not nav.buttons.has(&"Menu"), "bottom Menu is replaced by Pot")
	check_eq(nav.buttons[&"Pot"].get_node("Content/Label").text, "Pot", "tile-pot action has a clear label")
	var pair: Array[TileDefinition] = _rank_pair(screen.controller.human_deck(), 2)
	var cells: Array[Vector2i] = _line_cells(screen.controller.get_board(), 2)
	if not check(pair.size() == 2 and cells.size() == 2, "fixture supplies an opening pair"):
		_release(screen)
		return
	for index: int in range(2):
		screen.controller.stage_tile(pair[index].tile_id, cells[index])
	check(not nav.buttons[&"Play"].disabled, "staging enables Play")
	check(not nav.buttons[&"Undo"].disabled, "Undo becomes available for staged tiles")
	(screen.get_node("%HeaderSpacer") as Button).pressed.emit()
	check(screen.command_drawer.is_open, "Menu opens the existing settings drawer")
	check(screen.controller.has_pending(), "opening Menu preserves the staged hand")
	screen.command_drawer.set_open(false, false)
	check((screen.get_node("%HeaderSpacer") as Button).has_focus(), "closing the drawer returns focus to the header menu")
	nav.buttons[&"Play"].pressed.emit()
	check_eq(screen.controller.get_session().move_count(), 1, "Play commits the staged hand")
	check_eq(screen.turn_indicator.text, "Rival's turn", "turn status follows turn changes")
	for action: StringName in [&"Play", &"Swap", &"Undo"]:
		check(nav.buttons[action].disabled, "%s is unavailable off-turn" % action)
	check(not nav.buttons[&"Resign"].disabled, "Resign remains available off-turn")
	_release(screen)


func test_bottom_navigation_swap_uses_existing_selection_and_confirmation() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var swap: Button = screen.bottom_navigation.buttons[&"Swap"]
	swap.pressed.emit()
	check(screen.is_swap_mode(), "Swap starts rack selection")
	check(not screen.command_drawer.is_open, "the rack stays accessible while selecting")
	screen._on_deck_tile_toggled(screen.controller.human_deck()[0].tile_id)
	check(swap.disabled, "Swap stays disabled while selecting tiles")
	swap.pressed.emit()
	check(not screen.command_drawer.is_open, "Swap does not open the settings menu")
	(screen.get_node("%HeaderSpacer") as Button).pressed.emit()
	check(screen.command_drawer.is_open, "the header menu opens swap confirmation controls")
	check(screen.swap_confirm_button.visible and not screen.swap_confirm_button.disabled, "selected tiles can be returned")
	check_eq(screen.swap_tiles().size(), 1, "reopening keeps the selected tile")
	screen.swap_cancel_button.pressed.emit()
	check(not screen.is_swap_mode(), "Keep tiles cancels the swap")
	_release(screen)


func test_hub_navigation_buttons_request_the_hub() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var requests: Array[int] = []
	screen.hub_requested.connect(func() -> void: requests.append(1))
	(screen.get_node("%HeaderSpacer") as Button).pressed.emit()
	(screen.get_node("%MenuHubButton") as Button).pressed.emit()
	check_eq(requests.size(), 1, "the in-menu hub action uses the existing hub navigation signal")
	(screen.get_node("%BackToHubButton") as Button).pressed.emit()
	check_eq(requests.size(), 2, "the top-left back button requests the same hub navigation")
	_release(screen)


func test_pot_timer_updates_without_rebuilding_board_and_clears_swap_on_expiry() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var clock: Label = screen.turn_clock_label
	check_eq(clock.text, "1:00", "human opens with a 1:00 text countdown")
	check_eq(screen.turn_status_label.text, "Your turn", "concept row names the active human turn")
	check(screen.human_score_panel.get_theme_stylebox("panel") is StyleBoxEmpty, "human avatar and score have no surrounding panel")
	check(screen.ai_score_panel.get_theme_stylebox("panel") is StyleBoxEmpty, "rival avatar and score have no surrounding panel")
	check(not (screen.human_score_panel.get_node("HumanScoreBox/Portrait") as FramedPlayerAvatar).show_ring, "human avatar has no teal ring")
	check(not (screen.ai_score_panel.get_node("AiScoreBox/Portrait") as FramedPlayerAvatar).show_ring, "rival avatar has no teal ring")
	var refreshes: Array[int] = []
	screen.controller.state_changed.connect(func() -> void: refreshes.append(1))
	var turn: TurnState = screen.controller.get_session().get_turn_state()
	screen.controller.update_turn_clock(turn.deadline_unix_seconds - 20.0)
	check_eq(clock.text, "0:20", "the compact countdown follows controller seconds")
	check(refreshes.is_empty(), "clock ticks do not rebuild the board or interrupt input")
	var art: Control = screen.human_score_panel.get_node("HumanScoreBox") as Control
	var art_origin: Vector2 = art.position
	for seconds: int in range(10, 0, -1):
		screen.controller.update_turn_clock(turn.deadline_unix_seconds - float(seconds))
		check_eq(clock.text, "0:%02d" % seconds, "countdown continues without an avatar warning")
		check_eq(art.position, art_origin, "human avatar and score stay still at %d seconds" % seconds)
	check(not screen.human_score_panel.has_node("HumanScoreBox/TurnOutline"), "human avatar has no timer border")
	check(not screen.ai_score_panel.has_node("AiScoreBox/TurnOutline"), "rival avatar has no timer border")
	check(refreshes.is_empty(), "repeated warning ticks do not rebuild the board")
	screen.bottom_navigation.buttons[&"Swap"].pressed.emit()
	screen._on_deck_tile_toggled(screen.controller.human_deck()[0].tile_id)
	screen.command_drawer.open_settings()
	screen.controller.update_turn_clock(turn.deadline_unix_seconds)
	check(not screen.is_swap_mode(), "expiry clears swap selection")
	check_eq(clock.text, "1:00", "rival starts with a full text countdown")
	check_eq(screen.turn_status_label.text, "Rival's turn", "concept row names the active rival turn")
	check_eq(screen.get_node("%BoardMessageLabel").text, "Time up, play moves to other player", "expiry notice appears below the board")
	check(screen.feedback_layer.find_child("ToastLayout", true, false) == null, "expiry creates no toast overlay")
	_release(screen)


func test_turn_clock_uses_concept_format_type_and_position() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var expected: Dictionary = {
		0: "0:00", 1: "0:01", 9: "0:09", 42: "0:42", 59: "0:59", 60: "1:00", 125: "2:05", -1: "0:00",
	}
	for seconds: int in expected:
		check_eq(screen._format_turn_clock(seconds), expected[seconds], "seconds format as compact m:ss")
	check_eq(screen.turn_clock_label.get_theme_font_size("font_size"), 16, "timer uses the enlarged label size")
	check_eq(screen.turn_clock_label.get_theme_color("font_color"), Color("#173D42"), "timer uses deep teal ink")
	check_eq(screen.turn_clock_label.get_theme_font("font"), TABLETOP_THEME.SEMIBOLD, "timer uses Fredoka Semibold")
	check_eq(screen.turn_status_label.get_theme_font_size("font_size"), 16, "turn label uses the enlarged label size")
	check_eq(screen.turn_status_label.get_theme_font("font"), TABLETOP_THEME.REGULAR, "turn label remains Fredoka Regular")
	check(screen.turn_clock_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "timer aligns at the right edge of its row")
	check(screen.turn_info_panel.get_index() > screen.get_node("Root/Column/Hud").get_index() and screen.turn_info_panel.get_index() < screen.get_node("Root/Column/Body").get_index(), "turn information sits between the scores and board")
	var info_surface: StyleBoxFlat = screen.turn_info_panel.get_theme_stylebox("panel") as StyleBoxFlat
	check(info_surface != null and info_surface.bg_color == TABLETOP_THEME.CANVAS_ALT, "turn information uses the soft-ivory surface distinct from the canvas")
	var board_frame: NinePatchRect = screen.get_node("%BoardFrame") as NinePatchRect
	screen._fit_turn_info_margins()
	var turn_panel_rect: Rect2 = screen.turn_info_panel.get_global_rect()
	var board_frame_rect: Rect2 = board_frame.get_global_rect()
	check(is_equal_approx(info_surface.content_margin_left, board_frame_rect.position.x - turn_panel_rect.position.x), "Your turn text starts at the board frame's left outer edge")
	check(is_equal_approx(info_surface.content_margin_right, turn_panel_rect.end.x - board_frame_rect.end.x), "the timer text ends at the board frame's right outer edge")
	check_eq(screen.turn_info_row.get_child(0), screen.turn_status_label, "turn caption anchors at the left")
	check_eq(screen.turn_info_row.get_child(1), screen.get_node("%OpponentRack"), "compact rival tiles sit between the caption and timer")
	check_eq(screen.turn_info_row.get_child(2), screen.turn_clock_label, "timer anchors at the right")
	check_eq(screen.available_tiles_label.text, "%d left" % screen.controller.remaining_tiles(), "pot count follows the concept's 'N left' label")
	check_eq(screen.available_tiles_label.get_theme_font_size("font_size"), 14, "pot count uses the enlarged label size")
	check_eq(screen.available_tiles_label.get_theme_color("font_color"), Color("#173D42"), "pot count uses the concept's deep teal")
	check_eq(screen.available_tiles_label.get_theme_font("font"), TABLETOP_THEME.REGULAR, "pot count uses the regular concept font")
	check(screen.tile_pile_view._stack_rect.end.y < screen.available_tiles_label.position.y, "pot count sits below the stack icon")
	check_eq(TilePileView.POT_TEXTURE.resource_path, "res://assets/ui/tile_pot.png", "pot uses supplied tile pot artwork")
	_release(screen)


func test_game_header_matches_modern_tabletop_concept() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var brand: Label = screen.get_node("%Brand") as Label
	var divider: ColorRect = screen.get_node("%HeaderDivider") as ColorRect
	var back_button: Button = screen.get_node("%BackToHubButton") as Button
	var menu_button: Button = screen.get_node("%HeaderSpacer") as Button
	var human_portrait: TextureRect = screen.human_score_panel.get_node("HumanScoreBox/Portrait") as TextureRect
	var rival_portrait: TextureRect = screen.ai_score_panel.get_node("AiScoreBox/Portrait") as TextureRect
	var human_art: Control = screen.human_score_panel.get_node("HumanScoreBox") as Control
	var rival_art: Control = screen.ai_score_panel.get_node("AiScoreBox") as Control
	var human_title: Label = human_art.get_node("HumanScoreTitle") as Label
	var rival_title: Label = rival_art.get_node("AiScoreTitle") as Label
	check_eq(brand.get_theme_font("font"), TABLETOP_THEME.BOLD, "the header wordmark uses the requested bold weight")
	check_eq(brand.get_theme_font_size("font_size"), 22, "the wordmark uses the compact concept header size")
	check_eq(brand.get_theme_color("font_color"), Color("#173D42"), "the wordmark uses deep teal")
	check(human_portrait.scale.is_equal_approx(Vector2.ONE * 1.25), "the human avatar matches the enlarged concept scale")
	check(rival_portrait.scale.is_equal_approx(Vector2.ONE * 1.25), "the rival avatar matches the enlarged concept scale")
	var human_visual_right: float = human_portrait.position.x + human_portrait.size.x * 1.125
	var rival_visual_left: float = rival_portrait.position.x - rival_portrait.size.x * 0.125
	check(human_title.position.x - human_visual_right >= 13.0, "human name and score clear the scaled avatar with a concept-sized gap")
	check(rival_visual_left - rival_title.position.x - rival_title.size.x >= 13.0, "rival name and score clear the scaled avatar with a concept-sized gap")
	check(absf(human_portrait.get_global_rect().get_center().y - rival_portrait.get_global_rect().get_center().y) < 1.0,
		"enlarged avatars stay vertically aligned")
	check(brand.size_flags_horizontal == Control.SIZE_EXPAND_FILL and brand.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"the wordmark stays centered between equal-width header controls")
	check(divider.get_index() == brand.get_parent().get_index() + 1, "a horizontal divider sits immediately below the wordmark row")
	check_eq(divider.custom_minimum_size.y, 1.0, "the wordmark divider is a thin concept-style line")
	check_eq(back_button.icon.resource_path, "res://assets/ui/modern_tabletop/game_back.svg", "the back control uses the concept chevron")
	check_eq(back_button.get_theme_color("icon_normal_color"), TABLETOP_THEME.INK, "the chevron uses the primary ink color")
	check_eq(menu_button.icon.resource_path, "res://assets/ui/modern_tabletop/menu.svg", "the menu control uses the concept ellipsis")
	check(not back_button.expand_icon and not menu_button.expand_icon, "header icons keep their intrinsic compact scale inside the touch targets")
	_release(screen)


func test_board_uses_supplied_sage_cells_and_rounded_teal_frame() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var frame: NinePatchRect = screen.get_node("%BoardFrame") as NinePatchRect
	check_eq(BoardTileLayer.DEFAULT_CELL_TEXTURE.resource_path, "res://assets/board/board_cell_default.png", "empty cells use the supplied sage artwork")
	check_eq(BoardTileLayer.GRID_LINE, TABLETOP_THEME.INK, "cell spacing uses the deep-teal frame colour")
	check_eq(BoardTileLayer.CELL_INSET, 1.0, "adjacent board cells leave a compact 2px separator")
	check_eq(BoardView.PADDING, 20.0, "board has a substantial deep-teal outer border")
	check_eq(frame.patch_margin_left, 40, "frame nine-patch preserves rounded corners at board scale")
	check(is_equal_approx(float(frame.patch_margin_left) * BoardView.PADDING / BoardView.FRAME_PATCH_INSET, BoardView.PADDING), "the frame inner edge meets the board without a gap")
	check_eq(frame.texture.resource_path, "res://assets/ui/modern_tabletop/board_frame.svg", "board retains the deep-teal rounded frame artwork")
	_release(screen)


func test_notices_use_board_caption_and_restore_the_current_turn() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var turn_status: Label = screen.turn_indicator
	var board_message: Label = screen.get_node("%BoardMessageLabel")
	check(screen.get_node_or_null("%HeaderTurnStatus") == null, "no top message label is present")
	check_eq(board_message.text, "Pinch to explore the board", "the board hint appears below the board by default")
	check_eq(board_message.get_theme_font_size("font_size"), 14, "the board hint uses the concept caption size")
	check_eq(board_message.get_theme_color("font_color"), Color("#173D42"), "the board hint uses the concept deep-teal text")
	check(board_message.get_parent() == screen.get_node("Root/Column") and board_message.get_index() < screen.deck_bar.get_index(),
		"the board hint sits between the board and the tile rack")
	screen._on_notice(GameSessionController.NO_VALID_MOVE_NOTICE)
	check_eq(board_message.text, GameSessionController.NO_VALID_MOVE_NOTICE, "notification occupies the concept hint position")
	check_eq(turn_status.text, "Your turn", "notification leaves the turn status unchanged")
	check(screen.feedback_layer.find_child("ToastLayout", true, false) == null, "notifications never create a board overlay")
	screen._refresh_all()
	check_eq(board_message.text, GameSessionController.NO_VALID_MOVE_NOTICE, "HUD refresh preserves the notification")
	for message: String in [GameSessionController.INVALID_POKER_HAND_NOTICE, GameSessionController.NOT_CONNECTED_NOTICE]:
		screen._on_notice(message)
		check_eq(board_message.text, message, "placement warning appears below the board: %s" % message)
		check(screen._is_header_notice(message), "placement warning uses the below-board notification route: %s" % message)
		check_eq(screen._board_preview_reason(message), "", "placement warning is omitted from the board render state: %s" % message)
		check(BoardEffectLayer.HEADER_ONLY_REASONS.has(message), "placement warning is suppressed on the board: %s" % message)
	screen._on_notice("That cell is already taken")
	check_eq(board_message.text, "That cell is already taken", "latest message replaces the previous message")
	check(not screen._header_notice_timer.is_stopped(), "a fresh notification restarts its display period")
	screen._header_notice_timer.timeout.emit()
	check_eq(turn_status.text, "Your turn", "expiry leaves current turn status unchanged")
	check_eq(board_message.text, "Pinch to explore the board", "expiry restores the board hint")
	check(screen._header_notice_timer.is_stopped(), "expiry leaves no running notice timer")
	var turn: TurnState = screen.controller.get_session().get_turn_state()
	screen.controller.update_turn_clock(turn.deadline_unix_seconds)
	check_eq(board_message.text, GameSessionController.TURN_TIMEOUT_NOTICE, "timeout notice survives the automatic turn handover")
	screen._header_notice_timer.timeout.emit()
	check_eq(turn_status.text, "Rival's turn", "expiry leaves the new player's turn status unchanged")
	check_eq(board_message.text, "Pinch to explore the board", "timeout expiry restores the board hint")
	screen._on_notice("A temporary message")
	screen._on_restart_pressed()
	check_eq(turn_status.text, "Your turn", "a new match clears old notifications")
	check_eq(board_message.text, "Pinch to explore the board", "a new match restores the board hint")
	check(screen._header_notice_timer.is_stopped(), "restart cancels the old notification timer")
	screen._on_notice("A temporary message")
	var session: GameSessionState = screen.controller.get_session()
	session.finish(TurnEnums.MatchOutcome.DRAW, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))
	check_eq(turn_status.text, "Match over", "match end updates the turn status")
	check_eq(board_message.text, "Pinch to explore the board", "match end clears the transient notice")
	_release(screen)


func test_placement_warning_in_board_caption_clears_when_the_line_is_fixed() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var pair: Array[TileDefinition] = _rank_pair(screen.controller.human_deck(), 2)
	var cells: Array[Vector2i] = _line_cells(screen.controller.get_board(), 2)
	if not check(pair.size() == 2 and cells.size() == 2, "fixture has an opening pair"):
		_release(screen)
		return
	screen.controller.stage_tile(pair[0].tile_id, cells[0])
	check_eq(screen.get_node("%BoardMessageLabel").text, GameScreen.OPENING_NOTICE_TEXT, "single-tile opening warning appears below the board")
	screen.controller.stage_tile(pair[1].tile_id, cells[1])
	check_eq(screen.get_node("%BoardMessageLabel").text, "Pinch to explore the board", "fixing the line restores the board hint")
	_release(screen)


func test_command_drawer_opens_closes_and_returns_to_rack_for_swap() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var drawer: GameCommandDrawer = screen.command_drawer
	for removed: String in ["ConfirmButton", "RotateButton", "SwapButton", "CancelButton", "MatchToggle", "MenuTab"]:
		check(drawer.find_child(removed, true, false) == null, "%s is absent from the drawer" % removed)
	check(not drawer.is_open, "drawer starts folded")
	(screen.get_node("%HeaderSpacer") as Button).pressed.emit()
	check(drawer.panel.visible and drawer.scrim.visible, "open menu blocks covered board input")
	for option: String in ["DifficultyPicker", "RestartButton", "MenuHubButton"]:
		check((screen.get_node("%" + option) as Control).is_visible_in_tree(), "%s is visible immediately" % option)
	drawer.set_open(false, false)
	drawer.open_settings()
	for option: String in ["DifficultyPicker", "RestartButton", "MenuHubButton"]:
		check((screen.get_node("%" + option) as Control).is_visible_in_tree(), "%s stays available when reopened from settings" % option)
	screen._on_swap_pressed()
	check(screen.is_swap_mode(), "swap command enters rack selection")
	check(not drawer.is_open and not drawer.scrim.visible, "swap makes rack accessible")
	check(screen.swap_confirm_button.disabled, "an empty swap cannot be submitted")
	screen._on_deck_tile_toggled(screen.controller.human_deck()[0].tile_id)
	check(not screen.swap_confirm_button.disabled, "a selected swap can be submitted")
	_release(screen)


func test_command_preview_matches_commit_without_mutating_board() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), 2)
	var cells: Array[Vector2i] = _line_cells(controller.get_board(), 2)
	if not check(pair.size() == 2 and cells.size() == 2, "fixture supplies an opening pair"):
		_release(screen)
		return
	var revision: int = controller.get_board().get_revision()
	for index: int in range(2):
		controller.stage_tile(pair[index].tile_id, cells[index])
	var preview: ScoreTransaction = controller.pending_score_preview()
	if check_not_null(preview, "valid staged hand supplies a preview"):
		check_eq(controller.get_board().get_revision(), revision, "preview does not commit tiles")
		check_eq(screen.get_node("%TotalPreview").text, str(preview.total_points()), "drawer renders scorer total")
		var result: LineResult = controller.commit_line()
		check_eq(result.get_total_points(), preview.total_points(), "preview equals committed award")
		check_eq(screen.floating_scores.active_count(), 1, "a real committed move shows one total")
		check_eq((screen.floating_scores.get_child(0) as Label).text, str(result.get_total_points()), "popup equals the actual committed award")
		check_eq(screen.get_node("%TotalPreview").text, "—", "preview clears when the turn passes")
	_release(screen)


func _finish_opening_deal(screen: GameScreen) -> void:
	screen.deck_view.size = Vector2(720, 96)
	screen.board_view.size = Vector2(640, 640)
	screen._refresh_all()
	screen.deal_layer._process(10.0)


func _finish_hand_score_feedback(screen: GameScreen) -> void:
	var reveal: ScoreRevealLayer = screen.board_view.reveal_layer
	reveal._process(
		reveal.ripple_duration() + 0.1
	)
	# Advance the popup lifecycle without waiting for rendered frames.
	for popup: Node in screen.floating_scores.get_children():
		popup.free()


func test_committed_hand_returns_to_centered_overview_after_scores_and_refill() -> void:
	for score_first: bool in [true, false]:
		var screen: GameScreen = _host_screen()
		if screen == null:
			return
		_finish_opening_deal(screen)
		screen.board_view.pan_by(Vector2(100, 60))
		var result: LineResult = _stage_and_commit_opening_line(screen)
		if not check(result != null and result.was_committed(), "fixture commits a scored hand"):
			_release(screen)
			continue
		check(screen.controller.human_score() > 0, "points have been awarded")
		check(screen.deal_layer.is_playing(), "replacement tiles are being dealt")
		check(screen.board_view.reveal_layer.has_marks(), "score feedback is visible")
		screen._process(0.0)
		check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "commit keeps the close view during effects")
		if score_first:
			_finish_hand_score_feedback(screen)
		else:
			screen.deal_layer._process(10.0)
		screen._process(0.0)
		check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "camera waits for both scoring and refill")
		if score_first:
			screen.deal_layer._process(10.0)
		else:
			_finish_hand_score_feedback(screen)
		screen._process(0.0)
		check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "completed hand returns to full board")
		check(screen.board_view.global_board_rect().get_center().is_equal_approx(screen.board_view.global_visible_rect().get_center()), "overview centers the whole board")
		check(not screen.is_processing(), "camera completion stops polling")
		screen.board_view.set_close_view(true)
		check(screen.board_view.global_board_rect().get_center().is_equal_approx(screen.board_view.global_visible_rect().get_center()), "old pan was discarded")
		screen._process(0.0)
		check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "completed reset runs only once")
		_release(screen)


func test_hand_overview_handles_reduced_motion_and_partial_or_empty_refill() -> void:
	var reduced: Variant = ProjectSettings.get_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	for available: int in [0, 1, 2]:
		var screen: GameScreen = _host_screen()
		if screen == null:
			continue
		_finish_opening_deal(screen)
		ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, available == 2)
		var source: TileSource = screen.controller.get_session().get_tile_source()
		while screen.controller.remaining_tiles() > available:
			source.draw()
		var result: LineResult = _stage_and_commit_opening_line(screen)
		if check(result != null and result.was_committed(), "limited-pot hand commits"):
			if available == 2:
				screen.deal_layer._finish_deal_immediately()
			else:
				screen.deal_layer._process(10.0)
			screen._process(0.0)
			check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "score display still finishes before overview")
			_finish_hand_score_feedback(screen)
			screen._process(0.0)
			check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "overview does not require a full animated refill")
		ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, reduced)
		_release(screen)


func test_rival_hand_overview_waits_for_placement_refill_and_score_feedback() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	_finish_opening_deal(screen)
	_commit_rival_opening(screen)
	screen._process(0.0)
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "rival flight keeps the current camera")
	screen.rival_move_layer._process(screen.rival_move_layer.total_duration())
	screen._process(0.0)
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "rival score feedback remains visible after refill")
	_finish_hand_score_feedback(screen)
	screen._process(0.0)
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "completed rival hand returns to overview")
	_release(screen)


func test_hand_overview_does_not_interrupt_new_placement_or_survive_restart() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	_finish_opening_deal(screen)
	screen._process(0.0)
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "opening deal alone does not reset camera")
	screen._on_confirm_pressed()
	check(not screen._hand_overview_pending, "refused hand does not schedule a reset")
	_commit_rival_opening(screen)
	screen.rival_move_layer._process(screen.rival_move_layer.total_duration())
	check(_begin_deck_drag(screen, 0), "next player can start a placement")
	screen._process(0.0)
	check(not screen._hand_overview_pending, "new placement supersedes the old reset")
	screen.deck_view.cancel_drag()
	_finish_hand_score_feedback(screen)
	screen._process(0.0)
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "old effects cannot zoom out the new turn's placement")
	screen._set_hand_overview_pending(true)
	screen._on_restart_pressed()
	check(not screen._hand_overview_pending, "restart discards pending camera reset")
	screen._process(0.0)
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "new match keeps its starting close view")
	_release(screen)


func test_overview_drop_zooms_after_acceptance_and_centers_the_tile() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	screen._set_board_zoom(false)
	check(_begin_deck_drag(screen, 0), "overview deck drag starts")
	var cell := Vector2i(5, 5)
	var point: Vector2 = _drag_point_for(screen, cell)
	_send_motion(screen.deck_view, point)
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "aiming keeps the full board visible")
	_send_release(screen.deck_view, point)
	check_eq(screen.controller.staged_cells(), [cell], "drop stages the intended overview cell")
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "accepted overview drop zooms to 2x")
	var tile_center: Vector2 = BoardMetrics.cell_center(screen.board_view.global_board_rect(), cell)
	check(tile_center.is_equal_approx(screen.board_view.global_visible_rect().get_center()), "placed interior tile is centered")
	check_eq(screen.board_view.cell_at_global(tile_center), cell, "hit testing follows the focused camera")
	check_eq(screen.controller.get_board().get_revision(), 0, "camera focus does not commit the pending tile")
	screen._set_board_zoom(false)
	check(_begin_deck_drag(screen, 0), "second drag starts")
	_send_release(screen.deck_view, _drag_point_for(screen, cell))
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "occupied-cell refusal keeps overview")
	check_eq(screen.controller.staged_count(), 1, "refused drop adds no tile")
	_release(screen)


func test_moving_staged_tile_in_overview_focuses_destination_but_rotation_does_not() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var origin := Vector2i(5, 5)
	var destination := Vector2i(6, 5)
	screen.controller.select_deck_tile(screen.controller.human_deck()[0].tile_id)
	check(screen.stage_at(origin), "fixture stages one tile")
	screen._set_board_zoom(false)
	var point: Vector2 = _board_point_for(screen, origin)
	_send_board_touch(screen, 2, point, true)
	_send_board_touch(screen, 2, point, false)
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "rotation leaves overview unchanged")
	_send_board_touch(screen, 2, point, true)
	var target: Vector2 = _board_point_for(screen, destination)
	_send_board_touch_drag(screen, 2, target)
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "staged drag does not zoom before release")
	_send_board_touch(screen, 2, target, false)
	check_eq(screen.controller.staged_cells(), [destination], "touch drop moves the staged tile")
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "accepted staged move zooms in")
	var center: Vector2 = BoardMetrics.cell_center(screen.board_view.global_board_rect(), destination)
	check(center.is_equal_approx(screen.board_view.global_visible_rect().get_center()), "camera follows the new cell")
	_release(screen)


func test_placement_focus_clamps_edges_and_preserves_other_zoom_levels() -> void:
	var view := BoardView.new()
	for fill: bool in [false, true]:
		view.fill_available_space = fill
		for dimensions: Vector2 in [Vector2(320, 400), Vector2(540, 700), Vector2(800, 320)]:
			view.size = dimensions
			for cell: Vector2i in [Vector2i(0, 0), Vector2i(11, 0), Vector2i(0, 11), Vector2i(11, 11), Vector2i(5, 6)]:
				view.set_close_view(false)
				view.focus_placed_tile(cell)
				var visible: Rect2 = view.global_visible_rect()
				var board: Rect2 = view.global_board_rect()
				var tile: Rect2 = BoardMetrics.cell_rect(board, cell)
				check_eq(view.zoom, BoardView.CLOSE_ZOOM, "overview switches to close view at every viewport size")
				check(board.grow(0.01).encloses(visible), "focused board fills viewport without blank margins")
				check(visible.grow(0.01).encloses(tile), "focused tile remains fully visible")
				if cell.x == 0:
					check(is_equal_approx(board.position.x, visible.position.x), "left edge reaches pan limit")
				elif cell.x == 11:
					check(is_equal_approx(board.end.x, visible.end.x), "right edge reaches pan limit")
				else:
					check(is_equal_approx(tile.get_center().x, visible.get_center().x), "interior tile centers horizontally")
				if cell.y == 0:
					check(is_equal_approx(board.position.y, visible.position.y), "top edge reaches pan limit")
				elif cell.y == 11:
					check(is_equal_approx(board.end.y, visible.end.y), "bottom edge reaches pan limit")
				else:
					check(is_equal_approx(tile.get_center().y, visible.get_center().y), "interior tile centers vertically")
				var camera: Rect2 = view.global_board_rect()
				view.focus_placed_tile(Vector2i(3, 3))
				check_eq(view.global_board_rect(), camera, "already-close placement preserves pan")
	view.set_close_view(false)
	view.focus_placed_tile(BoardMetrics.NO_CELL)
	check_eq(view.zoom, BoardView.OVERVIEW_ZOOM, "invalid cell cannot zoom")
	var midpoint: Vector2 = view.global_visible_rect().get_center()
	view.pinch_by(1.5, midpoint, midpoint)
	var partial_camera: Rect2 = view.global_board_rect()
	view.focus_placed_tile(Vector2i(5, 5))
	check_eq(view.zoom, 1.5, "intermediate pinch zoom is retained")
	check_eq(view.global_board_rect(), partial_camera, "intermediate camera position is retained")
	view.free()


func test_pinch_zoom_keeps_anchor_and_mouse_wheel_steps() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	screen.board_view.size = Vector2(640.0, 640.0)
	screen._set_board_zoom(false)
	var center: Vector2 = screen.board_view.global_visible_rect().get_center()
	var left: Vector2 = center + Vector2(-60.0, 20.0)
	var right: Vector2 = center + Vector2(60.0, 20.0)
	var anchor: Vector2 = ((left + right) * 0.5 - screen.board_view.global_board_rect().position) / screen.board_view.global_board_rect().size
	_send_board_touch(screen, 4, left, true)
	_send_board_touch(screen, 9, right, true)
	_send_board_touch_drag(screen, 9, right + Vector2(60.0, 0.0))
	check(is_equal_approx(screen.board_view.zoom, 1.5), "finger separation smoothly scales the board")
	var rect: Rect2 = screen.board_view.global_board_rect()
	var midpoint: Vector2 = (left + right + Vector2(60.0, 0.0)) * 0.5
	check((rect.position + rect.size * anchor).is_equal_approx(midpoint), "pinch anchor follows the moving midpoint")
	check(screen.get_node_or_null("%ZoomInButton") == null and screen.get_node_or_null("%ZoomOutButton") == null,
		"the header no longer includes zoom buttons")
	_send_board_touch_drag(screen, 9, right + Vector2(600.0, 0.0))
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "pinch cannot exceed the close view")
	_send_board_touch_drag(screen, 9, left + Vector2(10.0, 0.0))
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "pinch cannot shrink below the full board")
	_send_board_touch(screen, 4, left, false)
	_send_board_touch(screen, 9, right, false)
	var wheel := InputEventAction.new()
	wheel.pressed = true
	wheel.action = &"mouse_wheel_zoom_in"
	screen._unhandled_input(wheel)
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "mouse wheel retains its existing 2x step")
	wheel.action = &"mouse_wheel_zoom_out"
	screen._unhandled_input(wheel)
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "mouse wheel retains its existing 1x step")
	_release(screen)


func test_pinch_cancels_staged_drag_and_waits_for_all_fingers() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var cell := Vector2i(5, 5)
	screen.controller.select_deck_tile(screen.controller.human_deck()[0].tile_id)
	check(screen.stage_at(cell), "fixture stages one tile")
	var point: Vector2 = _board_point_for(screen, cell)
	var rotation: int = screen.controller.staged_snapshots()[0].get_rotation()
	_send_board_touch(screen, 2, point, true)
	_send_board_touch_drag(screen, 2, point + Vector2(100.0, 0.0))
	_send_board_touch(screen, 7, point + Vector2(0.0, 100.0), true)
	check_eq(screen._move_from_cell, BoardMetrics.NO_CELL, "second finger abandons staged tile movement")
	_send_board_touch(screen, 7, _off_board_point(screen), false)
	_send_board_touch_drag(screen, 2, _off_board_point(screen))
	_send_board_touch(screen, 2, _off_board_point(screen), false)
	check_eq(screen.controller.staged_count(), 1, "pinch releases cannot remove the staged tile")
	check_eq(screen.controller.staged_cells()[0], cell, "pinch does not move the staged tile")
	check_eq(screen.controller.staged_snapshots()[0].get_rotation(), rotation, "pinch does not rotate the staged tile")
	check_eq(screen.controller.get_board().get_revision(), 0, "pinch never commits a move")
	_send_board_touch(screen, 2, point, true)
	_send_board_touch(screen, 2, point, false)
	check_eq(screen.controller.staged_snapshots()[0].get_rotation(), (rotation + 1) % TileEnums.ROTATION_COUNT,
		"a fresh single-finger tap still rotates the staged tile")
	_send_board_touch(screen, 2, point, true)
	_send_board_touch(screen, 2, _off_board_point(screen), false, true)
	check_eq(screen.controller.staged_count(), 1, "a canceled tile touch must not drop or remove its tile")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.device = -1
	mouse.position = point
	mouse.pressed = true
	screen.board_input._unhandled_input(mouse)
	mouse.pressed = false
	screen.board_input._unhandled_input(mouse)
	check_eq(screen.controller.staged_snapshots()[0].get_rotation(), (rotation + 1) % TileEnums.ROTATION_COUNT,
		"emulated mouse events cannot replay the touch as an extra rotation")
	_release(screen)


func test_pinch_ignores_outside_touches_and_recovers_from_cancel() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	screen.board_view.size = Vector2(640.0, 640.0)
	var center: Vector2 = screen.board_view.global_visible_rect().get_center()
	_send_board_touch(screen, 1, _off_board_point(screen), true)
	_send_board_touch(screen, 8, center, true)
	_send_board_touch_drag(screen, 8, center + Vector2(30.0, 0.0))
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "a touch beginning outside the board cannot start a pinch")
	check(screen.board_view._camera_center.x < 0.5, "single-finger panning still works")
	_send_board_touch(screen, 8, center, false, true)
	check(screen.board_input._touches.is_empty(), "canceled touches release their capture")
	screen.board_input.enabled = false
	_send_board_touch(screen, 1, center - Vector2(60.0, 0.0), true)
	_send_board_touch(screen, 8, center + Vector2(60.0, 0.0), true)
	_send_board_touch(screen, 12, center + Vector2(0.0, 60.0), true)
	_send_board_touch_drag(screen, 12, center + Vector2(0.0, 100.0))
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "an extra finger does not alter the active pinch")
	_send_board_touch_drag(screen, 8, center)
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "pinching remains available when tile placement is disabled")
	screen.board_input.reset()
	_send_board_touch_drag(screen, 8, center + Vector2(100.0, 0.0))
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "reset discards stale gesture events")
	_release(screen)


func _send_board_touch(screen: GameScreen, index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	if screen.board_input._touches.has(index):
		screen.board_input._input(event)
	else:
		screen.board_input._unhandled_input(event)


func _send_board_touch_drag(screen: GameScreen, index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	screen.board_input._input(event)


func test_rack_drag_eases_live_insertion_and_keeps_tile_identity() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var deck: Array[TileDefinition] = screen.controller.human_deck()
	var row: DeckView = screen.deck_view
	check(_begin_deck_drag(screen, 1), "rack drag begins")
	var before: Rect2 = row.tile_global_rect_for(deck[1].tile_id)
	var neighbor_before: Rect2 = row.tile_global_rect_for(deck[2].tile_id)
	var target: Vector2 = (row.tile_rect_at(3).get_center() + row.tile_rect_at(4).get_center()) * 0.5
	_send_motion(row, target)
	check(row.is_dragging(), "moving within rack keeps the drag alive")
	row._process(1.0 / 60.0)
	var moving_tile: Rect2 = row.tile_global_rect_for(deck[1].tile_id)
	var moving_neighbor: Rect2 = row.tile_global_rect_for(deck[2].tile_id)
	check(moving_tile.position.x > before.position.x, "the dragged tile's slot opens during the drag")
	check(moving_neighbor.position.x < neighbor_before.position.x, "neighboring tiles ease toward the open slot")
	check(moving_tile.position.distance_to(before.position) < before.size.x, "one frame never jumps a full tile width")
	_send_release(row, target)
	check(not row.is_dragging(), "release ends rack drag")
	for frame: int in range(60):
		row._process(1.0 / 60.0)
	check(row.tile_rect_at(3).position.x < row.tile_rect_at(1).position.x, "tile inserts after its left neighbor")
	check(row.tile_rect_at(1).position.x < row.tile_rect_at(4).position.x, "tile inserts before its right neighbor")
	screen._refresh_all()
	_tap_deck_fully(screen, 2)
	check_eq(screen.controller.selected_deck_tile_id(), deck[2].tile_id, "tap after reorder selects the drawn identity")
	check_eq(screen.controller.staged_count(), 0, "rack reorder stages nothing")
	check_eq(screen.controller.get_board().get_revision(), 0, "rack reorder never commits")
	check_eq(screen.controller.human_deck(), deck, "rack order does not mutate match ownership")
	_release(screen)


func test_staged_tile_returns_to_chosen_rack_position_with_touch_and_mouse() -> void:
	for touch: bool in [true, false]:
		var screen: GameScreen = _host_screen()
		if screen == null:
			return
		var deck: Array[TileDefinition] = screen.controller.human_deck()
		var row: DeckView = screen.deck_view
		row.size = Vector2(720, 96)
		var neighbor: Rect2 = row.tile_global_rect_for(deck[2].tile_id)
		var cell := Vector2i(5, 5)
		screen.controller.select_deck_tile(deck[1].tile_id)
		check(screen.stage_at(cell), "fixture stages middle rack tile")
		check_eq(row.tile_global_rect_for(deck[2].tile_id), neighbor, "staging preserves neighboring slot")
		# Put the row below the board without depending on a deferred layout pass.
		var origin: Vector2 = _board_point_for(screen, cell)
		row.global_position = screen.board_view.global_board_rect().end + Vector2(0, 20)
		var target: Vector2 = row.get_global_transform() * Vector2(row.size.x - 1, row.size.y * 0.5)
		if touch:
			_send_board_touch(screen, 2, origin, true)
			_send_board_touch_drag(screen, 2, target)
			_send_board_touch(screen, 2, target, false)
		else:
			screen.board_input._handle_press(origin, true)
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.position = target
			screen.board_input._input(release)
		check_eq(screen.controller.staged_count(), 0, "board release into rack unstages tile")
		check_eq(row.deck_size(), deck.size(), "returned tile is visible again")
		for frame: int in range(60):
			row._process(1.0 / 60.0)
		check(row.tile_rect_at(1).position.x > row.tile_rect_at(5).position.x, "returned tile inserts at requested end")
		check_eq(screen.controller.get_board().get_revision(), 0, "return never commits a tile")
		_release(screen)


func _host_screen() -> GameScreen:
	var screen: GameScreen = _instantiate(GAME_SCREEN_SCENE) as GameScreen
	if not check_not_null(screen, "the game screen must instantiate as a GameScreen"):
		return null
	if not _host(screen):
		check(false, "the scene tree must be available to host the game screen")
		screen.free()
		return null

	# Built with `new()` because that is how `AppRoot` composes the game
	# (ADR-008 section 5); the `create()` factory exists for intent and must not
	# be the only path these smoke tests exercise.
	var controller: GameSessionController = GameSessionController.new()
	controller.save_path = "user://game_screen_test_match.json"
	screen.add_child(controller)
	screen.attach_controller(controller)
	controller.start_new_match(TEST_MATCH_ID, TEST_SEED)
	return screen


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


## Commit a real, legal AI pair while the tree is paused between process frames.
func _commit_rival_opening(screen: GameScreen) -> LineResult:
	var controller: GameSessionController = screen.controller
	var session: GameSessionState = controller.get_session()
	var pair: Array[TileDefinition] = _rank_pair(session.deck_for(TurnEnums.AI_PLAYER_ID), 2)
	if not check(pair.size() == 2, "AI fixture has a pair"):
		return null
	var turn: TurnState = session.get_turn_state()
	turn.active_player_id = TurnEnums.AI_PLAYER_ID
	turn.phase = TurnEnums.MatchPhase.AWAIT_ACTION
	var snapshots: Array[TileSnapshot] = [
		TileSnapshot.create(pair[0], Vector2i(5, 5), 90),
		TileSnapshot.create(pair[1], Vector2i(6, 5), 180),
	]
	return controller._commit_line(TurnEnums.AI_PLAYER_ID, snapshots)


func test_rival_tiles_fly_from_rack_then_refill_without_changing_state() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var pot_before: int = screen.controller.remaining_tiles()
	var result: LineResult = _commit_rival_opening(screen)
	if not check(result != null and result.was_committed(), "AI fixture commits a legal pair"):
		_release(screen)
		return
	var layer: RivalMoveLayer = screen.rival_move_layer
	var rack: OpponentRackView = screen.get_node("%OpponentRack")
	var revision: int = screen.controller.get_board().get_revision()
	check(layer.is_playing(), "AI commit starts its flight")
	check_eq(layer._snapshots, result.staged_tiles, "flight uses committed faces and rotations only")
	check_eq(screen.controller.remaining_tiles(), pot_before - 2, "rules refill exactly the two spent tiles")
	check_eq(layer._refill_count, 2, "presentation refills the actual replacement count")
	check_eq(screen.board_view._state.concealed_cells.size(), 2, "board conceals tiles still in flight")
	check_eq(rack._concealed, [0], "first card leaves its existing rack slot immediately")
	check(not screen.board_input.enabled, "board input waits for the rival presentation")
	screen._on_swap_pressed()
	check(not screen.is_swap_mode(), "swap cannot race the rival presentation")
	screen._refresh_all()
	check_eq(rack._concealed, [0], "state refresh does not reveal flying rack tiles")
	layer._process(RivalMoveLayer.FLIGHT + 0.01)
	check_eq(screen.board_view._state.concealed_cells.size(), 1, "each tile becomes visible only after landing")
	check(not screen._rival_score_events.is_empty(), "score reveal waits for the full line to land")
	layer._process(RivalMoveLayer.STAGGER)
	check(screen.board_view._state.concealed_cells.is_empty(), "landed line is fully visible")
	check(screen._rival_score_events.is_empty(), "score feedback releases after placement")
	check_eq(rack._tile_count - rack._concealed.size(), 4, "rack temporarily shows only the four unplayed tiles")
	var elapsed: float = layer._elapsed
	screen.board_view.set_close_view(false)
	rack.size.x += 20.0
	check_eq(layer._elapsed, elapsed, "layout and zoom do not restart the animation")
	layer._process(layer.total_duration())
	check(not layer.is_playing(), "refill completes")
	check_eq(rack._tile_count, screen.controller.opponent_deck_count(), "rack ends at authoritative count")
	check(rack._concealed.is_empty(), "replacement backs appear after landing")
	check(screen.board_input.enabled, "human input returns after refill")
	check_eq(screen.controller.get_board().get_revision(), revision, "animation never mutates the committed board")
	_release(screen)


func test_rival_refill_uses_only_remaining_pot_tiles() -> void:
	for available: int in [0, 1]:
		var screen: GameScreen = _host_screen()
		if screen == null:
			return
		var source: TileSource = screen.controller.get_session().get_tile_source()
		while screen.controller.remaining_tiles() > available:
			source.draw()
		var result: LineResult = _commit_rival_opening(screen)
		if check(result != null and result.was_committed(), "limited-pot AI pair commits"):
			var layer: RivalMoveLayer = screen.rival_move_layer
			check_eq(layer._refill_count, available, "no replacement is invented when pot runs out")
			layer._process(layer.total_duration())
			check_eq(screen.get_node("%OpponentRack")._tile_count, 4 + available, "short hand displays its real size")
			check_eq(screen.controller.remaining_tiles(), 0, "refill exhausts only available tiles")
		_release(screen)


func test_rival_animation_clears_on_restart_and_respects_reduced_motion() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	_commit_rival_opening(screen)
	screen.rival_move_layer._process(0.2)
	screen._on_restart_pressed()
	check(not screen.rival_move_layer.is_playing(), "restart cancels the old move animation")
	check(screen.board_view._state.concealed_cells.is_empty(), "restart leaves no concealed cells")
	check(screen.get_node("%OpponentRack")._concealed.is_empty(), "restart leaves no concealed rack slots")
	check(screen._rival_score_events.is_empty(), "restart clears delayed score feedback")
	var reduced: Variant = ProjectSettings.get_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, true)
	_commit_rival_opening(screen)
	check(not screen.rival_move_layer.is_playing(), "reduced motion skips all flight and flip effects")
	check(screen.board_view._state.concealed_cells.is_empty(), "reduced motion shows the committed board immediately")
	check_eq(screen.get_node("%OpponentRack")._tile_count, screen.controller.opponent_deck_count(), "reduced motion shows the authoritative refill immediately")
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, reduced)
	_release(screen)


func test_rival_final_move_finishes_before_results_cover_board() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	_commit_rival_opening(screen)
	var session: GameSessionState = screen.controller.get_session()
	session.finish(TurnEnums.MatchOutcome.AI_WIN, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))
	check(not screen.summary_overlay.visible, "results wait for the final rival flight")
	screen.rival_move_layer._process(screen.rival_move_layer.total_duration())
	check(not screen.summary_overlay.visible, "results wait on the completed board after all rival tiles land")
	check(screen.board_view._state.concealed_cells.is_empty(), "final move leaves no hidden board cells")
	screen._on_final_board_pause_finished()
	check(screen.summary_overlay.visible, "results appear after the final-board pause")
	_release(screen)
