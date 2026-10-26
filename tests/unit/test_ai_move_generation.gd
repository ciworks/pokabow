extends TestCase

## Milestone 6 legal-line generation tests, retargeted by ADR-011 section 12.
##
## ADR-011 section 12 changes move generation from "one tile per candidate" to
## "one line per candidate", so this suite checks that the generator enumerates
## WHOLE LEGAL LINES from the rival's own deck: one orientation, contiguous with
## no gaps, optionally extending a committed line, and satisfying the ADR-012
## section 1 hand test over the merged line (a repeated rank, or a sequence hand
## that steps along the Jack-to-Ace ladder of section 2).
##
## Domain-level: no scene tree, no rendering, no input, no controller. The
## generator is checked against the authoritative `LineValidator` rather than
## against its own opinion, because ADR-011 section 12 requires the AI's
## candidate generator to apply the shared rules rather than approximate them.

const HUMAN: StringName = TurnEnums.HUMAN_PLAYER_ID
const AI: StringName = TurnEnums.AI_PLAYER_ID

const TEST_MATCH_ID: StringName = &"ai-generation"
const TEST_SEED: int = 4242

## A synthetic tile identity, distinct from any real bag identity.
const SYNTHETIC_TILE_ID: StringName = &"ai-fixture:tile:900"


func test_the_generator_enumerates_whole_lines_from_the_deck() -> void:
	var session: GameSessionState = _ai_turn_session(TEST_MATCH_ID, TEST_SEED)
	if session == null:
		return
	var board: BoardState = session.get_board()
	var deck: Array[TileDefinition] = session.deck_for(AI)
	if not check(deck.size() >= LegalMoveGenerator.MIN_LINE_LENGTH, "the rival must hold a hand"):
		return

	var report: Dictionary = {}
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate_with_report(
		board, deck, report
	)

	check(
		int(report["empty_runs"]) >= 2,
		"generation must read the empty runs, not the whole board"
	)
	check(int(report["windows"]) > 0, "an open board must offer line windows")
	check(
		candidates.size() > 0,
		"a rival holding a dealable hand must have at least one legal line"
	)
	check_eq(
		int(report["candidates"]),
		candidates.size(),
		"the report must state the candidate count"
	)
	if not bool(report["capped"]):
		check_eq(
			int(report["generated"]),
			int(report["deduplicated"]) + int(report["rejected"]) + int(report["candidates"]),
			"every generated line must be deduplicated, rejected, or kept"
		)

	var deck_ids: Dictionary = {}
	for tile: TileDefinition in deck:
		deck_ids[String(tile.tile_id)] = true

	for candidate: AiMoveCandidate in candidates:
		var label: String = candidate.describe()
		check(
			candidate.length() >= LegalMoveGenerator.MIN_LINE_LENGTH,
			"candidate %s must be a line of two or more tiles (ADR-011 sections 1 and 4)" % label
		)
		check(
			candidate.cells.size() == candidate.snapshots.size(),
			"candidate %s must name one target cell per tile" % label
		)
		check(
			candidate.tile_ids.size() == candidate.snapshots.size(),
			"candidate %s must name one deck tile per staged tile" % label
		)
		for tile_id: StringName in candidate.tile_ids:
			check(
				deck_ids.has(String(tile_id)),
				"candidate %s must use the rival's own deck tiles (ADR-010 section 4)" % label
			)
		for snapshot: TileSnapshot in candidate.snapshots:
			var cell: Vector2i = snapshot.get_cell()
			check(
				board.is_empty_cell(cell),
				"candidate %s must target an empty cell at %s"
				% [label, BoardEnums.cell_name(cell)]
			)
			check(
				snapshot.get_rotation() >= 0
				and snapshot.get_rotation() < TileEnums.ROTATION_COUNT,
				"candidate %s must use an accepted rotation (ADR-006 section 5)" % label
			)
		if candidate.length() > 1:
			check(
				candidate.orientation == LineValidator.orientation_of(candidate.cells),
				"candidate %s must report the orientation of its own cells (ADR-011 section 1)" % label
			)
		check(
			ScoringEnums.is_valid_orientation(candidate.orientation),
			"candidate %s must lie in exactly one orientation, never a mix (ADR-011 section 1)"
			% label
		)
		check(
			LineValidator.is_contiguous_line(candidate.cells, candidate.orientation),
			"candidate %s must be gapless (ADR-011 section 1)" % label
		)
		check(
			candidate.merged_size >= candidate.length(),
			"candidate %s must report the merged line it is judged over (ADR-011 section 2)" % label
		)
		check(
			candidate.merged_size <= ScoringEnums.WINDOW_SIZE,
			"candidate %s must not create a hand longer than five tiles" % label
		)
		check_eq(
			candidate.merged_ranks.size(),
			candidate.merged_size,
			"candidate %s must report one rank per merged cell" % label
		)
		check(
			LineValidator.is_legal_hand(candidate.merged_ranks),
			"candidate %s must classify as an ADR-012 section 1 hand over its merged line" % label
		)
		check(
			not candidate.move_key.is_empty(),
			"candidate %s must carry a canonical move key" % label
		)


