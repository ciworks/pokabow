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
##   not defined, and ADR-001 section 2 classifies poker windows by rank
##   *frequency* only. No comparison or ordering helper is provided here; do not
##   add one without an explicit specification decision.
## - The edge index order is fixed by ADR-004 section 4 ([top, right, bottom,
##   left]) and restated by docs/sections/01-tile-system.md section 5.1.

## Face rank identifiers. Ordering is not meaningful (see the note above).
enum TileRank {
	ACE = 0,
	KING = 1,
	QUEEN = 2,
	JACK = 3,
}

## Red/black face property (GAME_SPEC section 3.1). ADR-001 section 3 confirms
## this property carries no poker-hand role in Phase 1.
enum FaceColor {
	RED = 0,
	BLACK = 1,
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


## Returns true when `value` is one of the four defined face ranks.
static func is_valid_rank(value: int) -> bool:
	return TileRank.values().has(value)


## Returns true when `value` is one of the two defined face colours.
static func is_valid_face_color(value: int) -> bool:
	return FaceColor.values().has(value)


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
