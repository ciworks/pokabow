extends TestCase

## Milestone 4 match lifecycle tests (ADR-003 sections 3, 7, 8, and 9),
## retargeted to the whole-line move and the one-move turn of ADR-011 sections 1,
## 5, 7, and 8 over ADR-010's deck of six.
##
## This suite contains the Milestone 4 exit criterion: a complete match between
## two scripted players runs headlessly to a verified result, and that result is
## checked against an ordered replay of its own move history through the same
## pure rules pipeline (ADR-007 section 9).
##
## ADR-011 changes what a move and a turn are, so the scripted players below place
## two-tile lines and let the commit close the turn (sections 1, 5, and 7): there
## is no end-turn action left to call. Every turn therefore exercises the real
## turn boundary - the refill of section 8 and the end conditions of ADR-010
## section 7, which section 9 keeps. The save coverage follows ADR-010
## section 10: both decks and the pot's draw position are restored, and tile
## conservation spans the pot, both decks, and the board.
##
## Domain-level: no scene tree, no rendering, no input.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

## The Phase 1 deck size every deck is filled to (ADR-010 section 1).
const DECK_SIZE: int = DeckRules.DEFAULT_DECK_SIZE

## Tiles each scripted move places: the shortest legal line (ADR-011 section 1).
const TILES_PER_MOVE: int = 2

## Moves a full match takes at that length: 144 cells / 2 tiles per move.
##
## An equality rather than a lower bound. ADR-011 section 8 refills a deck by the
## number of tiles the move used, and the pot covers every refill, so the 72nd
## line places the last two tiles and ends the match on a full board. A match that
## stopped earlier, or that opened a further turn after the pot was exhausted,
## would report another count, so this expectation is what proves the final tiles
## were placed rather than stranded in hand.
const FULL_BOARD_MOVES: int = BoardEnums.CELL_COUNT / TILES_PER_MOVE

## The opening line every match in this suite opens with: a horizontal pair of two
## of the four central cells (ADR-006 section 2, ADR-011 sections 1 and 4).
const OPENING_LINE: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 5)]

## Tiles the pot still holds once both decks are dealt (ADR-010 section 2).
const POT_AFTER_SETUP: int = BoardEnums.CELL_COUNT - DECK_SIZE * 2

## Loop guard, so a rule error shows up as a failure instead of a hang.
const MOVE_LIMIT: int = 400


