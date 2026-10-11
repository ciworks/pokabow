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
## out, Rotate turns the tile the line last took without writing to the board,
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


func test_a_human_with_no_valid_move_sees_a_toast_and_loses_the_turn() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var session: GameSessionState = controller.get_session()
	var board: BoardState = controller.get_board()
	var tile: TileDefinition = controller.human_deck()[0]
	var filler: TileDefinition = TileDefinition.create(
		&"test-no-move-filler", TileEnums.TileRank.ACE, TileEnums.FaceColor.RED,
		[TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.BLUE, TileEnums.EdgeColor.BLUE]
	)
	var snapshots: Array[TileSnapshot] = []
	for x: int in range(BoardEnums.OPENING_MIN, BoardEnums.OPENING_MIN + 5):
		snapshots.append(TileSnapshot.create(filler, Vector2i(x, BoardEnums.OPENING_MIN), 0))
	if not check(LineValidator.validate(board, snapshots).is_legal(), "fixture line must be legal"):
		_release(screen)
		return
	board.commit_tiles(snapshots)
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
	check(screen._is_toast_notice(GameSessionController.NO_VALID_MOVE_NOTICE), "the no-move notice is presented as a toast")
	_release(screen)


## One scoring move must reveal what it awarded, not merely announce a number
## (AGENTS.md section 8, Milestone 8: edge and cluster visualization).
##
## The cells and the colour arrive on the events, so the board marks what really
## scored rather than re-deriving it from the board - which is what keeps the
## reveal and the ledger from ever disagreeing (ADR-008 section 4).
func test_a_scoring_move_reveals_its_edges_and_clusters() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return

	# One matching boundary and one paying cluster, in the order ADR-007 section 7
	# records them: edge matches by boundary id, then clusters by colour.
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
		2,
		"the hand and edge cluster are outlined; an individual edge match is not"
	)
	check_eq(
		screen.board_view.reveal_layer.wave_cells().size(),
		5,
		"the poker hand's five tiles are the ones that bounce"
	)
	screen.board_view.clear_score_reveal()
	check(
		not screen.board_view.reveal_layer.has_marks(),
		"clearing the reveal must leave nothing drawn (ADR-008 section 9)"
	)

	# A move that scored nothing must reveal nothing, rather than leaving the
	# previous move's marks up.
	screen._on_score_awarded([] as Array, Vector2i(5, 5))
	check(
		not screen.board_view.reveal_layer.has_marks(),
		"a move that scored nothing must not leave a stale reveal"
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
	check(screen.bottom_navigation.buttons[&"Undo"].disabled, "Undo waits for a staged hand")
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
	check(screen.bottom_navigation.buttons[&"Undo"].disabled, "Undo must be disabled off-turn")
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


func test_rotating_a_staged_tile_updates_the_line_without_writing_to_the_board() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
	# Nothing is armed when a match starts, so the test arms a tile the way a
	# player does before asking the staging commands for one.
	_tap_deck_fully(screen, 0)
	var tile: TileDefinition = controller.human_tile()
	if not check_not_null(tile, "the human must hold a tile to stage"):
		_release(screen)
		return
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if not check_eq(cells.size(), TILES_PER_LINE, "the opening board must offer a two-cell line"):
		_release(screen)
		return

	# Rotating with nothing staged only sets the rotation the next staged tile
	# takes, and must not write to the board (ADR-011 section 11).
	var revision_before: int = board.get_revision()
	screen._on_rotate_pressed()
	check_eq(controller.pending_rotation(), 1, "the rotate command advances the pending rotation")
	check_eq(controller.staged_count(), 0, "rotating must not stage a tile by itself")
	check_eq(board.get_revision(), revision_before, "rotating must not touch the board")

	# Stage one tile, then rotate the pending line.
	screen.stage_at(cells[0])
	if not check_eq(controller.staged_count(), 1, "the tile must be staged at the tapped cell"):
		_release(screen)
		return
	var staged_rotation: int = controller.pending_snapshot().get_rotation()
	var rotation_before: int = controller.pending_rotation()

	screen._on_rotate_pressed()
	check_eq(
		controller.pending_snapshot().get_rotation(),
		(staged_rotation + 1) % TileEnums.ROTATION_COUNT,
		"rotating must turn the staged tile one quarter-turn"
	)
	check_eq(
		controller.pending_rotation(),
		(rotation_before + 1) % TileEnums.ROTATION_COUNT,
		"the reported rotation must follow the staged tile"
	)
	check_eq(
		screen.board_view.get_pending_line()[0].get_rotation(),
		controller.pending_snapshot().get_rotation(),
		"the board must draw the staged tile at its rotated orientation"
	)
	check_eq(
		controller.staged_cells()[0],
		cells[0],
		"rotating must not move the tile to another cell"
	)
	check_eq(board.occupied_count(), 0, "rotating must not write to the board")
	check_eq(board.get_revision(), revision_before, "rotating must not touch the board")
	check_eq(controller.get_session().move_count(), 0, "rotating must not record a move")
	check(controller.is_human_turn(), "rotating must not consume the turn")

	# A full turn of the rotate control returns the tile to where it started.
	for _step: int in range(TileEnums.ROTATION_COUNT - 1):
		screen._on_rotate_pressed()
	check_eq(
		controller.pending_snapshot().get_rotation(),
		staged_rotation,
		"four rotations must return the tile to its starting orientation"
	)
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


func test_rival_win_uses_red_sweep_loss_title_and_no_confetti() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var session: GameSessionState = screen.controller.get_session()
	session.finish(TurnEnums.MatchOutcome.AI_WIN, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))
	var presentation: MatchEndPresentation = screen.summary_overlay as MatchEndPresentation
	presentation.seek(MatchEndPresentation.DURATION)
	check_eq(screen.summary_title.text, "YOU LOSE", "a rival win must show the loss heading")
	check_eq(presentation._panel_sweep_direction(), -1.0,
		"a rival win must sweep the lower red panel upward")
	check(not presentation._celebrating, "a rival win must not start confetti")
	screen._on_restart_pressed()
	session = screen.controller.get_session()
	session.finish(TurnEnums.MatchOutcome.HUMAN_WIN, TurnEnums.EndReason.BOARD_FULL)
	screen._on_match_ended(MatchResult.build(session))
	presentation.seek(MatchEndPresentation.DURATION)
	check_eq(presentation._panel_sweep_direction(), 1.0,
		"a human win must retain the blue panel sweep")
	check(presentation._celebrating, "a human win must retain confetti")
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

	check(screen.summary_overlay.visible, "the summary must appear when the match ends")
	check(not (screen.get_node("%PotPanel") as Control).visible,
		"game over must hide the pot, count plate and count")
	check(not screen.tile_pile_view.is_visible_in_tree(), "game over must hide the pot artwork")
	check(not screen.available_tiles_label.is_visible_in_tree(), "game over must hide the tile count")
	check(not screen.summary_body.text.contains("tiles left"), "the summary must omit the tile count")
	check_eq(screen.summary_title.text, "It's a draw", "a draw must be reported as one")
	check(
		screen.summary_body.text.contains("poker"),
		"the summary must break the score down by category"
	)
	check(not screen.board_input.enabled, "a finished match must stop accepting input")

	# Restarting must clear the summary and start a fresh board.
	screen._on_restart_pressed()
	check(not screen.summary_overlay.visible, "a new match must hide the summary")
	check((screen.get_node("%PotPanel") as Control).visible,
		"a new match must restore the pot and tile count")
	check(not screen.is_swap_mode(), "a new match must start with no swap set")
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
	var to_screen: Transform2D = screen.get_global_transform().affine_inverse() * row.get_global_transform()
	var deck_rect: Rect2 = to_screen * row.tile_rect_at(row.dragging_index())
	check(overlay.size.is_equal_approx(deck_rect.size * 0.9), "drag preview is ten percent smaller than its deck tile")
	check(overlay.get_rect().get_center().is_equal_approx(to_screen * destination), "smaller tile follows the pointer")
	check(not preview.state.drag_tile_visible, "board draws no duplicate snapped tile")
	check_eq(preview.TARGET_HIGHLIGHT_TEXTURE.resource_path, "res://assets/tiles/tile_highlight.png", "target uses the supplied highlight artwork")
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
## before the tap is aimed. `DeckView.tile_rect` is the same geometry the row
## draws and hit-tests with, so the tap lands on the tile it names.
func _tap_deck(screen: GameScreen, index: int) -> void:
	if screen == null or screen.deck_view == null:
		return
	var row: DeckView = screen.deck_view
	row.size = Vector2(720.0, 96.0)
	var count: int = row.deck_size()
	if count <= 0 or index < 0 or index >= count:
		return
	var rect: Rect2 = DeckView.tile_rect(index, count, row.size)
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
	_send_release(row, DeckView.tile_rect(index, count, row.size).get_center())


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
## `DeckView.tile_rect`, the same geometry the row draws and hit-tests with, so it
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
	var grab: Vector2 = DeckView.tile_rect(index, count, row.size).get_center()
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
func test_bottom_navigation_play_and_undo_use_staged_line_commands() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var nav: GameBottomNavigation = screen.bottom_navigation
	check_eq(nav.buttons.size(), 5, "the bottom bar offers five options")
	check(nav.buttons[&"Play"].disabled, "Play waits for a staged hand")
	check(nav.buttons[&"Undo"].disabled, "Undo waits for unplayed tiles")
	check(nav.buttons[&"Skip"].disabled, "Skip has no corresponding menu command")
	check(nav.buttons[&"Skip"].get_signal_connection_list("pressed").is_empty(), "Skip has no action")
	var pair: Array[TileDefinition] = _rank_pair(screen.controller.human_deck(), 2)
	var cells: Array[Vector2i] = _line_cells(screen.controller.get_board(), 2)
	if not check(pair.size() == 2 and cells.size() == 2, "fixture supplies an opening pair"):
		_release(screen)
		return
	for index: int in range(2):
		screen.controller.stage_tile(pair[index].tile_id, cells[index])
	check(not nav.buttons[&"Play"].disabled, "staging enables Play")
	check(not nav.buttons[&"Undo"].disabled, "staging enables Undo")
	nav.buttons[&"Undo"].pressed.emit()
	check(not screen.controller.has_pending(), "Undo clears the whole staged placement")
	check_eq(screen.controller.get_session().move_count(), 0, "Undo does not consume a turn")
	check_eq(screen.deck_view.deck_size(), DECK_SIZE, "Undo restores unplayed tiles")
	for index: int in range(2):
		screen.controller.stage_tile(pair[index].tile_id, cells[index])
	nav.buttons[&"Play"].pressed.emit()
	check_eq(screen.controller.get_session().move_count(), 1, "Play commits the staged hand")
	for action: StringName in [&"Play", &"Swap", &"Undo"]:
		check(nav.buttons[action].disabled, "%s is unavailable off-turn" % action)
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
	(screen.get_node("%OpenMenuButton") as Button).pressed.emit()
	check(screen.command_drawer.is_open, "the settings icon opens swap confirmation controls")
	check(screen.swap_confirm_button.visible and not screen.swap_confirm_button.disabled, "selected tiles can be returned")
	check_eq(screen.swap_tiles().size(), 1, "reopening keeps the selected tile")
	screen.swap_cancel_button.pressed.emit()
	check(not screen.is_swap_mode(), "Keep tiles cancels the swap")
	_release(screen)


