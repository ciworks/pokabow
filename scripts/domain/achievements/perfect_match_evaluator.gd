class_name PerfectMatchEvaluator
extends RefCounted

## Achievement predicate only. It never changes hand legality or scoring.
## A qualifying committed five-cell hand contains all four suits and matches
## every one of its four internal boundaries in the hand's line.
static func qualifies(board: BoardState, cells: Array[Vector2i]) -> bool:
	if board == null or cells.size() != 5:
		return false
	var ordered: Array[Vector2i] = cells.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	var horizontal: bool = ordered[0].y == ordered[4].y
	var vertical: bool = ordered[0].x == ordered[4].x
	if not horizontal and not vertical:
		return false
	var step: Vector2i = Vector2i.RIGHT if horizontal else Vector2i.DOWN
	var outgoing: int = TileEnums.EdgePosition.RIGHT if horizontal else TileEnums.EdgePosition.BOTTOM
	var incoming: int = TileEnums.EdgePosition.LEFT if horizontal else TileEnums.EdgePosition.TOP
	var suits: Dictionary = {}
	var previous: TileSnapshot = null
	for index: int in range(5):
		if index > 0 and ordered[index] != ordered[index - 1] + step:
			return false
		var snapshot: TileSnapshot = board.get_tile(ordered[index])
		if snapshot == null or snapshot.get_tile() == null:
			return false
		var suit: int = int(snapshot.get_tile().suit)
		if suit == TileEnums.Suit.NONE:
			return false
		suits[suit] = true
		if previous != null and previous.get_edge_at(outgoing) != snapshot.get_edge_at(incoming):
			return false
		previous = snapshot
	return suits.size() == 4