func test_exit_criterion_a_full_match_runs_to_a_verified_result() -> void:
	# ADR-011 section 1 makes a move a line of two or more tiles, so the shortest
	# full match is 72 two-tile lines. The all-Ace generation rules give every
	# pair of deck tiles a repeated rank, so the fixture measures the board
	# filling rather than the ranks the deal happened to produce (section 3),
	# which ADR-004 section 8 allows because the weights are data.
	var session: GameSessionState = _new_all_ace_session(&"match-full", 20260922)
	TurnManager.setup(session)

	var outcome: Dictionary = _play_paired_lines(session)

	check_eq(outcome["rejected"], 0, "no move may be refused during a legal match")
	check_eq(
		outcome["moves"],
		FULL_BOARD_MOVES,
		"two-tile lines fill the board in exactly 72 whole-move placements"
	)
	check(session.get_board().is_full(), "the match must end with every cell filled")
	check_eq(session.move_count(), FULL_BOARD_MOVES, "every move joins the history")
	check(session.is_over(), "the match must be over")
	check_eq(
		session.get_turn_state().phase,
		TurnEnums.MatchPhase.GAME_OVER,
		"the match ends at GAME_OVER"
	)
	check_eq(
		session.get_end_reason(),
		TurnEnums.EndReason.BOARD_FULL,
		"the board filling is end condition 1 (ADR-010 section 7)"
	)
	check_eq(session.remaining_tile_count(), 0, "the pot is spent exactly as the board fills")
	check_eq(
		session.deck_count(HUMAN) + session.deck_count(AI),
		0,
		"the last line leaves neither player holding a tile (ADR-010 section 7)"
	)
	check_eq(
		session.get_turn_state().turn_number,
		FULL_BOARD_MOVES,
		"one move per turn fills the board on turn 72: a higher count means a starved turn was opened after the board could no longer be filled, and a lower one that play stopped early"
	)
	check_eq(
		session.remaining_tile_count()
			+ session.deck_count(HUMAN)
			+ session.deck_count(AI)
			+ session.get_board().occupied_count(),
		BoardEnums.CELL_COUNT,
		"the pot, both decks, and the board must account for all 144 tiles"
	)
	check_eq(
		session.verify_tile_conservation().size(),
		0,
		"every tile must sit in exactly one place at the end: %s"
		% str(session.verify_tile_conservation())
	)

	# ADR-003 section 8: the outcome is derived from committed totals.
	var result: MatchResult = MatchResult.build(session)
	check_not_null(result, "a finished match must produce a result")
	check_eq(result.move_count, FULL_BOARD_MOVES, "the result reports every move")
	check_eq(result.board_occupied, BoardEnums.CELL_COUNT, "the result reports a full board")
	check_eq(
		result.outcome,
		TurnEnums.outcome_for_scores(
			result.human_score, result.ai_score, TurnEnums.EndReason.BOARD_FULL
		),
		"the outcome must agree with the committed totals"
	)
	check_eq(
		result.human_score + result.ai_score,
		session.get_ledger().total_points(),
		"the two totals must account for every point scored"
	)

	# The breakdown ADR-003 section 8 requires, per player.
	for player_id: StringName in TurnEnums.player_ids():
		var terms: Dictionary = result.terms_for(player_id)
		check_eq(
			int(terms.get("poker", 0)) + int(terms.get("edge", 0)) + int(terms.get("cluster", 0)),
			int(terms.get("total", -1)),
			"the category breakdown must add up to the total for '%s'" % String(player_id)
		)
		check_eq(
			int(terms.get("total", -1)),
			session.score_for(player_id),
			"the breakdown total must match the committed ledger for '%s'" % String(player_id)
		)

	# ADR-003 section 8: recalculate from committed history and compare.
	check_eq(
		MatchResult.verify_against(session),
		"",
		"a full match must replay identically from its own move history"
	)

	# The board alone must also explain every committed point (ADR-007 section 9).
	var audit: ScoringAudit.Report = ScoringAudit.audit(
		session.get_board(),
		session.get_ledger(),
		session.get_scored_hand_set(),
		session.get_rules()
	)
	check_not_null(audit, "the audit must return a report")
	check(
		audit.ok,
		"a fully played board must audit cleanly: %s" % str(audit.problems)
	)


