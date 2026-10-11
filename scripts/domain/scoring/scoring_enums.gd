class_name ScoringEnums
extends RefCounted

## Shared scoring vocabulary and canonical identifier formats
## (ADR-007 sections 1, 5, and 7).
##
## This script holds constants and pure string/coordinate helpers only. It owns
## no score state, no board access, and no scene dependency, so preview, commit,
## AI evaluation, replay verification, and tests all derive event identifiers the
## same way instead of re-implementing the formats.
##
## Authority notes:
## - Score categories are exactly the three Phase 1 categories of ADR-007
##   section 1: poker hands, edge matches, and edge clusters.
## - The valid poker hands are the closed seven-item list of ADR-012 section 1,
##   which supersedes ADR-001 section 2. A hand has two to five contiguous
##   orthogonal cells and must classify as one of those seven; anything else is
##   refused as a move and awards nothing.
## - A five-cell hand is valid only as a Full House (ADR-012 section 2), so
##   `WINDOW_SIZE` is a maximum hand length rather than the only legal length.
## - A matching boundary awards exactly +1 (ADR-002 section 1), which is why
##   EDGE_MATCH_POINTS is a constant here rather than a tunable resource value.
## - Phase 1 accepts non-negative integer points and no multipliers
##   (ADR-007 section 11).
##
## Identifier formats are centralised here because ADR-007 section 5 requires
## deterministic, stable ids, and AGENTS.md section 15 forbids encoding one rule
## in several unrelated places.

## Score categories (ADR-007 section 1).
enum ScoreCategory {
	POKER_HAND = 0,
	EDGE_MATCH = 1,
	EDGE_CLUSTER = 2,
}

## The closed list of poker hand categories (ADR-012 section 1).
##
## `NONE` is not a poker hand: the hand matched no pattern in the list, awards no
## points, and is refused as a move by the placement validator, so a hand never
## "scores as NONE" in play.
##
## ADR-012 section 1 lists exactly seven categories. Five-of-a-Kind is not one of
## them: five identical ranks are no longer a hand and have no point value.
##
## The declared order is ascending point value, which is what
## `PokerScoreRules.validate()` checks. The numeric values are internal indexes
## into `PokerScoreRules.points_by_category`; save data records the category
## *name* (ADR-007 section 5), so renumbering never invalidates a save.
enum PokerHandCategory {
	NONE = 0,
	PAIR = 1,
	TWO_PAIR = 2,
	STRAIGHT_3 = 3,
	THREE_OF_A_KIND = 4,
	STRAIGHT_4 = 5,
	FULL_HOUSE = 6,
	FOUR_OF_A_KIND = 7,
}

## Window orientation (ADR-001 section 1). Only horizontals and verticals count.
enum HandOrientation {
	HORIZONTAL = 0,
	VERTICAL = 1,
}

## Number of occupied cells in a poker window (ADR-001 section 1).
const WINDOW_SIZE: int = 5

## Points awarded for one matching edge boundary (ADR-002 section 1).
##
## Fixed by the accepted decision rather than configurable, because ADR-002
## states the +1 explicitly and only the cluster milestone is tunable.
const EDGE_MATCH_POINTS: int = 1

## Number of players the ledger is expected to track. Not a rule, only a hint
## for pre-sizing diagnostic output.
const PLAYER_COUNT_PHASE_1: int = 2


## Returns true when `value` is one of the three Phase 1 score categories.
static func is_valid_score_category(value: int) -> bool:
	return ScoreCategory.values().has(value)


## Returns the category's constant name, for diagnostics only.
static func score_category_name(value: int) -> String:
	if not is_valid_score_category(value):
		return "UNKNOWN_CATEGORY"
	return String(ScoreCategory.find_key(value))


## Returns true when `value` is one of the poker categories including `NONE`.
static func is_valid_poker_hand(value: int) -> bool:
	return PokerHandCategory.values().has(value)


## Returns the poker category's constant name, for diagnostics only.
static func poker_hand_name(value: int) -> String:
	if not is_valid_poker_hand(value):
		return "UNKNOWN_HAND"
	return String(PokerHandCategory.find_key(value))


## Returns true when `value` is one of the two scored window orientations.
static func is_valid_orientation(value: int) -> bool:
	return HandOrientation.values().has(value)


## Returns the orientation's constant name, for diagnostics only.
static func orientation_name(value: int) -> String:
	if not is_valid_orientation(value):
		return "UNKNOWN_ORIENTATION"
	return String(HandOrientation.find_key(value))


