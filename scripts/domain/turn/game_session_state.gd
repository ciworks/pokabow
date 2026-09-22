class_name GameSessionState
extends RefCounted

## The authoritative state of one match (ADR-003 section "Data ownership",
## ADR-007 section 10).
##
## ADR-003 gives `GameSession` ownership of the match lifecycle and its immutable
## configuration, and lists `BoardState`, `TileSource`, and `ScoreLedger` as the
## systems that own their own sub-state. This type is that container: it holds the
## pieces and owns nothing that another system owns. In particular it does not
## decide legality (`PlacementValidator`), apply score events
## (`ScoringCoordinator`), or sequence turns (`TurnManager`).
##
## ADR-007 section 10 names the authoritative persisted inputs: rules versions,
## the match seed and bag state, the ordered committed move history, and the
## committed score ledger. All four live here, and every derived value (player
## totals, the frontier, cluster entitlements) is rebuildable from them.
##
## It is deliberately not an autoload: the match that owns it holds it, so no
## match state lives in a global (ADR-008 section 6).

var _match_id: StringName = &""
var _seed: int = 0
var _board: BoardState = null
var _tile_source: TileSource = null
var _ledger: ScoreLedger = null
var _scored_hand_ids: ScoredHandSet = null
var _rules: ScoringRules = null
var _generation_rules: TileGenerationRules = null
var _generation_rules_version: String = ""
var _turn_state: TurnState = null
var _active_tiles: Dictionary = {}
var _history: Array[ScoringMove] = []
var _outcome: int = TurnEnums.MatchOutcome.IN_PROGRESS
var _end_reason: int = TurnEnums.EndReason.NONE


## Builds a fresh match: empty board, generated bag, empty ledger, and a turn
## state sitting at `MATCH_SETUP`.
##
## Returns null when the configuration is unusable, so a caller can never receive
## a half-built match. Tile generation is seeded here and nowhere else
## (ADR-004 section 3).
static func create(
	match_id: StringName,
	seed: int,
	scoring_rules: ScoringRules,
	generation_rules: TileGenerationRules
) -> GameSessionState:
	if String(match_id).is_empty():
		push_error("GameSessionState.create: a match identifier is required.")
		return null
	if scoring_rules == null or not scoring_rules.is_valid():
		push_error("GameSessionState.create: valid scoring rules are required.")
		return null
	if generation_rules == null or not generation_rules.is_valid():
		push_error("GameSessionState.create: valid tile generation rules are required.")
		return null

	var source: TileSource = TileSource.new()
	if not source.initialize(match_id, seed, generation_rules):
		push_error("GameSessionState.create: the tile source refused its configuration.")
		return null

	var session: GameSessionState = GameSessionState.new()
	session._match_id = match_id
	session._seed = seed
	session._board = BoardState.create()
	session._tile_source = source
	session._ledger = ScoreLedger.create()
	session._scored_hand_ids = ScoredHandSet.create()
	session._rules = scoring_rules
	session._generation_rules = generation_rules
	session._generation_rules_version = generation_rules.version_key()
	session._turn_state = TurnState.create()
	session._active_tiles = {}
	session._history = []
	session._outcome = TurnEnums.MatchOutcome.IN_PROGRESS
	session._end_reason = TurnEnums.EndReason.NONE
	return session


## Returns the match identity that owns this session.
func get_match_id() -> StringName:
	return _match_id


## Returns the match seed. Deterministic replay depends on this value.
func get_seed() -> int:
	return _seed


## Returns the authoritative board.
func get_board() -> BoardState:
	return _board


## Returns the deterministic tile supply.
func get_tile_source() -> TileSource:
	return _tile_source


## Returns the committed score ledger.
func get_ledger() -> ScoreLedger:
	return _ledger


## Returns the set of poker windows that have already scored (ADR-001 section 5).
func get_scored_hand_set() -> ScoredHandSet:
	return _scored_hand_ids