func test_bottom_navigation_quit_requests_the_hub() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var requests: Array[int] = []
	screen.hub_requested.connect(func() -> void: requests.append(1))
	screen.bottom_navigation.buttons[&"Quit"].pressed.emit()
	check_eq(requests.size(), 1, "Quit uses the existing hub navigation signal")
	_release(screen)


func test_avatar_timer_updates_without_rebuilding_board_and_clears_swap_on_expiry() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var human: TurnTimerOutline = screen.human_score_panel.get_node("HumanScoreBox/TurnOutline") as TurnTimerOutline
	var rival: TurnTimerOutline = screen.ai_score_panel.get_node("AiScoreBox/TurnOutline") as TurnTimerOutline
	check_eq(human.seconds_left, 60, "human opens with a full border")
	check_eq(rival.seconds_left, 0, "inactive rival has no yellow border")
	var refreshes: Array[int] = []
	screen.controller.state_changed.connect(func() -> void: refreshes.append(1))
	var turn: TurnState = screen.controller.get_session().get_turn_state()
	screen.controller.update_turn_clock(turn.deadline_unix_seconds - 20.0)
	check_eq(human.seconds_left, 20, "the ring follows the controller's whole seconds")
	check(refreshes.is_empty(), "clock ticks do not rebuild the board or interrupt input")
	var art: Control = human.get_parent() as Control
	var reduced_motion: bool = AccessibilitySettings.reduced_motion()
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	screen.controller.update_turn_clock(turn.deadline_unix_seconds - 10.0)
	var warning: Tween = art.get("_warning_tween") as Tween
	check(warning != null, "ten seconds starts a small avatar and panel shake")
	for seconds: int in range(9, 0, -1):
		screen.controller.update_turn_clock(turn.deadline_unix_seconds - float(seconds))
		var next_warning: Tween = art.get("_warning_tween") as Tween
		check(next_warning != null and next_warning != warning, "human warning restarts at %d seconds" % seconds)
		check(not warning.is_valid(), "the previous shake is stopped before the next starts")
		warning = next_warning
		screen._on_turn_clock_changed(TurnEnums.HUMAN_PLAYER_ID, seconds)
		check_eq(art.get("_warning_tween"), warning, "duplicate updates within one second do not restart the shake")
		check(rival.get_parent().get("_warning_tween") == null, "inactive rival does not shake")
	check(refreshes.is_empty(), "repeated warning ticks do not rebuild the board")
	screen.bottom_navigation.buttons[&"Swap"].pressed.emit()
	screen._on_deck_tile_toggled(screen.controller.human_deck()[0].tile_id)
	screen.command_drawer.open_settings()
	screen.controller.update_turn_clock(turn.deadline_unix_seconds)
	check(not screen.is_swap_mode(), "expiry clears swap selection")
	check_eq(human.seconds_left, 0, "expired human border disappears")
	check_eq(rival.seconds_left, 60, "rival starts with a full border")
	check_eq(screen._toast_label.text, "Time up, play moves to other player", "expiry displays the requested toast")
	check(screen._toast_panel.visible, "the expiry toast is visible")
	check(art.get("_warning_tween") == null, "expiry stops any unfinished shake")
	var rival_art: Control = rival.get_parent() as Control
	warning = null
	for seconds: int in range(10, 0, -1):
		screen.controller.update_turn_clock(turn.deadline_unix_seconds - float(seconds))
		var next_warning: Tween = rival_art.get("_warning_tween") as Tween
		check(next_warning != null and next_warning != warning, "rival warning restarts at %d seconds" % seconds)
		check(art.get("_warning_tween") == null, "inactive human does not shake")
		warning = next_warning
	screen.controller.update_turn_clock(turn.deadline_unix_seconds)
	check(rival_art.get("_warning_tween") == null, "rival expiry stops the shake")
	screen.controller.update_turn_clock(turn.deadline_unix_seconds - 10.0)
	check(art.get("_warning_tween") != null, "a later human turn warns again")
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, reduced_motion)
	_release(screen)


