class_name HandMultiplierScorer
extends RefCounted

## Calculates the approved card and newly created hand-edge multipliers.
## `new_cells` are the cells staged by this move; a boundary counts only when
## one of its endpoints is staged and both endpoints are in this hand.

static func card_value(rank: int) -> int:
	match rank:
		TileEnums.TileRank.JACK:
			return 1
		TileEnums.TileRank.QUEEN:
			return 2
		TileEnums.TileRank.KING:
			return 3
		TileEnums.TileRank.ACE:
			return 4
	return 0


static func card_points(board: BoardState, cells: Array[Vector2i]) -> int:
	var total: int = 0
	for cell: Vector2i in cells:
		var snapshot: TileSnapshot = board.get_tile(cell)
		if snapshot == null:
			return 0
		total += card_value(int(snapshot.get_tile().rank))
	return total


static func card_multiplier(board: BoardState, cells: Array[Vector2i]) -> int:
	if cells.is_empty():
		return 1
	var first: TileDefinition = board.get_tile(cells[0]).get_tile()
	var same_color: bool = true
	var same_suit: bool = true
	var same_rank: bool = true
	for cell: Vector2i in cells:
		var tile: TileDefinition = board.get_tile(cell).get_tile()
		same_color = same_color and tile.face_color == first.face_color
		same_suit = same_suit and tile.suit == first.suit
		same_rank = same_rank and tile.rank == first.rank
	if same_suit and same_rank:
		return 4
	if same_suit:
		return 3
	if same_color:
		return 2
	return 1


static func boundary_bonus(board: BoardState, a: Vector2i, b: Vector2i) -> int:
	var direction: int = BoardEnums.edge_position_toward(b - a)
	if direction < 0:
		return 0
	var first: TileSnapshot = board.get_tile(a)
	var second: TileSnapshot = board.get_tile(b)
	if first == null or second == null:
		return 0
	var color_a: int = first.get_edge_at(direction)
	var color_b: int = second.get_edge_at(BoardEnums.opposite_edge_position(direction))
	return 1 if color_a == color_b else 0


static func new_boundary_ids(
	board: BoardState, cells: Array[Vector2i], new_cells: Array[Vector2i]
) -> Array[StringName]:
	var ids: Array[StringName] = []
	for index: int in range(cells.size() - 1):
		var a: Vector2i = cells[index]
		var b: Vector2i = cells[index + 1]
		if not new_cells.has(a) and not new_cells.has(b):
			continue
		if boundary_bonus(board, a, b) > 0:
			ids.append(ScoringEnums.boundary_id_for(a, b))
	return ids


static func edge_multiplier_from_ids(board: BoardState, cells: Array[Vector2i], ids: Array[StringName]) -> int:
	var multiplier: int = 1
	for index: int in range(cells.size() - 1):
		var a: Vector2i = cells[index]
		var b: Vector2i = cells[index + 1]
		if ids.has(ScoringEnums.boundary_id_for(a, b)):
			multiplier += boundary_bonus(board, a, b)
	return multiplier
