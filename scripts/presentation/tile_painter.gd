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
##
## Matching edge colour is the scoring mechanic itself, so this palette is the one
## place the game's most load-bearing signal is decided. The previous palette
## paired a red and a green sitting on the exact axis red-green colour blindness
## collapses, which left the mechanic unreadable for a red-green player. These are
## Okabe-Ito values instead: the four separate by hue AND by lightness, so a player
## who cannot use hue still has a luminance difference to read, and they stay
## distinguishable across the common vision types.
##
## Colour deliberately remains the only channel here (a pattern pass was considered
## and declined), so this is a straight palette swap rather than a redundant
## encoding - it helps the red-green pair and leaves other vision types as they
## were.
const EDGE_COLORS: Array[Color] = [
	Color(0.0, 0.447, 0.698, 1.0),
	Color(0.835, 0.369, 0.0, 1.0),
	Color(0.0, 0.62, 0.451, 1.0),
	Color(0.941, 0.894, 0.259, 1.0),
	Color(0.98, 0.70, 0.12, 1.0),
]

## Face colours, indexed by `TileEnums.FaceColor`.
const FACE_COLORS: Array[Color] = [
	Color(0.80, 0.18, 0.22, 1.0),
	Color(0.13, 0.14, 0.18, 1.0),
	Color(0.48, 0.30, 0.65, 1.0),
]

## Fraction of a cell taken by one edge band.
const EDGE_RATIO: float = 0.20

## Fraction of a cell used as the rank glyph's font size.
const GLYPH_RATIO: float = 0.46

## The project's tile-back image, drawn on a tile whose face is not known yet.
##
## GAME_SPEC section 7.3 leaves the visual style to presentation, so the path lives
## here as the single place a later art pass changes it. It is resolved on first
## use rather than preloaded, so a project that supplies no image still runs: the
## drawn card is the fallback.
const TILE_BACK_TEXTURE: String = "res://assets/textures/tile_background_default.png"

## Border thickness of a face-down tile, as a fraction of its shorter side. Kept
## in step with the face's own border so a turning tile does not change shape.
const BACK_BORDER_RATIO: float = 0.05

## Fraction of a stack tile's size that each successive layer is offset by.
const STACK_OFFSET_RATIO: float = 0.09

## Tile art: a tile is composed as a stack of images, bottom layer first.
##
## Order is the authorised tile composition: `tile_base.png` as the base, then the
## face, then one overlay per edge, then `tile_shine.png`. Every layer is drawn
## into the whole tile rectangle, so a layer image may be authored at any size and
## is scaled to the tile it is drawn on.
##
## Each layer falls back to the drawn primitive when its image is absent, so a
## partly supplied art set still renders a readable board and improves layer by
## layer as images are added. A project with no art at all renders exactly as it
## did before this existed.
const TILE_BASE_TEXTURE: String = "res://assets/tiles/tile_base.png"
const TILE_SHINE_TEXTURE: String = "res://assets/tiles/tile_shine.png"
const TILE_EDGE_DIR: String = "res://assets/tiles/edges/"
const TILE_FACE_DIR: String = "res://assets/tiles/suits/"

## Edge overlay file name: `tile_<colour>_<side>.png`.
const EDGE_FILE_FORMAT: String = "%stile_%s_%s.png"

## Face file name: `tile_<value>_<suit>.png`.
const FACE_FILE_FORMAT: String = "%stile_%s_%s.png"
## The wildcard has its own face image and no suit suffix.
const WILDCARD_FACE_TEXTURE: String = "%stile_wildcard.png"

## The four edge sides, indexed by `TileEnums.EdgePosition`.
const EDGE_SIDES: Array[String] = ["top", "right", "bottom", "left"]

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
		TileEnums.TileRank.JOKER:
			return "W"
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
	var tile: TileDefinition = snapshot.get_tile()
	if tile == null:
		return
	var edges: Array = snapshot.get_rotated_edges()

	# The base layer decides the mode. Without it there is no card for the other
	# layers to compose onto, so the drawn renderer paints the whole tile exactly
	# as it did before the art existed.
	var base: Texture2D = _art_for(TILE_BASE_TEXTURE)
	if base == null:
		paint_face(canvas, rect, edges, int(tile.rank), alpha)
		return

	canvas.draw_texture_rect(base, rect, false, Color(1.0, 1.0, 1.0, alpha))
	_paint_face_layer(canvas, rect, tile, alpha)
	for position: int in range(TileEnums.EDGE_COUNT):
		var color: int = int(edges[position]) if position < edges.size() else -1
		_paint_edge_layer(canvas, rect, position, color, alpha)
	_paint_shine_layer(canvas, rect, alpha)


