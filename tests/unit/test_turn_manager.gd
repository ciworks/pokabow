extends TestCase

## Milestone 4 turn sequencing tests (ADR-003 sections 1 to 8), retargeted to the
## whole-line move and the one-move turn of ADR-011 sections 1, 5, 6, 7, and 8.
##
## Domain-level: no scene tree, no rendering, no input. Every expectation is
## checked against the session, the turn state, and the commit result.
##
## ADR-011 changes three things this suite previously fixed as ADR-010 rules, and
## the expectations below follow the new rules rather than the superseded ones:
##
## - a move is one line of two or more deck tiles committed atomically, so a
##   commit places several cells at once and carries ONE move identifier and ONE
##   history entry (ADR-011 sections 1 and 5);
## - a turn is exactly one move, so a committed line closes the turn itself and
##   ADR-010 section 4's explicit end-turn action is gone (ADR-011 section 7).
##   A player who cannot form a line swaps instead (section 6);
## - the deck is refilled by the number of tiles the move used, capped by the pot,
##   and then topped back up to `deck_size` (ADR-011 section 8, ADR-010
##   section 5). The end conditions are unchanged (ADR-011 section 9).
##
## The uniform default rank weights give every deck of six at least a pair, since
## six tiles drawn from four ranks cannot all differ. Where a test needs a pair
## guaranteed regardless of the seed it uses the all-Ace generation rules, which
## ADR-004 section 8 allows because weights are data.
##
## Where a rule is stated as a pure function of committed totals (the winner and
## draw rule of ADR-003 section 8) it is tested both directly and against a real
## played match, so the rule and the match cannot drift apart.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

const NONE_REJECTION: int = PlacementEnums.PlacementRejection.NONE
const OPENING_REQUIRED: int = PlacementEnums.PlacementRejection.OPENING_CELL_REQUIRED
const NOT_CONNECTED: int = PlacementEnums.PlacementRejection.NOT_CONNECTED
const NOT_PLAYERS_TURN: int = PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN
const DUPLICATE_MOVE: int = PlacementEnums.PlacementRejection.DUPLICATE_MOVE
const MATCH_FINISHED: int = PlacementEnums.PlacementRejection.MATCH_FINISHED
const INVALID_ROTATION: int = PlacementEnums.PlacementRejection.INVALID_ROTATION
const LONE_TILE: int = PlacementEnums.PlacementRejection.LONE_TILE

## The Phase 1 deck size every deck is filled to (ADR-010 section 1).
const DECK_SIZE: int = DeckRules.DEFAULT_DECK_SIZE

## Tiles dealt at `MATCH_SETUP`: one deck per Phase 1 player (ADR-010 section 2).
const TILES_DEALT_AT_SETUP: int = DECK_SIZE * 2

## Tiles the pot still holds once both decks are dealt (ADR-010 section 2).
##
## The real generation rules hold 52 tiles (ADR-004 section 1, amended
## 2026-09-23), so dealing twelve leaves 40. Every use of this constant below
## runs against a session built from the real default rules.
const POT_AFTER_SETUP: int = TileGenerationRules.DEFAULT_BAG_SIZE - TILES_DEALT_AT_SETUP

## The opening line every match in this suite opens with: a horizontal pair of
## two of the four central cells (ADR-006 section 2, ADR-011 sections 1 and 4).
const OPENING_LINE: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]


func test_setup_hands_the_first_turn_to_the_human() -> void:
	var session: GameSessionState = _new_session(&"turn-a", 11)

	check_eq(
		TurnManager.setup(session),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"setup must open the first action phase"
	)

	var turn_state: TurnState = session.get_turn_state()
	check_eq(turn_state.active_player_id, HUMAN, "the human takes the first turn")
	check_eq(turn_state.turn_number, 1, "the first turn is turn 1")
	check_eq(turn_state.consecutive_no_tile_skips, 0, "a fresh match has no skips")
	check_eq(turn_state.last_skip_reason, TurnEnums.SkipReason.NONE, "nothing has been skipped")

	# ADR-010 section 2: both decks are filled at setup, human first then AI.
	check_eq(
		session.deck_count(HUMAN), DECK_SIZE, "the human's deck is filled to deck_size"
	)
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival's deck is filled to deck_size")
	check(
		session.has_active_tile(HUMAN), "the human must be holding tiles to act with"
	)
	check(_holds_a_pair(session, HUMAN), "a deck of six from four ranks always holds a pair")
	check_eq(
		session.remaining_tile_count(),
		POT_AFTER_SETUP,
		"dealing twelve tiles leaves 40 in the shared pot"
	)
	check_eq(
		session.remaining_tile_count()
			+ session.deck_count(HUMAN)
			+ session.deck_count(AI)
			+ session.get_board().occupied_count(),
		TileGenerationRules.DEFAULT_BAG_SIZE,
		"the pot, both decks, and the board must account for all 52 tiles"
	)
	check_eq(
		session.verify_tile_conservation().size(),
		0,
		"every tile must sit in exactly one place after the deal: %s"
		% str(session.verify_tile_conservation())
	)
	check_eq(session.get_board().occupied_count(), 0, "setup must not place a tile")
	check(TurnManager.is_awaiting_human_action(session), "the human may act now")
	check(not TurnManager.is_awaiting_ai_action(session), "it is not the AI's turn")


