class_name MoveCommitter
extends RefCounted

## The single atomic commit path for one line (ADR-006 section 6, ADR-007
## section 4, ADR-011 section 5).
##
## ADR-011 section 5 replaces ADR-007 section 4's per-tile transaction with a
## per-move transaction: the unit is a whole assembled line, so
## `commit_line()` validates the line, then writes the board, the ledger, the
## scored-window set, and the history together, as one move with one identifier
## and one history entry.
##
## `commit()` below is the per-tile transaction ADR-011 supersedes. It is kept
## because the AI candidate generator and ADR-007's replay fixtures still build
## single placements, and those are later passes' surface; nothing in the live
## line path calls it.

## The single atomic commit path for one placement (ADR-006 section 6,
## ADR-007 section 4, superseded by ADR-011 section 5).
##
## ADR-007 section 4 defines a committed move as one transaction spanning
## validation, the hypothetical post-placement board, generated events, the
## board write, the ledger, the scored-window set, the active tile, and the move
## history. ADR-006 section 6 adds that if any step fails, none of the changes
## are applied. This type is that transaction, and it is the only place a match
## advances.
##
## Human input, a future `AIController`, and replay all reach scoring through the
## same two collaborators: `PlacementValidator` decides legality and
## `ScoringCoordinator` performs the board-plus-score write. Nothing here
## re-implements either, so there is no second copy of the rules to drift
## (AGENTS.md section 15).
##
## The tile is not a parameter: ADR-010 section 4 makes a deck tile the only tile
## a player may place, so deriving it from the session removes the possibility of
## committing a tile the player does not hold. The armed deck tile is taken when
## one is armed, and otherwise the deck's first tile, which is what a player who
## has not picked yet would place.
##
## ADR-010 sections 3 and 9 make a turn a sequence of independent committed
## placements rather than one transaction: this function commits exactly one
## placement, the turn stays open in `AWAIT_ACTION`, and the caller repeats it
## with any remaining deck tile or ends the turn through `end_turn`. Each
## placement keeps its own move identifier, its own score events, and its own
## history record, so ADR-007 section 4 and ADR-006 section 6 are unchanged.
##
## Ordering guarantees:
## - every refusal happens before any mutation, so a rejected move leaves the
##   board, ledger, scored windows, deck, and history untouched;
## - the move identifier is derived from the match identity, the turn number, and
##   the placement's 1-based index within that turn (ADR-010 section 9), rather
##   than accepted from the caller, so a caller cannot pick a colliding or
##   reusable identifier (ADR-007 section 5).


