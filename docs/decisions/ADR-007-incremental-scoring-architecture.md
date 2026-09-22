# ADR-007: Incremental Scoring Architecture

- **Status:** Accepted
- **Date:** 2026-09-21
- **Accepted:** 2026-09-21
- **Owners:** Game design and engineering
- **Decision scope:** Phase 1 core scoring architecture
- **Source:** `GAME_SPEC.md` and `iterative_specification.pdf`
- **Related:** ADR-001 (poker scoring), ADR-002 (edge clusters), ADR-003 (turn flow), ADR-006 (placement)

## Context

The source specification requires mobile-friendly incremental scoring that recalculates only affected tiles. Accepted decisions now define three scoring components:

- poker-hand awards from five-cell windows under ADR-001;
- +1 for each new matching boundary under ADR-002; and
- flat color-cluster milestone deltas under ADR-002.

ADR-006 requires placement and scoring to commit atomically. The architecture must also support preview, AI evaluation, save/resume, deterministic replay, debugging, and proof that incremental results agree with an authoritative full calculation.

## Constraints inherited from accepted decisions

1. Only a committed tile placement changes score.
2. Committed tiles are immutable.
3. One normal turn commits exactly one tile.
4. Poker windows score once through canonical window identifiers.
5. New matching boundaries award +1 each.
6. Cluster awards use positive entitlement deltas.
7. Multiple score events may be created by one placement.
8. All points go to the player who commits the scoring tile.
9. Phase 1 uses integer points and no multipliers.
10. Incremental and authoritative full calculations must agree.

## Decision

### 1. Append-only score ledger

Store every committed scoring award as an immutable event in an append-only `ScoreLedger`.

Each event records at least:

- schema and rules version;
- match ID, move ID, and turn number;
- player ID;
- score category;
- integer points;
- affected coordinates;
- category-specific evidence; and
- a deterministic event ID.

The player's displayed total is the sum of that player's committed events. Cached totals may be maintained for performance but are derived data.

Supported Phase 1 categories are:

- `POKER_HAND`
- `EDGE_MATCH`
- `EDGE_CLUSTER`

Presentation-only messages are not score events and cannot change totals.

### 2. Pure scoring calculators

Implement three focused rules services:

- `PokerHandEvaluator`
- `EdgeMatchScorer`
- `EdgeClusterScorer`

Each service receives immutable rule inputs and returns proposed score events without mutating board state, score state, UI, or scene nodes.

The same services are used for:

- human placement preview;
- committed move resolution;
- Medium and Hard AI move evaluation;
- automated tests; and
- replay verification.

Easy AI may ignore scores when selecting a move, but its committed move still uses the same scoring transaction.

### 3. Hypothetical post-placement view

Incremental calculators evaluate a read-only hypothetical board consisting of:

- the current committed `BoardState`; and
- one validated proposed placement.

The hypothetical view must expose the same cell and adjacency queries as a committed board without copying presentation nodes. A simple 12 x 12 board copy is acceptable initially; optimize only after profiling.

Preview calculations never update:

- board cells;
- scored poker-window IDs;
- cluster indexes or entitlements;
- the score ledger;
- player totals; or
- turn state.

### 4. Atomic score transaction

A committed move is processed as one transaction:

1. Validate player, active tile, coordinate, and rotation.
2. Assign a deterministic move ID.
3. Build the hypothetical post-placement board.
4. Generate proposed poker, edge-match, and cluster events.
5. Validate all proposed events and calculate the score delta.
6. Prepare updates to the board, derived indexes, scored-hand set, ledger, and totals.
7. Commit all prepared state together.
8. Emit one immutable `MoveResult` containing the placed tile and committed score events.
9. Advance the turn through ADR-003.

If any step before commit fails, no authoritative state changes. If persistence fails after an in-memory commit, recovery uses the last complete transaction boundary; partial score events are never exposed as a successful move.

### 5. Stable identifiers and idempotency

