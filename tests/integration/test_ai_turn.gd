extends TestCase

## Regression: the opponent must take its turn in the composition the game uses.
##
## `AppRoot` builds the controller with `new()` (ADR-008 section 5), while the
## other AI suites built it with `create()`. When the opponent service existed on
## only the factory path, the rival silently never moved in the running game even
## though every test passed. This suite therefore deliberately builds its
## controller with `new()`.
##
## ADR-010 made the same mistake visible in a second place: a turn now holds one
## or more placements from the player's deck (sections 3, 4, and 6) and the deck
## is refilled at the turn boundary (section 5), so the checks below drive a real
## multi-placement turn through the real construction path rather than trusting a
## domain fixture.
##
## Application-level: no scene tree, no `GameScreen`, no rendering. The controller
## is driven directly, so reaching the AI turn needs no timer and no frames.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

const MATCH_ID: StringName = &"ai-turn-regression"
const SEED: int = 4242

## The Phase 1 deck size every deck is filled to (ADR-010 section 1).
const DECK_SIZE: int = DeckRules.DEFAULT_DECK_SIZE

## Tiles the pot still holds once both decks are dealt (ADR-010 section 2).
const POT_AFTER_SETUP: int = BoardEnums.CELL_COUNT - DECK_SIZE * 2


func test_a_controller_built_with_new_owns_an_opponent_service() -> void:
	var controller: GameSessionController = GameSessionController.new()

	check_not_null(
		controller.get_ai_coordinator(),
		"a controller built with new() must own its opponent service, or the rival can never move"
	)
	check(not controller.is_ai_thinking(), "a fresh controller must not be thinking")


func test_the_opponent_actually_takes_its_turn() -> void:
	var controller: GameSessionController = GameSessionController.new()
	if not check(controller.start_new_match(MATCH_ID, SEED), "the match must start"):
		return

	var board: BoardState = controller.get_board()
	if not check_not_null(board, "a started match must expose a board"):
		return
	check_eq(board.occupied_count(), 0, "a new match must start on an empty board")

	var session: GameSessionState = controller.get_session()
	if not check_not_null(session, "the started match must expose a session"):
		return

	# ADR-010 section 2: both players are dealt a deck of six at setup.
	check_eq(session.deck_count(HUMAN), DECK_SIZE, "the human is dealt a deck of six")
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival is dealt a deck of six")

	# The human opens the match with one legal committed placement.
	controller.preview_placement(_first_frontier(board))
	controller.confirm_pending()

	check_eq(board.occupied_count(), 1, "the human's confirmed move must reach the board")
	check_eq(session.move_count(), 1, "the human's move must be recorded exactly once")
	check(
		controller.is_human_turn(),
		"a single placement leaves the turn with the human (ADR-010 section 3 step 9)"
	)

	# ADR-010 section 4: the rival only acts once the human ends their turn.
	_end_human_turn(controller)

	check(not controller.is_human_turn(), "ending the turn must hand play to the rival")

	# ADR-010 section 3 step 2: the rival holds a stocked deck on its turn.
	if not check_not_null(
		session.active_tile_for(AI), "the rival must hold a tile on its turn"
	):
		return

	# Drive the opponent directly. The running game reaches this through the
	# presentation timer; calling it straight keeps the check frame-independent.
	# A detached controller has no tree to schedule the next placement on, so the
	# rival places exactly once per call here.
	controller._play_ai_move()

	check_eq(board.occupied_count(), 2, "the opponent must commit a tile on its turn")
	check_eq(session.move_count(), 2, "the opponent's move must be recorded")
	check(
		session.has_move_id(ScoringCoordinator.move_id_for(MATCH_ID, 2, 1)),
		"the opponent's move must open turn 2 with placement index 1"
	)
	check(
		not controller.is_human_turn(),
		"the rival keeps its turn until it ends it (ADR-010 section 11)"
	)
	check(not controller.is_ai_thinking(), "the thinking state must clear once the move lands")