## Validates and commits one placement for the active player.
##
## Returns a rejected `PlacementResult` naming the reason when the move is
## refused, and an accepted result carrying the committed tile, the awarded
## events, and the move identifier when it succeeds.
static func commit(
	session: GameSessionState,
	player_id: StringName,
	cell: Vector2i,
	rotation: int
) -> PlacementResult:
	if session == null:
		push_error("MoveCommitter.commit: a session is required.")
		return null

	var board: BoardState = session.get_board()
	var turn_state: TurnState = session.get_turn_state()

	# ADR-003 section 1: GAME_OVER freezes input, and RECOVERY_ERROR marks the
	# match incomplete, so neither accepts another move.
	if turn_state.is_stopped():
		return _reject(PlacementEnums.PlacementRejection.MATCH_FINISHED, cell)

	# ADR-003 section 6: only the active player's move is accepted, and
	# ADR-010 section 3 step 3 keeps the authoritative phase at AWAIT_ACTION
	# until a validated placement returns, and each further placement of the same
	# turn is committed from that same phase.
	if not TurnEnums.is_valid_player_id(player_id):
		return _reject(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, cell)
	if turn_state.active_player_id != player_id:
		return _reject(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, cell)
	if not turn_state.is_awaiting_action():
		return _reject(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, cell)

	# ADR-010 section 9: the placement index is 1-based within the turn, so the
	# second placement of turn 3 is `move:<match-id>:3:2`. It is read from the
	# turn position rather than derived from the whole history, so a retried
	# placement reproduces the identifier of the placement it repeats.
	var placement_index: int = session.next_placement_index()
	var move_id: StringName = ScoringCoordinator.move_id_for(
		session.get_match_id(), turn_state.turn_number, placement_index
	)
	if String(move_id).is_empty():
		push_error(
			"MoveCommitter.commit: turn number %d cannot produce a move identifier; the match was not advanced to a turn."
			% turn_state.turn_number
		)
		return _reject(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, cell)

	# ADR-007 section 5: a move identifier may be committed at most once. The
	# refusal is checked before the tile is derived, so a repeated placement is
	# reported as a duplicate move whatever the player's deck happens to hold
	# (an empty deck after an earlier turn must not misreport it as no tile).
	if session.has_move_id(move_id):
		return _reject(PlacementEnums.PlacementRejection.DUPLICATE_MOVE, cell)

	# ADR-010 sections 3 and 4: the player places from their own deck, so a deck
	# with no tiles in it has nothing legal to place.
	var tile: TileDefinition = session.active_tile_for(player_id)
	if tile == null or not tile.is_valid():
		return _reject(PlacementEnums.PlacementRejection.TILE_NOT_AVAILABLE, cell)

	# ADR-006 section 6 step 1: revalidate against the current board.
	var request: PlacementRequest = PlacementRequest.create(
		player_id, tile.tile_id, cell, rotation
	)
	var validation: PlacementResult = PlacementValidator.validate(board, request, tile, true)
	if validation == null or not validation.accepted:
		return validation

	var snapshot: TileSnapshot = validation.placed_tile
	var rules: ScoringRules = session.get_rules()
	var ledger: ScoreLedger = session.get_ledger()
	var scored_hand_ids: ScoredHandSet = session.get_scored_hand_set()

	# ADR-007 section 4 step 5: validate the proposed events before any mutation.
	# Duplicate identifiers are refused here rather than after the board write, so
	# a retry can never leave the ledger and the board disagreeing.
	var proposed: Array[ScoreEvent] = ScoringCoordinator.build_events(
		board, snapshot, player_id, move_id, turn_state.turn_number, rules, scored_hand_ids
	)
	for event: ScoreEvent in proposed:
		if not event.is_valid():
			push_error(
				"MoveCommitter.commit: event '%s' is not a valid award; refusing the move."
				% String(event.event_id)
			)
			return _reject(PlacementEnums.PlacementRejection.MATCH_FINISHED, cell)
		if ledger.has_event(event.event_id):
			return _reject(PlacementEnums.PlacementRejection.DUPLICATE_MOVE, cell)

	var was_opening_move: bool = not board.has_any_tile()

	# ADR-007 section 4 steps 6 and 7: the board, the ledger, and the scored
	# window set commit together.
	var transaction: ScoreTransaction = ScoringCoordinator.commit_placement(
		board,
		snapshot,
		ledger,
		scored_hand_ids,
		player_id,
		move_id,
		turn_state.turn_number,
		rules
	)
	if not board.is_occupied(cell):
		push_error(
			"MoveCommitter.commit: the coordinator refused a pre-validated commit at %s; no state was changed."
			% BoardEnums.cell_name(cell)
		)
		return _reject(PlacementEnums.PlacementRejection.DUPLICATE_MOVE, cell)

	# ADR-003 section 3 step 9: the move joins the authoritative history that
	# replay and save/resume depend on.
	if not session.append_move(
		ScoringMove.create_single(
			move_id,
			turn_state.turn_number,
			player_id,
			tile.tile_id,
			cell,
			snapshot.get_rotation(),
			was_opening_move
		)
	):
		push_error(
			"MoveCommitter.commit: the committed move '%s' could not be recorded in the history."
			% String(move_id)
		)

	# ADR-010 section 9: the turn's placement sequence advances only on a
	# committed placement, so the next placement of this turn carries the
	# following index and a refused retry keeps the index it was given.
	session.note_placement_committed()

	# ADR-010 section 10: a committed tile leaves its owner's deck, which also
	# disarms it. The deck does not refill here: ADR-010 section 5 refills at the
	# turn boundary, which is what bounds a turn at `deck_size` placements.
	if not session.remove_deck_tile(player_id, tile.tile_id):
		push_error(
			"MoveCommitter.commit: the committed tile '%s' was not held by '%s'."
			% [String(tile.tile_id), String(player_id)]
		)

	validation.move_id = move_id
	validation.score_events = transaction.events
	validation.changed_cells = PlacementValidator.changed_cells_for(board, cell)
	return validation


