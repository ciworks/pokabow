class_name MoveCommitter
extends RefCounted

## The single atomic commit path for one placement (ADR-006 section 6,
## ADR-007 section 4).
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
## The tile is not a parameter: ADR-003 section 4 makes a player's active
## uncommitted tile the only tile they may place, so deriving it from the session
## removes the possibility of committing a tile the player does not hold.
##
## Ordering guarantees:
## - every refusal happens before any mutation, so a rejected move leaves the
##   board, ledger, scored windows, active tile, and history untouched;
## - the move identifier is derived from the match identity and turn number
##   rather than accepted from the caller, so a caller cannot pick a colliding or
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
	# ADR-003 section 3 step 3 keeps the authoritative phase at AWAIT_ACTION
	# until a validated decision returns.
	if not TurnEnums.is_valid_player_id(player_id):
		return _reject(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, cell)
	if turn_state.active_player_id != player_id:
		return _reject(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, cell)
	if not turn_state.is_awaiting_action():
		return _reject(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, cell)

	# ADR-003 section 4: at most one active tile, and it is the only tile this
	# player may place.
	var tile: TileDefinition = session.active_tile_for(player_id)
	if tile == null or not tile.is_valid():
		return _reject(PlacementEnums.PlacementRejection.TILE_NOT_AVAILABLE, cell)

	var move_id: StringName = ScoringCoordinator.move_id_for(
		session.get_match_id(), turn_state.turn_number
	)
	if String(move_id).is_empty():
		push_error(
			"MoveCommitter.commit: turn number %d cannot produce a move identifier; the match was not advanced to a turn."
			% turn_state.turn_number
		)
		return _reject(PlacementEnums.PlacementRejection.NOT_PLAYERS_TURN, cell)

	# ADR-007 section 5: a move identifier may be committed at most once.
	if session.has_move_id(move_id):
		return _reject(PlacementEnums.PlacementRejection.DUPLICATE_MOVE, cell)

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
		ScoringMove.create(
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

	# ADR-003 section 4: a committed tile leaves the active slot.
	session.clear_active_tile(player_id)

	validation.move_id = move_id
	validation.score_events = transaction.events
	validation.changed_cells = PlacementValidator.changed_cells_for(board, cell)
	return validation


## Returns a rejected result for `reason`, recording the target coordinate.
static func _reject(reason: int, cell: Vector2i) -> PlacementResult:
	return PlacementResult.create_rejected(reason, cell)