func test_generator_can_complete_a_board_pair_with_one_tile() -> void:
	var board: BoardState = BoardState.create()
	var green: TileEnums.EdgeColor = TileEnums.EdgeColor.GREEN
	var edges: Array[TileEnums.EdgeColor] = [green, green, green, green]
	check(board.commit_tiles([
		TileSnapshot.create(_tile_with_edges(&"pair-a", TileEnums.TileRank.ACE, edges), Vector2i(5, 5), 0),
		TileSnapshot.create(_tile_with_edges(&"pair-b", TileEnums.TileRank.ACE, edges), Vector2i(6, 5), 0),
	]), "fixture must hold a committed pair")
	var held: Array[TileDefinition] = [
		_tile_with_edges(&"one-ace", TileEnums.TileRank.ACE, edges)
	]
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(board, held)
	check(candidates.size() > 0, "one held tile can complete a hand with board tiles")
	for candidate: AiMoveCandidate in candidates:
		check_eq(candidate.length(), 1, "the single held tile is a complete move")
		check(candidate.is_committable(), "the candidate can be committed")
		check(LineValidator.validate(board, candidate.snapshots).accepted, "the validator accepts the candidate")


func test_every_generated_candidate_passes_the_shared_validator() -> void:
	var session: GameSessionState = _ai_turn_session(TEST_MATCH_ID, TEST_SEED + 2)
	if session == null:
		return
	var board: BoardState = session.get_board()
	var deck: Array[TileDefinition] = session.deck_for(AI)
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(board, deck)
	if not check(candidates.size() > 0, "the rival must have a legal line"):
		return

	# ADR-011 section 12: candidates cannot be looser than the rules. ADR-012
	# section 1 is the rule they cannot be looser than.
	check(
		LegalMoveGenerator.all_candidates_are_legal(board, candidates),
		"every generated candidate must be accepted by the shared LineValidator"
	)
	for candidate: AiMoveCandidate in candidates:
		var result: LineResult = LineValidator.validate(board, candidate.snapshots)
		if not check_not_null(result, "the validator must answer for %s" % candidate.describe()):
			continue
		check(
			result.accepted,
			"the human path's validator must accept %s" % candidate.describe()
		)
		check_eq(
			result.staged_count(),
			candidate.length(),
			"the accepted line must stage exactly the candidate's tiles"
		)

	# The validator is the authority: a contiguous two-tile line of two different
	# ranks must be refused even though the generator never offers one. ADR-012
	# section 1 makes a Pair the shortest hand, so two distinct ranks are a hand
	# only when they step along the Jack-to-Ace ladder of section 2, which a
	# two-tile line never does.
	var pair_cells: Array[Vector2i] = _empty_pair_on_frontier(board)
	if pair_cells.size() < 2:
		return
	var distinct: Array[TileDefinition] = _distinct_rank_tiles(deck, 2)
	if distinct.size() < 2:
		return
	var illegal: Array[TileSnapshot] = [
		TileSnapshot.create(distinct[0], pair_cells[0], 0),
		TileSnapshot.create(distinct[1], pair_cells[1], 0),
	]
	var refused: LineResult = LineValidator.validate(board, illegal)
	if check_not_null(refused, "the validator must answer for a two-tile line"):
		check(
			not refused.accepted,
			"a contiguous line of two distinct ranks must be refused: it is no Pair and no sequence hand (ADR-012 sections 1 and 2)"
		)