## Validates and commits one whole assembled line as a single atomic move
## (ADR-011 sections 1 to 5, and ADR-007 section 4 with a line as its unit).
##
## `staged` is the line as the player assembled it: tiles from the active player's
## own deck, in any order. The order is normalised to line order here, so a caller
## cannot influence the committed coordinate order.
##
## Ordering guarantees, which are what ADR-011 section 5 requires:
## - every refusal happens before any mutation, so a rejected line leaves the
##   board, the ledger, the scored-window set, the history, the deck, and the turn
##   state completely unchanged, and the player keeps their tiles;
## - the move identifier is derived from the match identity and the turn number
##   rather than accepted from the caller, and it is one identifier for the whole
##   line (section 7 makes a turn exactly one move, so its index is always 1);
## - the line produces exactly one history entry (section 5).
##
## Returns a rejected `LineResult` naming the reason when the line is refused, and
## an accepted result carrying the committed line, the awarded events, and the
## move identifier when it succeeds.
static func commit_line(
	session: GameSessionState,
	player_id: StringName,
	staged: Array[TileSnapshot]
) -> LineResult:
	if session == null:
		push_error("MoveCommitter.commit_line: a session is required.")
		return null

	var board: BoardState = session.get_board()
	var turn_state: TurnState = session.get_turn_state()
	var anchor: Vector2i = _anchor_cell(staged)

	# ADR-003 section 1: GAME_OVER freezes input, and RECOVERY_ERROR marks the
	# match incomplete, so neither accepts another move.
	if turn_state.is_stopped():
		return _reject_line(PlacementEnums.PlacementRejection.MATCH_FINISHED, anchor)

	# ADR-003 section 6: only the active player's move is accepted. ADR-011
	# section 7 keeps the authoritative phase at AWAIT_ACTION until a validated
	# move returns, because a turn is now exactly one move.
	if not TurnEnums.is_valid_player_id(player_id):
		return _reject_line(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, anchor)
	if turn_state.active_player_id != player_id:
		return _reject_line(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, anchor)
	if not turn_state.is_awaiting_action():
		return _reject_line(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, anchor)

	# ADR-011 section 7: one move per turn, so the move identifier always carries
	# placement index 1. Deriving it from the turn number keeps ADR-007 section 5's
	# idempotence: a retried line in the same turn reproduces the same identifier.
	var move_id: StringName = ScoringCoordinator.move_id_for(
		session.get_match_id(), turn_state.turn_number, 1
	)
	if String(move_id).is_empty():
		push_error(
			"MoveCommitter.commit_line: turn number %d cannot produce a move identifier; the match was not advanced to a turn."
			% turn_state.turn_number
		)
		return _reject_line(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, anchor)

	# ADR-007 section 5: a move identifier may be committed at most once. Checked
	# before the deck is consulted, so a repeated line is reported as a duplicate
	# move whatever the player's deck now happens to hold.
	if session.has_move_id(move_id):
		return _reject_line(PlacementEnums.PlacementRejection.DUPLICATE_MOVE, anchor)

	# ADR-011 sections 1 and 4: a move places two or more of the active player's
	# deck tiles. A tile the player does not hold can never be placed
	# (ADR-010 section 4), and the staged tiles must still be in the deck: a tile
	# already committed is not available again.
	if staged == null or staged.is_empty():
		return _reject_line(PlacementEnums.PlacementRejection.LONE_TILE, anchor)
	for snapshot: TileSnapshot in staged:
		if snapshot == null or not snapshot.is_valid():
			return _reject_line(
				PlacementEnums.PlacementRejection.TILE_NOT_AVAILABLE, anchor
			)
		if not session.holds_deck_tile(player_id, snapshot.get_tile_id()):
			return _reject_line(
				PlacementEnums.PlacementRejection.TILE_NOT_AVAILABLE, snapshot.get_cell()
			)

	# ADR-011 sections 1 to 4: the line itself must be legal, judged against the
	# current board and over the merged line.
	var validation: LineResult = LineValidator.validate(board, staged)
	if validation == null or not validation.accepted:
		return validation

	var ordered: Array[TileSnapshot] = validation.staged_tiles
	var rules: ScoringRules = session.get_rules()
	var ledger: ScoreLedger = session.get_ledger()
	var scored_hand_ids: ScoredHandSet = session.get_scored_hand_set()

	# ADR-007 section 4 step 5: validate the proposed events before any mutation.
	# Duplicate identifiers are refused here rather than after the board write, so
	# a retry can never leave the ledger and the board disagreeing.
	var proposed: Array[ScoreEvent] = ScoringCoordinator.build_events_for_line(
		board,
		ordered,
		player_id,
		move_id,
		turn_state.turn_number,
		rules,
		scored_hand_ids
	)
	for event: ScoreEvent in proposed:
		if not event.is_valid():
			push_error(
				"MoveCommitter.commit_line: event '%s' is not a valid award; refusing the line."
				% String(event.event_id)
			)
			return _reject_line(PlacementEnums.PlacementRejection.MATCH_FINISHED, anchor)
		if ledger.has_event(event.event_id):
			return _reject_line(PlacementEnums.PlacementRejection.DUPLICATE_MOVE, anchor)

	var was_opening_move: bool = not board.has_any_tile()

	# ADR-007 section 4 steps 6 and 7 with ADR-011 section 5's unit: the whole
	# line, the ledger, and the scored-window set commit together.
	var transaction: ScoreTransaction = ScoringCoordinator.commit_line(
		board,
		ordered,
		ledger,
		scored_hand_ids,
		player_id,
		move_id,
		turn_state.turn_number,
		rules
	)
	for snapshot: TileSnapshot in ordered:
		if not board.is_occupied(snapshot.get_cell()):
			push_error(
				"MoveCommitter.commit_line: the coordinator refused a pre-validated line commit at %s; no state was changed."
				% BoardEnums.cell_name(anchor)
			)
			return _reject_line(PlacementEnums.PlacementRejection.DUPLICATE_MOVE, anchor)

	# ADR-003 section 3 step 9 and ADR-011 section 5: the whole line joins the
	# authoritative history as ONE move with ONE identifier.
	var placements: Array[ScoringMove.Placement] = []
	for snapshot: TileSnapshot in ordered:
		placements.append(
			ScoringMove.Placement.create(
				snapshot.get_tile_id(), snapshot.get_cell(), snapshot.get_rotation()
			)
		)
	if not session.append_move(
		ScoringMove.create(
			move_id, turn_state.turn_number, player_id, placements, was_opening_move
		)
	):
		push_error(
			"MoveCommitter.commit_line: the committed line '%s' could not be recorded in the history."
			% String(move_id)
		)

	# ADR-011 section 7: the turn's move is now committed, so the turn position
	# reflects it and a retry of the same line reproduces the same identifier.
	session.note_placement_committed()

	# ADR-010 section 10: every committed tile leaves its owner's deck, which also
	# disarms it. ADR-011 section 8 refills the deck by the number of tiles the line
	# used, at the turn boundary rather than here.
	for snapshot: TileSnapshot in ordered:
		if not session.remove_deck_tile(player_id, snapshot.get_tile_id()):
			push_error(
				"MoveCommitter.commit_line: the committed tile '%s' was not held by '%s'."
				% [String(snapshot.get_tile_id()), String(player_id)]
			)

	validation.move_id = move_id
	validation.score_events = transaction.events
	return validation


