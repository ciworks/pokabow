class_name TileSource
extends RefCounted

## Deterministic, seeded tile bag (ADR-004 sections 1, 2, 3, 6, and 7).
##
## One shared bag of `rules.bag_size` tiles is generated once during
## MATCH_SETUP. The whole bag is produced up front so no later system behaviour
## can alter draw order through accidental RNG use (ADR-004 section 3).
##
## This source owns its own `RandomNumberGenerator`, seeded by the match seed.
## No UI animation, preview, AI search, or score calculation may draw from it,
## and the AI decision interface must never see undrawn tiles (ADR-004
## section 7).
##
## Generation consumes randomness in this fixed order per tile: rank, face
## colour, suit for non-Jokers, then top, right, bottom, left edges.
##
## The pot carries at most `rules.max_jokers` Joker-ranked tiles (ADR-014). Once
## that allowance is spent, the Joker rank weight is treated as zero for the
## remaining tiles, so the per-tile consumption above is unchanged and a capped
## bag stays deterministic for its seed.
## Rotation starts at zero and is carried by `TileSnapshot`, not by `TileDefinition`.
##
## Milestone 1 scope: supply and determinism only. Draw-and-assign atomicity,
## turn ownership, and active-tile slots belong to ADR-003 and are implemented
## in Milestone 4.

## Deterministic tile identity format: `<match-id>:tile:<index>` (ADR-004
## section 5), zero padded so IDs sort in draw order.
const TILE_ID_FORMAT: String = "%s:tile:%03d"

var _rules: TileGenerationRules = null
var _rules_version: String = ""
var _match_id: StringName = &""
var _seed: int = 0
var _bag: Array[TileDefinition] = []
var _next_draw_index: int = 0
var _initialized: bool = false


## Generates the complete bag.
##
## Returns false when the inputs are unusable, leaving the source uninitialized
## and unchanged. ADR-004 shows this as `-> void`; returning a bool lets callers
## handle bad configuration directly, which ADR-004 already expects this class
## to report through a separate recoverable-error channel.
func initialize(match_id: StringName, seed: int, rules: TileGenerationRules) -> bool:
	_rules = null
	_rules_version = ""
	_bag = []
	_next_draw_index = 0
	_initialized = false

	if rules == null:
		return false
	if not rules.is_valid():
		return false
	if String(match_id).is_empty():
		return false

	_match_id = match_id
	_seed = seed

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed

	var generated: Array[TileDefinition] = []
	generated.resize(rules.bag_size)
	var jokers_generated: int = 0
	for index: int in range(rules.bag_size):
		var tile: TileDefinition = _generate_tile(rng, rules, index, jokers_generated)
		if tile.rank == TileEnums.TileRank.JOKER:
			jokers_generated += 1
		generated[index] = tile

	_rules = rules
	_rules_version = rules.version_key()
	_bag = generated
	_initialized = true
	return true


## Returns the next tile in bag order, or null when nothing can be drawn.
##
## Never produces a replacement tile once the configured bag is depleted
## (ADR-004 tile-source interface note).
func draw() -> TileDefinition:
	if not _initialized:
		return null
	if is_exhausted():
		return null
	var tile: TileDefinition = _bag[_next_draw_index]
	_next_draw_index += 1
	return tile


## Returns one tile to the pot, so it can be drawn again later (ADR-011
## section 6).
##
## ADR-011 section 6 has a swapping player return deck tiles to the shared pot and
## draw the same number of replacements. The pot is this bag, so returning a tile
## makes it available again.
##
## The tile is appended to the end of the bag rather than inserted at the draw
## position, which is the one detail ADR-011 leaves unstated. Drawing the returned
## tiles straight back would make a swap a no-op, and section 4 makes the swap the
## escape hatch for a hand that cannot open, so the returned tiles must not be the
## immediate replacements. Appending keeps this deterministic without consuming
## any randomness, which ADR-004 section 3 requires of everything that can alter
## draw order.
##
## Returns false when the source is not initialized or the tile has no identity.
func return_to_pot(tile: TileDefinition) -> bool:
	if not _initialized:
		return false
	if tile == null or not tile.is_valid():
		return false
	_bag.append(tile)
	return true


## Returns how many tiles are still available to draw.
func remaining_count() -> int:
	if not _initialized:
		return 0
	return _bag.size() - _next_draw_index


## Returns true when no tile remains available.
func is_exhausted() -> bool:
	return remaining_count() <= 0


## Returns true once `initialize()` or `from_dto()` has succeeded.
func is_initialized() -> bool:
	return _initialized


## Returns the match ID that owns this bag.
func get_match_id() -> StringName:
	return _match_id


## Returns the match seed. Deterministic replay depends on this value.
func get_seed() -> int:
	return _seed


## Returns how many tiles have been drawn so far (the next bag index).
func get_draw_index() -> int:
	return _next_draw_index


