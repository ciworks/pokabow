extends TestCase

## Milestone 6 legal-move generation tests (ADR-005 sections 2, 6, and 7).
##
## Domain-level: no scene tree, no rendering, no input, no controller. The
## generator is checked against the authoritative validator rather than against
## its own opinion, because ADR-005 section 2 requires the AI to see exactly the
## moves the placement rules accept.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

const TEST_MATCH_ID: StringName = &"ai-generation"
const TEST_SEED: int = 4242

## A synthetic tile identity, distinct from any real bag identity.
const SYNTHETIC_TILE_ID: StringName = &"ai-fixture:tile:900"


func test_the_generator_pairs_the_frontier_with_rotations() -> void:
	var session: GameSessionState = _ai_turn_session(TEST_MATCH_ID, TEST_SEED)
	if session == null:
		return
	var tile: TileDefinition = session.active_tile_for(AI)
	if not check_not_null(tile, "the opponent must hold an active tile"):
		return

	var report: Dictionary = {}
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate_with_report(
		session.get_board(), tile, AI, report
	)
	var frontier: Array[Vector2i] = session.get_board().get_frontier_cells()

	check_eq(
		int(report["frontier_cells"]),
		frontier.size(),
		"generation must read the legal-placement frontier"
	)
	check_eq(
		int(report["generated"]),
		frontier.size() * TileEnums.ROTATION_COUNT,
		"every frontier cell must be paired with all four rotations"
	)
	check_eq(
		int(report["generated"]),
		int(report["deduplicated"]) + int(report["rejected"]) + int(report["candidates"]),
		"every generated rotation must be deduplicated, rejected, or kept"
	)
	check_eq(
		int(report["candidates"]), candidates.size(), "the report must state the candidate count"
	)
	check(
		candidates.size() > 0,
		"a board with a frontier cell must offer at least one legal candidate"
	)

	for candidate: AiMoveCandidate in candidates:
		check(
			frontier.has(candidate.cell),
			"candidate %s must sit on a legal frontier cell" % candidate.describe()
		)
		check(
			candidate.rotation >= 0 and candidate.rotation < TileEnums.ROTATION_COUNT,
			"candidate %s must use an accepted rotation" % candidate.describe()
		)
		check_not_null(candidate.snapshot, "candidate %s must carry a tile snapshot" % candidate.describe())
		check(
			not candidate.move_key.is_empty(),
			"candidate %s must carry a canonical move key" % candidate.describe()
		)


func test_rotationally_equivalent_candidates_collapse_to_one() -> void:
	# A tile with one colour on every edge has the same visible edge tuple in all
	# four orientations, so four rotations describe one move (ADR-005 section 2).
	var tile: TileDefinition = _tile_with_edges(
		SYNTHETIC_TILE_ID,
		TileEnums.TileRank.ACE,
		[
			TileEnums.EdgeColor.GREEN,
			TileEnums.EdgeColor.GREEN,
			TileEnums.EdgeColor.GREEN,
			TileEnums.EdgeColor.GREEN,
		]
	)
	var board: BoardState = BoardState.create()
	var report: Dictionary = {}
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate_with_report(
		board, tile, AI, report
	)
	var frontier: Array[Vector2i] = board.get_frontier_cells()

	check_eq(candidates.size(), frontier.size(), "one rotation per frontier cell must survive")
	check_eq(
		int(report["deduplicated"]),
		frontier.size() * (TileEnums.ROTATION_COUNT - 1),
		"the three equivalent rotations must be deduplicated"
	)
	for candidate: AiMoveCandidate in candidates:
		check_eq(candidate.rotation, 0, "deduplication must keep the lowest rotation")


func test_every_generated_candidate_is_accepted_by_the_validator() -> void:
	var session: GameSessionState = _ai_turn_session(TEST_MATCH_ID, TEST_SEED)
	if session == null:
		return
	var tile: TileDefinition = session.active_tile_for(AI)
	if not check_not_null(tile, "the opponent must hold an active tile"):
		return
	var board: BoardState = session.get_board()
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(board, tile, AI)
	if not check(candidates.size() > 0, "the opponent must have a legal candidate"):
		return

	# ADR-005 section 2: the generator must not be looser than the validator.
	check(
		LegalMoveGenerator.all_candidates_are_legal(board, candidates, tile, AI),
		"every generated candidate must be accepted by PlacementValidator"
	)

	# The validator is the authority: an occupied cell must be refused even
	# though the generator never offers one.
	var occupied: Vector2i = board.get_occupied_cells()[0]
	var refused: PlacementResult = PlacementValidator.validate(
		board, PlacementRequest.create(AI, tile.tile_id, occupied, 0), tile, true
	)
	check(
		refused != null and not refused.accepted,
		"a placement on an occupied cell must be refused"
	)


