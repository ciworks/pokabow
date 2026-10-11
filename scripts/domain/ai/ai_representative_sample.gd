class_name AiRepresentativeSample
extends Resource

## The versioned representative tile sample of ADR-005 section 6.
##
## ADR-005 section 6 makes the second ply a guaranteed average rather than a
## guess: the hidden future tile is represented by a small deterministic sample,
## built once, and never read from the undrawn bag (ADR-004 section 7). The
## current sample holds 20 tiles with equal weights.
##
## The sample is generated, not hand-written. It is five ranks x four
## rotations, with each tile using the four allowed edge colors:
##
##     ranks            all five ranks appear (4 tiles each)
##     face colours     red, black, and Joker's none appear
##     edge colours     each of the four colours occurs exactly 20 times
##                      across the 80 edge slots
##
## Face colour and suit affect card multipliers. This compact sample assigns a
## turn through the four ordinary suits for each rank and no suit for Joker; it is a deterministic
## approximation of hidden tiles, not a copy of the undrawn bag.
##
## Tile identifiers are synthetic and prefixed `ai-sample:`. Real bag identities
## are `<match-id>:tile:<index>` (ADR-004 section 5), so a sample tile can never
## collide with, or be mistaken for, a real tile.
##
## ADR-008 section 3 places versioned rule configuration in `Resource`, which is
## why this type extends `Resource` rather than `RefCounted`.

## Sample/schema version, persisted with saves so a rebalance can be detected.
const SCHEMA_VERSION: int = 2

## Number of representative tiles in the Phase 1 sample (ADR-005 section 6).
const SAMPLE_SIZE: int = 20

## Rotations generated per rank, so every rank appears in every orientation.
const ROTATIONS_PER_RANK: int = 4

## Prefix that keeps sample identities clear of real bag identities.
const ID_PREFIX: String = "ai-sample:"

## Ranks represented, one row of four rotations each (ADR-005 section 6).
const SAMPLE_RANKS: Array = [
	TileEnums.TileRank.ACE,
	TileEnums.TileRank.KING,
	TileEnums.TileRank.QUEEN,
	TileEnums.TileRank.JACK,
	TileEnums.TileRank.JOKER,
]

## Sample/schema version recorded alongside saved matches.
@export var schema_version: int = SCHEMA_VERSION

## The generated sample tiles, built on first use.
var _tiles: Array[TileDefinition] = []


## Returns a sample carrying the approved Phase 1 tiles.
static func create_default() -> AiRepresentativeSample:
	return AiRepresentativeSample.new()


## Returns the sample tiles, in canonical generation order.
##
## The array is rebuilt only when it has not been built yet; the returned array
## is a copy, so a caller cannot disturb the sample (ADR-005 section 6 requires
## the sample to stay fixed for the whole match).
func tiles() -> Array[TileDefinition]:
	_ensure_tiles()
	return _tiles.duplicate()


## Returns one positive weight per sample tile (ADR-005 section 6).
##
## Phase 1 weights are equal, so every representative tile contributes the same
## share of the expected response.
func weights() -> Array[float]:
	_ensure_tiles()
	var result: Array[float] = []
	for _index: int in range(_tiles.size()):
		result.append(1.0)
	return result


## Returns how many representative tiles this sample holds.
func sample_size() -> int:
	_ensure_tiles()
	return _tiles.size()


## Returns true when `tile_id` names a tile of this sample.
##
## Real bag identities contain `:tile:` (ADR-004 section 5); sample identities
## carry the sample prefix instead, which is what keeps the two sets disjoint.
static func is_sample_tile_id(tile_id: StringName) -> bool:
	return String(tile_id).begins_with(ID_PREFIX)


## Returns a stable identifier for this sample version, persisted with saves.
func version_key() -> String:
	return "ai-sample:%d" % schema_version