## Returns the scoring rules in force for this match.
func get_rules() -> ScoringRules:
	return _rules


## Returns the tile generation rules in force for this match.
func get_generation_rules() -> TileGenerationRules:
	return _generation_rules


## Returns the tile-generation rules version recorded at setup.
func get_generation_rules_version() -> String:
	return _generation_rules_version


## Returns the mutable turn position. `TurnManager` owns its transitions.
func get_turn_state() -> TurnState:
	return _turn_state


## Returns the ordered committed move history (ADR-007 section 10).
func get_history() -> Array[ScoringMove]:
	return _history.duplicate()


## Returns how many moves have been committed.
func move_count() -> int:
	return _history.size()


## Returns the most recently committed move, or null before the first move.
func last_move() -> ScoringMove:
	if _history.is_empty():
		return null
	return _history[_history.size() - 1]


## Returns true when a move with this identifier has already been committed.
##
## ADR-007 section 5 requires a repeated commit to be recognised instead of
## scoring twice, and this is the check that makes that possible.
func has_move_id(move_id: StringName) -> bool:
	return find_move(move_id) != null


## Returns the committed move with this identifier, or null.
func find_move(move_id: StringName) -> ScoringMove:
	for move: ScoringMove in _history:
		if move.move_id == move_id:
			return move
	return null


## Returns the outcome of this match (ADR-003 section 8).
func get_outcome() -> int:
	return _outcome


## Returns why this match ended (ADR-003 section 7).
func get_end_reason() -> int:
	return _end_reason


## Returns true once no further move may be committed.
##
## A recorded final outcome is checked first, because ADR-003 section 7 makes the
## outcome the authoritative statement that the match has ended: `TurnManager`
## sets both the outcome and the phase, but a caller that records a result
## directly must not leave the session reporting itself as still live. Without
## this check "over" would have two sources of truth that can disagree, and input
## gating reads only this function.
func is_over() -> bool:
	if _outcome != TurnEnums.MatchOutcome.IN_PROGRESS:
		return true
	return _turn_state != null and _turn_state.is_stopped()


## Returns how many tiles remain undrawn (ADR-004 information visibility).
##
## Only the count is exposed: undrawn contents and draw order stay hidden from
## both the player-facing UI and the AI decision interface.
func remaining_tile_count() -> int:
	if _tile_source == null:
		return 0
	return _tile_source.remaining_count()


## Returns one player's committed total, rebuilt from the ledger.
func score_for(player_id: StringName) -> int:
	if _ledger == null:
		return 0
	return _ledger.total_for(player_id)


## Returns the active uncommitted tile owned by a player, or null.
##
## ADR-003 section 4 allows at most one active tile per player, which is why this
## is a single lookup rather than a list.
func active_tile_for(player_id: StringName) -> TileDefinition:
	if not _active_tiles.has(player_id):
		return null
	return _active_tiles[player_id]


## Returns true when the player holds an uncommitted tile.
func has_active_tile(player_id: StringName) -> bool:
	return _active_tiles.has(player_id)


## Assigns a player's active tile, replacing any tile already there.
##
## Returns false when the player is not a Phase 1 player or the tile is unusable.
## Drawing and assignment are one atomic change under ADR-004 section 6: the
## caller draws from the source and assigns in the same step, and an assignment
## that fails leaves the bag untouched.
func set_active_tile(player_id: StringName, tile: TileDefinition) -> bool:
	if not TurnEnums.is_valid_player_id(player_id):
		push_error(
			"GameSessionState.set_active_tile: '%s' is not a Phase 1 player." % String(player_id)
		)
		return false
	if tile == null or not tile.is_valid():
		return false
	_active_tiles[player_id] = tile
	return true


## Removes a player's active tile, as a commit does. Returns true if one was held.
func clear_active_tile(player_id: StringName) -> bool:
	if not _active_tiles.has(player_id):
		return false
	_active_tiles.erase(player_id)
	return true


