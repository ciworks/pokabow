class_name TileSourceDto
extends RefCounted

## Versioned save record for a tile source (ADR-004 save and replay section).
##
## Stores the complete generated bag order plus the next draw index. ADR-004
## permits either the complete bag or enough versioned information to rebuild it
## exactly; storing the bag keeps restore independent of any future generator
## change and lets restore assert that no tile is duplicated or lost.
##
## `rules_version` records the generation rules that produced the bag so a
## mismatch can be detected on load (ADR-004 section 8, ADR-003 section 9).

const SCHEMA_VERSION: int = 1

var schema_version: int = SCHEMA_VERSION
var rules_version: String = ""
var match_id: StringName = &""
var seed: int = 0
var next_draw_index: int = 0
var tiles: Array[TileDto] = []


## Returns true when the record is self-consistent and safe to restore.
##
## Rejects a bad schema version, a missing match or rules identity, an
## impossible draw index, any invalid tile, and any duplicated tile ID.
func is_valid() -> bool:
	if schema_version != SCHEMA_VERSION:
		return false
	if String(match_id).is_empty():
		return false
	if rules_version.is_empty():
		return false
	if tiles.is_empty():
		return false
	if next_draw_index < 0 or next_draw_index > tiles.size():
		return false
	var seen_ids: Dictionary = {}
	for tile in tiles:
		if tile == null or not tile.is_valid():
			return false
		if seen_ids.has(tile.tile_id):
			return false
		seen_ids[tile.tile_id] = true
	return true


## Serializes to a JSON-safe dictionary.
func to_dictionary() -> Dictionary:
	var tile_records: Array = []
	for tile in tiles:
		tile_records.append(tile.to_dictionary())
	return {
		"schema_version": schema_version,
		"rules_version": rules_version,
		"match_id": String(match_id),
		"seed": seed,
		"next_draw_index": next_draw_index,
		"tiles": tile_records,
	}


## Builds a DTO from a dictionary produced by `to_dictionary()`.
static func from_dictionary(source: Dictionary) -> TileSourceDto:
	var dto: TileSourceDto = TileSourceDto.new()
	dto.schema_version = int(source.get("schema_version", 0))
	dto.rules_version = String(source.get("rules_version", ""))
	dto.match_id = StringName(String(source.get("match_id", "")))
	dto.seed = int(source.get("seed", 0))
	dto.next_draw_index = int(source.get("next_draw_index", 0))
	dto.tiles = []
	var raw_tiles: Variant = source.get("tiles", [])
	if raw_tiles is Array:
		for record in raw_tiles:
			if record is Dictionary:
				dto.tiles.append(TileDto.from_dictionary(record))
	return dto
