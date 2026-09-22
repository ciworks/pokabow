# ADR-004: Tile Distribution and Generation

- **Status:** Accepted
- **Date:** 2026-09-21
- **Accepted:** 2026-09-21
- **Owners:** Game design and engineering
- **Decision scope:** Phase 1 Human vs AI mode
- **Source:** `GAME_SPEC.md` and `iterative_specification.pdf`
- **Related:** ADR-001 (poker scoring), ADR-003 (turn flow), ADR-006 (placement), ADR-007 (incremental scoring)

## Context

The source specification requires random tile generation. Every tile has an Ace, King, Queen, or Jack face; a red/black property; four independently colored edges chosen from blue, red, green, and yellow; and an initial rotation of zero degrees.

The source does not define whether generation uses a finite bag, whether values are uniformly distributed, whether duplicates are allowed, when random values are consumed, what information players can see, or how a saved match reproduces the same sequence. These decisions affect fairness, game length, poker-hand frequency, AI behavior, testing, replay, and save compatibility.

## Constraints inherited from the specification

1. Tile ranks are Ace, King, Queen, and Jack.
2. Every face has a red/black property.
3. Edge positions are top, right, bottom, and left.
4. Edge colors are blue, red, green, and yellow.
5. Tiles are generated randomly.
6. Newly generated tiles start at zero-degree rotation.
7. Rotation changes orientation but not the canonical tile values.
8. The Phase 1 board contains 144 cells.

## Decision

### 1. Finite shared tile bag

Create one shared bag of exactly **144 tiles** during `MATCH_SETUP`, one tile for every board cell.

- Both players draw from the same bag.
- Tiles are drawn in the bag's generated order.
- A draw removes exactly one tile from the bag.
- Tiles are not returned, exchanged, discarded, or regenerated in Phase 1.
- Because ADR-006 allows every tile to be placed while space remains, a normal match can fill the board and consume the entire bag.
- The bag is gameplay state, not a visual object.

This produces a finite, predictable upper bound of 144 committed turns and aligns normal tile exhaustion with a full board.

### 2. Tile value generation

Each bag entry is generated independently with replacement. Duplicate tile configurations are allowed.

For each tile:

1. Select one rank uniformly from Ace, King, Queen, and Jack.
2. Select the red/black property uniformly.
3. Select each of the four canonical edge colors independently and uniformly from blue, red, green, and yellow.
4. Set rotation to `0` quarter-turns.
5. Assign a unique immutable tile ID.

The resulting base configuration space contains:

```text
4 ranks x 2 face colors x 4^4 edge combinations = 2,048 configurations
```

Generation with replacement means no exact quota is guaranteed in a particular match. Across many seeded simulations, the distributions should converge toward the configured probabilities.

### 3. Random number generation

- Use a dedicated `RandomNumberGenerator` owned by the tile source.
- Generate and store a 64-bit match seed during setup.
- Tests, replays, daily challenges, and debugging may supply an explicit seed.
- Production free-play matches generate a new seed unless one is supplied by the mode.
- No UI animation, preview, AI search, or score calculation may consume the tile-source RNG.
- Generate the complete bag once during setup so later system behavior cannot alter draw order through accidental RNG calls.

The exact generator algorithm and serialization format must be versioned. A replay should store either the complete generated bag or enough versioned information to reconstruct it exactly.

### 4. Canonical tile data

Tile data stores edges in the unrotated order `[top, right, bottom, left]`. Rotation is separate state.

```gdscript
class_name TileData
extends Resource

@export var tile_id: StringName
@export var rank: TileRank
@export var face_color: FaceColor
@export var base_edges: Array[EdgeColor]
```

The authoritative tile definition is immutable after generation. A placed tile snapshot adds its committed board coordinate and rotation without modifying `base_edges`.

`get_rotated_edges(rotation)` returns a new four-value sequence in visible top/right/bottom/left order. It must not mutate the canonical edge array.