func test_the_generator_proposes_nothing_when_the_hand_cannot_form_a_line() -> void:
	# ADR-012 section 1: the shortest legal hand is a Pair, and the only other
	# two-tile shape is a sequence hand, which needs at least three ladder ranks.
	# A hand holding one Jack and one Queen therefore has no legal line at all.
	# That is the state ADR-011 section 6 answers with a swap, so the generator
	# must report an empty list rather than an illegal fallback.
	var board: BoardState = BoardState.create()
	var deck: Array[TileDefinition] = []
	var ranks: Array[int] = [
		TileEnums.TileRank.JACK,
		TileEnums.TileRank.QUEEN,
	]
	for index: int in range(ranks.size()):
		deck.append(
			_tile_with_edges(
				StringName("ai-fixture:tile:%d" % (800 + index)),
				ranks[index],
				[
					TileEnums.EdgeColor.BLUE,
					TileEnums.EdgeColor.BLUE,
					TileEnums.EdgeColor.BLUE,
					TileEnums.EdgeColor.BLUE,
				]
			)
		)

	var report: Dictionary = {}
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate_with_report(
		board, deck, report
	)
	check_eq(
		candidates.size(),
		0,
		"a hand that repeats no rank and forms no sequence hand has no legal line (ADR-012 section 1)"
	)
	check(
		int(report["rejected"]) > 0,
		"the refused windows must be reported as rejected by the shared validator"
	)
	# The contrast: the same board offers lines as soon as the hand holds a pair,
	# so the empty result above is about the hand, not the board.
	var paired: Array[TileDefinition] = [
		_tile_with_edges(
			&"ai-fixture:tile:830",
			TileEnums.TileRank.ACE,
			[
				TileEnums.EdgeColor.BLUE,
				TileEnums.EdgeColor.BLUE,
				TileEnums.EdgeColor.BLUE,
				TileEnums.EdgeColor.BLUE,
			]
		),
		_tile_with_edges(
			&"ai-fixture:tile:831",
			TileEnums.TileRank.ACE,
			[
				TileEnums.EdgeColor.BLUE,
				TileEnums.EdgeColor.BLUE,
				TileEnums.EdgeColor.BLUE,
				TileEnums.EdgeColor.BLUE,
			]
		),
	]
	check(
		LegalMoveGenerator.generate(board, paired).size() > 0,
		"the same board must offer a line once the hand holds a pair (ADR-012 section 1)"
	)


