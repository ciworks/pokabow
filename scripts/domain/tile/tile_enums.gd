class_name TileEnums
extends RefCounted

## Shared tile vocabulary (GAME_SPEC section 3, ADR-004 sections 2 and 8).
##
## This script holds values and small pure helpers only. It has no state, no
## scene dependency, and no Godot node usage, so every layer can share one
## definition of the tile vocabulary instead of duplicating constants.
##
## Authority notes:
## - Face set, face colour, edge positions, and edge colours come from
##   GAME_SPEC section 3.1 and docs/sections/01-tile-system.md section 3.
## - `TileRank` is an identifier set, NOT a strength order.
##   docs/sections/01-tile-system.md section 4 states that face rank order is
##   not defined, and repeated-rank hands are classified by rank *frequency*
##   (ADR-001 section 2, ADR-012 section 1).
## - ADR-012 section 2 is the one explicit decision that defines a face ladder,
##   lowest to highest: Jack, Queen, King, Ace. It is exposed here as
##   `SEQUENCE_ORDER` with `sequence_position()` and `is_sequence_order()`, and
##   exists only so sequence hands can be recognised. It is the ONLY ordering
##   helper permitted; do not add another, and do not treat `TileRank` itself as
##   ordered.
## - The edge index order is fixed by ADR-004 section 4 ([top, right, bottom,
##   left]) and restated by docs/sections/01-tile-system.md section 5.1.

## Face rank identifiers. Ordering is not meaningful (see the note above).
enum TileRank {
	ACE = 0,
	KING = 1,
	QUEEN = 2,
	JACK = 3,
	JOKER = 4,
}

## Red/black face property (GAME_SPEC section 3.1). ADR-001 section 3 confirms
## this property carries no poker-hand role in Phase 1.
enum FaceColor {
	RED = 0,
	BLACK = 1,
	NONE = 2,
}

enum Suit {
	HEARTS = 0,
	DIAMONDS = 1,
	CLUBS = 2,
	SPADES = 3,
	NONE = 4,
}

## Edge colours, in the order GAME_SPEC section 5.4 lists them.
enum EdgeColor {
	BLUE = 0,
	RED = 1,
	GREEN = 2,
	YELLOW = 3,
}

## Edge positions, clockwise starting from the top. This is the canonical edge
## index order locked by unit tests.
enum EdgePosition {
	TOP = 0,
	RIGHT = 1,
	BOTTOM = 2,
	LEFT = 3,
}

## Number of edge positions on every tile (GAME_SPEC section 3.1).
const EDGE_COUNT: int = 4

## Number of quarter-turn orientations a tile can occupy (GAME_SPEC section 3.2).
const ROTATION_COUNT: int = 4


## Maps any integer rotation to the canonical 0-3 quarter-turn index.
##
## This is rotation arithmetic used for composing and displaying orientations.
## It is NOT placement validation: ADR-006 owns the `INVALID_ROTATION` rejection
## reason and the placement validator applies it in Milestone 2.
static func normalize_rotation(rotation: int) -> int:
	return ((rotation % ROTATION_COUNT) + ROTATION_COUNT) % ROTATION_COUNT


## The face ladder of ADR-012 section 2, lowest to highest: Jack, Queen, King,
## Ace.
##
## This is the one place a rank order exists. `TileRank` above stays an unordered
## identifier set, and ADR-012 section 2 is the explicit decision that authorises
## this ladder, so no other ordering helper may be added.
const SEQUENCE_ORDER: Array[int] = [
	TileRank.JACK,
	TileRank.QUEEN,
	TileRank.KING,
	TileRank.ACE,
]


## Returns true when `value` is one of the four defined face ranks.
static func is_valid_rank(value: int) -> bool:
	return TileRank.values().has(value)


## Returns the rank's position on the sequence ladder, or -1 when `rank` is not a
## defined face.
static func sequence_position(rank: int) -> int:
	return SEQUENCE_ORDER.find(rank)


## Returns true when `ranks` reads as a sequence hand in either direction.
##
## ADR-012 section 2 requires the tiles to sit in sequence order along the line,
## ascending or descending, stepping exactly one ladder position per tile. A line
## holding the right faces in the wrong order is not a sequence hand.
static func is_sequence_order(ranks: Array) -> bool:
	if ranks.size() < 2:
		return false
	var ascending: bool = true
	var descending: bool = true
	var previous: int = -1
	for rank: Variant in ranks:
		var position: int = sequence_position(int(rank))
		if position == -1:
			return false
		if previous >= 0:
			if position != previous + 1:
				ascending = false
			if position != previous - 1:
				descending = false
		previous = position
	return ascending or descending


## Returns true when `value` is one of the two defined face colours.
static func is_valid_face_color(value: int) -> bool:
	return FaceColor.values().has(value)


static func is_valid_suit(value: int) -> bool:
	return Suit.values().has(value)


static func color_for_suit(suit: int) -> int:
	if suit == Suit.HEARTS or suit == Suit.DIAMONDS:
		return FaceColor.RED
	if suit == Suit.CLUBS or suit == Suit.SPADES:
		return FaceColor.BLACK
	return FaceColor.NONE


## Returns true when `value` is one of the four defined edge colours.
static func is_valid_edge_color(value: int) -> bool:
	return EdgeColor.values().has(value)


## Returns true when `value` is a valid edge position index.
static func is_valid_edge_position(value: int) -> bool:
	return EdgePosition.values().has(value)


## Returns the face rank's constant name, for diagnostics only.
static func rank_name(value: int) -> String:
	if not is_valid_rank(value):
		return "UNKNOWN"
	return String(TileRank.find_key(value))


## Returns the face colour's constant name, for diagnostics only.
static func face_color_name(value: int) -> String:
	if not is_valid_face_color(value):
		return "UNKNOWN"
	return String(FaceColor.find_key(value))


## Returns the edge colour's constant name, for diagnostics only.
static func edge_color_name(value: int) -> String:
	if not is_valid_edge_color(value):
		return "UNKNOWN"
	return String(EdgeColor.find_key(value))
