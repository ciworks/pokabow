class_name LineAssembler
extends RefCounted

## Builds the shortest legal line through a chosen cell (ADR-011 sections 1 to 4).
##
## ADR-011 section 12 changes the AI's move generation from "one tile per
## candidate" to "one line per candidate", and that retarget is a later pass: the
## existing generator still proposes one coordinate and rotation for one of the
## rival's deck tiles. Until it is retargeted, something has to turn that proposal
## into a legal move, because section 1 makes a lone tile illegal.
##
## This type is that narrow bridge and nothing more. It does not choose where to
## play: the proposed cell and rotation are the anchor and are kept exactly as
## given. It only looks for the second tile that makes the anchor's line legal,
## searching in a fixed order so the result is deterministic (ADR-004 section 3),
## validates every candidate through `LineValidator`, and returns the first line
## that is actually legal. A proposal that cannot be completed into a legal line
## returns an empty array, and the caller then has to handle the turn some other
## way rather than commit an illegal move (ADR-011 section 12, ADR-005 section 2).
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
## them and is not considered as its own partner. Returns the staged snapshots in
## line order, or an empty array when no two-tile line through the anchor is
## legal.
static func shortest_line_from(
	board: BoardState,
	deck: Array[TileDefinition],
	anchor: TileDefinition,
	cell: Vector2i,
	rotation: int
) -> Array[TileSnapshot]:
	var line: Array[TileSnapshot] = []
	if board == null or anchor == null or not anchor.is_valid():
		return line
	if not board.is_empty_cell(cell):
		return line
	var anchor_snapshot: TileSnapshot = TileSnapshot.create(anchor, cell, rotation)
	if not anchor_snapshot.is_valid():
		return line

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
				var staged: Array[TileSnapshot] = [
					anchor_snapshot,
					TileSnapshot.create(partner, partner_cell, 0),
				]
				var result: LineResult = LineValidator.validate(board, staged)
				if result != null and result.accepted:
					return result.staged_tiles
	return line


## Returns the cell one step from `cell` along an orientation and direction.
static func _neighbor(cell: Vector2i, orientation: int, direction: int) -> Vector2i:
	if orientation == ScoringEnums.HandOrientation.HORIZONTAL:
		return cell + Vector2i(direction, 0)
	return cell + Vector2i(0, direction)