## Cached tile art, keyed by path.
##
## A deal redraws every frame, so resolving a resource per tile per frame would
## stall the animation. A null entry records "resolved, and this image is absent"
## so a missing file is looked for once rather than on every draw.
static var _art: Dictionary = {}


## Returns the texture at `path`, or null when the project supplies none.
static func _art_for(path: String) -> Texture2D:
	if _art.has(path):
		return _art[path] as Texture2D
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_art[path] = texture
	return texture


## Returns the tile's stored suit for its face image.
static func suit_name(tile: TileDefinition) -> String:
	if tile == null:
		return ""
	match tile.suit:
		TileEnums.Suit.HEARTS:
			return "hearts"
		TileEnums.Suit.DIAMONDS:
			return "diamonds"
		TileEnums.Suit.CLUBS:
			return "clubs"
		TileEnums.Suit.SPADES:
			return "spades"
	return "none"


## Returns the face image path for `tile`: `tile_<value>_<suit>.png`.
static func _face_path(tile: TileDefinition) -> String:
	if int(tile.rank) == TileEnums.TileRank.JOKER:
		return WILDCARD_FACE_TEXTURE % TILE_FACE_DIR
	return FACE_FILE_FORMAT % [
		TILE_FACE_DIR, TileEnums.rank_name(int(tile.rank)).to_lower(), suit_name(tile)
	]


## Draws the face layer, or the rank glyph when that face image is absent.
##
## The glyph alone is the fallback rather than the drawn card: the base layer has
## already supplied the card, and an opaque fill here would paint over it.
static func _paint_face_layer(
	canvas: CanvasItem, rect: Rect2, tile: TileDefinition, alpha: float
) -> void:
	var art: Texture2D = _art_for(_face_path(tile))
	if art != null:
		canvas.draw_texture_rect(art, rect, false, Color(1.0, 1.0, 1.0, alpha))
		return
	_paint_glyph(canvas, rect, int(tile.rank), alpha)


## Draws one edge overlay for the colour visible on `position`, or the drawn
## colour band when that edge image is absent.
##
## The position is the visible side, so the image chosen is the one for the side
## the player can see rather than the tile's stored orientation.
static func _paint_edge_layer(
	canvas: CanvasItem, rect: Rect2, position: int, color: int, alpha: float
) -> void:
	if color < 0 or not TileEnums.is_valid_edge_position(position):
		return
	var path: String = EDGE_FILE_FORMAT % [
		TILE_EDGE_DIR, TileEnums.edge_color_name(color).to_lower(), EDGE_SIDES[position]
	]
	var art: Texture2D = _art_for(path)
	if art != null:
		# The palette stays authoritative over the overlay as well. Drawn as
		# authored, an edge overlay carries its own colour, so a palette change
		# would reach only the three sides drawn as bands and leave the overlay's
		# old colour on the top edge - the most visible side of every tile.
		# Tinting by the palette colour instead means one palette governs both
		# paths. A neutral overlay takes the colour exactly; a coloured one
		# multiplies within its own hue family, which is why the palette values
		# have to survive a multiply and why the top edge may read a shade
		# darker than the other three sides.
		var tint: Color = edge_color_for(color)
		tint.a = alpha
		canvas.draw_texture_rect(art, rect, false, tint)
		return
	var band: float = maxf(minf(rect.size.x, rect.size.y) * EDGE_RATIO, 1.0)
	var drawn: Color = edge_color_for(color)
	drawn.a *= alpha
	canvas.draw_rect(_edge_band(rect, position, band), drawn, true)


