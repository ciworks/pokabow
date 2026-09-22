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
## these tests fix is: a deck tap names the tile the next board tap stages, board
## taps build the pending line and it is drawn whole with one validity verdict,
## Rotate turns the pending line without writing to the board, Cancel returns
## every staged tile to the deck, and one Confirm commits the whole line as one
## move. Swapping (section 6) returns deck tiles for equal replacements and
## consumes the whole turn.
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
const POT_AFTER_SETUP: int = BoardEnums.CELL_COUNT - DECK_SIZE * 2

## Gap that must be refused as a hole in a line (ADR-011 section 1).
const LINE_GAP: int = PlacementEnums.PlacementRejection.LINE_GAP

## Diagonal continuation that must be refused as a mixed orientation.
const MIXED_ORIENTATION: int = PlacementEnums.PlacementRejection.MIXED_ORIENTATION


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
		"Root/Column/DeckBar/DeckPanel/DeckRow/DeckView": "Control",
		"Root/Column/DeckBar/SwapPanel/SwapBox/SwapButton": "Button",
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
		"DeckView",
		"RotateButton",
		"ConfirmButton",
		"CancelButton",
		"SwapButton",
		"SwapConfirmButton",
		"SwapCancelButton",
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


func test_human_input_is_gated_to_the_human_action_phase() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller

	check(controller.is_human_turn(), "the human opens the match")
	check(screen.board_input.enabled, "the board accepts input on the human's turn")
	check(not screen.confirm_button.disabled, "Confirm is available on the human's turn")
	check(not screen.rotate_button.disabled, "Rotate is available on the human's turn")
	check(not screen.cancel_button.disabled, "Cancel is available on the human's turn")
	check(not screen.swap_button.disabled, "Swap is available on the human's turn")
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
	check(screen.confirm_button.disabled, "Confirm must be disabled off-turn")
	check(screen.cancel_button.disabled, "Cancel must be disabled off-turn")
	check(screen.rotate_button.disabled, "Rotate must be disabled off-turn")
	check(screen.swap_button.disabled, "Swap must be disabled off-turn")
	check(screen.deck_view.is_locked(), "the deck row must not be selectable off-turn")
	check(
		screen.deck_view.deck_size() == DECK_SIZE,
		"the player's refilled tiles are still shown after the commit"
	)
	_release(screen)


func test_a_deck_tap_names_the_tile_the_next_board_tap_stages() -> void:
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
	_tap_deck(screen, _index_of_tile(controller.human_deck(), pair[0].tile_id))
	screen.stage_at(cells[0])

	check_eq(controller.staged_count(), 1, "the board tap must stage one tile")
	check(controller.has_pending(), "staging must leave a pending line")
	check_eq(controller.staged_cells()[0], cells[0], "the tile must be staged at the tapped cell")
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
		DECK_SIZE,
		"staged tiles stay in the deck until the line commits"
	)

	# The second tile of the pair completes a legal line, still without writing to
	# the board (ADR-011 sections 3 and 5).
	_tap_deck(screen, _index_of_tile(controller.human_deck(), pair[1].tile_id))
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
	check_eq(controller.get_session().move_count(), 0, "a staged line must not record a move")
	check(controller.is_human_turn(), "a staged line must not consume the turn")

	# Tapping a staged cell again takes that tile back out, still without touching
	# the board.
	screen.stage_at(cells[1])
	check_eq(controller.staged_count(), 1, "tapping a staged cell must take its tile back out")
	check_eq(board.get_revision(), revision_before, "un-staging must not touch the board")
	_release(screen)


func test_rotating_a_staged_tile_updates_the_line_without_writing_to_the_board() -> void:
	var screen: GameScreen = _host_screen()
	if screen == null:
		return
	var controller: GameSessionController = screen.controller
	var board: BoardState = controller.get_board()
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

	_tap_deck(screen, _index_of_tile(controller.human_deck(), pair[0].tile_id))
	screen.stage_at(cells[0])
	_tap_deck(screen, _index_of_tile(controller.human_deck(), pair[1].tile_id))
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
	check(screen.swap_button.disabled, "Swap must be disabled off-turn")
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
		_tap_deck(screen, _index_of_tile(controller.human_deck(), pair[index].tile_id))
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
		_tap_deck(screen, _index_of_tile(controller.human_deck(), pair[index].tile_id))
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
## ADR-011 section 3 makes a repeated rank the shortest legal hand, so a line is
## staged from held tiles of one rank. Six tiles drawn from four ranks cannot all
## differ, so any dealt deck supplies a pair.
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