## Returns the identities of every player holding an active tile, in fixed order.
func players_with_active_tiles() -> Array[StringName]:
	var players: Array[StringName] = []
	for player_id: StringName in TurnEnums.player_ids():
		if _active_tiles.has(player_id):
			players.append(player_id)
	return players


## Returns the tile definition with this identity, from anywhere it can legally
## be: a player's active slot, a committed board cell, or the generated bag.
##
## The bag is searched last and only through its debug accessor, because ADR-004
## section 7 hides undrawn contents from gameplay code. This lookup exists so a
## restored match can resolve a placed tile identity back to its definition
## without duplicating tile values into the save record.
func tile_by_id(tile_id: StringName) -> TileDefinition:
	if String(tile_id).is_empty():
		return null
	for player_id: StringName in TurnEnums.player_ids():
		var active: TileDefinition = active_tile_for(player_id)
		if active != null and active.tile_id == tile_id:
			return active
	for cell: Vector2i in _board.get_occupied_cells():
		var snapshot: TileSnapshot = _board.get_tile(cell)
		if snapshot != null and snapshot.get_tile_id() == tile_id:
			return snapshot.get_tile()
	if _tile_source != null and _tile_source.is_initialized():
		for tile: TileDefinition in _tile_source.debug_bag_snapshot():
			if tile != null and tile.tile_id == tile_id:
				return tile
	return null


## Appends a committed move to the history.
##
## Returns false for an unusable record or a repeated move identifier, so the
## history can never hold the same move twice (ADR-007 section 5).
func append_move(move: ScoringMove) -> bool:
	if move == null or not move.is_valid():
		return false
	if has_move_id(move.move_id):
		return false
	_history.append(move)
	return true


## Marks the match finished with its outcome and end reason.
##
## The outcome is derived from committed totals, never from a caller's
## preference, so the result cannot disagree with the ledger
## (ADR-003 section 8).
func finish(outcome: int, end_reason: int) -> bool:
	if not TurnEnums.is_valid_outcome(outcome):
		return false
	if not TurnEnums.is_valid_end_reason(end_reason):
		return false
	_outcome = outcome
	_end_reason = end_reason
	return true


## Returns every tile-conservation problem found (ADR-004 save requirements).
##
## ADR-004 requires a load to assert that every tile ID appears in exactly one
## place: the remaining bag, a player's active slot, or a committed board cell,
## with the total unchanged. Duplicates and lost tiles are both reported.
func verify_tile_conservation() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if _tile_source == null or not _tile_source.is_initialized():
		problems.append("the tile source is not initialized, so conservation cannot be checked")
		return problems

	var located: Dictionary = {}
	var bag: Array[TileDefinition] = _tile_source.debug_bag_snapshot()
	var next_index: int = _tile_source.get_draw_index()

	for index: int in range(next_index, bag.size()):
		var tile: TileDefinition = bag[index]
		if tile == null:
			problems.append("bag index %d holds no tile" % index)
			continue
		_add_location(problems, located, tile.tile_id, "remaining bag")

	for player_id: StringName in _active_tiles.keys():
		var active: TileDefinition = _active_tiles[player_id]
		if active == null:
			problems.append("player '%s' has a null active tile" % String(player_id))
			continue
		_add_location(
			problems, located, active.tile_id, "active slot of '%s'" % String(player_id)
		)

	for cell: Vector2i in _board.get_occupied_cells():
		var snapshot: TileSnapshot = _board.get_tile(cell)
		if snapshot == null:
			continue
		_add_location(
			problems,
			located,
			snapshot.get_tile_id(),
			"committed cell %s" % BoardEnums.cell_name(cell)
		)

	for tile: TileDefinition in bag:
		if tile == null:
			continue
		if not located.has(tile.tile_id):
			problems.append(
				"drawn tile '%s' is in neither the bag, an active slot, nor a cell"
				% String(tile.tile_id)
			)
	return problems