## Returns every validation problem found, so callers can report all of them.
func validate() -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		problems.append(
			"unsupported schema_version %d (expected %d)" % [schema_version, SCHEMA_VERSION]
		)
	_ensure_tiles()

	if _tiles.size() != SAMPLE_SIZE:
		problems.append(
			"the sample must hold %d tiles, got %d" % [SAMPLE_SIZE, _tiles.size()]
		)

	var seen_ids: Dictionary = {}
	var ranks: Dictionary = {}
	var face_colors: Dictionary = {}
	var edge_counts: Dictionary = {}
	for color: int in TileEnums.EdgeColor.values():
		edge_counts[color] = 0

	for tile: TileDefinition in _tiles:
		if tile == null or not tile.is_valid():
			problems.append("the sample must hold only valid tiles")
			continue
		var tile_id: String = String(tile.tile_id)
		if seen_ids.has(tile_id):
			problems.append("duplicate sample tile identifier '%s'" % tile_id)
		seen_ids[tile_id] = true
		if not is_sample_tile_id(tile.tile_id):
			problems.append("sample tile '%s' must carry the '%s' prefix" % [tile_id, ID_PREFIX])
		ranks[int(tile.rank)] = true
		face_colors[int(tile.face_color)] = true
		for edge: TileEnums.EdgeColor in tile.get_base_edges():
			edge_counts[int(edge)] = int(edge_counts.get(int(edge), 0)) + 1

	for rank: int in SAMPLE_RANKS:
		if not ranks.has(int(rank)):
			problems.append("the sample must represent rank %s" % TileEnums.rank_name(rank))
	for face_color: int in TileEnums.FaceColor.values():
		if not face_colors.has(face_color):
			problems.append(
				"the sample must represent face colour %s"
				% TileEnums.face_color_name(face_color)
			)

	var expected_per_color: int = SAMPLE_SIZE * TileEnums.EDGE_COUNT / TileEnums.EdgeColor.size()
	for color: int in TileEnums.EdgeColor.values():
		var count: int = int(edge_counts.get(color, 0))
		if count != expected_per_color:
			problems.append(
				"edge colour %s must occur %d times in the sample, got %d"
				% [TileEnums.edge_color_name(color), expected_per_color, count]
			)

	var sample_weights: Array[float] = weights()
	if sample_weights.size() != _tiles.size():
		problems.append(
			"the sample must carry one weight per tile (%d), got %d"
			% [_tiles.size(), sample_weights.size()]
		)
	else:
		var smallest: float = INF
		var largest: float = -INF
		for weight: float in sample_weights:
			if weight <= 0.0:
				problems.append("sample weights must be positive, got %f" % weight)
				break
			smallest = minf(smallest, weight)
			largest = maxf(largest, weight)
		if smallest > 0.0 and not is_equal_approx(smallest, largest):
			problems.append("Phase 1 sample weights must be equal (ADR-005 section 6)")

	return problems


## Returns true when no validation problem was found.
func is_valid() -> bool:
	return validate().is_empty()


## Builds the sample tiles once, in the documented generation order.
func _ensure_tiles() -> void:
	if not _tiles.is_empty():
		return
	_tiles = _build_tiles()


## Returns 5 ranks x 4 rotations of four-edge patterns using the four edge colors.
##
## Rotated variants are produced with `TileDefinition.get_rotated_edges()`, so
## the sample can never disagree with the rotation rule the board uses.
func _build_tiles() -> Array[TileDefinition]:
	var colors: Array[TileEnums.EdgeColor] = [
		TileEnums.EdgeColor.BLUE,
		TileEnums.EdgeColor.RED,
		TileEnums.EdgeColor.GREEN,
		TileEnums.EdgeColor.YELLOW,
	]
	var tiles: Array[TileDefinition] = []
	var index: int = 0
	for rank_index: int in range(SAMPLE_RANKS.size()):
		var rank: int = SAMPLE_RANKS[rank_index]
		var is_joker: bool = rank == TileEnums.TileRank.JOKER
		var base_suit: int = TileEnums.Suit.NONE if is_joker else TileEnums.Suit.HEARTS
		var base_color: int = TileEnums.color_for_suit(base_suit)
		var pattern: Array[TileEnums.EdgeColor] = []
		for edge_index: int in range(TileEnums.EDGE_COUNT):
			pattern.append(colors[(rank_index + edge_index) % colors.size()])
		var base: TileDefinition = TileDefinition.create(
			_id_for_index(index), rank, base_color, pattern, base_suit
		)
		for rotation: int in range(ROTATIONS_PER_RANK):
			var edges: Array[TileEnums.EdgeColor] = base.get_rotated_edges(rotation)
			var suit: int = TileEnums.Suit.NONE if is_joker else rotation
			var face_color: int = TileEnums.color_for_suit(suit)
			tiles.append(
				TileDefinition.create(_id_for_index(index), rank, face_color, edges, suit)
			)
			index += 1
	return tiles


## Returns the synthetic identity of a sample tile.
##
## The `ai-sample:` prefix plus a zero-padded index cannot be produced by
## `TileSource`, whose identities are `<match-id>:tile:<index>`.
func _id_for_index(index: int) -> StringName:
	return StringName("%s%02d" % [ID_PREFIX, index])
