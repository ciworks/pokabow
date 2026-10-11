class_name AiGameSnapshot
extends RefCounted

## A detached, immutable view of the match as the AI may see it
## (ADR-005 sections 1, 3, 7, and "Data ownership").
##
## ADR-005 section 1 states that the snapshot includes only public or
## legitimately owned information, and "Data ownership" states that AI strategies
## and the AI coordinator read snapshots rather than live authoritative state.
## This type is that snapshot:
##
## - the board and the scored-window set are COPIES, so search can never mutate
##   the authoritative match;
## - the undrawn bag is deliberately absent. ADR-004 section 7 hides future tiles
##   from both the player-facing UI and the AI decision interface, so no accessor
##   here can expose one;
## - the rules, the two committed totals, the board revision, the turn number,
##   and the match seed are carried because scoring and determinism need them.
##
## The snapshot owns no rules and no scene node; it is a read-only record.

var _board: BoardState = null
var _scored_hand_set: ScoredHandSet = null
var _rules: ScoringRules = null
var _ai_player_id: StringName = &""
var _human_player_id: StringName = &""
var _ai_total: int = 0
var _human_total: int = 0
var _turn_number: int = 0
var _board_revision: int = 0
var _match_id: StringName = &""
var _match_seed: int = 0

## The two held decks, in deal order (ADR-010 section 2).
##
## ADR-011 section 12 makes the AI's move generation line-shaped, and a line is
## built from the tiles a player HOLDS, so the deck is part of the state the
## analysis needs. The AI's own deck is legitimately owned information, and the
## opponent's deck is public in Phase 1 because a deck tile is placed face up
## when it is committed (ADR-011 section 1). The undrawn pot is still absent:
## only the two decks are carried, and they are copies.
var _ai_deck: Array[TileDefinition] = []
var _human_deck: Array[TileDefinition] = []


## Builds a snapshot from the authoritative session for one AI player.
##
## Returns null when the session, the board, or the player identities are
## unusable: a snapshot that silently dropped the AI's own identity could not
## attribute a move, and ADR-005 section 11 prefers a stop to a wrong proposal.
static func create(session: GameSessionState, ai_player_id: StringName) -> AiGameSnapshot:
	if session == null:
		push_error("AiGameSnapshot.create: a session is required.")
		return null
	var board: BoardState = session.get_board()
	if board == null:
		push_error("AiGameSnapshot.create: the session has no board.")
		return null
	var human_player_id: StringName = TurnEnums.opponent_of(ai_player_id)
	if not TurnEnums.is_valid_player_id(ai_player_id) or String(human_player_id).is_empty():
		push_error(
			"AiGameSnapshot.create: '%s' is not one of the two Phase 1 players."
			% String(ai_player_id)
		)
		return null

	var scored: ScoredHandSet = session.get_scored_hand_set()
	var snapshot: AiGameSnapshot = AiGameSnapshot.new()
	# Copies, never live references: search must not be able to touch the match.
	snapshot._board = board.copy()
	snapshot._scored_hand_set = (
		scored.copy() if scored != null else ScoredHandSet.create()
	)
	snapshot._rules = session.get_rules()
	snapshot._ai_player_id = ai_player_id
	snapshot._human_player_id = human_player_id
	snapshot._ai_total = session.score_for(ai_player_id)
	snapshot._human_total = session.score_for(human_player_id)
	snapshot._turn_number = session.get_turn_state().turn_number
	snapshot._board_revision = snapshot._board.get_revision()
	snapshot._match_id = session.get_match_id()
	snapshot._match_seed = session.get_seed()
	snapshot._ai_deck = session.deck_for(ai_player_id)
	snapshot._human_deck = session.deck_for(human_player_id)
	return snapshot


## Builds a snapshot from explicit values, for tests and hypothetical views.
##
## The board and the scored set are copied, exactly as `create()` copies them.
## `ai_deck` and `human_deck` are the two held decks; a caller that leaves them
## out gets a snapshot whose decks are empty, which is the honest answer for a
## view that does not know what either player holds (and yields no candidates).
static func from_parts(
	board: BoardState,
	scored_hand_set: ScoredHandSet,
	rules: ScoringRules,
	ai_player_id: StringName,
	human_player_id: StringName,
	ai_total: int,
	human_total: int,
	turn_number: int,
	match_id: StringName,
	match_seed: int,
	ai_deck: Array[TileDefinition] = [],
	human_deck: Array[TileDefinition] = []
) -> AiGameSnapshot:
	var snapshot: AiGameSnapshot = AiGameSnapshot.new()
	snapshot._board = null if board == null else board.copy()
	snapshot._scored_hand_set = (
		ScoredHandSet.create() if scored_hand_set == null else scored_hand_set.copy()
	)
	snapshot._rules = rules
	snapshot._ai_player_id = ai_player_id
	snapshot._human_player_id = human_player_id
	snapshot._ai_total = ai_total
	snapshot._human_total = human_total
	snapshot._turn_number = turn_number
	snapshot._board_revision = 0 if snapshot._board == null else snapshot._board.get_revision()
	snapshot._match_id = match_id
	snapshot._match_seed = match_seed
	if ai_deck != null:
		for tile: TileDefinition in ai_deck:
			if tile != null and tile.is_valid():
				snapshot._ai_deck.append(tile)
	if human_deck != null:
		for tile: TileDefinition in human_deck:
			if tile != null and tile.is_valid():
				snapshot._human_deck.append(tile)
	return snapshot