func test_setup_is_refused_once_the_match_has_started() -> void:
	var session: GameSessionState = _new_session(&"turn-b", 12)
	TurnManager.setup(session)
	var dealt_ids: PackedStringArray = _deck_ids(session, HUMAN)
	var held_id: StringName = session.active_tile_for(HUMAN).tile_id
	var remaining_before: int = session.remaining_tile_count()

	check_eq(
		TurnManager.setup(session),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"a second setup must leave the match where it is"
	)

	check_eq(session.get_turn_state().turn_number, 1, "a second setup must not reset the turn")
	check_eq(
		session.active_tile_for(HUMAN).tile_id,
		held_id,
		"a second setup must not deal a replacement tile"
	)
	check_eq(
		_deck_ids(session, HUMAN),
		dealt_ids,
		"a second setup must not redeal the human's deck"
	)
	check_eq(
		session.deck_count(AI), DECK_SIZE, "a second setup must not redeal the rival's deck"
	)
	check_eq(
		session.remaining_tile_count(),
		remaining_before,
		"a second setup must not consume a tile"
	)


func test_a_committed_line_is_one_atomic_move_that_ends_the_turn() -> void:
	# ADR-011 sections 1, 5, and 7: one line, one transaction, one move
	# identifier, one history entry, and the turn closes on the commit.
	var session: GameSessionState = _new_session(&"turn-c", 13)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()
	var deck_ids: PackedStringArray = _deck_ids(session, HUMAN)
	# Read the fixture's line tiles BEFORE the commit: the commit takes them out
	# of the deck, so the pair has to be captured from the hand as it was dealt.
	var expected_pair: Array[TileDefinition] = _pair_tiles(session, HUMAN, OPENING_LINE.size())

	var result: LineResult = _commit_line_at(session, HUMAN, OPENING_LINE)

	check_not_null(result, "the commit must produce a structured result")
	check(result.was_committed(), "the opening line must commit: %s" % result.describe())
	check_eq(result.rejection, NONE_REJECTION, "an accepted line carries no rejection")
	check_eq(result.staged_count(), 2, "the line stages exactly the tiles the move placed")
	check_eq(board.occupied_count(), 2, "one committed line writes both of its tiles together")

	# ADR-011 sections 3 and 4: the opening line must be a pair, so the fixture
	# stages two tiles of ONE rank, which are not necessarily the first two the
	# deck was dealt. The commit places the tiles in row-major cell order, so the
	# expected tile of each cell is the fixture's line pair in that order, and the
	# two placed tiles are asserted to be that pair rather than the deck's first
	# two.
	if check_eq(expected_pair.size(), OPENING_LINE.size(), "the fixture must supply a held pair"):
		check_eq(
			board.get_tile(OPENING_LINE[0]).get_tile_id(),
			expected_pair[0].tile_id,
			"the first tile placed is the fixture's first line tile"
		)
		check_eq(
			board.get_tile(OPENING_LINE[1]).get_tile_id(),
			expected_pair[1].tile_id,
			"the second tile placed is the fixture's second line tile"
		)
		check_eq(
			int(expected_pair[0].rank),
			int(expected_pair[1].rank),
			"the placed pair must share a rank, which is what makes the line legal"
		)
		check(
			deck_ids.has(String(expected_pair[0].tile_id))
				and deck_ids.has(String(expected_pair[1].tile_id)),
			"both placed tiles must come from the human's own deck"
		)
	check_eq(
		String(result.move_id),
		"move:turn-c:1:1",
		"the whole line carries ONE move identifier: match, turn, and index 1"
	)
	check(session.has_move_id(result.move_id), "the committed move joins the history")
	check_eq(session.move_count(), 1, "the whole line is ONE history entry")
	check_eq(
		session.last_move().placement_count(),
		2,
		"the history entry carries every tile of the line"
	)
	check_eq(
		session.deck_count(HUMAN),
		DECK_SIZE - 2,
		"both committed tiles leave their owner's deck"
	)
	check_eq(
		session.remaining_tile_count(),
		POT_AFTER_SETUP,
		"the pot is untouched until the turn boundary: refill happens there"
	)

	# ADR-011 section 7: the committed line ends the turn.
	check_eq(
		TurnManager.resolve(session, result),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"a committed line closes the turn and opens the rival's"
	)

	var turn_state: TurnState = session.get_turn_state()
	check_eq(turn_state.active_player_id, AI, "the committed line passes the turn")
	check_eq(turn_state.turn_number, 2, "the committed line advances the turn number")
	check_eq(turn_state.placements_this_turn, 0, "seating the rival restarts the move index")
	check_eq(session.next_placement_index(), 1, "the new turn's move is index 1")
	check(not TurnManager.is_awaiting_human_action(session), "the human no longer acts")
	check(TurnManager.is_awaiting_ai_action(session), "the rival acts now")
	check_eq(
		turn_state.consecutive_no_tile_skips, 0, "committing a line keeps the skip count clear"
	)

	# ADR-011 section 8: the deck is refilled by the number of tiles the line used.
	var taken: int = POT_AFTER_SETUP - session.remaining_tile_count()
	check_eq(taken, 2, "the refill takes exactly the number of tiles the line consumed")
	check_eq(
		session.deck_count(HUMAN),
		DECK_SIZE,
		"the human's deck is filled back to deck_size at the turn boundary"
	)
	check_eq(
		session.verify_tile_conservation().size(),
		0,
		"the refill must keep every tile in exactly one place"
	)


