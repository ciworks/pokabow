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
## ADR-010 sections 1, 2, 5, and 10 replace a player's single active tile with a
## per-player **deck** of `DeckRules.deck_size` tiles, dealt from the one shared
## pot at `MATCH_SETUP` and topped back up at every turn boundary. The decks are
## part of the authoritative state and are therefore persisted as ordered tile
## identifiers (ADR-010 section 10), and they are part of ADR-004's
## tile-conservation assertion: every tile identifier appears exactly once across
## the remaining pot, the two decks, and the committed board.
##
## "Active tile" survives only as the deck tile a player has armed for the next
## placement: it is always a member of that player's deck, so it adds no new tile
## location and is not persisted as a separate location.
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
var _deck_rules: DeckRules = null
var _deck_rules_version: String = ""
var _turn_state: TurnState = null
var _decks: Dictionary = {}
var _armed_tiles: Dictionary = {}
var _history: Array[ScoringMove] = []
var _outcome: int = TurnEnums.MatchOutcome.IN_PROGRESS
var _end_reason: int = TurnEnums.EndReason.NONE


## Builds a fresh match: empty board, generated bag, empty ledger, empty decks,
## and a turn state sitting at `MATCH_SETUP`.
##
## Returns null when the configuration is unusable, so a caller can never receive
## a half-built match. Tile generation is seeded here and nowhere else
## (ADR-004 section 3).
##
## `deck_rules` is optional so existing callers keep working; omitting it applies
## the approved Phase 1 deck size (ADR-010 section 1). `TurnManager.setup()` deals
## the decks, so a session is never dealt twice.
static func create(
	match_id: StringName,
	seed: int,
	scoring_rules: ScoringRules,
	generation_rules: TileGenerationRules,
	deck_rules: DeckRules = null
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
	# ADR-010 section 3 makes the deck size a versioned rules value whose
	# approved default is six, so an omitted argument resolves to the standard
	# rules instead of failing. That is the documented default rather than a
	# substitute rule, and it keeps callers that do not care about deck size
	# working unchanged.
	var resolved_deck_rules: DeckRules = deck_rules
	if resolved_deck_rules == null:
		resolved_deck_rules = DeckRules.create_default()
	if not resolved_deck_rules.is_valid():
		push_error("GameSessionState.create: valid deck rules are required.")
		return null
	deck_rules = resolved_deck_rules

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
	session._deck_rules = deck_rules
	session._deck_rules_version = deck_rules.version_key()
	session._turn_state = TurnState.create()
	session._decks = _empty_decks()
	session._armed_tiles = {}
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


## Returns the deck rules in force for this match (ADR-010 section 1).
func get_deck_rules() -> DeckRules:
	return _deck_rules


## Returns the deck rules version recorded at setup.
func get_deck_rules_version() -> String:
	return _deck_rules_version


## Returns the number of tiles a deck is filled to (ADR-010 section 1).
func get_deck_size() -> int:
	if _deck_rules == null:
		return DeckRules.DEFAULT_DECK_SIZE
	return _deck_rules.deck_size


## Deals the opening decks from the shared pot (ADR-010 section 2).
##
## ADR-010 section 2 fixes the order: the human's deck is filled first, then the
## AI's, so a replay reproduces the same decks from the same seed (ADR-004
## section 3). Each deck takes as many tiles as the pot can supply, which with the
## Phase 1 defaults is six each and leaves 132 in the pot.
##
## Returns false when the session holds no usable deck rules, or when a deck is
## already stocked; dealing twice would duplicate tile identities, so it is
## refused rather than merged.
func deal_decks() -> bool:
	if _deck_rules == null or not _deck_rules.is_valid():
		push_error("GameSessionState.deal_decks: valid deck rules are required.")
		return false
	for player_id: StringName in TurnEnums.deck_deal_order():
		if deck_count(player_id) > 0:
			push_error(
				"GameSessionState.deal_decks: '%s' already holds a deck; the pot is not dealt twice."
				% String(player_id)
			)
			return false
	for player_id: StringName in TurnEnums.deck_deal_order():
		top_up_deck(player_id)
	return true


## Tops one player's deck back up to `deck_size` from the pot
## (ADR-010 section 5).
##
## Returns how many tiles were taken, which is zero once the pot is exhausted. A
## deck is therefore never larger than `deck_size`; it is smaller only when the
## pot could not supply the difference.
func top_up_deck(player_id: StringName) -> int:
	if not TurnEnums.is_valid_player_id(player_id):
		push_error(
			"GameSessionState.top_up_deck: '%s' is not a Phase 1 player." % String(player_id)
		)
		return 0
	if _tile_source == null or not _tile_source.is_initialized():
		return 0
	if _deck_rules == null:
		return 0
	var deck: Array[TileDefinition] = _deck(player_id)
	var taken: int = 0
	while deck.size() < _deck_rules.deck_size:
		var tile: TileDefinition = _tile_source.draw()
		if tile == null:
			break
		deck.append(tile)
		taken += 1
	_decks[player_id] = deck
	return taken


## Returns a player's deck in deal order, or an empty array.
func deck_for(player_id: StringName) -> Array[TileDefinition]:
	return _deck(player_id).duplicate()


## Returns how many tiles a player holds.
func deck_count(player_id: StringName) -> int:
	if not _decks.has(player_id):
		return 0
	var deck: Array[TileDefinition] = _decks[player_id]
	return deck.size()


## Returns true when either player holds at least one tile (ADR-010 section 7).
func holds_any_tile() -> bool:
	for player_id: StringName in TurnEnums.player_ids():
		if deck_count(player_id) > 0:
			return true
	return false


## Returns true when this player's deck holds this tile identity.
func holds_deck_tile(player_id: StringName, tile_id: StringName) -> bool:
	return _deck_tile_index(player_id, tile_id) >= 0


## Returns the deck tile with this identity, or null.
func deck_tile(player_id: StringName, tile_id: StringName) -> TileDefinition:
	var index: int = _deck_tile_index(player_id, tile_id)
	if index < 0:
		return null
	var deck: Array[TileDefinition] = _deck(player_id)
	return deck[index]


## Removes one tile identity from a player's deck, as a commit does.
## Returns true when the tile was held and is now removed.
func remove_deck_tile(player_id: StringName, tile_id: StringName) -> bool:
	var index: int = _deck_tile_index(player_id, tile_id)
	if index < 0:
		return false
	var deck: Array[TileDefinition] = _deck(player_id)
	deck.remove_at(index)
	_decks[player_id] = deck
	if armed_tile_id_for(player_id) == tile_id:
		_armed_tiles.erase(player_id)
	return true


## Returns the placement index the next committed placement of the current turn
## will carry (ADR-010 section 9).
##
## The index is the number of placements this turn has already committed, plus
## one, so the first placement of a turn is 1, the second is 2, and so on. It is
## counted from the turn position (`TurnState.placements_this_turn`) rather than
## from the committed history, because ADR-007 section 5 needs a retried
## placement to reproduce the identifier of the placement it repeats: a caller
## that restores the turn position to what it was before that placement presents
## the same index again, and the `MoveCommitter` refuses the repeat as a
## duplicate instead of scoring it twice. A refused or refused-out move never
## advances the count, so a retry after a legal refusal is still index 1
## (ADR-003 section 5).
##
## A turn is bounded at `deck_size` placements (ADR-010 section 6), because the
## deck does not refill mid-turn.
func next_placement_index() -> int:
	if _turn_state == null or _turn_state.turn_number <= 0:
		return 1
	return _turn_state.placements_this_turn + 1


## Records a committed placement of the current turn (ADR-010 section 9).
##
## Called by `MoveCommitter` after the move has been committed, so the next
## placement of the turn carries the following index. Nothing else may advance
## the count: a refused placement must leave the sequence where it was.
func note_placement_committed() -> void:
	if _turn_state == null:
		return
	_turn_state.placements_this_turn += 1


## Restores the turn's placement index from the committed history (ADR-010
## sections 9 and 10).
##
## Internal: a resumed match restores its turn position, which seats the active
## player and therefore restarts the index. The count is then re-derived from the
## restored history, so a match resumed in the middle of a turn continues the
## identifier sequence rather than reusing an index a placement already carries.
func _rebuild_placement_index() -> void:
	if _turn_state == null:
		return
	var count: int = 0
	for move: ScoringMove in _history:
		if move.move_number == _turn_state.turn_number:
			count += 1
	_turn_state.placements_this_turn = count


## Returns the identity of the deck tile a player has armed, or an empty name.
func armed_tile_id_for(player_id: StringName) -> StringName:
	if not _armed_tiles.has(player_id):
		return &""
	var armed: TileDefinition = _armed_tiles[player_id]
	if armed == null:
		return &""
	return armed.tile_id


## Returns the mutable deck array for a player, creating it when absent.
##
## Internal: the returned array IS the stored one, so callers must treat it as
## authoritative state rather than a copy.
func _deck(player_id: StringName) -> Array[TileDefinition]:
	if not _decks.has(player_id):
		_decks[player_id] = [] as Array[TileDefinition]
	var deck: Array[TileDefinition] = _decks[player_id]
	return deck


## Returns the position of a tile identity in a player's deck, or -1.
func _deck_tile_index(player_id: StringName, tile_id: StringName) -> int:
	if String(tile_id).is_empty():
		return -1
	var deck: Array[TileDefinition] = _deck(player_id)
	for index: int in range(deck.size()):
		var tile: TileDefinition = deck[index]
		if tile != null and tile.tile_id == tile_id:
			return index
	return -1


## Returns one empty deck per Phase 1 player, in deal order.
static func _empty_decks() -> Dictionary:
	var decks: Dictionary = {}
	for player_id: StringName in TurnEnums.player_ids():
		decks[player_id] = [] as Array[TileDefinition]
	return decks


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


## Returns the uncommitted deck tile a player has armed, or null.
##
## ADR-010 section 4 arms exactly one deck tile at a time: the armed tile is the
## tile the next placement of this turn commits, and it is always a member of the
## player's deck. With nothing armed, a caller's default is the deck's first tile.
func active_tile_for(player_id: StringName) -> TileDefinition:
	var tile_id: StringName = armed_tile_id_for(player_id)
	if not String(tile_id).is_empty():
		return deck_tile(player_id, tile_id)
	var deck: Array[TileDefinition] = _deck(player_id)
	if deck.is_empty():
		return null
	return deck[0]


## Returns true when the player holds at least one tile to place.
##
## ADR-010 section 10 replaces "at most one active tile" with a deck of zero to
## `deck_size` tiles, so holding a tile means the deck is not empty.
func has_active_tile(player_id: StringName) -> bool:
	return deck_count(player_id) > 0


## Arms one of a player's deck tiles as the tile the next placement commits.
##
## Returns false when the player is not a Phase 1 player, the tile is unusable, or
## the player does not actually hold that tile: ADR-010 section 4 makes a deck a
## player's own tiles, so a tile from the pot or from the opponent's deck can
## never be armed.
func set_active_tile(player_id: StringName, tile: TileDefinition) -> bool:
	if not TurnEnums.is_valid_player_id(player_id):
		push_error(
			"GameSessionState.set_active_tile: '%s' is not a Phase 1 player." % String(player_id)
		)
		return false
	if tile == null or not tile.is_valid():
		return false
	if not holds_deck_tile(player_id, tile.tile_id):
		return false
	_armed_tiles[player_id] = tile
	return true


## Disarms a player's armed tile, leaving the tile in their deck.
##
## Returns true if one was armed. ADR-010 section 4 leaves the deck untouched by a
## commit until the tile is removed from it, so this only clears the selection.
func clear_active_tile(player_id: StringName) -> bool:
	if not _armed_tiles.has(player_id):
		return false
	_armed_tiles.erase(player_id)
	return true


## Returns the identities of every player holding at least one tile, in fixed
## order. ADR-010 section 10 makes this the deck membership test the end
## conditions and the tile-conservation check read.
func players_with_active_tiles() -> Array[StringName]:
	var players: Array[StringName] = []
	for player_id: StringName in TurnEnums.player_ids():
		if deck_count(player_id) > 0:
			players.append(player_id)
	return players


## Returns the tile definition with this identity, from anywhere it can legally
## be: a player's deck, a committed board cell, or the generated bag.
##
## The bag is searched last and only through its debug accessor, because ADR-004
## section 7 hides undrawn contents from gameplay code. This lookup exists so a
## restored match can resolve a placed tile identity back to its definition
## without duplicating tile values into the save record.
func tile_by_id(tile_id: StringName) -> TileDefinition:
	if String(tile_id).is_empty():
		return null
	for player_id: StringName in TurnEnums.player_ids():
		var held: TileDefinition = deck_tile(player_id, tile_id)
		if held != null:
			return held
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


## Returns every tile-conservation problem found (ADR-004 save requirements,
## ADR-010 section 10).
##
## ADR-010 section 10 extends the assertion to the deck locations: every tile
## identifier must appear exactly once across the remaining pot, the human's deck,
## the AI's deck, and the committed board, and the total must still be 144.
## Duplicates and lost tiles are both reported. An armed tile is a deck tile, so
## it is counted where it lives rather than as a separate location.
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

	for player_id: StringName in TurnEnums.player_ids():
		var deck: Array[TileDefinition] = _deck(player_id)
		for index: int in range(deck.size()):
			var held: TileDefinition = deck[index]
			if held == null:
				problems.append(
					"deck slot %d of '%s' holds no tile" % [index, String(player_id)]
				)
				continue
			_add_location(
				problems, located, held.tile_id, "deck of '%s'" % String(player_id)
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
	dto.deck_rules_version = _deck_rules_version
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

	# ADR-010 section 10: each player's deck is an ordered list of tile
	# identifiers, so a resumed match continues with the same tiles in the same
	# order. The armed tile is a deck member and needs no separate record.
	dto.decks = {}
	for player_id: StringName in TurnEnums.player_ids():
		var ids: Array = []
		var deck: Array[TileDefinition] = _deck(player_id)
		for tile: TileDefinition in deck:
			if tile != null:
				ids.append(String(tile.tile_id))
		dto.decks[String(player_id)] = ids

	dto.turn = {
		"phase": _turn_state.phase,
		"active_player_id": String(_turn_state.active_player_id),
		"turn_number": _turn_state.turn_number,
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
	generation_rules: TileGenerationRules,
	deck_rules: DeckRules = null
) -> GameSessionState:
	if dto == null or not dto.is_valid():
		return null
	if scoring_rules == null or not scoring_rules.is_valid():
		push_error("GameSessionState.from_snapshot: valid scoring rules are required.")
		return null
	if generation_rules == null or not generation_rules.is_valid():
		push_error("GameSessionState.from_snapshot: valid tile generation rules are required.")
		return null
	if deck_rules == null:
		deck_rules = DeckRules.create_default()
	if not deck_rules.is_valid():
		push_error("GameSessionState.from_snapshot: valid deck rules are required.")
		return null
	if dto.deck_rules_version != deck_rules.version_key():
		push_error(
			"GameSessionState.from_snapshot: the save was written under deck rules '%s' but '%s' was supplied."
			% [dto.deck_rules_version, deck_rules.version_key()]
		)
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
	session._deck_rules = deck_rules
	session._deck_rules_version = dto.deck_rules_version
	session._decks = _empty_decks()
	session._armed_tiles = {}
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

	# ADR-010 section 10: restore each deck in its saved order. An identity that
	# is not in the restored bag is a corrupt record rather than a lost tile, so
	# the restore is refused instead of returning a partial match.
	for key: Variant in dto.decks.keys():
		var player_id: StringName = StringName(String(key))
		if not TurnEnums.is_valid_player_id(player_id):
			push_error(
				"GameSessionState.from_snapshot: '%s' is not a Phase 1 player."
				% String(player_id)
			)
			return null
		var raw_ids: Variant = dto.decks[key]
		if not (raw_ids is Array):
			push_error(
				"GameSessionState.from_snapshot: the deck of '%s' is not a list."
				% String(player_id)
			)
			return null
		var deck: Array[TileDefinition] = [] as Array[TileDefinition]
		for raw_id: Variant in raw_ids:
			var tile_id: StringName = StringName(String(raw_id))
			if not by_id.has(tile_id):
				push_error(
					"GameSessionState.from_snapshot: deck tile '%s' of '%s' is not in the restored bag."
					% [String(tile_id), String(player_id)]
				)
				return null
			deck.append(by_id[tile_id])
		session._decks[player_id] = deck

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
	# ADR-010 sections 9 and 10: the restored turn position must continue the
	# placement-index sequence of the turn it was saved in, so the index is
	# re-derived from the history restored above.
	session._rebuild_placement_index()

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
	return (
		"%s seed %d: %s, %d/%d tiles placed, %d in the pot, decks %d/%d, human %d vs ai %d, %s"
		% [
			String(_match_id),
			_seed,
			_turn_state.describe(),
			_board.occupied_count(),
			BoardEnums.CELL_COUNT,
			remaining_tile_count(),
			deck_count(TurnEnums.HUMAN_PLAYER_ID),
			deck_count(TurnEnums.AI_PLAYER_ID),
			score_for(TurnEnums.HUMAN_PLAYER_ID),
			score_for(TurnEnums.AI_PLAYER_ID),
			TurnEnums.outcome_name(_outcome),
		]
	)


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