func test_a_candidate_can_extend_a_line_already_on_the_board() -> void:
	# ADR-011 section 2: the line may include committed tiles, and the hand is
	# judged over the whole merged line.
	#
	# The committed pair is A A and the deck holds two Kings, so the one legal
	# extension is to stage both Kings at one end, reading A A K K or K K A A.
	# ADR-012 section 1 makes two pair the only four-tile shape of two ranks and
	# requires each rank's tiles to be adjacent, so a single King (A A K, an
	# unmatched tile) is refused and both Kings must be staged together.
	var board: BoardState = BoardState.create()
	board.commit_tile(
		TileSnapshot.create(
			_tile_with_edges(
				&"ai-fixture:tile:810",
				TileEnums.TileRank.ACE,
				[
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
				]
			),
			Vector2i(5, 5),
			0
		)
	)
	board.commit_tile(
		TileSnapshot.create(
			_tile_with_edges(
				&"ai-fixture:tile:811",
				TileEnums.TileRank.ACE,
				[
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
				]
			),
			Vector2i(6, 5),
			0
		)
	)
	var deck: Array[TileDefinition] = [
		_tile_with_edges(
			&"ai-fixture:tile:812",
			TileEnums.TileRank.KING,
			[
				TileEnums.EdgeColor.BLUE,
				TileEnums.EdgeColor.BLUE,
				TileEnums.EdgeColor.BLUE,
				TileEnums.EdgeColor.BLUE,
			]
		),
		_tile_with_edges(
			&"ai-fixture:tile:813",
			TileEnums.TileRank.KING,
			[
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
				TileEnums.EdgeColor.RED,
			]
		),
	]

	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(board, deck)
	if not check(candidates.size() > 0, "the fixture must offer a line"):
		return

	var extending: AiMoveCandidate = null
	for candidate: AiMoveCandidate in candidates:
		if candidate.extends_board_line:
			extending = candidate
			break
	if not check_not_null(extending, "a window beside a committed line must extend it"):
		return
	check(
		extending.merged_size > extending.length(),
		"the merged line must be longer than the staged line (ADR-011 section 2)"
	)
	var extended_line: LineResult = LineValidator.validate(board, extending.snapshots)
	if not check(extended_line != null and extended_line.accepted, "the extension must validate"):
		return
	check(
		extended_line.merged_cells.has(Vector2i(5, 5)) and extended_line.merged_cells.has(Vector2i(6, 5)),
		"the merged line must include the committed tiles it joins"
	)
	check(
		LineValidator.is_legal_hand(extending.merged_ranks),
		"the merged line must classify as an ADR-012 section 1 hand, which needs a repeated rank or a sequence"
	)
	for snapshot: TileSnapshot in extending.snapshots:
		check(
			board.is_empty_cell(snapshot.get_cell()),
			"only the staged tiles are new; the committed ones are read, not written"
		)


func test_the_generator_collapses_lines_that_produce_the_same_board() -> void:
	# Four functionally identical tiles: every assignment places the same ranks
	# with the same rotated edges at the same cells, so the outcomes collapse to
	# one candidate (ADR-005 section 2 de-duplication), which is what keeps the
	# search from re-evaluating identical positions.
	var board: BoardState = BoardState.create()
	var deck: Array[TileDefinition] = []
	for index: int in range(4):
		deck.append(
			_tile_with_edges(
				StringName("ai-fixture:tile:%d" % (820 + index)),
				TileEnums.TileRank.ACE,
				[
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
					TileEnums.EdgeColor.GREEN,
				]
			)
		)
	var report: Dictionary = {}
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate_with_report(
		board, deck, report
	)
	check(
		int(report["deduplicated"]) > 0,
		"identical board outcomes must be recognised as duplicates"
	)
	check(
		int(report["deduplicated"]) + int(report["rejected"]) + int(report["candidates"]) == int(report["generated"]),
		"every generated line must survive, be rejected, or be deduplicated"
	)
	var keys: Dictionary = {}
	for candidate: AiMoveCandidate in candidates:
		check(
			not keys.has(candidate.move_key),
			"candidate keys must be unique: %s" % candidate.move_key
		)
		keys[candidate.move_key] = true


func test_candidates_are_ordered_by_the_documented_order() -> void:
	var session: GameSessionState = _ai_turn_session(TEST_MATCH_ID, TEST_SEED + 3)
	if session == null:
		return
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(
		session.get_board(), session.deck_for(AI)
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
		"candidates must be ordered anchor cell row-major, then orientation, then length (ADR-005 section 2)"
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
		"the sample covers four ranks in four rotations"
	)
	check_eq(sample.weights().size(), sample.sample_size(), "every sample tile needs a weight")

	var seen_ids: Dictionary = {}
	var ranks: Dictionary = {}
	var face_colors: Dictionary = {}
	var suits: Dictionary = {}
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
		suits[int(tile.suit)] = true

	check_eq(ranks.size(), TileEnums.TileRank.size(), "every rank must be represented")
	check_eq(
		face_colors.size(), TileEnums.FaceColor.size() - 1, "both face colours must be represented"
	)
	check_eq(suits.size(), TileEnums.Suit.size() - 1, "all four suits must be represented")

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