## Returns the detached board copy. Never the authoritative board.
func get_board() -> BoardState:
	return _board


## Returns the detached scored-window copy. Never the authoritative set.
func get_scored_hand_set() -> ScoredHandSet:
	return _scored_hand_set


## Returns the scoring rules in force (ADR-007 section 1).
func get_rules() -> ScoringRules:
	return _rules


## Returns the AI player this snapshot was built for.
func ai_player_id() -> StringName:
	return _ai_player_id


## Returns the deck the AI holds, in deal order (ADR-010 section 2).
##
## A copy, so a strategy can never disturb the analysis state it was handed.
func ai_deck() -> Array[TileDefinition]:
	return _ai_deck.duplicate()


## Returns the deck the opponent holds, in deal order.
func human_deck() -> Array[TileDefinition]:
	return _human_deck.duplicate()


## Returns one player's deck, or an empty array for an unknown player.
func deck_for(player_id: StringName) -> Array[TileDefinition]:
	if player_id == _ai_player_id:
		return ai_deck()
	if player_id == _human_player_id:
		return human_deck()
	return [] as Array[TileDefinition]


## Returns true when both held decks are present, which line generation needs.
func has_decks() -> bool:
	return not _ai_deck.is_empty() and not _human_deck.is_empty()


## Returns the other Phase 1 player (ADR-003 constraint 1).
func human_player_id() -> StringName:
	return _human_player_id


## Returns the opponent of `player_id` within this snapshot.
func opponent_of(player_id: StringName) -> StringName:
	if player_id == _ai_player_id:
		return _human_player_id
	if player_id == _human_player_id:
		return _ai_player_id
	return &""


## Returns a player's committed total at the time of the snapshot.
func committed_total_for(player_id: StringName) -> int:
	if player_id == _ai_player_id:
		return _ai_total
	if player_id == _human_player_id:
		return _human_total
	return 0


## Returns the board revision the snapshot was taken at (ADR-005 section 11).
func board_revision() -> int:
	return _board_revision


## Returns the turn number the snapshot was taken at (ADR-005 section 3).
func turn_number() -> int:
	return _turn_number


## Returns the match identity, for diagnostics and move identifiers.
func match_id() -> StringName:
	return _match_id


## Returns the match seed (ADR-004 section 3, ADR-005 section 3).
func match_seed() -> int:
	return _match_seed


## Returns a detached board with one hypothetical tile added.
##
## Thin delegation to `BoardState.with_tile()` so a strategy never builds a
## hypothetical board by mutating the snapshot's copy (ADR-007 section 3).
func hypothetical_board(tile_snapshot: TileSnapshot) -> BoardState:
	if _board == null:
		return null
	return _board.with_tile(tile_snapshot)


## Returns a detached board with a whole hypothetical line added.
##
## The line-shaped counterpart of `hypothetical_board` (ADR-011 sections 2 and
## 5): the board a two-ply reply is evaluated against is the board this line
## would leave behind. It copies, so the snapshot's own board is never touched.
func hypothetical_board_for_line(line: Array[TileSnapshot]) -> BoardState:
	if _board == null:
		return null
	if line == null or line.is_empty():
		return _board.copy()
	return _board.with_tiles(line)


## Returns true when the snapshot carries everything a line decision needs.
func is_valid() -> bool:
	if _board == null or _scored_hand_set == null:
		return false
	if _ai_deck.is_empty():
		return false
	if _rules == null or not _rules.is_valid():
		return false
	if not TurnEnums.is_valid_player_id(_ai_player_id):
		return false
	if _human_player_id == _ai_player_id:
		return false
	if not TurnEnums.is_valid_player_id(_human_player_id):
		return false
	return _turn_number >= 0


## Returns every validation problem found, so callers can report all of them.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if _board == null:
		problems.append("a board copy is required")
	if _scored_hand_set == null:
		problems.append("a scored-window copy is required")
	if _rules == null:
		problems.append("scoring rules are required")
	elif not _rules.is_valid():
		problems.append("the scoring rules are invalid")
	if _ai_deck.is_empty():
		problems.append("the AI's held deck is required to generate lines (ADR-011 section 12)")
	if not TurnEnums.is_valid_player_id(_ai_player_id):
		problems.append("a valid AI player identity is required")
	if _human_player_id == _ai_player_id:
		problems.append("the two player identities must differ")
	if _turn_number < 0:
		problems.append("the turn number must not be negative, got %d" % _turn_number)
	return problems


## Returns a short description of this snapshot, for diagnostics only.
func describe() -> String:
	return "%s turn %d revision %d, board %d/%d occupied, totals %s %d / %s %d" % [
		String(_match_id),
		_turn_number,
		_board_revision,
		0 if _board == null else _board.occupied_count(),
		0 if _board == null else _board.cell_count(),
		String(_ai_player_id),
		_ai_total,
		String(_human_player_id),
		_human_total,
	]
