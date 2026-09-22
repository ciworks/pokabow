extends TestCase

## Regression: the opponent must take its turn in the composition the game uses.
##
## `AppRoot` builds the controller with `new()` (ADR-008 section 5), while the
## other AI suites built it with `create()`. When the opponent service existed on
## only the factory path, the rival silently never moved in the running game even
## though every test passed. This suite therefore deliberately builds its
## controller with `new()`.
##
## Application-level: no scene tree, no `GameScreen`, no rendering. The controller
## is driven directly, so reaching the AI turn needs no timer and no frames.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

const MATCH_ID: StringName = &"ai-turn-regression"
const SEED: int = 4242


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

	# The human opens the match with one legal committed tile.
	controller.preview_placement(_first_frontier(board))
	controller.confirm_pending()

	var session: GameSessionState = controller.get_session()
	if not check_not_null(session, "the started match must expose a session"):
		return
	check_eq(board.occupied_count(), 1, "the human's confirmed move must reach the board")
	check_eq(session.move_count(), 1, "the human's move must be recorded exactly once")
	check(not controller.is_human_turn(), "a committed move must hand the turn to the rival")

	# ADR-003 section 3 step 2: the rival is dealt its tile at TURN_START.
	if not check_not_null(
		session.active_tile_for(AI), "the rival must hold a tile on its turn"
	):
		return

	# Drive the opponent directly. The running game reaches this through the
	# presentation timer; calling it straight keeps the check frame-independent.
	controller._play_ai_move()

	check_eq(board.occupied_count(), 2, "the opponent must commit a tile on its turn")
	check_eq(session.move_count(), 2, "the opponent's move must be recorded")
	check(
		session.has_move_id(ScoringCoordinator.move_id_for(MATCH_ID, 2)),
		"the opponent's move must carry the deterministic turn-2 identifier"
	)
	check(controller.is_human_turn(), "the turn must come back to the human")
	check(not controller.is_ai_thinking(), "the thinking state must clear once the move lands")


## Returns the first legal frontier cell in row-major order.
func _first_frontier(board: BoardState) -> Vector2i:
	var frontier: Array[Vector2i] = board.get_frontier_cells()
	if frontier.is_empty():
		return BoardMetrics.NO_CELL
	return frontier[0]