func test_a_turn_holds_exactly_one_move() -> void:
	# ADR-011 section 7: a turn is ONE move. There is no end-turn action to close
	# a longer turn, so a second move in the same turn is simply out of turn.
	var session: GameSessionState = _new_session(&"turn-c2", 113)
	TurnManager.setup(session)

	var first: LineResult = _commit_line_at(session, HUMAN, OPENING_LINE)
	check(first.was_committed(), "the human's line must commit")

	var turn_state: TurnState = session.get_turn_state()
	check_eq(turn_state.placements_this_turn, 1, "the turn holds exactly one committed move")
	check_eq(
		String(first.move_id),
		"move:turn-c2:1:1",
		"the move of turn 1 carries index 1, because a turn has only one move"
	)

	check_eq(
		TurnManager.resolve(session, first),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"resolving the human's line opens the rival's turn"
	)
	check_eq(turn_state.active_player_id, AI, "play passes on the committed line")
	check_eq(turn_state.turn_number, 2, "the turn number advances once for one move")

	# The human's turn is over, so a second line for the human is refused.
	var again: LineResult = _commit_line_at(session, HUMAN, [Vector2i(7, 5), Vector2i(8, 5)])
	check(not again.accepted, "a player cannot take a second move in the closed turn")
	check_eq(again.rejection, NOT_PLAYERS_TURN, "the reason names turn ownership")
	check_eq(session.move_count(), 1, "the refused second move records nothing")

	# The rival takes its own single move, at index 1 of its turn.
	var rival: LineResult = _commit_line_at(session, AI, [Vector2i(7, 5), Vector2i(8, 5)])
	check(rival.was_committed(), "the rival's line must commit: %s" % rival.describe())
	check_eq(
		String(rival.move_id),
		"move:turn-c2:2:1",
		"the rival's move is index 1 of turn 2, not a continuation of the human's turn"
	)
	check_eq(
		TurnManager.resolve(session, rival),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"the rival's line ends its turn too"
	)
	check_eq(session.move_count(), 2, "two turns hold exactly two moves")
	check_eq(turn_state.turn_number, 3, "the turn number advances once per move")


func test_a_swap_consumes_the_whole_turn_without_placing_a_tile() -> void:
	# ADR-011 section 6 replaces ADR-010 section 4's explicit pass: a player who
	# cannot or will not form a line returns deck tiles for equal replacements and
	# that is their whole turn.
	var session: GameSessionState = _new_session(&"turn-n", 23)
	TurnManager.setup(session)
	var turn_state: TurnState = session.get_turn_state()
	var before_ids: PackedStringArray = _deck_ids(session, HUMAN)
	var returned: Array[StringName] = [StringName(before_ids[0]), StringName(before_ids[1])]

	check_eq(
		session.deck_count(HUMAN), DECK_SIZE, "the human holds a deck before deciding to swap"
	)

	var swapped: int = session.request_swap(HUMAN, returned)
	check_eq(swapped, 2, "the pot supplied a two-tile swap")

	check_eq(
		TurnManager.resolve_swap(session, swapped),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"a resolved swap closes the turn and opens the rival's"
	)

	check_eq(turn_state.active_player_id, AI, "the swap hands play to the rival")
	check_eq(turn_state.turn_number, 2, "the swap advances the turn number")
	check_eq(session.get_board().occupied_count(), 0, "a swap cannot place a tile")
	check_eq(session.move_count(), 0, "a swap records no move and cannot score")
	check_eq(
		session.deck_count(HUMAN), DECK_SIZE, "two tiles returned and two replacements drawn"
	)
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival's deck is untouched by the swap")
	check_eq(
		session.remaining_tile_count(),
		POT_AFTER_SETUP,
		"a swap returns as many tiles to the pot as it draws"
	)
	var after_ids: PackedStringArray = _deck_ids(session, HUMAN)
	check(after_ids != before_ids, "the replacements are different tiles")
	check(
		not after_ids.has(before_ids[0]) and not after_ids.has(before_ids[1]),
		"the returned tiles are not drawn straight back"
	)
	check_eq(
		session.verify_tile_conservation().size(),
		0,
		"a swap must keep every tile in exactly one place"
	)


