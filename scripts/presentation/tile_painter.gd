class_name TilePainter
extends RefCounted

## Draws one tile face into a canvas (ADR-008 section 4, GAME_SPEC section 7.3).
##
## The whole Phase 1 tile is four coloured edges and a rank glyph, so a tile is
## drawn rather than assembled from a sprite: this keeps the board a single
## redraw per state change, and it keeps the visual honest about the data. Every
## value drawn here comes from an immutable `TileSnapshot`, so presentation
## never invents a face or an edge.
##
## Colours are presentation-only. GAME_SPEC section 7.3 leaves the visual style
## unspecified, so these are deliberately plain, high-contrast choices that stay
## distinguishable on a small mobile screen, and they are the single place a
## later art pass needs to change.
##
## Everything here is a static painter: no node owns state, and the caller
## decides when to redraw.

## Card face and border.
const CARD_FACE: Color = Color(0.96, 0.96, 0.94, 1.0)
const CARD_BORDER: Color = Color(0.20, 0.21, 0.25, 1.0)

## Empty board cell.
const EMPTY_CELL: Color = Color(0.16, 0.18, 0.22, 1.0)

## Edge colours, indexed by `TileEnums.EdgeColor`.
const EDGE_COLORS: Array[Color] = [
	Color(0.22, 0.48, 0.92, 1.0),
	Color(0.88, 0.26, 0.30, 1.0),
	Color(0.22, 0.70, 0.38, 1.0),
	Color(0.95, 0.79, 0.22, 1.0),
]

## Face colours, indexed by `TileEnums.FaceColor`.
const FACE_COLORS: Array[Color] = [
	Color(0.80, 0.18, 0.22, 1.0),
	Color(0.13, 0.14, 0.18, 1.0),
]

## Fraction of a cell taken by one edge band.
const EDGE_RATIO: float = 0.20

## Fraction of a cell used as the rank glyph's font size.
const GLYPH_RATIO: float = 0.46


## Returns the presentation colour of an edge colour value.
static func edge_color_for(edge: int) -> Color:
	if edge < 0 or edge >= EDGE_COLORS.size():
		return Color(0.5, 0.5, 0.5, 1.0)
	return EDGE_COLORS[edge]


## Returns the presentation colour of a face colour value.
static func face_color_for(face: int) -> Color:
	if face < 0 or face >= FACE_COLORS.size():
		return FACE_COLORS[TileEnums.FaceColor.BLACK]
	return FACE_COLORS[face]


## Returns the glyph drawn on a tile face (GAME_SPEC section 3.1).
static func rank_glyph(rank: int) -> String:
	match rank:
		TileEnums.TileRank.ACE:
			return "A"
		TileEnums.TileRank.KING:
			return "K"
		TileEnums.TileRank.QUEEN:
			return "Q"
		TileEnums.TileRank.JACK:
			return "J"
	return "?"


## Returns true when `rect` is large enough to hold a legible tile.
static func is_drawable(rect: Rect2) -> bool:
	return rect.size.x > 1.0 and rect.size.y > 1.0


## Draws an empty board cell.
static func paint_cell(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	if not is_drawable(rect):
		return
	canvas.draw_rect(rect, color, true)


## Draws one committed or previewed tile from its immutable snapshot.
##
## `alpha` lets the preview layer draw the same tile as a ghost without a second
## code path, so a preview can never look different from what will be committed.
static func paint_tile(
	canvas: CanvasItem, rect: Rect2, snapshot: TileSnapshot, alpha: float = 1.0
) -> void:
	if snapshot == null or not is_drawable(rect):
		return
	var edges: Array = snapshot.get_rotated_edges()
	paint_face(canvas, rect, edges, int(snapshot.get_tile().rank), alpha)


## Draws a tile face from already-resolved visible edges.
##
## `edges` is the rotated edge list in `TileEnums.EdgePosition` order
## (top, right, bottom, left). It is read defensively because it may come from
## an invalid tile.
static func paint_face(
	canvas: CanvasItem, rect: Rect2, edges: Array, rank: int, alpha: float = 1.0
) -> void:
	if not is_drawable(rect):
		return

	var face: Color = CARD_FACE
	face.a *= alpha
	canvas.draw_rect(rect, face, true)

	var band: float = maxf(minf(rect.size.x, rect.size.y) * EDGE_RATIO, 1.0)
	for position: int in range(TileEnums.EDGE_COUNT):
		var color: Color = Color(0.5, 0.5, 0.5, 1.0)
		if position < edges.size():
			color = edge_color_for(int(edges[position]))
		color.a *= alpha
		canvas.draw_rect(_edge_band(rect, position, band), color, true)

	var border: Color = CARD_BORDER
	border.a *= alpha
	canvas.draw_rect(rect, border, false, maxf(1.0, band * 0.25))

	_paint_glyph(canvas, rect, rank, alpha)


## Returns the pixel rectangle of one edge band on a tile of `rect`.
##
## Edge position order is the canonical [top, right, bottom, left]
## (`TileEnums.EdgePosition`), the same order the scoring rules compare in.
static func _edge_band(rect: Rect2, position: int, band: float) -> Rect2:
	match position:
		TileEnums.EdgePosition.TOP:
			return Rect2(rect.position, Vector2(rect.size.x, band))
		TileEnums.EdgePosition.RIGHT:
			return Rect2(
				rect.position + Vector2(rect.size.x - band, 0.0), Vector2(band, rect.size.y)
			)
		TileEnums.EdgePosition.BOTTOM:
			return Rect2(
				rect.position + Vector2(0.0, rect.size.y - band), Vector2(rect.size.x, band)
			)
		TileEnums.EdgePosition.LEFT:
			return Rect2(rect.position, Vector2(band, rect.size.y))
	return Rect2(rect.position, Vector2.ZERO)


## Draws the rank glyph centred on the tile face.
##
## Uses the engine fallback font so the board needs no font asset to be
## readable; a later art pass can supply a theme instead.
static func _paint_glyph(canvas: CanvasItem, rect: Rect2, rank: int, alpha: float) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var font_size: int = int(minf(rect.size.x, rect.size.y) * GLYPH_RATIO)
	if font_size < 6:
		return

	var text: String = rank_glyph(rank)
	var text_size: Vector2 = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	)
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	var origin: Vector2 = Vector2(
		rect.position.x + (rect.size.x - text_size.x) * 0.5,
		rect.position.y + rect.size.y * 0.5 + (ascent - descent) * 0.5
	)

	var color: Color = FACE_COLORS[TileEnums.FaceColor.BLACK]
	color.a *= alpha
	canvas.draw_string(
		font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color
	)
