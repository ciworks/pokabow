class_name MatchSnapshotDto
extends RefCounted

## Versioned save record for one match (ADR-003 section 9, ADR-004 save and
## replay requirements, ADR-010 sections 5 and 9).
##
## ADR-003 section 9 lists what a restorable snapshot must contain; this type is
## that record. It deliberately stores tile *identity plus placement* rather than
## tile values, because the bag record already carries every generated tile, so a
## restored match resolves each placed tile back out of its own bag instead of
## duplicating face and edge data.
##
## ADR-004 requires a load to assert that every tile ID appears in exactly one
## place: the remaining pot, a player's deck, or a committed cell. That assertion
## lives in `GameSessionState.verify_tile_conservation()`, which
## `GameSessionState.from_snapshot()` runs before accepting a restore.
##
## ADR-010 section 5 replaces the single active tile with a per-player deck, so
## this record stores each player's deck rather than an active-tile slot, and
## ADR-010 section 9 records the deck rules version alongside the other rule
## versions so a deck-size change can be detected on load.
##
## ADR-003 section 9 forbids persisting a transient visual preview as
## authoritative board state, and requires a resume during a preview to come back
## at `AWAIT_ACTION` with the player's uncommitted tiles intact. A snapshot taken
## while a move is mid-resolution is therefore rejected rather than restored.

## Save schema version.
##
## Raised to 2 when ADR-010 replaced the single active tile with per-player
## decks: a version 1 record has no deck identity and would restore a match with
## no tiles in hand, so it is refused rather than migrated.
##
## Raised to 3 when ADR-011 made a move one whole line of two or more tiles
## (section 5) and a turn exactly one move (section 7). The history record shape
## changed (a move now carries several placements, not one tile), and a version 2
## record could describe a turn holding several committed placements, which the
## one-move turn of section 7 cannot represent: its move identifier would already
## exist, so the rest of that turn could neither be replayed nor continued. The
## record is therefore refused rather than migrated, exactly as version 1 was.
const SCHEMA_VERSION: int = 3

var schema_version: int = SCHEMA_VERSION

## Identity of the match this snapshot belongs to (ADR-004 section 5).
var match_id: StringName = &""

## Deterministic match seed. Replay depends on this value (ADR-003 section 9).
var seed: int = 0

## Tile-generation rules version recorded when the bag was created.
var tile_generation_version: String = ""

## Scoring rules version recorded in force for this match.
var scoring_version: String = ""

## Deck rules version recorded in force for this match (ADR-010 section 9).
##
## Deck size and the placements-per-turn allowance live in a versioned resource
## (ADR-010 section 1), so a match saved under one deck rule set cannot be
## silently resumed under another.
var deck_rules_version: String = ""

## Complete bag order, draw position, and generation identity (ADR-004).
var tile_source: TileSourceDto = null

## Committed tiles: records of `{tile_id, cell, rotation}`.
var board: Array = []

## Each player's deck of unplayed tiles: `{player_id: [tile_id, ...]}`
## (ADR-010 section 2). Only the IDs are stored; the tile values come back out of
## the bag record on restore.
var decks: Dictionary = {}

## Turn position: `{phase, active_player_id, turn_number, consecutive_no_tile_skips}`.
var turn: Dictionary = {}

## Ordered committed move history (ADR-007 section 10, ADR-011 section 5).
##
## Each record is `{move_id, move_number, player_id, placements: [{tile_id, cell,
## rotation}, ...], is_opening_move}`. ADR-011 section 5 commits a whole line as
## one move with one identifier and one history entry, so the record carries every
## tile that move placed rather than a single tile; `is_history_record_valid()`
## enforces that shape on load.
var history: Array = []

## Committed score ledger (ADR-007 section 1).
var ledger: Dictionary = {}

## Canonical identifiers of poker windows that have already scored
## (ADR-001 section 5).
var scored_hand_ids: Array = []

## `TurnEnums.MatchOutcome` value.
var outcome: int = TurnEnums.MatchOutcome.IN_PROGRESS

## `TurnEnums.EndReason` value.
var end_reason: int = TurnEnums.EndReason.NONE


## Returns true when the record is self-consistent and safe to restore.
func is_valid() -> bool:
	if schema_version != SCHEMA_VERSION:
		return false
	if String(match_id).is_empty():
		return false
	if tile_generation_version.is_empty() or scoring_version.is_empty():
		return false
	if deck_rules_version.is_empty():
		return false
	if tile_source == null or not tile_source.is_valid():
		return false
	if not turn.has("phase"):
		return false
	var phase: int = int(turn.get("phase", TurnEnums.MatchPhase.MATCH_SETUP))
	if not TurnEnums.is_valid_phase(phase):
		return false
	# A move in flight is not a transaction boundary (ADR-003 section 9).
	if phase == TurnEnums.MatchPhase.RESOLVE_MOVE:
		return false
	if not TurnEnums.is_valid_outcome(outcome):
		return false
	if not TurnEnums.is_valid_end_reason(end_reason):
		return false
	var turn_number: int = int(turn.get("turn_number", 0))
	if turn_number < 0:
		return false
	var remaining: Variant = turn.get("remaining_seconds", TurnManager.TURN_SECONDS)
	if not (remaining is float or remaining is int):
		return false
	if not is_finite(float(remaining)) or float(remaining) < 0.0 or float(remaining) > TurnManager.TURN_SECONDS:
		return false
	var deadline: Variant = turn.get("deadline_unix_seconds", 0.0)
	if not (deadline is float or deadline is int):
		return false
	if not is_finite(float(deadline)) or float(deadline) < 0.0:
		return false
	var skips: int = int(turn.get("consecutive_no_tile_skips", 0))
	if skips < 0 or skips > TurnEnums.MAX_CONSECUTIVE_SKIPS:
		return false
	for record: Variant in board:
		if not _is_board_record_valid(record):
			return false
	for key: Variant in decks.keys():
		if not _is_deck_record_valid(decks[key]):
			return false
	for record: Variant in history:
		if not is_history_record_valid(record):
			return false
	return true