func test_a_real_path_turn_holds_several_placements_and_tops_the_deck_up_at_turn_end() -> void:
	# ADR-010 sections 3 to 6 exercised through the construction path the game
	# uses: `AppRoot` builds the controller with `new()`, so a deck that existed
	# only on the `create()` path would leave the running game unable to place a
	# second tile while a suite built on the factory still passed.
	var controller: GameSessionController = GameSessionController.new()
	if not check(controller.start_new_match(MATCH_ID, SEED), "the match must start"):
		return

	var session: GameSessionState = controller.get_session()
	var board: BoardState = controller.get_board()
	if not check_not_null(session, "the started match must expose a session"):
		return
	if not check_not_null(board, "the started match must expose a board"):
		return

	var pot_after_setup: int = session.remaining_tile_count()
	check_eq(session.deck_count(HUMAN), DECK_SIZE, "the human is dealt a deck of six")
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival is dealt a deck of six")
	check_eq(pot_after_setup, POT_AFTER_SETUP, "dealing both decks leaves 132 in the pot")

	# An unselected deck presents its first tile as the tile a placement commits.
	var first_tile: TileDefinition = controller.human_tile()
	if not check_not_null(first_tile, "the human must hold a tile to place"):
		return
	check_eq(
		String(first_tile.tile_id),
		String(controller.human_deck()[0].tile_id),
		"an unselected deck presents its first tile"
	)

	controller.preview_placement(_first_frontier(board))
	controller.confirm_pending()

	check_eq(board.occupied_count(), 1, "the first placement must reach the board")
	check_eq(
		session.deck_count(HUMAN), DECK_SIZE - 1, "the committed tile leaves the deck"
	)
	check(controller.is_human_turn(), "the turn stays open after one placement")
	check(
		controller.can_end_turn(),
		"the human may end the turn at any point in the action phase (ADR-010 section 4)"
	)

	# ADR-010 sections 4 and 12: selecting a deck tile is what arms the next
	# placement, so the player chooses which of their tiles to commit.
	var second_tile: TileDefinition = controller.human_deck()[0]
	check(controller.select_deck_tile(second_tile.tile_id), "a deck tile may be selected")
	check_eq(
		String(controller.selected_deck_tile_id()),
		String(second_tile.tile_id),
		"the selection is the tile the next placement commits"
	)
	check_eq(
		String(controller.human_tile().tile_id),
		String(second_tile.tile_id),
		"the selected tile is the tile a preview places"
	)

	controller.preview_placement(_first_frontier(board))
	check(controller.has_pending(), "the selected tile must produce a preview")
	check(controller.is_pending_valid(), "the preview must be legal on a frontier cell")
	controller.confirm_pending()

	check_eq(
		board.occupied_count(), 2, "the second placement of the same turn must reach the board"
	)
	check_eq(session.move_count(), 2, "both placements of the turn are recorded")
	check(
		session.has_move_id(ScoringCoordinator.move_id_for(MATCH_ID, 1, 1)),
		"the first placement of turn 1 carries placement index 1 (ADR-010 section 9)"
	)
	check(
		session.has_move_id(ScoringCoordinator.move_id_for(MATCH_ID, 1, 2)),
		"the second placement of turn 1 carries placement index 2 (ADR-010 section 9)"
	)
	check(controller.is_human_turn(), "two placements still do not end the turn")
	check_eq(
		session.deck_count(HUMAN), DECK_SIZE - 2, "two placements leave four tiles in the deck"
	)
	check_eq(
		session.remaining_tile_count(),
		pot_after_setup,
		"the pot is untouched while the turn is open (ADR-010 section 5)"
	)

	# ADR-010 sections 4 and 5: the explicit end-turn action closes the turn and
	# the deck is topped back up at that boundary and nowhere else.
	_end_human_turn(controller)

	check(not controller.is_human_turn(), "the explicit end-turn hands play to the rival")
	check_eq(
		session.deck_count(HUMAN),
		DECK_SIZE,
		"the human's deck is topped back up to deck_size at the turn boundary"
	)
	check_eq(
		pot_after_setup - session.remaining_tile_count(),
		2,
		"the refill takes exactly the two tiles that were played"
	)
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival holds a full deck for its turn")
	check_eq(
		session.get_turn_state().turn_number, 2, "ending the turn advances the turn number"
	)


## Ends the human's turn through the real construction path and proves the turn
## actually handed play to the opponent's action phase (ADR-010 section 4).
##
## ADR-010 section 3 makes a turn one or more placements, so the human's turn has
## to be closed explicitly before the rival may act. Driving that through the
## controller rather than the domain directly is the point of this suite: a turn
## boundary that only existed on the domain path would leave the running game
## unable to give the rival a turn.
func _end_human_turn(controller: GameSessionController) -> void:
	controller.end_human_turn()
	var session: GameSessionState = controller.get_session()
	check_not_null(session, "an ended turn must leave a session")
	check(
		TurnManager.is_awaiting_ai_action(session),
		"ending the human's turn must reach the opponent's action phase"
	)


## Returns the first legal frontier cell in row-major order.
func _first_frontier(board: BoardState) -> Vector2i:
	var frontier: Array[Vector2i] = board.get_frontier_cells()
	if frontier.is_empty():
		return BoardMetrics.NO_CELL
	return frontier[0]
