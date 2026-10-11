class_name LineAssembler
extends RefCounted

## Builds the shortest legal line through a chosen cell (ADR-011 sections 1 to 4).
##
## ADR-011 section 12 makes the AI's own move generation line-shaped: the AI
## enumerates whole lines and proposes them as complete candidates, which is
## `LegalMoveGenerator` and the strategies. This type is the narrower helper that
## remains useful beside it: given an anchor placement - one cell and one
## rotation the caller has already chosen - it looks for the shortest line
## through that anchor, searching in a fixed order so the result is deterministic
## (ADR-004 section 3), and validates every candidate through `LineValidator`.
##
## It therefore does two jobs, both of them "do not duplicate the rules":
##
## - the application layer uses it for a proposal that arrives as a single
##   placement rather than a line, so an anchor the coordinator accepted can still
##   become the shortest legal line through it (ADR-011 sections 1 and 3);
## - tests and fixtures use it to check that a line the validator accepts is
##   exactly the line a caller would assemble.
##
## The anchor cell and the anchor's own rotation are kept exactly as given, and
## only the partner tile's rotation is chosen, among the planar quarter turns that
## suit the line's axis (ADR-006 section 5). Searching both planar rotations is
## what lets the helper find a legal line for a real tile whose canonical edges
## are laid down in the opposite orientation to the anchor's.
##
## A proposal that cannot be completed into a legal line returns an empty array,
## and the caller then has to handle the turn some other way rather than commit an
## illegal move (ADR-011 section 12, ADR-005 section 2).
##
## It reads a board and a deck and never mutates either.

## Orientation search order: a row first, then a column, so a tie is stable.
const ORIENTATION_ORDER: Array[int] = [
	ScoringEnums.HandOrientation.HORIZONTAL,
	ScoringEnums.HandOrientation.VERTICAL,
]

## Directions searched along each orientation, in a fixed order.
const DIRECTION_ORDER: Array[int] = [1, -1]


## Returns the shortest legal line whose first tile is `anchor` at `cell`.
##
## `deck` is the tiles the player holds, in deal order; the anchor must be one of
## them and is not considered as its own partner. Returns the line as
## `LineValidator` accepted it - in line order, with its merged cells and ranks -
## or null when no two-tile line through the anchor is legal.
static func shortest_result_from(
	board: BoardState,
	deck: Array[TileDefinition],
	anchor: TileDefinition,
	cell: Vector2i,
	rotation: int
) -> LineResult:
	if board == null or anchor == null or not anchor.is_valid():
		return null
	if not board.is_empty_cell(cell):
		return null
	var anchor_snapshot: TileSnapshot = TileSnapshot.create(anchor, cell, rotation)
	if not anchor_snapshot.is_valid():
		return null

	for orientation: int in ORIENTATION_ORDER:
		for direction: int in DIRECTION_ORDER:
			var partner_cell: Vector2i = _neighbor(cell, orientation, direction)
			if not board.is_empty_cell(partner_cell):
				continue
			for partner: TileDefinition in deck:
				if partner == null or not partner.is_valid():
					continue
				if partner.tile_id == anchor.tile_id:
					continue
				for partner_rotation: int in _planar_rotations(orientation):
					var staged: Array[TileSnapshot] = [
						anchor_snapshot,
						TileSnapshot.create(partner, partner_cell, partner_rotation),
					]
					var result: LineResult = LineValidator.validate(board, staged)
					if result != null and result.accepted:
						return result
	return null


## Returns the shortest legal line's staged tiles through the anchor, or empty.
##
## Compatibility form for callers that only need the tiles; the structured answer
## is `shortest_result_from`.
static func shortest_line_from(
	board: BoardState,
	deck: Array[TileDefinition],
	anchor: TileDefinition,
	cell: Vector2i,
	rotation: int
) -> Array[TileSnapshot]:
	var result: LineResult = shortest_result_from(board, deck, anchor, cell, rotation)
	if result == null:
		return [] as Array[TileSnapshot]
	return result.staged_tiles


## Returns the two quarter turns a tile takes when laid along a line's axis.
##
## 0 and 2 are the two ways a tile can face along a row, and 1 and 3 the two ways
## it can face along a column (ADR-006 section 5), so searching both finds the
## orientation in which the partner's facing edge matches the anchor's.
static func _planar_rotations(orientation: int) -> Array[int]:
	if orientation == ScoringEnums.HandOrientation.VERTICAL:
		return [1, 3]
	return [0, 2]


## Returns the cell one step from `cell` along an orientation and direction.
static func _neighbor(cell: Vector2i, orientation: int, direction: int) -> Vector2i:
	if orientation == ScoringEnums.HandOrientation.HORIZONTAL:
		return cell + Vector2i(direction, 0)
	return cell + Vector2i(0, direction)