## Returns the slug used inside event identifiers for a score category.
##
## ADR-007 section 5 uses `poker`, `edge`, and `cluster` in its documented event
## formats, so these slugs are part of the identifier contract.
static func category_slug(value: int) -> String:
	match value:
		ScoreCategory.POKER_HAND:
			return "poker"
		ScoreCategory.EDGE_MATCH:
			return "edge"
		ScoreCategory.EDGE_CLUSTER:
			return "cluster"
	return "unknown"


## Returns the canonical identifier of a five-cell poker window.
##
## ADR-001 section 1 requires a window to be identified by its orientation and
## its ordered cell coordinates. The origin is the first cell in reading order
## along the orientation: the lowest column for a horizontal window, the lowest
## row for a vertical one. That makes the identifier independent of the direction
## the evaluator happened to walk the window.
##
## Returns an empty name when the orientation or origin is invalid.
static func hand_id_for(orientation: int, origin: Vector2i) -> StringName:
	if not is_valid_orientation(orientation):
		return &""
	if not BoardEnums.is_in_bounds(origin):
		return &""
	if orientation == HandOrientation.HORIZONTAL:
		return StringName("hand:H:%d:%d" % [origin.y, origin.x])
	return StringName("hand:V:%d:%d" % [origin.x, origin.y])


## Returns the canonical identifier of an undirected tile-to-tile boundary.
##
## ADR-002 section 1 requires each boundary to be evaluated once and
## ADR-007 section 5 requires a canonical ordered coordinate pair. The pair is
## ordered by row-major storage index, so the two tiles always produce the same
## identifier regardless of which one the caller started from.
##
## Returns an empty name when the two cells are not orthogonally adjacent.
static func boundary_id_for(a: Vector2i, b: Vector2i) -> StringName:
	if not BoardEnums.is_in_bounds(a) or not BoardEnums.is_in_bounds(b):
		return &""
	var delta: Vector2i = b - a
	if BoardEnums.edge_position_toward(delta) == -1:
		return &""
	var first: Vector2i = a
	var second: Vector2i = b
	if BoardEnums.cell_index(b) < BoardEnums.cell_index(a):
		first = b
		second = a
	return StringName(
		"edge:%d,%d-%d,%d" % [first.x, first.y, second.x, second.y]
	)


## Returns a canonical key for a cluster component of one colour.
##
## ADR-002 section 7 calls this the "canonical component key for diagnostics" and
## explicitly warns it is not a permanent identity: a component that grows has a
## different key, which is why repeat scoring is prevented by entitlement deltas
## rather than by the key. It is still deterministic, which event ordering and
## tests require.
##
## `cells` is sorted into row-major order before the key is built, so callers may
## pass coordinates in any order.
static func component_key_for(color: int, cells: Array[Vector2i]) -> StringName:
	if not TileEnums.is_valid_edge_color(color):
		return &""
	var sorted_cells: Array[Vector2i] = sort_cells(cells)
	var parts: PackedStringArray = PackedStringArray()
	for cell: Vector2i in sorted_cells:
		parts.append("%d,%d" % [cell.x, cell.y])
	return StringName(
		"%s:%s" % [TileEnums.edge_color_name(color).to_lower(), "|".join(parts)]
	)


## Returns the deterministic identifier of one committed score event.
##
## ADR-007 section 5 documents the shapes
## `score:<move-id>:poker:<hand-id>`, `score:<move-id>:edge:<boundary-id>`, and
## `score:<move-id>:cluster:<color>:<ordinal>`. The canonical hand and boundary
## identifiers already carry their own prefix, so this helper only supplies the
## move, category slug, and discriminator without duplicating them.
static func event_id_for(
	move_id: StringName,
	category: int,
	discriminator: String
) -> StringName:
	if String(move_id).is_empty():
		return &""
	if not is_valid_score_category(category):
		return &""
	if discriminator.is_empty():
		return &""
	return StringName(
		"score:%s:%s:%s" % [String(move_id), category_slug(category), discriminator]
	)


## Returns a copy of `cells` sorted into row-major order, de-duplicated.
##
## Row-major ordering is the fixed canonical order used for component keys,
## component coordinate lists, and changed-cell reporting.
static func sort_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var sorted_cells: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if not sorted_cells.has(cell):
			sorted_cells.append(cell)
	sorted_cells.sort_custom(_compare_cells)
	return sorted_cells


## Returns a "x,y|x,y" rendering of cells, for diagnostics only.
static func cells_label(cells: Array[Vector2i]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for cell: Vector2i in sort_cells(cells):
		parts.append("%d,%d" % [cell.x, cell.y])
	return "|".join(parts)


## Orders two cells by row-major storage index.
static func _compare_cells(a: Vector2i, b: Vector2i) -> bool:
	return BoardEnums.cell_index(a) < BoardEnums.cell_index(b)