Every move and score event has a deterministic identifier.

Recommended formats are conceptually:

```text
move:<match-id>:<turn-number>
score:<move-id>:poker:<hand-id>
score:<move-id>:edge:<ordered-cell-pair>
score:<move-id>:cluster:<color>:<ordinal>
```

- A move ID may be committed at most once.
- An event ID may appear in the ledger at most once.
- Repeating a commit request with an already committed move ID returns the original result or an explicit duplicate response; it never awards points again.
- Poker hand IDs follow ADR-001.
- Matching boundaries use a canonical ordered coordinate pair.
- Cluster event evidence records pre- and post-entitlement values under ADR-002.

### 6. Incremental affected regions

For a placement at coordinate `p`:

- **Poker:** inspect only horizontal and vertical five-cell windows containing `p`.
- **Edge matches:** inspect only the four orthogonal boundaries touching `p`.
- **Clusters:** inspect only colors that form a new matching boundary at `p`, traversing the distinct affected pre-move components.

Calculators may share a placement context containing the rotated edges, neighbors, and hypothetical board. They must not share mutable scoring decisions or duplicate rules.

### 7. Event ordering

Event generation is normalized to a deterministic order:

1. Poker events ordered by canonical hand ID.
2. Edge-match events ordered by canonical boundary ID.
3. Cluster events ordered by edge-color enum and then canonical component evidence.

The final numeric total must be independent of evaluation order. Ordering exists for reproducible saves, replays, tests, animations, and debugging.

### 8. Preview contract

A preview returns a `ScorePreview` with the same proposed event data used at commit time, clearly marked as non-authoritative.

- Preview is calculated against a specific board revision.
- Confirmation revalidates the placement against the current revision.
- If state changed, discard the preview and recalculate.
- A successful commit on the same revision must produce the same category events and points as the preview.
- UI may summarize or animate preview events but cannot alter them.

### 9. Authoritative verification

Use two complementary verification paths.

#### Static board audit

From the current board alone:

- enumerate every matching boundary once;
- enumerate current single-color clusters and entitlements;
- validate scored poker-window IDs against their coordinates and faces; and
- validate derived indexes and caches.

#### Full replay

Rebuild the match from an empty board by replaying committed moves in order through the pure rules pipeline. Compare:

- board state;
- score events and IDs;
- per-player totals;
- scored poker-window IDs;
- matching boundaries;
- cluster entitlements; and
- final match state.

Replay is the authoritative equivalence test because player attribution and one-time poker scoring depend on move order, not only the final board.

### 10. Source of truth and caches

Authoritative persisted inputs are:

- rules/configuration versions;
- initial match seed and tile bag state;
- ordered committed move history; and
- committed score ledger.

The board snapshot is an authoritative checkpoint that must agree with replay. The following are rebuildable caches:

- per-player score totals;
- legal-placement frontier;
- adjacency lookups;
- matching-boundary index;
- cluster/component index; and
- UI score summaries.

The scored poker-window set is persisted for efficient play and verified against replay.

### 11. Error handling

- Reject negative points in Phase 1.
- Reject unknown score categories or rules versions.
- Reject events whose player or move does not match the active transaction.
- Reject duplicate event IDs.
- Treat a preview/commit mismatch on the same board revision as a rules error.
- In development and test builds, fail fast on replay divergence and print structured evidence.
- In production, preserve the last valid transaction and enter ADR-003's recoverable error state.

## Core data structures

```gdscript
class_name ScoreEvent
extends RefCounted

var event_id: StringName
var move_id: StringName
var player_id: StringName
var category: ScoreCategory
var points: int
var cells: Array[Vector2i]
var evidence: Dictionary
```

```gdscript
class_name ScoreTransaction
extends RefCounted

var move_id: StringName
var board_revision_before: int
var placement: TilePlacement
var events: Array[ScoreEvent]
var total_points: int
```