### 5. Tile IDs

Every generated tile receives a deterministic unique ID derived from the match ID and its bag index, for example:

```text
<match-id>:tile:000
<match-id>:tile:001
...
<match-id>:tile:143
```

Rules code compares tile identity by ID rather than by rank or edge values. Two visually identical tiles remain distinct entities.

### 6. Draw timing and ownership

ADR-003 controls draw timing:

- At a player's `TURN_START`, draw one tile only if that player has no active tile.
- Assign the drawn tile to that player's active slot.
- Previewing, rotating, canceling, or retrying an invalid placement does not consume another tile.
- Committing placement moves the tile from the active slot to board state.
- Save/resume preserves active tile ownership and the remaining bag order.

Drawing and assignment form one atomic state change. If assignment fails, the bag remains unchanged.

### 7. Information visibility

- The active human tile and its canonical face/edge values are visible to the human.
- The AI receives its active tile when its turn begins.
- A committed tile is public information to both players.
- Undrawn bag contents and future draw order are hidden from both the player-facing UI and the AI decision interface.
- The remaining tile count may be shown, but ranks, face colors, edges, and order are not revealed.
- Debug tooling may inspect the bag only behind an explicit development flag.

The AI may know the generation probabilities and public history, but it cannot inspect future tiles.

### 8. Configuration and balance

Generation probabilities must be stored in a versioned rules resource rather than embedded throughout the code. The initial configuration is:

| Property | Values | Initial weight per value |
|---|---|---:|
| Rank | Ace, King, Queen, Jack | 1 |
| Face color | Red, Black | 1 |
| Each edge | Blue, Red, Green, Yellow | 1 |

The resource should validate that every category has at least one positive weight. Weighted generation may be used in a future mode, but changing weights for the base mode is a balance change requiring simulation and documentation.

### 9. Statistical validation

Randomness tests should not assert exact frequencies for a single match. Instead:

- fixed-seed tests assert exact deterministic output;
- invariant tests assert valid enum values, four edges, unique IDs, and zero initial rotation;
- large-sample simulations use documented tolerances to detect gross weighting errors;
- balance simulations measure poker-hand rates, edge-match rates, first-player advantage, and average game duration.

Statistical simulations must use separate explicit seeds and must not change production rules state.

## Tile-source interface

A rules-focused interface may be expressed as:

```gdscript
class_name TileSource
extends RefCounted

func initialize(match_id: StringName, seed: int, rules: TileGenerationRules) -> void:
    pass

func draw() -> TileData:
    return null

func remaining_count() -> int:
    return 0

func is_exhausted() -> bool:
    return true
```

`draw()` returns no tile only when the bag is exhausted or a recoverable error is reported separately. It must never silently generate an extra tile after the configured bag is depleted.

## Save and replay requirements

A match snapshot must retain:

- tile-generation schema version;
- rules-resource version or stable hash;
- match seed;
- complete bag order or reconstructable generator state;
- next draw index;
- active tile IDs and owners;
- committed tile IDs, values, coordinates, and rotations; and
- integrity data sufficient to detect a missing or duplicated tile.

On load, assert that every tile ID appears in exactly one location: remaining bag, a player's active slot, or a committed board cell. The total must remain 144.

## Alternatives considered

### Generate a new random tile on every turn without a finite bag

This is simpler but provides no natural supply exhaustion, makes future draw state harder to audit, and allows accidental RNG consumption to affect outcomes. It is not recommended.

### Build a perfectly balanced bag with exact quotas

Exact quotas reduce variance, but balancing four independent edges across complete tile configurations becomes artificial and can make future draws inferable. Independent generation better matches the source requirement.

### Give each player a separate bag

Separate bags complicate fairness comparisons and exhaustion behavior. A shared bag creates one reproducible sequence for the match.

### Let the AI inspect the future bag

This would give the AI information unavailable to the human and make difficulty depend on hidden-information cheating. Difficulty should arise from move evaluation and search instead.