## Serializes to a JSON-safe dictionary.
func to_dictionary() -> Dictionary:
	var history_records: Array = []
	for record: Variant in history:
		if record is Dictionary:
			history_records.append(record)
	return {
		"schema_version": schema_version,
		"match_id": String(match_id),
		"seed": seed,
		"tile_generation_version": tile_generation_version,
		"scoring_version": scoring_version,
		"deck_rules_version": deck_rules_version,
		"tile_source": null if tile_source == null else tile_source.to_dictionary(),
		"board": board.duplicate(),
		"decks": decks.duplicate(),
		"turn": turn.duplicate(),
		"history": history_records,
		"ledger": ledger.duplicate(),
		"scored_hand_ids": scored_hand_ids.duplicate(),
		"outcome": outcome,
		"end_reason": end_reason,
	}


## Builds a snapshot from a dictionary produced by `to_dictionary()`.
static func from_dictionary(source: Dictionary) -> MatchSnapshotDto:
	var dto: MatchSnapshotDto = MatchSnapshotDto.new()
	dto.schema_version = int(source.get("schema_version", 0))
	dto.match_id = StringName(String(source.get("match_id", "")))
	dto.seed = int(source.get("seed", 0))
	dto.tile_generation_version = String(source.get("tile_generation_version", ""))
	dto.scoring_version = String(source.get("scoring_version", ""))
	dto.deck_rules_version = String(source.get("deck_rules_version", ""))
	var raw_source: Variant = source.get("tile_source", null)
	if raw_source is Dictionary:
		dto.tile_source = TileSourceDto.from_dictionary(raw_source)
	var raw_board: Variant = source.get("board", [])
	if raw_board is Array:
		dto.board = raw_board.duplicate()
	var raw_decks: Variant = source.get("decks", {})
	if raw_decks is Dictionary:
		dto.decks = raw_decks.duplicate()
	var raw_turn: Variant = source.get("turn", {})
	if raw_turn is Dictionary:
		dto.turn = raw_turn.duplicate()
	var raw_history: Variant = source.get("history", [])
	if raw_history is Array:
		dto.history = raw_history.duplicate()
	var raw_ledger: Variant = source.get("ledger", {})
	if raw_ledger is Dictionary:
		dto.ledger = raw_ledger.duplicate()
	var raw_hands: Variant = source.get("scored_hand_ids", [])
	if raw_hands is Array:
		dto.scored_hand_ids = raw_hands.duplicate()
	dto.outcome = int(source.get("outcome", TurnEnums.MatchOutcome.IN_PROGRESS))
	dto.end_reason = int(source.get("end_reason", TurnEnums.EndReason.NONE))
	return dto


## Returns true when one deck record is a list of non-empty tile identifiers.
##
## An empty deck is legal (ADR-010 section 6 lets a player finish a turn with no
## tiles left while the pot is empty), so only the record's shape is checked here;
## whether the tiles it names actually exist is settled by the tile-conservation
## check on restore.
static func _is_deck_record_valid(record: Variant) -> bool:
	if not (record is Array):
		return false
	for entry: Variant in record:
		if String(entry).is_empty():
			return false
	return true


## Returns true when one history record describes a committable move
## (ADR-007 section 10, ADR-011 section 5).
##
## ADR-011 section 5 makes a move one whole line, so the record must carry a move
## identity, a player, a positive turn number, and at least one placement, and
## every placement must name a tile and sit on a valid cell with a valid rotation.
## A record written in the pre-ADR-011 single-tile shape is read as a
## one-placement move rather than refused, so a fixture in that shape still
## replays; the record shape check itself is unchanged either way.
static func is_history_record_valid(record: Variant) -> bool:
	if not (record is Dictionary):
		return false
	if String(record.get("move_id", "")).is_empty():
		return false
	if String(record.get("player_id", "")).is_empty():
		return false
	if int(record.get("move_number", 0)) <= 0:
		return false

	var raw_placements: Variant = record.get("placements", null)
	if raw_placements is Array:
		if (raw_placements as Array).is_empty():
			return false
		for entry: Variant in raw_placements:
			if not _is_placement_record_valid(entry):
				return false
		return true

	# The single-placement shape ADR-011 section 5 replaced.
	return record.has("tile_id") and _is_placement_record_valid(record)


## Returns true when one placement record names a tile on a valid cell.
static func _is_placement_record_valid(record: Variant) -> bool:
	if not (record is Dictionary):
		return false
	if String(record.get("tile_id", "")).is_empty():
		return false
	var raw_cell: Variant = record.get("cell", null)
	if not (raw_cell is Array) or raw_cell.size() < 2:
		return false
	var cell: Vector2i = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	if not BoardEnums.is_in_bounds(cell):
		return false
	var rotation: int = int(record.get("rotation", 0))
	return rotation >= 0 and rotation < TileEnums.ROTATION_COUNT


## Returns true when one board record names a tile and a valid cell and rotation.
static func _is_board_record_valid(record: Variant) -> bool:
	if not (record is Dictionary):
		return false
	var tile_id: String = String(record.get("tile_id", ""))
	if tile_id.is_empty():
		return false
	var raw_cell: Variant = record.get("cell", null)
	if not (raw_cell is Array) or raw_cell.size() < 2:
		return false
	var cell: Vector2i = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
	if not BoardEnums.is_in_bounds(cell):
		return false
	var rotation: int = int(record.get("rotation", 0))
	return rotation >= 0 and rotation < TileEnums.ROTATION_COUNT