## Returns a versioned, JSON-safe save record (ADR-003 section 9).
func to_snapshot() -> MatchSnapshotDto:
	var dto: MatchSnapshotDto = MatchSnapshotDto.new()
	dto.schema_version = MatchSnapshotDto.SCHEMA_VERSION
	dto.match_id = _match_id
	dto.seed = _seed
	dto.tile_generation_version = _generation_rules_version
	dto.scoring_version = "" if _rules == null else _rules.version_key()
	dto.tile_source = null if _tile_source == null else _tile_source.to_dto()

	dto.board = []
	for cell: Vector2i in _board.get_occupied_cells():
		var snapshot: TileSnapshot = _board.get_tile(cell)
		if snapshot == null:
			continue
		dto.board.append(
			{
				"tile_id": String(snapshot.get_tile_id()),
				"cell": [cell.x, cell.y],
				"rotation": snapshot.get_rotation(),
			}
		)

	dto.active_tiles = {}
	for player_id: StringName in TurnEnums.player_ids():
		var active: TileDefinition = active_tile_for(player_id)
		if active != null:
			dto.active_tiles[String(player_id)] = String(active.tile_id)

	dto.turn = {
		"phase": _turn_state.phase,
		"active_player_id": String(_turn_state.active_player_id),
		"turn_number": _turn_state.turn_number,
		"consecutive_no_tile_skips": _turn_state.consecutive_no_tile_skips,
	}

	dto.history = []
	for move: ScoringMove in _history:
		dto.history.append(move.to_dictionary())

	dto.ledger = _ledger.to_dictionary()
	dto.scored_hand_ids = []
	for hand_id: StringName in _scored_hand_ids.to_array():
		dto.scored_hand_ids.append(String(hand_id))
	dto.outcome = _outcome
	dto.end_reason = _end_reason
	return dto