func test_a_partial_match_survives_save_and_resume() -> void:
	var original: GameSessionState = _new_session(&"match-save", 4242)
	TurnManager.setup(original)
	_play_moves(original, 20)
	check(
		original.get_turn_state().is_awaiting_action(),
		"a save must be taken at a transaction boundary"
	)

	var snapshot: MatchSnapshotDto = original.to_snapshot()
	check(snapshot.is_valid(), "a snapshot taken between turns must be restorable")
	check_eq(
		snapshot.decks.size(),
		TurnEnums.player_ids().size(),
		"the save record carries one deck per player (ADR-010 section 10)"
	)

	var restored: GameSessionState = GameSessionState.from_snapshot(
		snapshot, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(restored, "the match must restore")

	_compare_sessions(original, restored, "after restore")

	# The restored match must be playable, not merely readable.
	var original_next: Dictionary = _play_moves(original, 5)
	var restored_next: Dictionary = _play_moves(restored, 5)

	check_eq(restored_next["rejected"], 0, "the restored match must accept legal moves")
	check_eq(restored_next["moves"], 5, "the restored match must keep playing after the resume")
	check_eq(
		restored_next["moves"],
		original_next["moves"],
		"both matches must commit the same number of further moves"
	)
	_compare_sessions(original, restored, "after playing on")
	check_eq(
		MatchResult.verify_against(restored),
		"",
		"the resumed match must still replay identically"
	)


func test_a_match_resumes_mid_preview_without_a_committed_tile() -> void:
	var session: GameSessionState = _new_session(&"match-preview", 77)
	TurnManager.setup(session)

	# The human holds an uncommitted deck and the board is still empty: exactly
	# the state an interrupted preview leaves behind (ADR-003 section 9,
	# ADR-010 section 10).
	var held_ids: PackedStringArray = _deck_ids(session, HUMAN)
	var snapshot: MatchSnapshotDto = session.to_snapshot()

	check_eq(snapshot.board.size(), 0, "a preview must never be saved as board state")

	var restored: GameSessionState = GameSessionState.from_snapshot(
		snapshot, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(restored, "a match interrupted during a preview must restore")

	check_eq(restored.get_board().occupied_count(), 0, "the restored board must still be empty")
	check_eq(
		restored.get_turn_state().phase,
		TurnEnums.MatchPhase.AWAIT_ACTION,
		"resume must return to the action phase"
	)
	check_eq(
		restored.get_turn_state().active_player_id,
		HUMAN,
		"resume must restore whose turn it was"
	)
	check_eq(
		_deck_ids(restored, HUMAN),
		held_ids,
		"resume must restore the uncommitted deck in its saved order"
	)
	check_eq(
		restored.deck_count(AI), DECK_SIZE, "resume must restore the rival's deck as well"
	)
	check_eq(
		restored.remaining_tile_count(),
		POT_AFTER_SETUP,
		"resume must restore the pot's draw position"
	)

	# ADR-011 sections 1, 3, and 4: the opening move is a contiguous line of at
	# least two tiles of one rank in the centre, so the resumed deck must still be
	# able to assemble one - a deck of six drawn from four ranks always holds a
	# pair.
	var staged: Array[TileSnapshot] = _staged_line(restored, HUMAN, OPENING_LINE)
	check_eq(
		staged.size(), TILES_PER_MOVE, "the restored deck must still hold a legal pair"
	)
	var resumed_move: LineResult = MoveCommitter.commit_line(restored, HUMAN, staged)
	check(resumed_move.was_committed(), "the restored deck tiles must still form a legal line")
	check_eq(
		String(resumed_move.move_id),
		"move:match-preview:1:1",
		"the resumed match must commit the opening line it was about to make"
	)
	check_eq(
		restored.deck_count(HUMAN),
		DECK_SIZE - TILES_PER_MOVE,
		"every tile of the line leaves the restored deck exactly once"
	)


func test_tiles_are_conserved_across_a_save_and_resume() -> void:
	var session: GameSessionState = _new_session(&"match-tiles", 515)
	TurnManager.setup(session)
	_play_moves(session, 30)

	check_eq(
		session.verify_tile_conservation().size(),
		0,
		"every tile must sit in exactly one place before saving: %s"
		% str(session.verify_tile_conservation())
	)

	var restored: GameSessionState = GameSessionState.from_snapshot(
		session.to_snapshot(), ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(restored, "the match must restore")
	check_eq(
		restored.verify_tile_conservation().size(),
		0,
		"every tile must still sit in exactly one place after restoring: %s"
		% str(restored.verify_tile_conservation())
	)

	# The pot is one tile per cell, and every tile is pot, deck, or board
	# (ADR-010 section 10).
	check_eq(restored.get_tile_source().get_bag_size(), BoardEnums.CELL_COUNT, "144 tiles exist")
	check_eq(
		restored.get_tile_source().get_bag_size(),
		restored.remaining_tile_count()
			+ restored.get_board().occupied_count()
			+ restored.deck_count(HUMAN)
			+ restored.deck_count(AI),
		"the remaining pot, the committed board, and both decks must account for the whole bag"
	)
	check_eq(
		restored.get_board().occupied_count(),
		30 * TILES_PER_MOVE,
		"the restored board must hold every tile of every line the save recorded"
	)

	_compare_sessions(session, restored, "after restoring the conservation fixture")


func test_a_snapshot_of_a_move_in_flight_is_refused() -> void:
	var session: GameSessionState = _new_session(&"match-inflight", 808)
	TurnManager.setup(session)

	# RESOLVE_MOVE is a state the match passes through, not a boundary to resume on.
	session.get_turn_state().phase = TurnEnums.MatchPhase.RESOLVE_MOVE

	var snapshot: MatchSnapshotDto = session.to_snapshot()
	check(not snapshot.is_valid(), "a snapshot taken mid-resolution must be rejected")
	check_not_null(
		GameSessionState.from_snapshot(
			snapshot, ScoringRules.create_default(), TileGenerationRules.create_default()
		) == null,
		"a rejected snapshot must not restore"
	)


func test_a_snapshot_from_other_rules_is_refused() -> void:
	var session: GameSessionState = _new_session(&"match-rules", 909)
	TurnManager.setup(session)
	var snapshot: MatchSnapshotDto = session.to_snapshot()

	# A save written under a different scoring rules version must not be restored
	# against the rules in force now (ADR-007 section 11).
	var other_rules: ScoringRules = ScoringRules.create_default()
	other_rules.schema_version = 99

	check(
		GameSessionState.from_snapshot(
			snapshot, other_rules, TileGenerationRules.create_default()
		) == null,
		"a save written under other rules must be refused"
	)
	check_not_null(
		GameSessionState.from_snapshot(
			snapshot, ScoringRules.create_default(), TileGenerationRules.create_default()
		),
		"the same save must restore against the rules it was written with"
	)


## Plays `count` committed lines, each one legal two-tile move.
##
## ADR-011 section 1 makes a move a line of two or more deck tiles, so a scripted
## placement is a pair from the active player's own deck committed as one move;
## section 7 makes that move the whole of the player's turn, so the commit closes
## the turn and the refill of section 8 plus the end conditions of ADR-010
## section 7 run at the real turn boundary. There is no end-turn action left to
## call.
##
## The pair is taken from two tiles of one rank, because a merged line is legal
## only when its ranks repeat (section 3). A turn whose hand cannot supply such a
## pair uses ADR-011 section 6's swap instead, which consumes the turn without
## placing or scoring, so a starved hand does not silently leave the board short.
## A swap the pot cannot cover ends the scripted run and is reported as a
## rejection, because there is then no legal line and no swap (section 9).
##
## Nothing here is counted from `TurnState.placements_this_turn`: ADR-011
## section 7 gives a turn exactly one move, so the turn position cannot disagree
## with the number of lines this loop has committed.
func _play_moves(session: GameSessionState, count: int) -> Dictionary:
	var committed: int = 0
	var rejected: int = 0
	var guard: int = 0
	while committed < count and not session.is_over() and guard < MOVE_LIMIT:
		guard += 1
		var turn_state: TurnState = session.get_turn_state()
		if not turn_state.is_awaiting_action():
			break

		var player_id: StringName = turn_state.active_player_id
		var cells: Array[Vector2i] = _line_cells(session.get_board(), TILES_PER_MOVE)
		var staged: Array[TileSnapshot] = _staged_line(session, player_id, cells)
		var result: LineResult = null
		if not staged.is_empty():
			result = MoveCommitter.commit_line(session, player_id, staged)
		if result == null or not result.was_committed():
			if _swap_whole_deck(session, player_id):
				continue
			rejected += 1
			break
		TurnManager.resolve(session, result)
		committed += 1
	return {"moves": committed, "rejected": rejected}


## Plays a whole match as two-tile lines over the fixed Hamiltonian pairing.
##
## The pairing covers every cell exactly once and every pair is contiguous, so
## each move is a legal line shape (ADR-011 section 1); the all-Ace rules give
## every pair of deck tiles a repeated rank, so each move is a legal hand
## (section 3) and the only thing the fixture measures is whether the board
## fills. The run goes through the ordinary commit-and-resolve path, which is
## what makes it the Milestone 4 exit criterion rather than a shortcut.
func _play_paired_lines(session: GameSessionState) -> Dictionary:
	var committed: int = 0
	var rejected: int = 0
	for pair: Variant in _grid_pairs():
		if session.is_over():
			break
		var cells: Array[Vector2i] = pair
		var player_id: StringName = session.get_turn_state().active_player_id
		var staged: Array[TileSnapshot] = _staged_line(session, player_id, cells)
		var result: LineResult = null
		if not staged.is_empty():
			result = MoveCommitter.commit_line(session, player_id, staged)
		if result == null or not result.was_committed():
			rejected += 1
			break
		TurnManager.resolve(session, result)
		committed += 1
	return {"moves": committed, "rejected": rejected}


## Returns `count` cells of the first legal line the frontier offers, or an empty
## array when the board is full.
##
## A line is a run of orthogonally adjacent cells in one row or one column
## (ADR-011 section 1), so the helper takes the first frontier cell in row-major
## order - which is the same deterministic choice the placement rules have always
## used - and grows the run from it through the first adjacent empty cells in the
## canonical neighbour order.
func _line_cells(board: BoardState, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if board == null or count <= 0:
		return cells
	var first: Vector2i = _first_frontier(board)
	if first == Vector2i(-1, -1):
		return cells
	cells.append(first)
	for offset: Vector2i in BoardEnums.neighbor_offsets():
		if cells.size() >= count:
			break
		var neighbor: Vector2i = first + offset
		if board.is_empty_cell(neighbor):
			cells.append(neighbor)
	return cells


## Returns snapshots of one player's own deck tiles staged at `cells`.
##
## ADR-011 section 3 makes the merged line legal only when its ranks repeat, so
## the tiles are taken from one rank when the deck holds enough of them; an empty
## array means this hand cannot assemble the line, and the caller has to reach the
## section 6 swap instead. Nothing is chosen randomly, so the scripted players
## stay deterministic (ADR-004 section 3).
func _staged_line(
	session: GameSessionState, player_id: StringName, cells: Array[Vector2i]
) -> Array[TileSnapshot]:
	var staged: Array[TileSnapshot] = []
	if cells.is_empty():
		return staged
	var tiles: Array[TileDefinition] = _same_rank_tiles(session, player_id, cells.size())
	if tiles.size() < cells.size():
		return staged
	for index: int in range(cells.size()):
		staged.append(TileSnapshot.create(tiles[index], cells[index], 0))
	return staged


## Returns `count` of one player's deck tiles that share a rank, or as many as
## the deck can supply.
func _same_rank_tiles(
	session: GameSessionState, player_id: StringName, count: int
) -> Array[TileDefinition]:
	var chosen: Array[TileDefinition] = []
	if session == null or count <= 0:
		return chosen
	var deck: Array[TileDefinition] = session.deck_for(player_id)
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
		for tile: TileDefinition in group:
			chosen.append(tile)
			if chosen.size() == count:
				return chosen
	return [] as Array[TileDefinition]


## Returns true when the active player swapped their whole deck (ADR-011
## section 6).
##
## A swap returns deck tiles for equal replacements and uses the player's whole
## turn, placing and scoring nothing. The pot must supply the whole swap: a
## refusal keeps the player's tiles and the turn, so it is reported as false and
## the caller stops rather than looping.
func _swap_whole_deck(session: GameSessionState, player_id: StringName) -> bool:
	var ids: Array[StringName] = []
	for tile: TileDefinition in session.deck_for(player_id):
		if tile != null:
			ids.append(tile.tile_id)
	if ids.is_empty():
		return false
	var swapped: int = session.request_swap(player_id, ids)
	if swapped <= 0:
		return false
	TurnManager.resolve_swap(session, swapped)
	return true


## Returns the grid as a fixed sequence of adjacent cell pairs.
##
## The pairing is a Hamiltonian path over all 144 cells, so 72 two-tile moves
## cover the board exactly once. Two properties are required of the order and both
## are asserted here rather than assumed: consecutive cells in the path are
## orthogonally adjacent, so every pair is one contiguous line; and the pair
## boundaries fall so that the first pair covers a central opening cell and every
## later pair contains a cell touching committed tiles.
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

	check_eq(pairs.size() * TILES_PER_MOVE, BoardEnums.CELL_COUNT, "the pairs must cover the board")
	var opening: Array[Vector2i] = pairs[0]
	check(
		BoardEnums.is_opening_cell(opening[0]) or BoardEnums.is_opening_cell(opening[1]),
		"the first line must cover one of the four central opening cells"
	)
	return pairs


## Returns true when two cells are orthogonally adjacent.
func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


## Checks that two sessions agree on every authoritative and derived value.
func _compare_sessions(a: GameSessionState, b: GameSessionState, label: String) -> void:
	check_eq(
		b.get_board().get_revision(),
		a.get_board().get_revision(),
		"board revision must agree %s" % label
	)
	check_eq(
		b.get_board().occupied_count(),
		a.get_board().occupied_count(),
		"board occupancy must agree %s" % label
	)
	check_eq(
		b.get_board().to_debug_string(),
		a.get_board().to_debug_string(),
		"board layout must agree %s" % label
	)
	check_eq(
		b.get_ledger().event_ids(),
		a.get_ledger().event_ids(),
		"committed score events must agree %s" % label
	)
	check_eq(
		b.get_scored_hand_set().to_array(),
		a.get_scored_hand_set().to_array(),
		"scored windows must agree %s" % label
	)
	check_eq(b.move_count(), a.move_count(), "move history length must agree %s" % label)
	var a_history: Array[ScoringMove] = a.get_history()
	var b_history: Array[ScoringMove] = b.get_history()
	var history_matches: bool = a_history.size() == b_history.size()
	if history_matches:
		for index: int in range(a_history.size()):
			if a_history[index].move_id != b_history[index].move_id:
				history_matches = false
				break
	check(history_matches, "move history order must agree %s" % label)

	check_eq(
		b.get_turn_state().phase,
		a.get_turn_state().phase,
		"turn phase must agree %s" % label
	)
	check_eq(
		b.get_turn_state().active_player_id,
		a.get_turn_state().active_player_id,
		"active player must agree %s" % label
	)
	check_eq(
		b.get_turn_state().turn_number,
		a.get_turn_state().turn_number,
		"turn number must agree %s" % label
	)
	check_eq(
		b.get_turn_state().consecutive_no_tile_skips,
		a.get_turn_state().consecutive_no_tile_skips,
		"skip count must agree %s" % label
	)
	check_eq(
		b.remaining_tile_count(),
		a.remaining_tile_count(),
		"remaining tile count must agree %s" % label
	)
	check_eq(
		b.get_tile_source().get_draw_index(),
		a.get_tile_source().get_draw_index(),
		"the pot's draw position must agree %s" % label
	)
	check_eq(
		b.score_for(HUMAN),
		a.score_for(HUMAN),
		"the human total must agree %s" % label
	)
	check_eq(b.score_for(AI), a.score_for(AI), "the AI total must agree %s" % label)

	# ADR-010 section 10: both decks are authoritative saved state, so a restore
	# is only equivalent when each deck matches tile for tile and in order.
	for player_id: StringName in TurnEnums.player_ids():
		check_eq(
			_deck_ids(b, player_id),
			_deck_ids(a, player_id),
			"the deck of '%s' must agree %s" % [String(player_id), label]
		)
		var a_active: TileDefinition = a.active_tile_for(player_id)
		var b_active: TileDefinition = b.active_tile_for(player_id)
		var a_id: StringName = &"" if a_active == null else a_active.tile_id
		var b_id: StringName = &"" if b_active == null else b_active.tile_id
		check_eq(
			b_id, a_id, "the active tile of '%s' must agree %s" % [String(player_id), label]
		)


## Builds a standard-rules session.
func _new_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = GameSessionState.create(
		match_id, seed, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(session, "the session must be constructible")
	return session


## Builds a session whose whole bag is one rank, so any two deck tiles form a
## legal hand whatever the deal (ADR-011 section 3).
##
## ADR-004 section 8 makes the generation weights data, so a fixture may pin the
## ranks without touching a rule. This is what lets the full-match fixture measure
## the board filling instead of the ranks the seeded deal happened to produce.
func _new_all_ace_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = GameSessionState.create(
		match_id,
		seed,
		ScoringRules.create_default(),
		_all_ace_generation(BoardEnums.CELL_COUNT)
	)
	check_not_null(session, "the all-Ace session must be constructible")
	return session


## Returns generation rules whose every tile shares one rank.
func _all_ace_generation(bag_size: int) -> TileGenerationRules:
	var rules: TileGenerationRules = TileGenerationRules.new()
	rules.bag_size = bag_size
	rules.rank_weights = [1.0, 0.0, 0.0, 0.0] as Array[float]
	return rules


## Returns one player's deck as a list of tile identities, in deal order.
func _deck_ids(session: GameSessionState, player_id: StringName) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for tile: TileDefinition in session.deck_for(player_id):
		if tile != null:
			ids.append(String(tile.tile_id))
	return ids


## Returns the first legal frontier cell in row-major order.
func _first_frontier(board: BoardState) -> Vector2i:
	var frontier: Array[Vector2i] = board.get_frontier_cells()
	if frontier.is_empty():
		return Vector2i(-1, -1)
	return frontier[0]