func test_the_snapshot_copies_the_board_the_scored_set_and_both_decks() -> void:
	var session: GameSessionState = _new_session(&"ai-snapshot", 77)
	if session == null:
		return
	TurnManager.setup(session)
	_play_human_line(session)

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
	# ADR-011 section 12 needs the held hands to generate lines from.
	check_eq(
		snapshot.ai_deck().size(),
		session.deck_count(AI),
		"the snapshot must carry the rival's held deck in deal order"
	)
	check_eq(
		snapshot.human_deck().size(),
		session.deck_count(HUMAN),
		"the snapshot must carry the opponent's held deck"
	)

	var revision_at_snapshot: int = snapshot.board_revision()
	var occupancy_at_snapshot: int = snapshot.get_board().occupied_count()
	var scored_at_snapshot: int = snapshot.get_scored_hand_set().size()
	var ai_deck_at_snapshot: int = snapshot.ai_deck().size()

	# Mutate the live match. A copy must not follow it (ADR-005 "Data ownership").
	var board: BoardState = session.get_board()
	var extra_cell: Vector2i = board.get_frontier_cells()[0]
	board.commit_tile(
		TileSnapshot.create(_plain_tile(&"ai-fixture:tile:901"), extra_cell, 0)
	)
	session.get_scored_hand_set().add(&"hand:H:5:6")
	session.remove_deck_tile(AI, snapshot.ai_deck()[0].tile_id)

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
	check(!snapshot.has_decks() or snapshot.ai_deck().size() == ai_deck_at_snapshot,
		"the snapshot's decks must be copies, not live references"
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
	_play_human_line(session)
	if not check(
		TurnManager.is_awaiting_ai_action(session),
		"the fixture must reach the opponent's action phase"
	):
		return null
	return session


## Commits the human's opening line and closes the turn (ADR-011 section 7).
##
## The line comes from the generator's own candidate list, so the fixture cannot
## be the thing that decides what is legal: the shared validator already did.
func _play_human_line(session: GameSessionState) -> void:
	var staged: Array[TileSnapshot] = _opening_line_for(session, HUMAN)
	if not check(
		staged.size() >= LegalMoveGenerator.MIN_LINE_LENGTH,
		"the human must be able to assemble an opening line"
	):
		return
	var result: LineResult = MoveCommitter.commit_line(session, HUMAN, staged)
	if not check(
		result != null and result.was_committed(), "the human's opening line must commit"
	):
		return
	TurnManager.resolve(session, result)


## Returns the first legal line the generator offers for one player's own deck.
func _opening_line_for(session: GameSessionState, player_id: StringName) -> Array[TileSnapshot]:
	var candidates: Array[AiMoveCandidate] = LegalMoveGenerator.generate(
		session.get_board(), session.deck_for(player_id)
	)
	if candidates.is_empty():
		return [] as Array[TileSnapshot]
	return candidates[0].snapshots


## Returns two adjacent empty cells on the board's frontier, or fewer.
func _empty_pair_on_frontier(board: BoardState) -> Array[Vector2i]:
	var pair: Array[Vector2i] = []
	for cell: Vector2i in board.get_frontier_cells():
		pair.append(cell)
		for offset: Vector2i in BoardEnums.neighbor_offsets():
			var neighbor: Vector2i = cell + offset
			if board.is_empty_cell(neighbor):
				pair.append(neighbor)
				return pair
		pair = [] as Array[Vector2i]
	return pair


## Returns `count` usable deck tiles whose ranks all differ, or fewer.
func _distinct_rank_tiles(
	deck: Array[TileDefinition], count: int
) -> Array[TileDefinition]:
	var chosen: Array[TileDefinition] = []
	var seen: Dictionary = {}
	for tile: TileDefinition in deck:
		if tile == null or not tile.is_valid():
			continue
		if seen.has(int(tile.rank)):
			continue
		seen[int(tile.rank)] = true
		chosen.append(tile)
		if chosen.size() >= count:
			break
	return chosen


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