func test_candidates_are_ordered_by_cell_then_rotation() -> void:
	var session: GameSessionState = _ai_turn_session(TEST_MATCH_ID, TEST_SEED)
	if session == null:
		return
	var tile: TileDefinition = session.active_tile_for(AI)
	if not check_not_null(tile, "the opponent must hold an active tile"):
		return
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(
		session.get_board(), tile, AI
	)
	if not check(candidates.size() > 1, "the fixture must offer several candidates"):
		return

	var ordered: bool = true
	for index: int in range(1, candidates.size()):
		if not LegalMoveGenerator.compare_candidates(candidates[index - 1], candidates[index]):
			ordered = false
			break
	check(
		ordered,
		"candidates must be ordered by cell row-major then rotation (ADR-005 section 2)"
	)


func test_the_representative_sample_is_versioned_and_collision_free() -> void:
	var sample: AiRepresentativeSample = AiRepresentativeSample.create_default()
	check_not_null(sample, "the sample must be constructible")
	check(
		sample.is_valid(),
		"the sample must validate: %s" % str(sample.validate())
	)
	check_eq(
		sample.sample_size(),
		AiRepresentativeSample.SAMPLE_SIZE,
		"ADR-005 section 6 fixes the Phase 1 sample at 16 tiles"
	)
	check_eq(sample.weights().size(), sample.sample_size(), "every sample tile needs a weight")

	var seen_ids: Dictionary = {}
	var ranks: Dictionary = {}
	var face_colors: Dictionary = {}
	for tile: TileDefinition in sample.tiles():
		if not check_not_null(tile, "the sample must hold tiles"):
			continue
		var tile_id: String = String(tile.tile_id)
		check(
			AiRepresentativeSample.is_sample_tile_id(tile.tile_id),
			"sample id '%s' must be recognisable as a sample id" % tile_id
		)
		check(not seen_ids.has(tile_id), "sample id '%s' must be unique" % tile_id)
		seen_ids[tile_id] = true
		ranks[int(tile.rank)] = true
		face_colors[int(tile.face_color)] = true

	check_eq(ranks.size(), TileEnums.TileRank.size(), "every rank must be represented")
	check_eq(
		face_colors.size(), TileEnums.FaceColor.size(), "both face colours must be represented"
	)

	# Real bag identities are `<match-id>:tile:<index>` (ADR-004 section 5), so a
	# sample id must never coincide with one.
	var session: GameSessionState = _new_session(TEST_MATCH_ID, TEST_SEED)
	if check_not_null(session, "a session is required to compare identities"):
		for tile: TileDefinition in session.get_tile_source().debug_bag_snapshot():
			check(
				not seen_ids.has(String(tile.tile_id)),
				"sample id '%s' must not collide with a bag id" % String(tile.tile_id)
			)
			check(
				not AiRepresentativeSample.is_sample_tile_id(tile.tile_id),
				"a real bag id must not be recognised as a sample id"
			)


func test_the_snapshot_copies_the_board_and_the_scored_set() -> void:
	var session: GameSessionState = _new_session(&"ai-snapshot", 77)
	if session == null:
		return
	TurnManager.setup(session)
	_play_human_move(session)

	# A window that has already scored, recorded on the live set.
	check(
		session.get_scored_hand_set().add(&"hand:H:5:5"),
		"the live scored-window set must accept an identifier"
	)

	var snapshot: AiGameSnapshot = AiGameSnapshot.create(session, AI)
	if not check_not_null(snapshot, "the snapshot must build from a live match"):
		return
	check(snapshot.is_valid(), "the snapshot must be valid: %s" % str(snapshot.validate()))
	check_eq(snapshot.ai_player_id(), AI, "the snapshot must record the AI identity")
	check_eq(snapshot.human_player_id(), HUMAN, "the snapshot must record the opponent identity")
	check_eq(
		snapshot.board_revision(),
		session.get_board().get_revision(),
		"the snapshot must record the revision it was taken at"
	)

	var revision_at_snapshot: int = snapshot.board_revision()
	var occupancy_at_snapshot: int = snapshot.get_board().occupied_count()
	var scored_at_snapshot: int = snapshot.get_scored_hand_set().size()

	# Mutate the live match. A copy must not follow it (ADR-005 "Data ownership").
	var board: BoardState = session.get_board()
	var extra_cell: Vector2i = board.get_frontier_cells()[0]
	board.commit_tile(
		TileSnapshot.create(_plain_tile(&"ai-fixture:tile:901"), extra_cell, 0)
	)
	session.get_scored_hand_set().add(&"hand:H:5:6")

	check_eq(
		snapshot.board_revision(),
		revision_at_snapshot,
		"the snapshot's board revision must not follow the live board"
	)
	check_eq(
		snapshot.get_board().occupied_count(),
		occupancy_at_snapshot,
		"the snapshot's board must be a copy, not a live reference"
	)
	check_eq(
		snapshot.get_scored_hand_set().size(),
		scored_at_snapshot,
		"the snapshot's scored-window set must be a copy, not a live reference"
	)
	check(
		snapshot.get_board().get_revision() != board.get_revision(),
		"the live board must have moved on from the snapshot"
	)


