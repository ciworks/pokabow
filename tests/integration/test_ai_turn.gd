extends TestCase

## Regression: the opponent must take its turn in the composition the game uses.
##
## `AppRoot` builds the controller with `new()` (ADR-008 section 5), while the
## other AI suites built it with `create()`. When the opponent service existed on
## only the factory path, the rival silently never moved in the running game even
## though every test passed. This suite therefore deliberately builds its
## controller with `new()`.
##
## ADR-011 made the same mistake visible in a second place: a move is now one
## whole line of two or more deck tiles committed atomically (sections 1 and 5)
## and a turn is exactly one move, so the commit closes the turn itself and the
## explicit end-turn action is gone (section 7). The checks below drive a real
## line-commit turn through the real construction path rather than trusting a
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

## Tiles the shortest legal line places, in each player's own line (ADR-011
## section 1). A six-tile deck drawn from four ranks always holds a pair, so both
## players can assemble one (section 3).
const TILES_PER_LINE: int = 2

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

	# The human opens the match with one legal committed line (ADR-011 section 1).
	var opening: LineResult = _commit_opening_line(controller)
	check(
		opening != null and opening.was_committed(),
		"the human's opening line must commit through the controller"
	)

	check_eq(
		board.occupied_count(),
		TILES_PER_LINE,
		"the human's confirmed line must reach the board as a whole"
	)
	check_eq(session.move_count(), 1, "the human's whole line is one recorded move")
	check(
		not controller.is_human_turn(),
		"the committed line closes the human's turn by itself (ADR-011 section 7)"
	)
	check_eq(
		controller.turn_number(), 2, "the committed line must advance the turn number"
	)

	# ADR-010 section 3 step 2: the rival holds a stocked deck on its turn.
	if not check_not_null(
		session.active_tile_for(AI), "the rival must hold a tile on its turn"
	):
		return

	# Drive the opponent directly. The running game reaches this through the
	# presentation timer; calling it straight keeps the check frame-independent.
	# A detached controller has no tree to schedule anything on, so the rival
	# plays its whole turn - one move - in this call.
	controller._play_ai_move()

	# ADR-011 sections 6 and 7: the rival's turn is exactly one move, and there
	# are only two of them - a committed line or the swap. A committed line is
	# what an opening board should produce, because a deck of six drawn from four
	# ranks always holds a pair (section 3) and the proposal is completed into a
	# legal line through the proposed cell; a rival whose own hand cannot form
	# that line takes the section 6 swap, which places nothing. Either way the
	# turn is consumed, which is what this regression guards: a rival that
	# neither lines nor swaps would leave the running game waiting forever.
	var rival_placed: int = board.occupied_count() - TILES_PER_LINE
	if rival_placed == TILES_PER_LINE:
		check_eq(
			session.move_count(), 2, "the rival's line is one recorded move, not one per tile"
		)
		check(
			session.has_move_id(ScoringCoordinator.move_id_for(MATCH_ID, 2, 1)),
			"the rival's line is turn 2's one move, at placement index 1 (ADR-011 section 7)"
		)
	else:
		check_eq(
			rival_placed,
			0,
			"the rival's whole turn places a line of two tiles or nothing at all (ADR-011 sections 1 and 6); a board one tile short is a partial line, which section 5 forbids"
		)
		check_eq(session.move_count(), 1, "a swap records no move (ADR-011 section 6)")
	check(
		controller.is_human_turn(),
		"the rival's one move ends the rival's turn and hands play back (ADR-011 section 7)"
	)
	check(not controller.is_ai_thinking(), "the thinking state must clear once the move lands")