## Draws the shine above every other layer. It is optional: a project without it
## gets the flat tile.
static func _paint_shine_layer(canvas: CanvasItem, rect: Rect2, alpha: float) -> void:
	var art: Texture2D = _art_for(TILE_SHINE_TEXTURE)
	if art == null:
		return
	canvas.draw_texture_rect(art, rect, false, Color(1.0, 1.0, 1.0, alpha))


## Cached tile-back image, resolved once.
##
## A deal redraws every frame, so loading the resource per tile would stall the
## animation; the two flags distinguish "not looked yet" from "looked, and there
## is no image".
static var _tile_back: Texture2D = null
static var _tile_back_resolved: bool = false


## Returns the project's tile-back image, or null when it supplies none.
static func tile_back_texture() -> Texture2D:
	if not _tile_back_resolved:
		_tile_back_resolved = true
		if ResourceLoader.exists(TILE_BACK_TEXTURE):
			_tile_back = load(TILE_BACK_TEXTURE) as Texture2D
	return _tile_back


## Draws the back of a tile: the project's tile-back image when there is one, and
## the drawn card otherwise.
##
## A face-down tile shows no rank and no edge colour, because the bag holds tiles
## nobody has drawn and a face here would publish information the game does not
## give the player.
##
## The image's largest centred region that already has the tile's shape is cropped
## into `rect`, so an image that is not the same shape as a tile is neither
## distorted nor allowed to spill past the tile. The border matches the face's, so
## a tile mid-turn neither gains nor loses its outline. Pass a narrowed rect to
## draw the tile part-way through turning over.
static func paint_tile_back(canvas: CanvasItem, rect: Rect2, alpha: float = 1.0) -> void:
	if not is_drawable(rect):
		return
	var back: Texture2D = tile_back_texture()
	if back == null:
		var plain: Color = CARD_FACE
		plain.a *= alpha
		canvas.draw_rect(rect, plain, true)
	else:
		var source: Vector2 = back.get_size()
		if source.x > 0.0 and source.y > 0.0:
			# Crop the largest centred region of the image that already has the
			# tile's shape, and draw that region INTO the tile rectangle. Drawing
			# the whole image scaled to cover instead would let an image that is
			# not tile-shaped spill past the tile and overlap whatever is beside
			# or behind the stack.
			var target_aspect: float = rect.size.x / rect.size.y
			var region: Vector2 = source
			if source.x / source.y > target_aspect:
				region.x = source.y * target_aspect
			else:
				region.y = source.x / target_aspect
			canvas.draw_texture_rect_region(
				back,
				rect,
				Rect2((source - region) * 0.5, region),
				Color(1.0, 1.0, 1.0, alpha)
			)
	var border: Color = CARD_BORDER
	border.a *= alpha
	canvas.draw_rect(
		rect,
		border,
		false,
		maxf(1.0, minf(rect.size.x, rect.size.y) * BACK_BORDER_RATIO)
	)


## Draws a face-down stack of `layers` tiles filling `area`.
##
## Every layer is the tile back, so the pile the deal flies out of is the same
## object as the tile that leaves it. The bag holds tiles nobody has drawn, so a
## rank glyph or an edge colour here would publish information the game does not
## give the player.
##
## The stack grows up and to the right from the bottom-left of `area`, and the
## tiles shrink to leave room for that offset, so the whole stack always fits the
## rectangle it is given.
static func paint_stack(canvas: CanvasItem, area: Rect2, layers: int) -> void:
	if not is_drawable(area):
		return
	var count: int = maxi(layers, 1)
	var step: float = minf(area.size.x, area.size.y) * STACK_OFFSET_RATIO
	var tile_size: Vector2 = area.size - Vector2(step, step) * float(count - 1)
	if tile_size.x <= 1.0 or tile_size.y <= 1.0:
		return
	# Drawn from the back forward, so each nearer tile lands on top of the one
	# behind it and the pile reads as a single stack.
	var base: Vector2 = area.position + Vector2(0.0, step * float(count - 1))
	for index: int in range(count - 1, -1, -1):
		paint_tile_back(canvas, Rect2(base + Vector2(step, -step) * float(index), tile_size))


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
