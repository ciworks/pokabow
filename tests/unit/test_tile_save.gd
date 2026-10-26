extends TestCase

## Milestone 1 save and resume tests (docs/PHASE-1-IMPLEMENTATION-PLAN.md).
##
## The first test is the Milestone 1 exit criterion: a headless test that
## generates, draws, serializes, restores, and verifies all 52 tiles.
##
## ADR-004 requires the bag order and draw position to survive a save cycle and
## every tile ID to appear exactly once. Board-committed tiles, active-tile
## ownership, and move history belong to later milestones and are not saved here.

const MATCH_ID: StringName = &"match-save"
const SEED: int = 31415926
const PARTIAL_DRAW_COUNT: int = 40


func test_exit_criterion_generate_draw_serialize_restore_and_verify_all_52_tiles() -> void:
	var source: TileSource = _source()
	var drawn_signatures: PackedStringArray = PackedStringArray()
	var drawn_ids: Dictionary = {}

	for index: int in range(52):
		var tile: TileDefinition = source.draw()
		if not check_not_null(tile, "draw %d must return a tile before the bag empties" % index):
			return
		drawn_signatures.append(_tile_signature(tile))
		drawn_ids[tile.tile_id] = true

	var dto: TileSourceDto = source.to_dto()
	check(dto.is_valid(), "the serialized bag must be self-consistent")

	var restored: TileSource = TileSource.from_dto(dto)
	if not check_not_null(restored, "the saved bag must restore"):
		return

	check_eq(restored.get_bag_size(), 52, "restore must preserve all 52 tiles")
	check_eq(restored.get_match_id(), MATCH_ID, "restore must preserve the match ID")
	check_eq(restored.get_seed(), SEED, "restore must preserve the match seed")
	check_eq(restored.get_draw_index(), 52, "restore must preserve the draw position")
	check_eq(
		restored.get_rules_version(),
		source.get_rules_version(),
		"restore must preserve the generation rules version"
	)
	check(restored.is_exhausted(), "a fully drawn bag must restore as exhausted")

	var restored_signatures: PackedStringArray = PackedStringArray()
	var restored_ids: Dictionary = {}
	for tile in restored.debug_bag_snapshot():
		restored_signatures.append(_tile_signature(tile))
		restored_ids[tile.tile_id] = true

	check_eq(restored_ids.size(), 52, "no tile may be duplicated or lost by a save cycle")
	check_eq(restored_ids.size(), drawn_ids.size(), "the restored identity set must match the generated set")
	check_eq(
		restored_signatures, drawn_signatures, "every drawn tile must survive serialization exactly"
	)


func test_resume_after_a_partial_draw_continues_the_same_sequence() -> void:
	var source: TileSource = _source()
	for _index: int in range(PARTIAL_DRAW_COUNT):
		source.draw()

	var restored: TileSource = TileSource.from_dto(source.to_dto())
	if not check_not_null(restored, "a partially drawn bag must restore"):
		return

	check_eq(
		restored.remaining_count(),
		52 - PARTIAL_DRAW_COUNT,
		"restore must resume with the remaining tiles"
	)

	var mismatches: int = 0
	for index: int in range(52 - PARTIAL_DRAW_COUNT):
		var expected: TileDefinition = source.draw()
		var actual: TileDefinition = restored.draw()
		if actual == null:
			check(false, "the restored source must still supply tile %d" % index)
			return
		if actual.tile_id != expected.tile_id:
			mismatches += 1

	check_eq(mismatches, 0, "draws after resume must match the original sequence exactly")
	check(restored.is_exhausted(), "the restored source must empty at the same point as the original")