func test_a_real_path_turn_is_one_line_and_tops_the_deck_up_at_turn_end() -> void:
	# ADR-011 sections 5, 7, and 8 exercised through the construction path the
	# game uses: `AppRoot` builds the controller with `new()`, so a deck that
	# existed only on the `create()` path would leave the running game unable to
	# assemble a line while a suite built on the factory still passed.
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

	# ADR-011 section 7: a turn is exactly one move, so there is no end-turn
	# action left. Both entry points still have to answer, because a caller built
	# against ADR-010 reaches them, and neither may close a turn.
	check(
		not controller.can_end_turn(),
		"ADR-011 section 7 removed the explicit end-turn action, so none is available"
	)
	check(
		not controller.has_pending(),
		"nothing is staged before the human assembles a line"
	)
	controller.end_human_turn()
	check(
		controller.is_human_turn(),
		"the removed end-turn action must not hand play to the rival"
	)
	check_eq(session.move_count(), 0, "the removed end-turn action must commit nothing")
	check_eq(
		controller.turn_number(), 1, "the removed end-turn action must not advance the turn"
	)

	# ADR-011 sections 3 and 11: the player selects a deck tile and stages the
	# pending line on the board before confirming. Selecting is what names the
	# tile the next staging command takes from the deck.
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if not check_eq(
		pair.size(), TILES_PER_LINE, "a deck of six from four ranks must hold a pair"
	):
		return
	check(controller.select_deck_tile(pair[0].tile_id), "a deck tile may be selected")
	check_eq(
		String(controller.selected_deck_tile_id()),
		String(pair[0].tile_id),
		"the selection is the tile the next staging command takes"
	)
	check_eq(
		String(controller.human_tile().tile_id),
		String(pair[0].tile_id),
		"the selected tile is the tile the staging commands place"
	)

	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if not check_eq(cells.size(), TILES_PER_LINE, "the opening board must offer a two-cell line"):
		return
	for index: int in range(cells.size()):
		check(
			controller.stage_tile(pair[index].tile_id, cells[index], 0),
			"the selected deck tile must stage at %s" % BoardEnums.cell_name(cells[index])
		)
		if index == 0:
			check(
				not controller.is_line_valid(),
				"ADR-011 section 1: one staged tile is not yet a legal whole move"
			)
	check(controller.has_pending(), "the staged line must be outstanding")
	check(
		controller.is_line_valid(),
		"a contiguous pair of one rank is a legal line: %s" % controller.line_reason()
	)

	var committed: LineResult = controller.commit_line()
	if not check(
		committed != null and committed.was_committed(),
		"the assembled line must commit as one move (ADR-011 section 5)"
	):
		return

	check_eq(
		board.occupied_count(),
		TILES_PER_LINE,
		"the whole staged line must reach the board in one commit"
	)
	check_eq(session.move_count(), 1, "the whole line is one move in the history")
	check(
		session.has_move_id(ScoringCoordinator.move_id_for(MATCH_ID, 1, 1)),
		"the line of turn 1 is that turn's one move, at placement index 1 (ADR-011 section 7)"
	)
	check(not controller.has_pending(), "a committed line clears the staging state")

	# ADR-011 section 7: the commit closed the turn and handed play to the rival.
	check(not controller.is_human_turn(), "the committed line hands play to the rival")
	check(
		TurnManager.is_awaiting_ai_action(session),
		"the turn boundary must reach the opponent's action phase"
	)

	# ADR-011 section 8: the deck is refilled by the number of tiles the line used
	# and topped back up to deck_size at the turn boundary, and nowhere else.
	check_eq(
		session.deck_count(HUMAN),
		DECK_SIZE,
		"the human's deck is refilled to deck_size at the turn boundary"
	)
	check_eq(
		pot_after_setup - session.remaining_tile_count(),
		TILES_PER_LINE,
		"the refill takes exactly the tiles the line consumed"
	)
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival holds a full deck for its turn")
	check_eq(
		session.get_turn_state().turn_number, 2, "the committed line advances the turn number"
	)


## Assembles and commits the human's opening line through the controller.
##
## ADR-011 sections 1, 3, and 11: a legal move is a contiguous line of two or more
## deck tiles of one rank, staged on the board and confirmed as a whole. Returns
## the commit result, or null when this hand cannot supply the pair the line
## needs.
func _commit_opening_line(controller: GameSessionController) -> LineResult:
	var board: BoardState = controller.get_board()
	if board == null:
		return null
	var pair: Array[TileDefinition] = _rank_pair(controller.human_deck(), TILES_PER_LINE)
	if pair.size() < TILES_PER_LINE:
		return null
	var cells: Array[Vector2i] = _line_cells(board, TILES_PER_LINE)
	if cells.size() < TILES_PER_LINE:
		return null
	for index: int in range(cells.size()):
		controller.select_deck_tile(pair[index].tile_id)
		if not controller.stage_tile(pair[index].tile_id, cells[index], 0):
			return null
	return controller.commit_line()


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


## Returns `count` tiles of one rank from `deck`, or an empty array.
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