func test_a_swap_the_pot_cannot_supply_is_refused_and_keeps_the_turn() -> void:
	# ADR-011 section 6: when the pot cannot supply the whole swap, the swap is
	# refused and the player keeps their tiles.
	var generation: TileGenerationRules = _all_ace_generation(TILES_DEALT_AT_SETUP)
	var deck_rules: DeckRules = DeckRules.new()
	deck_rules.deck_size = DECK_SIZE
	var session: GameSessionState = GameSessionState.create(
		&"turn-n2", 123, ScoringRules.create_default(), generation, deck_rules
	)
	check_not_null(session, "the session must be constructible")
	TurnManager.setup(session)

	check_eq(session.remaining_tile_count(), 0, "the whole pot is dealt, so it can supply nothing")
	var before_ids: PackedStringArray = _deck_ids(session, HUMAN)
	var returned: Array[StringName] = [StringName(before_ids[0])]

	check_eq(session.request_swap(HUMAN, returned), -1, "a swap with an empty pot is refused")
	check_eq(
		TurnManager.resolve_swap(session, -1),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"a refused swap does not consume the turn"
	)

	var turn_state: TurnState = session.get_turn_state()
	check_eq(turn_state.active_player_id, HUMAN, "the turn stays with the human")
	check_eq(turn_state.turn_number, 1, "a refused swap does not advance the turn")
	check_eq(_deck_ids(session, HUMAN), before_ids, "the player keeps their tiles")
	check_eq(session.move_count(), 0, "a refused swap records nothing")
	check_eq(session.verify_tile_conservation().size(), 0, "a refused swap changes no tile's home")


func test_an_illegal_line_does_not_consume_the_turn() -> void:
	var session: GameSessionState = _new_session(&"turn-d", 14)
	TurnManager.setup(session)
	var held_id: StringName = session.active_tile_for(HUMAN).tile_id

	# (0, 0) and (1, 0) are empty and in bounds but outside the opening cells.
	var result: LineResult = _commit_line_at(session, HUMAN, [Vector2i(0, 0), Vector2i(1, 0)])

	check_not_null(result, "a refused line is still a structured result")
	check(not result.accepted, "a line outside the opening cells must be refused")
	check_eq(result.rejection, OPENING_REQUIRED, "the reason names the opening rule")
	check_eq(session.get_board().occupied_count(), 0, "a refused line places nothing")
	check_eq(session.get_turn_state().turn_number, 1, "a refused line does not advance the turn")
	check_eq(session.get_turn_state().active_player_id, HUMAN, "the turn stays with the human")
	check_eq(
		session.active_tile_for(HUMAN).tile_id,
		held_id,
		"a refused line keeps the armed tile"
	)
	check_eq(
		session.deck_count(HUMAN), DECK_SIZE, "a refused line consumes no deck tile"
	)
	check_eq(
		session.remaining_tile_count(),
		POT_AFTER_SETUP,
		"a refused line consumes no tile from the pot"
	)
	check_eq(session.get_ledger().size(), 0, "a refused line scores nothing")
	check_eq(session.move_count(), 0, "a refused line is not recorded")
	check_eq(
		TurnManager.resolve(session, result),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"resolving a refused line leaves the match awaiting action"
	)
	check_eq(session.get_turn_state().turn_number, 1, "resolving a refusal still does not advance")
	check_eq(session.move_count(), 0, "resolving a refusal records nothing")
	check(session.has_active_tile(HUMAN), "the human still holds tiles after a refusal")
	check_eq(
		session.next_placement_index(),
		1,
		"a refused line consumes no move identifier, so a retry is still index 1"
	)


func test_a_lone_tile_is_not_a_move() -> void:
	# ADR-011 sections 1 and 4: a move places two or more tiles, because a single
	# tile cannot form a hand.
	var session: GameSessionState = _new_session(&"turn-p", 41)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()
	var tile: TileDefinition = session.deck_for(HUMAN)[0]
	var single: Array[TileSnapshot] = [
		TileSnapshot.create(tile, OPENING_LINE[0], 0),
	]

	var result: LineResult = MoveCommitter.commit_line(session, HUMAN, single)

	check_not_null(result, "the refusal is still a structured result")
	check(not result.accepted, "one tile is not a legal move")
	check_eq(result.rejection, LONE_TILE, "the reason names the lone-tile rule")
	check_eq(board.occupied_count(), 0, "a lone tile places nothing")
	check_eq(session.deck_count(HUMAN), DECK_SIZE, "a lone tile consumes no deck tile")
	check_eq(session.move_count(), 0, "a lone tile is not recorded")


