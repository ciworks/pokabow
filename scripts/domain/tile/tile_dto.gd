class_name TileDto
extends RefCounted

## Versioned, JSON-ready save record for one tile (ADR-008 section 11).
##
## This type deliberately holds primitives only and references no tile type, so
## the tile domain depends on it in one direction and no class cycle exists.
##
## Enum values are stored as plain ints because Godot enums are ints; the
## specification's value ranges are re-checked by `is_valid()`.
##
## The record is versioned because ADR-004 section 3 requires the serialization
## format to be versioned.

const SCHEMA_VERSION: int = 3

var schema_version: int = SCHEMA_VERSION
var tile_id: StringName = &""
var rank: int = 0
var face_color: int = 0
var suit: int = 0
var edges: Array[int] = []


## Returns true when every field is within the specification's value ranges.
func is_valid() -> bool:
	if schema_version != SCHEMA_VERSION:
		return false
	if String(tile_id).is_empty():
		return false
	if not TileEnums.is_valid_rank(rank):
		return false
	if not TileEnums.is_valid_face_color(face_color):
		return false
	if not TileEnums.is_valid_suit(suit):
		return false
	if rank == TileEnums.TileRank.JOKER:
		if suit != TileEnums.Suit.NONE or face_color != TileEnums.FaceColor.NONE:
			return false
	elif suit == TileEnums.Suit.NONE or TileEnums.color_for_suit(suit) != face_color:
		return false
	if edges.size() != TileEnums.EDGE_COUNT:
		return false
	for edge in edges:
		if not TileEnums.is_valid_edge_color(edge):
			return false
	return true


## Serializes to a JSON-safe dictionary.
func to_dictionary() -> Dictionary:
	return {
		"schema_version": schema_version,
		"tile_id": String(tile_id),
		"rank": rank,
		"face_color": face_color,
		"suit": suit,
		"edges": edges.duplicate(),
	}


## Builds a DTO from a dictionary produced by `to_dictionary()`.
##
## Missing or malformed entries are left at failing values so `is_valid()`
## rejects the record instead of silently repairing it.
static func from_dictionary(source: Dictionary) -> TileDto:
	var dto: TileDto = TileDto.new()
	dto.schema_version = int(source.get("schema_version", 0))
	dto.tile_id = StringName(String(source.get("tile_id", "")))
	dto.rank = int(source.get("rank", -1))
	dto.face_color = int(source.get("face_color", -1))
	dto.suit = int(source.get("suit", -1))
	dto.edges = []
	var raw_edges: Variant = source.get("edges", [])
	if raw_edges is Array:
		for edge in raw_edges:
			dto.edges.append(int(edge))
	return dto