## Rebuilds a match from a save record.
##
## Returns null when the record is unusable, when the supplied rule sets do not
## match the versions the record was written with, or when the restored tiles do
## not satisfy ADR-004's conservation assertion. A match is never partially
## restored: either every piece is rebuilt or the caller gets null.
static func from_snapshot(
	dto: MatchSnapshotDto,
	scoring_rules: ScoringRules,
	generation_rules: TileGenerationRules
) -> GameSessionState:
	if dto == null or not dto.is_valid():
		return null
	if scoring_rules == null or not scoring_rules.is_valid():
		push_error("GameSessionState.from_snapshot: valid scoring rules are required.")
		return null
	if generation_rules == null or not generation_rules.is_valid():
		push_error("GameSessionState.from_snapshot: valid tile generation rules are required.")
		return null
	if dto.scoring_version != scoring_rules.version_key():
		push_error(
			"GameSessionState.from_snapshot: the save was written under scoring rules '%s' but '%s' was supplied."
			% [dto.scoring_version, scoring_rules.version_key()]
		)
		return null
	if dto.tile_generation_version != generation_rules.version_key():
		push_error(
			"GameSessionState.from_snapshot: the save was written under tile rules '%s' but '%s' was supplied."
			% [dto.tile_generation_version, generation_rules.version_key()]
		)
		return null

	var source: TileSource = TileSource.from_dto(dto.tile_source)
	if source == null:
		push_error("GameSessionState.from_snapshot: the tile source record could not be restored.")
		return null

	var by_id: Dictionary = {}
	for tile: TileDefinition in source.debug_bag_snapshot():
		if tile != null:
			by_id[tile.tile_id] = tile

	var session: GameSessionState = GameSessionState.new()
	session._match_id = dto.match_id
	session._seed = dto.seed
	session._board = BoardState.create()
	session._tile_source = source
	session._scored_hand_ids = ScoredHandSet.create()
	session._rules = scoring_rules
	session._generation_rules = generation_rules
	session._generation_rules_version = dto.tile_generation_version
	session._active_tiles = {}
	session._history = []
	session._outcome = dto.outcome
	session._end_reason = dto.end_reason

	for record: Variant in dto.board:
		var entry: Dictionary = record
		var tile_id: StringName = StringName(String(entry.get("tile_id", "")))
		if not by_id.has(tile_id):
			push_error(
				"GameSessionState.from_snapshot: committed tile '%s' is not in the restored bag."
				% String(tile_id)
			)
			return null
		var raw_cell: Array = entry.get("cell", [])
		var cell: Vector2i = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		var rotation: int = int(entry.get("rotation", 0))
		var snapshot: TileSnapshot = TileSnapshot.create(by_id[tile_id], cell, rotation)
		if not session._board.commit_tile(snapshot):
			push_error(
				"GameSessionState.from_snapshot: the board refused a committed tile at %s."
				% BoardEnums.cell_name(cell)
			)
			return null

	for key: Variant in dto.active_tiles.keys():
		var player_id: StringName = StringName(String(key))
		var tile_id: StringName = StringName(String(dto.active_tiles[key]))
		if not by_id.has(tile_id):
			push_error(
				"GameSessionState.from_snapshot: active tile '%s' is not in the restored bag."
				% String(tile_id)
			)
			return null
		if not session.set_active_tile(player_id, by_id[tile_id]):
			push_error(
				"GameSessionState.from_snapshot: player '%s' could not be given its active tile."
				% String(player_id)
			)
			return null

	for record: Variant in dto.history:
		var move: ScoringMove = ScoringMove.from_dictionary(record)
		if not session.append_move(move):
			push_error(
				"GameSessionState.from_snapshot: the move history holds an unusable or repeated move."
			)
			return null

	session._ledger = ScoreLedger.from_dictionary(dto.ledger)
	for hand_id: Variant in dto.scored_hand_ids:
		session._scored_hand_ids.add(StringName(String(hand_id)))

	session._turn_state = TurnState.create()
	session._turn_state.phase = int(dto.turn.get("phase", TurnEnums.MatchPhase.MATCH_SETUP))
	session._turn_state.active_player_id = StringName(
		String(dto.turn.get("active_player_id", ""))
	)
	session._turn_state.turn_number = int(dto.turn.get("turn_number", 0))
	session._turn_state.consecutive_no_tile_skips = int(
		dto.turn.get("consecutive_no_tile_skips", 0)
	)

	# ADR-004: assert on load that every tile is in exactly one place.
	var problems: PackedStringArray = session.verify_tile_conservation()
	if not problems.is_empty():
		push_error(
			"GameSessionState.from_snapshot: restored tiles are inconsistent: %s"
			% "; ".join(problems)
		)
		return null
	return session


## Returns a compact one-line description, for diagnostics only.
func describe() -> String:
	return "%s seed %d: %s, %d/%d tiles placed, %d drawn tile(s) left, human %d vs ai %d, %s" % [
		String(_match_id),
		_seed,
		_turn_state.describe(),
		_board.occupied_count(),
		BoardEnums.CELL_COUNT,
		remaining_tile_count(),
		score_for(TurnEnums.HUMAN_PLAYER_ID),
		score_for(TurnEnums.AI_PLAYER_ID),
		TurnEnums.outcome_name(_outcome),
	]


## Records one tile location, reporting a tile found in two places at once.
static func _add_location(
	problems: PackedStringArray, located: Dictionary, tile_id: StringName, label: String
) -> void:
	if String(tile_id).is_empty():
		problems.append("a tile with no identity is located in the %s" % label)
		return
	if located.has(tile_id):
		problems.append(
			"tile '%s' is recorded twice: in the %s and the %s"
			% [String(tile_id), String(located[tile_id]), label]
		)
		return
	located[tile_id] = label