## Builds a session and advances it to the opponent's action phase.
func _ai_turn_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = _new_session(match_id, seed)
	if session == null:
		return null
	TurnManager.setup(session)
	_play_human_move(session)
	if not check(
		TurnManager.is_awaiting_ai_action(session),
		"the fixture must reach the opponent's action phase"
	):
		return null
	return session


## Commits the human's opening move and closes the turn (ADR-011 section 7).
##
## ADR-011 section 7 makes a turn exactly one move, so resolving the committed
## move passes play to the opponent by itself: the explicit end-turn action of
## ADR-010 section 4 is gone. Resolving it here also runs the turn boundary of
## ADR-011 section 8, so the deck a test inspects is the refilled one.
##
## The commit itself still goes through `MoveCommitter.commit`, the per-tile
## transaction of ADR-007 section 4, because retargeting the candidate generator
## to whole lines is ADR-011 section 12's later pass; the commit is then resolved
## as the one move the turn holds.
func _play_human_move(session: GameSessionState) -> void:
	var frontier: Array[Vector2i] = session.get_board().get_frontier_cells()
	if not check(frontier.size() > 0, "the board must offer a frontier cell"):
		return
	var result: PlacementResult = MoveCommitter.commit(session, HUMAN, frontier[0], 0)
	if not check(
		result != null and result.was_committed(), "the human's opening move must commit"
	):
		return
	TurnManager.resolve(session, _as_whole_move(result))


## Re-expresses a committed per-tile move as the whole-move result the ADR-011
## turn boundary resolves (ADR-011 section 7).
##
## The AI candidate generator still proposes one coordinate and rotation for one
## deck tile, and retargeting it to whole lines is ADR-011 section 12's later
## pass, so this fixture commits through `MoveCommitter.commit` as it did under
## ADR-010 and then resolves the commit as the one move a turn holds. Only the
## fields the boundary reads are carried - the committed flag, the move
## identifier, and the tile count the deck is refilled by (section 8) - and
## nothing is re-scored: the points stay on the committed result's own events.
func _as_whole_move(result: PlacementResult) -> LineResult:
	if result == null or result.placed_tile == null:
		return null
	var tile: TileDefinition = result.placed_tile.get_tile()
	if tile == null:
		return null
	var cell: Vector2i = result.placed_tile.get_cell()
	var snapshots: Array[TileSnapshot] = [result.placed_tile]
	var cells: Array[Vector2i] = [cell]
	var ranks: Array[int] = [int(tile.rank)]
	var view: LineResult = LineResult.create_accepted(
		ScoringEnums.HandOrientation.HORIZONTAL, snapshots, cells, ranks, cells
	)
	view.move_id = result.move_id
	return view


## Builds a standard-rules session.
func _new_session(match_id: StringName, seed: int) -> GameSessionState:
	var session: GameSessionState = GameSessionState.create(
		match_id, seed, ScoringRules.create_default(), TileGenerationRules.create_default()
	)
	check_not_null(session, "the session must be constructible")
	return session


## Builds a valid tile with the given visible edges.
func _tile_with_edges(
	tile_id: StringName, rank: int, edges: Array[TileEnums.EdgeColor]
) -> TileDefinition:
	return TileDefinition.create(
		tile_id, rank, TileEnums.FaceColor.RED, edges.duplicate()
	)


## Builds a valid tile whose edges never match the fixture's all-green tiles.
func _plain_tile(tile_id: StringName) -> TileDefinition:
	return _tile_with_edges(
		tile_id,
		TileEnums.TileRank.KING,
		[
			TileEnums.EdgeColor.BLUE,
			TileEnums.EdgeColor.BLUE,
			TileEnums.EdgeColor.BLUE,
			TileEnums.EdgeColor.BLUE,
		]
	)