func test_avatar_timer_repeated_warning_respects_reduced_motion() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var reduced_motion: bool = AccessibilitySettings.reduced_motion()
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, false)
	var turn: TurnState = screen.controller.get_session().get_turn_state()
	var art: Control = screen.human_score_panel.get_node("HumanScoreBox") as Control
	var origin: Vector2 = art.position
	screen.controller.update_turn_clock(turn.deadline_unix_seconds - 10.0)
	check(art.get("_warning_tween") != null, "warning starts when motion is enabled")
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, true)
	for seconds: int in range(9, 0, -1):
		screen.controller.update_turn_clock(turn.deadline_unix_seconds - float(seconds))
		check(art.get("_warning_tween") == null, "reduced motion suppresses every subsequent shake")
		check_eq(art.position, origin, "suppressed warnings leave artwork at its original position")
	ProjectSettings.set_setting(AccessibilitySettings.REDUCED_MOTION_PATH, reduced_motion)
	_release(screen)


func test_command_drawer_opens_closes_and_returns_to_rack_for_swap() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var drawer: GameCommandDrawer = screen.command_drawer
	for removed: String in ["ConfirmButton", "RotateButton", "SwapButton", "CancelButton", "MatchToggle", "MenuTab"]:
		check(drawer.find_child(removed, true, false) == null, "%s is absent from the drawer" % removed)
	check(not drawer.is_open, "drawer starts folded")
	(screen.get_node("%OpenMenuButton") as Button).pressed.emit()
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


func test_pinch_zoom_keeps_anchor_and_existing_button_steps() -> void:
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
	check(not screen.get_node("%ZoomInButton").disabled and not screen.get_node("%ZoomOutButton").disabled,
		"both zoom buttons remain available between the endpoints")
	_send_board_touch_drag(screen, 9, right + Vector2(600.0, 0.0))
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "pinch cannot exceed the close view")
	check(screen.get_node("%ZoomInButton").disabled, "zoom in disables at the upper limit")
	_send_board_touch_drag(screen, 9, left + Vector2(10.0, 0.0))
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "pinch cannot shrink below the full board")
	check(screen.get_node("%ZoomOutButton").disabled, "zoom out disables at the lower limit")
	_send_board_touch(screen, 4, left, false)
	_send_board_touch(screen, 9, right, false)
	screen.get_node("%ZoomInButton").pressed.emit()
	check_eq(screen.board_view.zoom, BoardView.CLOSE_ZOOM, "plus retains its existing 2x step")
	screen.get_node("%ZoomOutButton").pressed.emit()
	check_eq(screen.board_view.zoom, BoardView.OVERVIEW_ZOOM, "minus retains its existing 1x step")
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