## Writes one whole already-committed move's tiles to a board as a single board
## commit (ADR-011 section 5, ADR-007 section 8).
##
## The board half of a move, with no scoring, no identifier, and no history: it
## exists because ADR-011 section 5 makes the board revision count committed
## MOVES, not tiles, and something that rebuilds a board from committed moves
## must write each move the way the live commit did. The live path reaches the
## same board write through `ScoringCoordinator.commit_line`, which calls the
## board's batch commit; `commit_line` above is where a live move is validated
## and scored, and this is the same one-revision-per-move write without them.
##
## `GameSessionState.from_snapshot` is the caller: it rebuilds a restored board
## move by move from the restored history rather than tile by tile from the flat
## board record, so a resumed match carries the revision live play reached.
## Committing N restored tiles one at a time would advance the revision N times
## and make the resumed match disagree with live play and with a replay of its
## own history, which ADR-007 section 8's per-move staleness check cannot allow.
##
## Returns false, changing nothing, when the board or the snapshots are unusable,
## when a snapshot is invalid, or when a target cell is not empty: the board's own
## batch commit checks every precondition before its first write, so a refusal
## cannot leave half a move's tiles on the board.
static func commit_move_tiles(board: BoardState, snapshots: Array[TileSnapshot]) -> bool:
	if board == null or snapshots == null or snapshots.is_empty():
		return false
	return board.commit_tiles(snapshots)


## Returns a rejected line result for `reason`, recording the target coordinate.
static func _reject_line(reason: int, cell: Vector2i) -> LineResult:
	return LineResult.create_rejected(reason, cell)


## Returns the cell a refusal is reported against: the line's first staged cell.
static func _anchor_cell(staged: Array[TileSnapshot]) -> Vector2i:
	if staged == null:
		return Vector2i.ZERO
	for snapshot: TileSnapshot in staged:
		if snapshot != null:
			return snapshot.get_cell()
	return Vector2i.ZERO


## Returns a rejected result for `reason`, recording the target coordinate.
static func _reject(reason: int, cell: Vector2i) -> PlacementResult:
	return PlacementResult.create_rejected(reason, cell)
