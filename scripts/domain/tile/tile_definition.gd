class_name TileDefinition
extends Resource

## Immutable tile definition (GAME_SPEC section 3, ADR-004 section 4).
##
## Canonical edge order is [top, right, bottom, left], stored unrotated.
## Rotation is separate state held by `TileSnapshot`, so a TileDefinition instance is
## never mutated after generation.
##
## Immutability is enforced by construction and convention: this type exposes no
## mutators, every accessor returns a copy, and `TileSource` is the only
## producer. Godot Resource fields are technically assignable, so the guarantee
## is architectural rather than enforced by the language.
##
## ADR-008 section 3 places versioned rule configuration and serializable
## immutable definitions in `Resource`, which is why this type extends Resource
## rather than RefCounted.

## Deterministic unique identity, `<match-id>:tile:<index>` (ADR-004 section 5).
## Rules code compares tiles by this ID, never by rank or edge values.
@export var tile_id: StringName = &""

## Face rank identifier (see the ordering note in `TileEnums`).
@export var rank: TileEnums.TileRank = TileEnums.TileRank.ACE

## Red/black face property. Not consumed by Phase 1 scoring (ADR-001 section 3).
@export var face_color: TileEnums.FaceColor = TileEnums.FaceColor.RED

@export var suit: TileEnums.Suit = TileEnums.Suit.HEARTS

## Canonical unrotated edges in [top, right, bottom, left] order.
@export var base_edges: Array[TileEnums.EdgeColor] = []


## Builds a tile definition. The caller's edge array is copied, so later changes
## to it cannot reach back into the created tile.
static func create(
	tile_id: StringName,
	rank: int,
	face_color: int,
	base_edges: Array[TileEnums.EdgeColor],
	suit: int = -1
) -> TileDefinition:
	var tile: TileDefinition = TileDefinition.new()
	tile.tile_id = tile_id
	tile.rank = rank
	tile.face_color = face_color
	if suit < 0:
		tile.suit = TileEnums.Suit.HEARTS if face_color == TileEnums.FaceColor.RED else TileEnums.Suit.CLUBS
	else:
		tile.suit = suit
	tile.base_edges = base_edges.duplicate()
	return tile


## Returns a copy of the canonical edges in [top, right, bottom, left] order.
func get_base_edges() -> Array[TileEnums.EdgeColor]:
	return base_edges.duplicate()


## Returns the edge colours visible in the given orientation (ADR-004 section 4).
##
## The mapping is the clockwise quarter-turn convention required by ADR-006
## section 5 and proposed by docs/sections/01-tile-system.md section 6.2:
##
##     rotated[i] = base[(i - turns + 4) % 4]
##
## Calling this with no argument returns the canonical orientation, which
## satisfies the `get_rotated_edges()` form in GAME_SPEC section 3.2: a TileDefinition
## holds no rotation of its own.
##
## The returned array is always new; `base_edges` is never modified.
func get_rotated_edges(rotation: int = 0) -> Array[TileEnums.EdgeColor]:
	var rotated: Array[TileEnums.EdgeColor] = []
	if base_edges.size() != TileEnums.EDGE_COUNT:
		push_error(
			"TileDefinition.get_rotated_edges: tile '%s' must hold exactly %d canonical edges, got %d."
			% [String(tile_id), TileEnums.EDGE_COUNT, base_edges.size()]
		)
		return rotated

	var turns: int = TileEnums.normalize_rotation(rotation)
	for index: int in range(TileEnums.EDGE_COUNT):
		var source_index: int = (index - turns + TileEnums.EDGE_COUNT) % TileEnums.EDGE_COUNT
		rotated.append(base_edges[source_index])
	return rotated


## Returns the visible colour on one edge position in the given orientation.
##
## Returns -1 when the position or the tile itself is invalid; callers must
## treat that as a programming error, not as a game outcome.
func get_edge_at(position: int, rotation: int = 0) -> int:
	if not TileEnums.is_valid_edge_position(position):
		push_error(
			"TileDefinition.get_edge_at: '%d' is not a valid edge position." % position
		)
		return -1
	var rotated: Array[TileEnums.EdgeColor] = get_rotated_edges(rotation)
	if rotated.size() != TileEnums.EDGE_COUNT:
		return -1
	return int(rotated[position])


## Returns true when every field holds a value permitted by the specification.
func is_valid() -> bool:
	if String(tile_id).is_empty():
		return false
	if not TileEnums.is_valid_rank(int(rank)):
		return false
	if not TileEnums.is_valid_face_color(int(face_color)):
		return false
	if not TileEnums.is_valid_suit(int(suit)):
		return false
	if TileEnums.color_for_suit(suit) != face_color:
		return false
	if base_edges.size() != TileEnums.EDGE_COUNT:
		return false
	for edge in base_edges:
		if not TileEnums.is_valid_edge_color(int(edge)):
			return false
	return true


## Returns a save DTO describing this tile (ADR-008 section 11).
func to_dto() -> TileDto:
	var dto: TileDto = TileDto.new()
	dto.tile_id = tile_id
	dto.rank = int(rank)
	dto.face_color = int(face_color)
	dto.suit = int(suit)
	dto.edges = []
	for edge in base_edges:
		dto.edges.append(int(edge))
	return dto


## Rebuilds a tile definition from a save DTO. Returns null when `dto` is null.
static func from_dto(dto: TileDto) -> TileDefinition:
	if dto == null:
		return null
	var edges: Array[TileEnums.EdgeColor] = []
	for edge in dto.edges:
		edges.append(int(edge))
	return TileDefinition.create(dto.tile_id, dto.rank, dto.face_color, edges, dto.suit)