### Generate lazily from a seed

Lazy generation can be deterministic, but unrelated RNG calls or future code changes can alter draw order. Pre-generating the full bag isolates the sequence at match setup.

## Consequences

### Benefits

- A match has a clear maximum of 144 draws and placements.
- Human and AI draw from one deterministic, auditable sequence.
- All random values are isolated from UI, scoring, and AI behavior.
- Fixed seeds make bugs, tests, simulations, and replays reproducible.
- Duplicate configurations remain valid without identity ambiguity.
- Hidden future tiles prevent information advantages.

### Costs and risks

- Independent generation can produce unusually uneven ranks or edge colors in an individual match.
- A 144-tile pre-generated bag must be included in or reconstructable from save data.
- Human-first alternating draws may interact with a particular random sequence; simulations must measure first-player advantage.
- Changing the generator algorithm or rules weights requires schema/version handling.
- Face color remains mechanically unused under ADR-001 and may appear decorative until a later feature gives it purpose.

## Required tests

Automated tests must cover:

- exactly 144 generated tiles;
- valid rank, face-color, and edge enums;
- exactly four canonical edges per tile;
- zero initial rotation;
- unique deterministic IDs for all tiles;
- duplicates in visual configuration being permitted;
- identical bags from identical seed, rules version, and match ID;
- expected difference from known distinct seeds;
- draw order and remaining-count behavior;
- exhaustion returning no additional tile;
- atomic draw/assignment rollback;
- previews and invalid actions consuming no tile or RNG value;
- save/resume preserving bag order and active ownership;
- no tile duplicated or lost across bag, active slots, and board;
- AI interface hiding future bag entries; and
- large-sample distribution sanity within documented tolerances.

## Decision confirmation

The gameplay owner accepted the complete proposal on 2026-09-21. This confirms that:

1. Phase 1 uses one shared, pre-generated bag of exactly 144 tiles.
2. Rank, red/black property, and each edge color are selected independently and uniformly.
3. Duplicate tile configurations are allowed.
4. The complete bag is generated from one versioned match seed during setup.
5. Undrawn tiles and draw order remain hidden from both the human UI and AI.
6. Active tiles always begin at zero rotation.
7. Phase 1 prohibits exchanges, discards, redraws, and returning tiles to the bag.

These rules are authoritative for Phase 1 unless this ADR is superseded or explicitly amended.

## Implementation follow-up

1. Update `GAME_SPEC.md` with the approved generation and distribution rules.
2. Implement `TileData`, `TileGenerationRules`, and `TileSource` independently of scene nodes.
3. Add deterministic unit tests and large-sample balance simulations.
4. Version the generator and save schema before relying on seed-only reconstruction.
5. Connect the tile source to ADR-003 only through atomic draw/assignment operations.

## Amendments

- 2026-09-21: The initial proposal was accepted without changes.
- 2026-09-22: Section 6 (draw timing and ownership) is superseded by ADR-010. Tiles are no longer drawn one at a time at TURN_START: each player holds a deck of six, dealt from the shared pot at match setup and topped back up to six when a turn ends. Sections 1 to 5 and 7 to 9 stand unchanged, including the finite pot, the hidden future order, and the tile-conservation save requirements.
- 2026-09-22: Engine-forced rename. Section 4 declares the domain tile type as
  `TileData`, but Godot 4 ships a native `TileData` class (the TileSet tile
  resource). `class_name TileData` is a GDScript analyzer error ("Class
  TileData hides a native class"), so the type could not be declared under that
  name. The owner approved naming it `TileDefinition` (file
  `scripts/domain/tile/tile_definition.gd`). Nothing else in this ADR changes:
  the fields, immutability, canonical `[top, right, bottom, left]` edge order,
  and `get_rotated_edges(rotation)` behaviour are as specified. Where this ADR,
  ADR-005, or ADR-008 write `TileData`, read `TileDefinition`.