## Returns the generation rules version recorded at initialization.
func get_rules_version() -> String:
	return _rules_version


## Returns the number of tiles in the generated bag, or 0 when uninitialized.
func get_bag_size() -> int:
	if not _initialized:
		return 0
	return _bag.size()


## Returns the complete bag in generated order.
##
## Deliberately named `debug_` so gameplay code cannot mistake it for a legal
## information source: ADR-004 section 7 hides undrawn tiles and draw order from
## both the player-facing UI and the AI decision interface. Intended for tests,
## replay verification, and save serialization.
func debug_bag_snapshot() -> Array[TileDefinition]:
	return _bag.duplicate()


## Serializes the bag order, draw position, and generation identity.
func to_dto() -> TileSourceDto:
	var dto: TileSourceDto = TileSourceDto.new()
	dto.schema_version = TileSourceDto.SCHEMA_VERSION
	dto.rules_version = _rules_version
	dto.match_id = _match_id
	dto.seed = _seed
	dto.next_draw_index = _next_draw_index
	dto.tiles = []
	for tile in _bag:
		dto.tiles.append(tile.to_dto())
	return dto


## Restores a source from a saved record.
##
## Returns null when the record is not restorable, so callers never receive a
## partially built source. The restored source keeps its draw position, so
## subsequent draws continue at the same point in the bag.
static func from_dto(dto: TileSourceDto) -> TileSource:
	if dto == null or not dto.is_valid():
		return null

	var restored: Array[TileDefinition] = []
	for record in dto.tiles:
		var tile: TileDefinition = TileDefinition.from_dto(record)
		if tile == null:
			return null
		restored.append(tile)

	var source: TileSource = TileSource.new()
	source._rules = null
	source._rules_version = dto.rules_version
	source._match_id = dto.match_id
	source._seed = dto.seed
	source._bag = restored
	source._next_draw_index = dto.next_draw_index
	source._initialized = true
	return source


## Builds one tile, consuming randomness in the fixed ADR-004 section 2 order.
func _generate_tile(
	rng: RandomNumberGenerator,
	rules: TileGenerationRules,
	index: int,
	jokers_generated: int
) -> TileDefinition:
	var rank: int = _pick_weighted_index(rng, _effective_rank_weights(rules, jokers_generated))
	var face_color: int = _pick_weighted_index(rng, rules.face_color_weights)
	var suit: int = TileEnums.Suit.NONE
	if rank == TileEnums.TileRank.JOKER:
		face_color = TileEnums.FaceColor.NONE
	else:
		var candidates: Array[float] = []
		var first_suit: int = TileEnums.Suit.HEARTS if face_color == TileEnums.FaceColor.RED else TileEnums.Suit.CLUBS
		candidates.append(rules.suit_weights[first_suit])
		candidates.append(rules.suit_weights[first_suit + 1])
		suit = first_suit + _pick_weighted_index(rng, candidates)
	var edges: Array[TileEnums.EdgeColor] = []
	for _edge_index: int in range(TileEnums.EDGE_COUNT):
		edges.append(_pick_weighted_index(rng, rules.edge_color_weights))
	return TileDefinition.create(_tile_id_for_index(index), rank, face_color, edges, suit)


## Returns the rank weights to draw from, with the Joker allowance applied.
##
## ADR-014 caps how many Joker-ranked tiles one pot may hold. The cap is applied
## here, before the rank draw, so the generator still consumes exactly one random
## value per tile in the fixed ADR-004 section 2 order: a bag that has spent its
## allowance draws from the ordinary ranks weighted exactly as configured, and
## the same seed always produces the same capped bag.
##
## The returned array is only built when the cap is actually in force, so an
## uncapped pot draws from `rules.rank_weights` itself and is unchanged.
func _effective_rank_weights(rules: TileGenerationRules, jokers_generated: int) -> Array[float]:
	if rules.max_jokers < 0 or jokers_generated < rules.max_jokers:
		return rules.rank_weights

	var weights: Array[float] = rules.rank_weights.duplicate()
	var joker_index: int = TileEnums.TileRank.JOKER
	if joker_index >= 0 and joker_index < weights.size():
		weights[joker_index] = 0.0
	return weights


## Returns one weighted index, consuming exactly one random value.
##
## A zero or negative total cannot occur on validated rules; the guard keeps the
## generator total in the impossible case rather than looping or erroring.
func _pick_weighted_index(rng: RandomNumberGenerator, weights: Array[float]) -> int:
	var total: float = 0.0
	for weight in weights:
		total += weight
	if total <= 0.0:
		return 0

	var roll: float = rng.randf() * total
	var cumulative: float = 0.0
	for index: int in range(weights.size()):
		cumulative += weights[index]
		if roll < cumulative:
			return index
	return weights.size() - 1


## Returns the deterministic tile ID for a bag position.
func _tile_id_for_index(index: int) -> StringName:
	return StringName(TILE_ID_FORMAT % [String(_match_id), index])