func test_a_line_rotation_travels_with_its_tile() -> void:
	# ADR-011 section 11: rotation updates the pending line without writing to the
	# board, and the rotation committed is the rotation of that tile. The
	# request-shaped rotation refusal of ADR-006 section 5 still owns the
	# vocabulary for a placement request.
	var session: GameSessionState = _new_session(&"turn-e", 15)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()
	var tiles: Array[TileDefinition] = _pair_tiles(session, HUMAN, 2)
	var staged: Array[TileSnapshot] = [
		TileSnapshot.create(tiles[0], Vector2i(5, 5), 1),
		TileSnapshot.create(tiles[1], Vector2i(5, 6), 2),
	]

	var result: LineResult = MoveCommitter.commit_line(session, HUMAN, staged)

	check(result.was_committed(), "a vertical pair is a legal opening line: %s" % result.describe())
	check_eq(
		board.get_tile(Vector2i(5, 5)).get_rotation(), 1, "each tile keeps its own rotation"
	)
	check_eq(
		board.get_tile(Vector2i(5, 6)).get_rotation(), 2, "each tile keeps its own rotation"
	)

	# ADR-011 section 7: committing the line does not advance the turn by itself;
	# the caller pairs the commit with the resolution, exactly as the live path
	# does, so the turn the refused request below must not touch is the rival's.
	check_eq(
		TurnManager.resolve(session, result),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"the committed line must be resolved to close the turn"
	)

	# A tile outside the deck, so this request can only be refused for its
	# rotation: ADR-006 section 5 rejects an out-of-range rotation before it
	# considers whether the tile is available, which is the vocabulary a
	# per-placement request still owns.
	var outside_deck: TileDefinition = TileDefinition.create(
		&"turn-e:outside-the-deck",
		TileEnums.TileRank.ACE,
		TileEnums.FaceColor.RED,
		[
			TileEnums.EdgeColor.BLUE,
			TileEnums.EdgeColor.BLUE,
			TileEnums.EdgeColor.BLUE,
			TileEnums.EdgeColor.BLUE,
		]
	)
	var request: PlacementRequest = PlacementRequest.create(
		HUMAN, outside_deck.tile_id, Vector2i(7, 5), 4
	)
	var refused: PlacementResult = PlacementValidator.validate(board, request, outside_deck, true)
	check_not_null(refused, "the request-shaped validator still answers")
	check(not refused.accepted, "a fifth orientation is not a rotation")
	check_eq(refused.rejection, INVALID_ROTATION, "the reason names the rotation rule")
	check_eq(
		session.get_turn_state().turn_number,
		2,
		"a refused request-shaped placement does not touch the turn"
	)


func test_the_wrong_player_cannot_move() -> void:
	var session: GameSessionState = _new_session(&"turn-f", 16)
	TurnManager.setup(session)

	var result: LineResult = _commit_line_at(session, AI, OPENING_LINE)

	check(not result.accepted, "the inactive player must not be able to move")
	check_eq(result.rejection, NOT_PLAYERS_TURN, "the reason names turn ownership")
	check_eq(session.get_board().occupied_count(), 0, "nothing may be placed out of turn")
	check_eq(session.get_turn_state().turn_number, 1, "the turn must not advance")
	check_eq(session.deck_count(AI), DECK_SIZE, "an out-of-turn move consumes no deck tile")
	check_eq(
		session.next_placement_index(), 1, "an out-of-turn move consumes no move identifier"
	)


func test_a_repeated_move_identifier_is_refused_before_anything_changes() -> void:
	var session: GameSessionState = _new_session(&"turn-g", 17)
	TurnManager.setup(session)
	var board: BoardState = session.get_board()
	var first: LineResult = _commit_line_at(session, HUMAN, OPENING_LINE)
	check(first.was_committed(), "the first line must commit")
	check_eq(String(first.move_id), "move:turn-g:1:1", "the line of turn 1 is index 1")
	TurnManager.resolve(session, first)

	# Re-open turn 1 in the action phase, which is exactly the state a retry of
	# the committed line would present: ADR-011 section 7 makes a turn one move,
	# so the identifier of that turn is the only one a caller can re-present.
	var turn_state: TurnState = session.get_turn_state()
	turn_state.active_player_id = HUMAN
	turn_state.turn_number = 1
	turn_state.placements_this_turn = 0
	turn_state.phase = TurnEnums.MatchPhase.AWAIT_ACTION

	var occupied_before: int = board.occupied_count()
	var ledger_before: int = session.get_ledger().size()
	var deck_before: int = session.deck_count(HUMAN)

	var repeat: LineResult = _commit_line_at(session, HUMAN, [Vector2i(7, 5), Vector2i(8, 5)])

	check(not repeat.accepted, "a move identifier may be committed at most once")
	check_eq(repeat.rejection, DUPLICATE_MOVE, "the reason names the duplicate move")
	check_eq(board.occupied_count(), occupied_before, "a refused retry places nothing")
	check_eq(session.get_ledger().size(), ledger_before, "a refused retry scores nothing")
	check_eq(session.deck_count(HUMAN), deck_before, "a refused retry consumes no deck tile")
	check_eq(session.move_count(), 1, "the history keeps exactly one move")


func test_a_finished_match_refuses_further_moves() -> void:
	var session: GameSessionState = _new_session(&"turn-h", 18)
	TurnManager.setup(session)
	session.finish(TurnEnums.MatchOutcome.DRAW, TurnEnums.EndReason.BOARD_FULL)
	session.get_turn_state().phase = TurnEnums.MatchPhase.GAME_OVER

	var result: LineResult = _commit_line_at(session, HUMAN, OPENING_LINE)

	check(not result.accepted, "a finished match must refuse a move")
	check_eq(result.rejection, MATCH_FINISHED, "the reason names the finished match")
	check_eq(session.get_board().occupied_count(), 0, "nothing may be placed after the match")
	check_eq(session.deck_count(HUMAN), DECK_SIZE, "a finished match consumes no deck tile")
	check(session.is_over(), "the session reports the match is over")