func test_dictionary_round_trip_preserves_the_bag_and_draw_position() -> void:
	var source: TileSource = _source()
	for _index: int in range(17):
		source.draw()

	var reloaded: TileSourceDto = TileSourceDto.from_dictionary(source.to_dto().to_dictionary())
	if not check(reloaded.is_valid(), "a dictionary round trip must stay valid"):
		return

	var restored: TileSource = TileSource.from_dto(reloaded)
	if not check_not_null(restored, "a dictionary round trip must restore"):
		return

	check_eq(restored.get_draw_index(), 17, "a dictionary round trip must preserve the draw position")
	check_eq(restored.get_seed(), SEED, "a dictionary round trip must preserve the seed")
	check_eq(
		_restored_signature(restored),
		_restored_signature(source),
		"a dictionary round trip must preserve bag order and every tile value"
	)


func test_restored_bag_matches_regeneration_from_the_seed() -> void:
	var source: TileSource = _source()
	var restored: TileSource = TileSource.from_dto(source.to_dto())
	if not check_not_null(restored, "the bag must restore before it can be compared"):
		return

	check_eq(
		_restored_signature(restored),
		_restored_signature(_source()),
		"ADR-004 section 3 requires the stored bag to equal regeneration from the same seed"
	)


func test_restore_rejects_an_unknown_schema_version() -> void:
	var dto: TileSourceDto = _source().to_dto()
	dto.schema_version = TileSourceDto.SCHEMA_VERSION + 1

	check(not dto.is_valid(), "an unknown schema version must be invalid")
	check(TileSource.from_dto(dto) == null, "an unknown schema version must not restore")


func test_restore_rejects_removed_tile_rank_and_old_tile_schema() -> void:
	var dto: TileSourceDto = _source().to_dto()
	dto.tiles[0].rank = 4
	check(not dto.is_valid(), "the removed fifth rank cannot be restored")
	check(TileSource.from_dto(dto) == null, "a bag with a removed rank cannot restore")
	dto = _source().to_dto()
	dto.tiles[0].schema_version = TileDto.SCHEMA_VERSION - 1
	check(not dto.is_valid(), "tile records from the earlier rules are rejected")
	check(TileSource.from_dto(dto) == null, "an old tile record cannot restore")


func test_restore_rejects_duplicate_tile_identity() -> void:
	var dto: TileSourceDto = _source().to_dto()
	dto.tiles[1].tile_id = dto.tiles[0].tile_id

	check(not dto.is_valid(), "a duplicated tile ID must be invalid")
	check(TileSource.from_dto(dto) == null, "a bag with a duplicated tile must not restore")


func test_restore_rejects_an_impossible_draw_position() -> void:
	var dto: TileSourceDto = _source().to_dto()

	dto.next_draw_index = dto.tiles.size() + 1
	check(not dto.is_valid(), "a draw position past the bag end must be invalid")

	dto.next_draw_index = -1
	check(not dto.is_valid(), "a negative draw position must be invalid")

	check(TileSource.from_dto(dto) == null, "an impossible draw position must not restore")


func test_restore_rejects_a_corrupted_tile_record() -> void:
	var dto: TileSourceDto = _source().to_dto()
	dto.tiles[0].edges = []

	check(not dto.is_valid(), "a tile without exactly four edges must be invalid")
	check(TileSource.from_dto(dto) == null, "a corrupted tile record must not restore")


func test_restore_rejects_a_missing_rules_identity() -> void:
	var dto: TileSourceDto = _source().to_dto()
	dto.rules_version = ""

	check(not dto.is_valid(), "a missing generation rules version must be invalid")
	check(TileSource.from_dto(dto) == null, "a bag without a rules identity must not restore")


# --- Helpers ---


func _source() -> TileSource:
	var source: TileSource = TileSource.new()
	source.initialize(MATCH_ID, SEED, TileGenerationRules.create_default())
	return source


func _restored_signature(source: TileSource) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for tile in source.debug_bag_snapshot():
		parts.append(_tile_signature(tile))
	return "~".join(parts)


func _tile_signature(tile: TileDefinition) -> String:
	var edges: PackedStringArray = PackedStringArray()
	for edge in tile.get_base_edges():
		edges.append(str(int(edge)))
	return "%s|%d|%d|%s" % [tile.tile_id, tile.rank, tile.face_color, ",".join(edges)]
