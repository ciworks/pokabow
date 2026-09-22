class_name TileSnapshot
extends RefCounted

## A tile together with a committed board coordinate and rotation
## (ADR-004 section 4, ADR-006 section 5).
##
## A snapshot adds placement state to an immutable `TileDefinition` and never modifies
## the tile's canonical edges. Position and rotation become immutable once a
## move is committed (ADR-006 section 5), so this type has no mutators.
##
## Milestone 1 scope: this type exists so that rotation can be represented and
## tested independently of the board. Board ownership, occupancy, legality, and
## the legal-placement frontier are Milestone 2 (ADR-006) and must not be added
## here.

var _tile: TileDefinition = null
var _cell: Vector2i = Vector2i.ZERO
var _rotation: int = 0


## Builds a placed snapshot. `rotation` is normalized to 0-3 quarter-turns.
static func create(tile: TileDefinition, cell: Vector2i, rotation: int = 0) -> TileSnapshot:
	var snapshot: TileSnapshot = TileSnapshot.new()
	snapshot._tile = tile
	snapshot._cell = cell
	snapshot._rotation = TileEnums.normalize_rotation(rotation)
	return snapshot


## Returns the underlying immutable tile definition.
func get_tile() -> TileDefinition:
	return _tile


## Returns the tile's deterministic ID, or an empty name when unset.
func get_tile_id() -> StringName:
	if _tile == null:
		return &""
	return _tile.tile_id


## Returns the committed board coordinate (ADR-006 section 1).
func get_cell() -> Vector2i:
	return _cell


## Returns the committed rotation as a 0-3 quarter-turn index.
func get_rotation() -> int:
	return _rotation


## Returns the edges visible in the committed orientation (GAME_SPEC 3.2).
func get_rotated_edges() -> Array[TileEnums.EdgeColor]:
	if _tile == null:
		return []
	return _tile.get_rotated_edges(_rotation)


## Returns the visible colour on one edge position in the committed orientation.
func get_edge_at(position: int) -> int:
	if _tile == null:
		return -1
	return _tile.get_edge_at(position, _rotation)


## Returns true when the snapshot wraps a valid tile.
func is_valid() -> bool:
	return _tile != null and _tile.is_valid()