func test_neither_player_holding_a_tile_while_the_pot_is_empty_ends_the_match() -> void:
	# ADR-010 section 7 condition 2, kept by ADR-011 section 9: the match ends when
	# neither player holds a tile and the pot cannot supply one. The all-Ace rules
	# guarantee every held pair is a legal line, so the supply is the only thing
	# under test.
	var generation: TileGenerationRules = _all_ace_generation(4)
	var deck_rules: DeckRules = DeckRules.new()
	deck_rules.deck_size = 2
	var session: GameSessionState = GameSessionState.create(
		&"turn-i", 19, ScoringRules.create_default(), generation, deck_rules
	)
	check_not_null(session, "a four-tile match must be constructible")
	TurnManager.setup(session)
	var board: BoardState = session.get_board()

	check_eq(session.deck_count(HUMAN), 2, "a deck_size of two deals two tiles to each player")
	check_eq(session.deck_count(AI), 2, "a deck_size of two deals two tiles to each player")
	check_eq(session.remaining_tile_count(), 0, "the whole pot is dealt at setup")
	check_eq(
		TurnManager.detect_end_reason(session),
		TurnEnums.EndReason.NONE,
		"the match continues while a player still holds a tile"
	)

	var human_move: LineResult = _commit_line_at(session, HUMAN, OPENING_LINE)
	check(human_move.was_committed(), "the human's line must commit: %s" % human_move.describe())
	check_eq(
		TurnManager.resolve(session, human_move),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"play continues because the rival still holds a tile"
	)
	check_eq(
		session.deck_count(HUMAN), 0, "both of the human's tiles left the deck when they were placed"
	)

	var ai_move: LineResult = _commit_line_at(session, AI, [Vector2i(7, 5), Vector2i(8, 5)])
	check(ai_move.was_committed(), "the AI's line must commit: %s" % ai_move.describe())
	check_eq(
		TurnManager.resolve(session, ai_move),
		TurnEnums.MatchPhase.GAME_OVER,
		"the match ends when neither player holds a tile and the pot is empty"
	)

	var turn_state: TurnState = session.get_turn_state()
	check_eq(
		session.get_end_reason(),
		TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED,
		"the end reason is the empty pot"
	)
	check_eq(board.occupied_count(), 4, "both lines were placed in full")
	check_eq(session.deck_count(HUMAN), 0, "no player holds a tile at the end")
	check_eq(session.deck_count(AI), 0, "no player holds a tile at the end")
	check(not session.holds_any_tile(), "the end condition is that neither player holds a tile")
	check_eq(session.remaining_tile_count(), 0, "the pot is exhausted")
	check_eq(
		turn_state.turn_number,
		2,
		"the match ends on the turn that emptied the decks without opening another"
	)
	check_eq(
		turn_state.consecutive_no_tile_skips,
		0,
		"no skip count is read: ADR-010 section 7 removed the two-consecutive-skip rule"
	)
	check_eq(
		session.get_outcome(),
		TurnEnums.outcome_for_scores(
			session.score_for(HUMAN), session.score_for(AI), TurnEnums.EndReason.TILE_SOURCE_EXHAUSTED
		),
		"the outcome must match the committed totals"
	)


func test_an_overlong_hand_is_refused_without_ending_the_match() -> void:
	# A line may reach five tiles, but a later move cannot extend it beyond five.
	var session: GameSessionState = GameSessionState.create(
		&"turn-o", 24, ScoringRules.create_default(), _all_ace_generation(BoardEnums.CELL_COUNT)
	)
	check_not_null(session, "the session must be constructible")
	TurnManager.setup(session)
	var board: BoardState = session.get_board()
	var opening: LineResult = _commit_line_at(session, HUMAN, [Vector2i(5, 5), Vector2i(6, 5)])
	check(opening.was_committed(), "the opening pair commits")
	TurnManager.resolve(session, opening)
	var extension: LineResult = _commit_line_at(session, AI, [Vector2i(7, 5), Vector2i(8, 5)])
	check(extension.was_committed(), "a four-tile hand is legal")
	TurnManager.resolve(session, extension)
	var refused: LineResult = _commit_line_at(session, HUMAN, [Vector2i(9, 5), Vector2i(10, 5)])
	check_eq(refused.rejection, PlacementEnums.PlacementRejection.HAND_TOO_LONG, "six tiles are refused")
	check_eq(board.occupied_count(), 4, "the rejected move changes no cells")
	check_eq(session.move_count(), 2, "the rejected move does not enter history")
	check(not session.is_over(), "other placements remain available")


func test_the_winner_rule_has_no_tie_breaker() -> void:
	check_eq(
		TurnEnums.outcome_for_scores(10, 4, TurnEnums.EndReason.BOARD_FULL),
		TurnEnums.MatchOutcome.HUMAN_WIN,
		"the greater committed total wins"
	)
	check_eq(
		TurnEnums.outcome_for_scores(4, 10, TurnEnums.EndReason.BOARD_FULL),
		TurnEnums.MatchOutcome.AI_WIN,
		"either player may win"
	)
	check_eq(
		TurnEnums.outcome_for_scores(7, 7, TurnEnums.EndReason.BOARD_FULL),
		TurnEnums.MatchOutcome.DRAW,
		"equal totals are a draw, with no tie-breaker"
	)
	check_eq(
		TurnEnums.outcome_for_scores(99, 0, TurnEnums.EndReason.RULES_FAILURE),
		TurnEnums.MatchOutcome.INCOMPLETE,
		"an unrecoverable failure awards no winner however the scores stand"
	)


