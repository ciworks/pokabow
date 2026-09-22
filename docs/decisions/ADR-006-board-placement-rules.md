# ADR-006: Board Placement Rules

- **Status:** Accepted
- **Date:** 2026-09-21
- **Accepted:** 2026-09-21
- **Owners:** Game design and engineering
- **Decision scope:** Phase 1 core game
- **Source:** `GAME_SPEC.md` and `iterative_specification.pdf`
- **Related:** ADR-001 (poker hands), ADR-002 (edge clusters), ADR-003 (turn flow), ADR-007 (incremental scoring)

## Context

The source specification establishes a 12 x 12 board, empty-cell-only placement, snap-to-grid behavior, tile rotation, adjacency tracking, and incremental scoring. It does not define the opening cell, whether later tiles must connect to the board, whether edge colors restrict placement, whether diagonal contact counts, or when a preview becomes a committed move.

Those details must be stable before implementing placement validation, legal-move generation, AI search, scoring triggers, or mobile drag-and-drop behavior.

## Constraints inherited from the specification

This decision must preserve the following confirmed requirements:

1. The board is 12 cells wide and 12 cells high.
2. A tile may be placed only in an empty cell.
3. Tiles snap to board cells.
4. Tiles support rotations of 0, 90, 180, and 270 degrees.
5. Orthogonal adjacency is tracked for edge and cluster scoring.
6. Placement must trigger incremental scoring of affected regions.
7. The initial game mode is Human vs AI and is mobile-first.

## Decision

### 1. Coordinate system

Use integer coordinates with the origin at the top-left:

- `x` increases from left to right and ranges from `0` to `11`.
- `y` increases from top to bottom and ranges from `0` to `11`.
- A coordinate is valid when `0 <= x < 12` and `0 <= y < 12`.
- Board state, validation, scoring, and AI use `Vector2i`; pixel positions exist only in presentation code.

### 2. Opening placement

Because an even-sized board has no single center cell, the first tile must occupy any one of the four central cells:

```text
(5,5)  (6,5)
(5,6)  (6,6)
```

The UI highlights all four cells until the first move is committed. This keeps the opening symmetric and avoids arbitrarily favoring one coordinate.

### 3. Later placements

After the opening move, a legal placement must:

1. Be inside the board.
2. Target an empty cell.
3. Be orthogonally adjacent to at least one committed tile.

Diagonal contact alone does not satisfy the connection rule. A legal tile may have one to four orthogonal neighbors.

### 4. Edge colors

Edge colors affect scoring, not placement legality:

- Matching adjacent colors earn the edge-match points defined by the scoring rules.
- Non-matching colors are permitted and award no edge-match point.
- A tile is not required to match any neighbor.

This prevents random tile generation from producing unusable tiles and keeps edge matching as an optimization choice rather than a hard placement constraint.

### 5. Rotation and preview

- A tile may be rotated only in 90-degree increments.
- Rules-layer placement requests accept only `0`, `1`, `2`, or `3` quarter-turns clockwise; presentation code converts degree values before validation.
- The player may rotate the active tile before or while previewing a placement.
- Previewing and rotating do not mutate authoritative board state.
- Placement feedback uses the previewed rotation when displaying edge matches and predicted scoring.
- On mobile, dropping a tile creates a preview; an explicit confirm action commits it.
- The tile's position and rotation become immutable when the move is committed.
- Canceling a preview returns the tile to the player's active-tile area without changing board state.

### 6. Atomic move commitment

A placement is committed as one atomic rules operation:

1. Revalidate the coordinate and active tile against current board state.
2. Write a snapshot of the tile and its normalized rotation into the target cell.
3. Update occupied-cell and frontier-cell indexes.
4. Evaluate affected edge matches and edge clusters.
5. Evaluate poker windows containing the placed coordinate, as defined by ADR-001.
6. Record all score events and previously-scored identifiers.
7. Advance turn state through the turn manager.
8. Emit a committed move result for UI, animation, audio, haptics, and AI observation.

If validation or rule evaluation fails, none of these changes are applied. Visual animation occurs only after a successful commit.

### 7. Legal-placement frontier

Maintain a derived set of empty cells orthogonally adjacent to committed tiles:

- Before the first move, the frontier contains the four central cells.
- After a commit, remove the occupied coordinate.
- Add each in-bounds, empty orthogonal neighbor.
- The frontier is a performance index, not an independent source of truth.
- Debug and test builds must be able to rebuild it from the board array and compare the results.

Easy AI may choose randomly from the frontier and a valid rotation. Medium and Hard AI may enumerate the same frontier with all four rotations for scoring and search.

### 8. Board-full and no-move state

Under these rules, every frontier cell accepts every available tile, regardless of edge colors. Therefore, a player lacks a board placement only when:

- the board is full; or
- no active tile can be supplied under the tile-distribution rules.

Board-full behavior and unavailable-tile behavior are resolved in ADR-003 (turn flow and game end) and ADR-004 (tile distribution), respectively. This ADR does not introduce a voluntary pass action.

## Rules-layer interface

Placement validation must be independent of scene nodes. A minimal interface may be expressed as:

```gdscript
class_name PlacementRequest
extends RefCounted

var player_id: StringName
var tile_id: StringName
var cell: Vector2i
var rotation: int
```

```gdscript
class_name PlacementResult
extends RefCounted

var accepted: bool
var rejection: PlacementRejection
var cell: Vector2i
var placed_tile: TileSnapshot
var score_events: Array[ScoreEvent]
var changed_cells: Array[Vector2i]
```

Recommended rejection values are:

- `NONE`
- `OUT_OF_BOUNDS`
- `CELL_OCCUPIED`
- `OPENING_CELL_REQUIRED`
- `NOT_CONNECTED`
- `TILE_NOT_AVAILABLE`
- `NOT_PLAYERS_TURN`
- `INVALID_ROTATION`

The validator should return a structured rejection reason so mobile UI can provide specific feedback without recreating gameplay rules.

## Data ownership

- `BoardState` owns the authoritative cell array and occupancy/frontier queries.
- `PlacementValidator` is a pure reader of board state plus turn/tile availability.
- `MoveCommitter` performs the atomic state transition after validation.
- `TileView` and `BoardView` translate between pixels and cells but do not decide legality.
- Scoring systems consume the committed coordinate and board snapshot.
- AI requests legal moves through the same rules interfaces used by the human player.

## Alternatives considered

### Require all touching edge colors to match

This produces a stricter puzzle, but random tiles could become unplayable and the specification describes matches as bonuses. It is not recommended for the base game.

### Permit placement in any empty cell

This follows the literal empty-cell requirement but creates disconnected islands, weakens local interaction, and complicates the meaning of clusters. It is not recommended.

### Allow diagonal connectivity

Diagonal connectivity expands the frontier without creating an edge relationship. Because edge scoring is orthogonal, this would create connected-looking moves with no direct scoring interaction. It is not recommended.

### Require one fixed opening cell

This is mechanically simple but arbitrary on an even 12 x 12 board. The four-cell center provides symmetry with negligible complexity.

## Consequences

### Benefits

- Every generated tile remains playable while board space exists.
- The board grows as one orthogonally connected structure.
- The same frontier supports highlighting and all AI difficulties.
- Preview behavior cannot corrupt authoritative state.
- Atomic commits provide a clear point for scoring, turn advancement, replay, and save data.
- Validation remains deterministic and testable without Godot scenes.

### Costs and risks

- Allowing mismatched edges may reduce tension unless edge bonuses are balanced strongly enough.
- Four opening cells create four equivalent initial actions for AI enumeration.
- Immutable committed tiles prevent correction after confirmation; mobile UX needs a clear confirm/cancel flow.
- The frontier index must be checked against board state to prevent stale-cache bugs.

## Required tests

Automated tests must cover:

- all in-bounds and out-of-bounds boundaries;
- occupied-cell rejection;
- each of the four valid opening cells and nearby invalid opening cells;
- orthogonal connectivity in all four directions;
- diagonal-only rejection;
- matching and mismatching edge colors both being legal;
- normalization and rejection behavior for rotations;
- preview and cancellation leaving board state unchanged;
- atomic rollback when a commit fails;
- frontier updates at corners, edges, and interior cells;
- frontier rebuild equivalence;
- a full board producing an empty frontier;
- human and AI validation producing identical results; and
- affected-cell reporting for incremental scoring.

## Decision confirmation

The gameplay owner accepted the complete proposal on 2026-09-21. This confirms that:

1. The opening tile may occupy any of the four central cells.
2. Every later tile must be orthogonally adjacent to the existing board.
3. Diagonal-only contact is illegal.
4. Mismatched edge colors are legal and award zero edge-match points.
5. A committed tile's position and rotation are immutable.
6. Mobile placement requires an explicit confirmation after preview.
7. Voluntary passing is outside the placement rules and is decided by ADR-003.

These rules are authoritative for Phase 1 unless this ADR is superseded or explicitly amended.

## Implementation follow-up

1. Update `GAME_SPEC.md` with the approved placement rules.
2. Implement `BoardState`, `PlacementValidator`, and the frontier index.
3. Add the required rule tests before building drag-and-drop presentation.
4. Integrate ADR-001 scoring only through atomic move commitment.
5. Resolve ADR-003 and ADR-004 before completing the playable turn loop.

## Amendments

- 2026-09-21: The initial proposal was accepted without changes.
