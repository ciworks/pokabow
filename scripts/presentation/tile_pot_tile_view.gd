class_name TilePotTileView
extends Control

## A read-only rendering of one undrawn tile. Its synthetic ID is never a bag ID.
var _tile: TileDefinition = null


func set_face(face: Dictionary, index: int) -> bool:
	var raw_edges: Variant = face.get("edges", [])
	if not raw_edges is Array or raw_edges.size() != TileEnums.EDGE_COUNT:
		return false
	var edges: Array[TileEnums.EdgeColor] = []
	for value: Variant in raw_edges:
		edges.append(int(value))
	_tile = TileDefinition.create(
		StringName("pot-view:%d" % index),
		int(face.get("rank", -1)),
		int(face.get("face_color", -1)),
		edges,
		int(face.get("suit", -1))
	)
	if not _tile.is_valid():
		_tile = null
		return false
	var face_name: String = TileEnums.rank_name(int(_tile.rank))
	face_name += " of " + TilePainter.suit_name(_tile)
	var edge_names: Array[String] = []
	for edge: TileEnums.EdgeColor in _tile.get_base_edges():
		edge_names.append(TileEnums.edge_color_name(int(edge)))
	accessibility_name = "%s; top %s, right %s, bottom %s, left %s" % [face_name, edge_names[0], edge_names[1], edge_names[2], edge_names[3]]
	tooltip_text = accessibility_name
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return true


func _draw() -> void:
	if _tile != null:
		var side: float = minf(size.x, size.y)
		TilePainter.paint_tile(self, Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side), TileSnapshot.create(_tile, BoardMetrics.NO_CELL))