func test_a_rules_failure_stops_the_match_without_a_winner() -> void:
	var session: GameSessionState = _new_session(&"turn-j", 20)
	TurnManager.setup(session)

	check_eq(
		TurnManager.fail_recovery(session, TurnEnums.EndReason.RULES_FAILURE),
		TurnEnums.MatchPhase.RECOVERY_ERROR,
		"a rules failure moves the match into recovery"
	)
	check(session.is_over(), "a match in recovery accepts no further move")
	check_eq(
		session.get_outcome(),
		TurnEnums.MatchOutcome.INCOMPLETE,
		"no winner is awarded"
	)
	check_eq(
		session.get_end_reason(),
		TurnEnums.EndReason.RULES_FAILURE,
		"the end reason is recorded"
	)


func test_human_and_ai_reach_scoring_through_the_same_path() -> void:
	var session: GameSessionState = GameSessionState.create(
		&"turn-k", 21, ScoringRules.create_default(), _all_ace_generation(52)
	)
	if not check_not_null(session, "the same-path fixture must be constructible"):
		return
	TurnManager.setup(session)
	var board: BoardState = session.get_board()

	var human_move: LineResult = _commit_line_at(session, HUMAN, OPENING_LINE)
	check_eq(
		TurnManager.resolve(session, human_move),
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"the human's line ends their turn"
	)
	var ai_move: LineResult = _commit_line_at(session, AI, [Vector2i(7, 5), Vector2i(8, 5)])

	check(human_move.was_committed(), "the human's line commits through the transaction")
	check(ai_move.was_committed(), "the AI's line commits through the same transaction")
	check_eq(
		human_move.move_id,
		StringName("move:turn-k:1:1"),
		"the human's opening line is turn 1, move 1"
	)
	check_eq(
		ai_move.move_id,
		StringName("move:turn-k:2:1"),
		"the rival's opening line is turn 2, move 1"
	)
	check_eq(session.move_count(), 2, "both moves are recorded in history")

	# The same rule refuses both players equally: a line touching nothing.
	var isolated: Vector2i = _isolated_cell(board)
	if isolated != Vector2i(-1, -1):
		TurnManager.resolve(session, ai_move)
		var partner: Vector2i = _adjacent_empty_cell(board, isolated)
		if partner != Vector2i(-1, -1):
			var refused: LineResult = _commit_line_at(session, HUMAN, [isolated, partner])
			check(not refused.accepted, "an unconnected line is refused")
			check_eq(
				refused.rejection,
				NOT_CONNECTED,
				"the connection rule applies to the human exactly as it would to the AI"
			)


func test_the_remaining_count_is_visible_but_the_bag_is_not() -> void:
	var session: GameSessionState = _new_session(&"turn-l", 22)
	TurnManager.setup(session)

	check_eq(
		session.get_tile_source().get_bag_size(),
		TileGenerationRules.DEFAULT_BAG_SIZE,
		"the configured bag holds the 52 tiles of ADR-004 section 1 (amended 2026-09-23)"
	)
	check_eq(session.remaining_tile_count(), POT_AFTER_SETUP, "the remaining count is public")
	check_eq(
		session.get_tile_source().get_draw_index(),
		TILES_DEALT_AT_SETUP,
		"twelve tiles were dealt, and the pot still holds the rest undrawn"
	)

	# ADR-011 section 1: a move takes tiles the player already holds, so the tiles
	# the human would place are members of their own deck.
	var human_tile: TileDefinition = session.active_tile_for(HUMAN)
	check_not_null(human_tile, "the active player's own tile is known to them")
	check(human_tile.is_valid(), "the active player's own tile is a usable tile")
	check(
		session.holds_deck_tile(HUMAN, human_tile.tile_id),
		"the tile the human would place is one of their own deck"
	)

	# ADR-010 section 2 gives both players a deck, so the rival's deck is a known
	# size while its contents are the rival's own business.
	check_eq(session.deck_count(AI), DECK_SIZE, "the rival's deck size is known")
	check_eq(
		session.deck_for(AI).size(), DECK_SIZE, "the rival's deck exists across the turn boundary"
	)