```gdscript
class_name MoveResult
extends RefCounted

var move_id: StringName
var board_revision_after: int
var placed_tile: TileSnapshot
var score_events: Array[ScoreEvent]
var total_points: int
```

Use typed category-specific evidence objects later if profiling or schema safety justifies replacing `Dictionary`.

## Data ownership

- `ScoringCoordinator` orchestrates pure calculators and normalizes events.
- Category calculators own only their specific rules.
- `MoveCommitter` owns the atomic transaction boundary.
- `ScoreLedger` owns committed events and rejects duplicates.
- `BoardState` owns committed tiles and board revision.
- `TurnManager` advances only after a successful committed result.
- UI and AI consume previews/results but do not write score state.

## Alternatives considered

### Recalculate the whole board after every move

This is simple but ignores the mobile optimization requirement and obscures whether score attribution is tied to the current move. Full replay remains available for verification instead.

### Store only player totals

Totals are compact but cannot explain scoring, prevent duplicates, animate specific awards, audit saves, or reproduce bugs. An event ledger provides those capabilities.

### Let each scorer mutate the ledger directly

This creates partial commits if a later scorer fails and makes ordering significant. Returning proposed events keeps mutation at one transaction boundary.

### Use preview-specific scoring logic

Duplicated preview rules will drift from committed scoring. The same pure calculators should serve both paths.

### Treat the final board as sufficient for full verification

The final board cannot reconstruct who completed each award or when a one-time poker window first scored. Ordered move replay is required.

## Consequences

### Benefits

- Mobile play evaluates only locally affected scoring regions.
- One atomic transaction prevents board/score/turn disagreement.
- Append-only events support explanations, animation, debugging, analytics, and replay.
- Human preview and AI evaluation cannot drift from committed scoring rules.
- Stable IDs make retries idempotent.
- Full replay gives a strong correctness oracle for optimization work.

### Costs and risks

- The score ledger and move history consume more save space than totals alone.
- Event schemas and rules versions require migration discipline.
- Atomic persistence needs careful failure handling.
- Cluster evidence is more complex than a simple point delta.
- A pure reference path and optimized caches must be maintained and compared.

## Required tests

Automated tests must cover:

- every category calculator in isolation;
- multiple poker, edge, and cluster events from one placement;
- deterministic event order and IDs;
- duplicate move and event rejection;
- preview causing no mutations;
- preview matching commit on the same board revision;
- stale preview rejection and recalculation;
- rollback after failure at every pre-commit stage;
- board, ledger, totals, indexes, and turn advancing together;
- score total reconstruction from the ledger;
- incremental affected-region boundaries;
- saved transaction recovery;
- static audit against derived indexes;
- full replay equality for board, events, and totals;
- randomized seeded matches comparing incremental play with replay; and
- rejection of negative, unknown, or mismatched events.

## Decision confirmation

The gameplay owner accepted the complete proposal on 2026-09-21. This confirms that:

1. Committed scoring uses an append-only event ledger rather than totals alone.
2. Preview, commit, AI evaluation, and replay share the same pure calculators.
3. Placement, score events, derived indexes, and turn advancement form one atomic transaction.
4. Deterministic move and event IDs make commit retries idempotent.
5. Ordered full replay is the authoritative incremental-scoring equivalence check.
6. Totals and indexes are rebuildable caches verified against authoritative state.
7. Phase 1 accepts only non-negative integer score events with no multipliers.

These rules are authoritative for Phase 1 unless this ADR is superseded or explicitly amended.

## Implementation follow-up

1. Update `GAME_SPEC.md` with the approved scoring architecture.
2. Implement reference category calculators and event schemas first.
3. Implement atomic `MoveCommitter` and `ScoreLedger` behavior.
4. Add preview and full-replay verification before adding optimized caches.
5. Use the scoring API as the sole score source for UI and AI.

## Amendments

- 2026-09-21: The initial proposal was accepted without changes.