## Builds a standard-rules session at MATCH_SETUP.
func _new_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = GameSessionState.create(
		match_id, seed, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(session, "the session must be constructible")
	return session


## Returns generation rules whose every tile shares one rank, so any held pair is
## the Pair of ADR-012 section 1 and a legal line whatever the seed (ADR-004
## section 8 allows weights to be data).
func _all_ace_generation(bag_size: int) -> TileGenerationRules:
	var rules: TileGenerationRules = TileGenerationRules.new()
	rules.bag_size = bag_size
	rules.rank_weights = [1.0, 0.0, 0.0, 0.0] as Array[float]
	return rules


## Commits a line of `cells` for `player_id`, staging a pair of equal ranks so
## the line is the Pair of ADR-012 section 1 and a legal hand whatever the seed
## dealt.
func _commit_line_at(
	session: GameSessionState, player_id: StringName, cells: Array[Vector2i]
) -> LineResult:
	var tiles: Array[TileDefinition] = _pair_tiles(session, player_id, cells.size())
	var staged: Array[TileSnapshot] = []
	for index: int in range(cells.size()):
		if index >= tiles.size():
			return null
		staged.append(TileSnapshot.create(tiles[index], cells[index], 0))
	return MoveCommitter.commit_line(session, player_id, staged)


## Returns `count` tiles of one player's deck, preferring `count` of equal rank so
## the assembled line is at least the repeated rank of an ADR-012 section 1 Pair.
func _pair_tiles(
	session: GameSessionState, player_id: StringName, count: int
) -> Array[TileDefinition]:
	var deck: Array[TileDefinition] = session.deck_for(player_id)
	var chosen: Array[TileDefinition] = []
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
		if group.size() >= count:
			for tile: TileDefinition in group:
				chosen.append(tile)
				if chosen.size() == count:
					return chosen
	chosen.clear()
	for tile: TileDefinition in deck:
		if tile == null:
			continue
		chosen.append(tile)
		if chosen.size() == count:
			return chosen
	return chosen


## Returns true when a player's deck holds two tiles of one rank.
func _holds_a_pair(session: GameSessionState, player_id: StringName) -> bool:
	var ranks: Dictionary = {}
	for tile: TileDefinition in session.deck_for(player_id):
		if tile == null:
			continue
		var seen: int = int(ranks.get(int(tile.rank), 0)) + 1
		if seen >= 2:
			return true
		ranks[int(tile.rank)] = seen
	return false


## Returns one player's deck as a list of tile identities, in deal order.
func _deck_ids(session: GameSessionState, player_id: StringName) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for tile: TileDefinition in session.deck_for(player_id):
		if tile != null:
			ids.append(String(tile.tile_id))
	return ids


## Returns the grid as a fixed sequence of adjacent cell pairs.
##
## The pairing is a Hamiltonian path over all 144 cells, so 72 two-tile moves
## cover the board exactly once. Two properties are required of the order and both
## are asserted by `test_...`'s own checks below rather than assumed: consecutive
## cells in the path are orthogonally adjacent, so every pair is one contiguous
## line; and the pair boundaries fall so that the first pair covers a central
## opening cell and every later pair contains a cell touching committed tiles.
func _grid_pairs() -> Array:
	var path: Array[Vector2i] = []

	# Row 5 leftwards from the centre, so the first pair covers an opening cell.
	for x: int in range(5, -1, -1):
		path.append(Vector2i(x, 5))
	# Rows 6 to 11, snaking.
	for y: int in range(6, 12):
		if (y - 6) % 2 == 0:
			for x: int in range(0, 12):
				path.append(Vector2i(x, y))
		else:
			for x: int in range(11, -1, -1):
				path.append(Vector2i(x, y))
	# Rows 4 up to 0, snaking.
	for y: int in range(4, -1, -1):
		if (4 - y) % 2 == 0:
			for x: int in range(0, 12):
				path.append(Vector2i(x, y))
		else:
			for x: int in range(11, -1, -1):
				path.append(Vector2i(x, y))
	# The rest of row 5, rightwards from the centre.
	for x: int in range(6, 12):
		path.append(Vector2i(x, 5))

	check_eq(
		path.size(), BoardEnums.CELL_COUNT, "the pairing path must cover every cell exactly once"
	)
	var seen: Dictionary = {}
	for cell: Vector2i in path:
		check(not seen.has(cell), "the pairing path must not repeat a cell")
		seen[cell] = true

	var pairs: Array = []
	for index: int in range(0, path.size() - 1, 2):
		var first: Vector2i = path[index]
		var second: Vector2i = path[index + 1]
		check(
			_is_adjacent(first, second),
			"every paired line must be contiguous: %s and %s"
			% [BoardEnums.cell_name(first), BoardEnums.cell_name(second)]
		)
		var pair: Array[Vector2i] = [first, second]
		pairs.append(pair)

	check_eq(pairs.size() * 2, BoardEnums.CELL_COUNT, "the pairs must cover the board")
	var opening: Array[Vector2i] = pairs[0]
	check(
		BoardEnums.is_opening_cell(opening[0]) or BoardEnums.is_opening_cell(opening[1]),
		"the first line must cover one of the four central opening cells"
	)
	return pairs


## Returns true when two cells are orthogonally adjacent.
func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


## Returns the first empty neighbour of `cell`, or (-1, -1).
func _adjacent_empty_cell(board: BoardState, cell: Vector2i) -> Vector2i:
	for offset: Vector2i in BoardEnums.neighbor_offsets():
		var neighbor: Vector2i = cell + offset
		if board.is_empty_cell(neighbor):
			return neighbor
	return Vector2i(-1, -1)


## Returns the first legal frontier cell in row-major order.
func _first_frontier(board: BoardState) -> Vector2i:
	var frontier: Array[Vector2i] = board.get_frontier_cells()
	if frontier.is_empty():
		return Vector2i(-1, -1)
	return frontier[0]


## Returns an empty in-bounds cell that touches no committed tile, or (-1, -1).
func _isolated_cell(board: BoardState) -> Vector2i:
	for y: int in range(BoardEnums.BOARD_HEIGHT):
		for x: int in range(BoardEnums.BOARD_WIDTH):
			var cell: Vector2i = Vector2i(x, y)
			if board.is_empty_cell(cell) and not board.has_occupied_neighbor(cell):
				return cell
	return Vector2i(-1, -1)
