# ADR-002: Edge Cluster Definition and Bonus

- **Status:** Accepted
- **Date:** 2026-09-21
- **Accepted:** 2026-09-21
- **Owners:** Game design and engineering
- **Decision scope:** Phase 1 core scoring
- **Source:** `GAME_SPEC.md` and `iterative_specification.pdf`
- **Related:** ADR-001 (poker scoring), ADR-003 (turn flow), ADR-006 (placement), ADR-007 (incremental scoring)

## Context

The source specification awards +1 point for each matching adjacent edge and requires an additional flat bonus for edge clusters. It identifies flood-fill or adjacency search as suitable for cluster detection, but it does not define what constitutes a cluster, its minimum size, its bonus value, whether colors mix, whether clusters score repeatedly, or how merged clusters are handled.

These rules must be explicit before implementing scoring, AI move evaluation, cluster visualization, save data, or incremental/full-score equivalence tests.

## Constraints inherited from the specification

1. Each tile has top, right, bottom, and left edges.
2. Edge colors are blue, red, green, and yellow.
3. A matching touching edge awards +1 point.
4. Connected edge clusters award additional flat points.
5. Cluster detection uses orthogonal adjacency, such as flood-fill or graph traversal.
6. Scoring is incremental and should recalculate only affected regions.
7. The base game has no score multipliers.

## Decision

### 1. Matching edge

A matching edge exists when two committed tiles occupy orthogonally adjacent cells and their touching edges have the same visible color after rotation.

- Top compares with the upper neighbor's bottom.
- Right compares with the right neighbor's left.
- Bottom compares with the lower neighbor's top.
- Left compares with the left neighbor's right.
- Each undirected tile-to-tile boundary is evaluated once.
- A matching boundary awards exactly **+1 edge-match point** when the second tile is committed.
- A non-matching boundary is legal under ADR-006 and awards zero edge-match points.

Edge-match points and cluster bonuses are separate score events. A matching boundary can contribute its +1 point and also connect tiles inside a cluster.

### 2. Color-specific cluster

For each edge color, construct an undirected graph:

- A vertex is a committed tile incident to at least one matching boundary of that color.
- An edge connects two orthogonally adjacent tiles whose touching edges both have that color.
- A cluster is one connected component of this single-color graph.

Colors never mix within one cluster. A tile may simultaneously belong to multiple clusters of different colors through different edges. Diagonal contact does not connect clusters.

### 3. Cluster size

Cluster size is the number of unique tiles in the connected component, not the number of matching boundaries.

Examples:

- Two tiles joined by one blue boundary form a blue component of size 2.
- Three blue tiles in a line form one blue component of size 3.
- Four blue tiles in a loop still have size 4 even though the loop contains four matching boundaries.
- A tile with a blue match and a red match belongs to one blue component and one red component; those components remain distinct.

### 4. Flat milestone bonus

A color cluster earns a flat **+3 cluster points for each completed group of four tiles**.

The total cluster entitlement for size `n` is:

```text
cluster_entitlement(n) = 3 * floor(n / 4)
```

| Cluster size | Total entitlement |
|---:|---:|
| 1-3 | 0 |
| 4-7 | 3 |
| 8-11 | 6 |
| 12-15 | 9 |

This is a series of fixed milestone awards, not a score multiplier. The milestone size and flat award must be configurable in a versioned `ClusterScoreRules` resource, with Phase 1 defaults of `4` tiles and `3` points.

### 5. Incremental award on placement

Only clusters connected through the newly placed tile can change. For each color appearing on at least one new matching boundary:

1. Identify the distinct pre-move components of that color touched by the new tile.
2. Sum their existing cluster entitlements.
3. Add the new tile and matching boundaries to form the post-move component.
4. Calculate the post-move component's entitlement.
5. Award the positive difference:

```text
award = max(0, post_entitlement - sum(pre_entitlements))
```

This delta rule prevents double-scoring when a tile grows or merges clusters.

Examples with the Phase 1 defaults:

| Before placement | After placement | Award |
|---|---|---:|
| One size-3 component | Size 4 | 3 |
| One size-7 component | Size 8 | 3 |
| Size 3 + size 3 joined by new tile | Size 7 | 3 |
| Size 4 + size 4 joined by new tile | Size 9 | 0 |
| Size 3 + size 4 joined by new tile | Size 8 | 3 |

If one placement creates qualifying milestones in two or more colors, calculate and award each color independently.

### 6. Player attribution

The player who commits the tile receives:

- +1 for every new matching boundary created by that tile; and
- every positive cluster-entitlement delta created by that placement.

It does not matter who placed the older tiles. Previously awarded points are never transferred when clusters grow or merge.

### 7. Component identity and score events

Cluster state should be reconstructable from board state; mutable component IDs are an optimization, not the source of truth.

Each cluster score event records at least:

- player ID;
- turn number and move ID;
- edge color;
- newly placed coordinate;
- post-move component coordinates in canonical order;
- pre-entitlement total;
- post-entitlement total; and
- awarded delta.

The canonical component key for diagnostics may combine the color with sorted coordinates. Because a growing component changes coordinates, prevention of repeat scoring relies on entitlement deltas and committed history, not on treating that key as permanently stable.

### 8. Full recalculation

A full-board validation pass must:

1. Enumerate every matching boundary once.
2. Build connected components separately for all four colors.
3. Calculate each component's current entitlement.
4. Verify that total committed cluster awards equal the entitlement represented by the final components.
5. Verify edge-match totals against all matching boundaries.

Because placement only adds immutable tiles and matching connections, total cluster entitlement never decreases. If a future feature removes, rotates, recolors, or moves committed tiles, this ADR must be revisited.

## Rules-layer interface

Cluster evaluation must remain independent of scene nodes. A result may be represented as:

```gdscript
class_name ClusterScoreEvent
extends RefCounted

var player_id: StringName
var move_id: StringName
var color: EdgeColor
var cells: Array[Vector2i]
var previous_entitlement: int
var current_entitlement: int
var points: int
```

A scorer may expose:

```gdscript
func evaluate_placement(
    board_before: BoardState,
    placement: TilePlacement,
    rules: ClusterScoreRules
) -> Array[ClusterScoreEvent]:
    return []
```

The production implementation may use local flood-fill, union-find, or cached component indexes. All approaches must return the same deterministic results.

## Incremental implementation notes

For each of the new tile's four sides:

1. Read the in-bounds committed neighbor, if any.
2. Compare the touching rotated edge colors.
3. Record +1 for a match.
4. Group matching neighbors by color.
5. For each affected color, traverse or look up the distinct pre-move components.
6. Apply the entitlement-delta formula.
7. Commit component/index changes only as part of ADR-006's atomic move.

With a 12 x 12 board, a local flood-fill is acceptable for the first correct implementation. Introduce union-find or more complex caches only if profiling shows a real need.

## Alternatives considered

### Define clusters as any connected tiles regardless of edge color

This would overlap with the board's general connectivity rule and would not reward deliberate color matching. It is not recommended.

### Count matching boundaries rather than unique tiles

Boundary count rewards loops differently and makes the term cluster size less intuitive. Edge boundaries already receive +1 individually.

### Award one +3 bonus only when a cluster first reaches four tiles

This is simple but gives no further cluster incentive after size four. Fixed four-tile milestones preserve a flat award while rewarding continued growth.

### Award +3 on every placement into an existing size-four-or-larger cluster

This repeatedly rewards the same achievement and can dominate poker scoring. The entitlement-delta method prevents farming.

### Use a size multiplier

Multipliers conflict with the explicit Phase 1 restriction. Milestones add fixed points instead.

## Consequences

### Benefits

- Cluster membership has a precise, visual interpretation.
- Edge-match points and cluster bonuses cannot be confused or double-counted.
- Fixed milestones are tunable and comply with the no-multiplier requirement.
- The delta formula handles growth and merges without replaying old awards.
- Incremental and full-board calculations can be tested for equivalence.
- Human previews and AI evaluation can use the same pure scoring path.

### Costs and risks

- A tile may contribute to several color clusters, which requires clear visual feedback.
- Merging two already-rewarded components may correctly award zero, which may surprise players without explanation.
- Milestones of four and awards of three are initial balance choices requiring playtesting.
- Cached component indexes add consistency requirements beyond the board array.
- Future tile mutation or removal would require reversible entitlement accounting.

## Required tests

Automated tests must cover:

- matching and non-matching boundaries in all four directions;
- rotated-edge comparison;
- each matching boundary scored exactly once;
- single-color line, branch, and loop components;
- diagonal contact not joining components;
- different colors remaining separate;
- one tile belonging to clusters of multiple colors;
- size 3 to 4 and size 7 to 8 milestone awards;
- growth within a milestone band awarding zero;
- merges of unscored, mixed, and already-scored components;
- simultaneous awards in multiple colors;
- correct player attribution;
- atomic rollback leaving component state and scores unchanged;
- save/resume preserving score-event integrity;
- incremental versus full-board edge totals; and
- incremental versus full-board cluster entitlement totals.

## Decision confirmation

The gameplay owner accepted the complete proposal on 2026-09-21. This confirms that:

1. A cluster is a connected component of matching edges of one color.
2. Cluster size counts unique tiles rather than matching boundaries.
3. Different colors always form separate clusters.
4. Phase 1 awards a flat +3 points for every four-tile milestone.
5. Entitlement deltas prevent repeated scoring when clusters grow or merge.
6. A placement receives separate cluster awards for multiple colors when applicable.
7. The player placing the milestone-completing tile receives the full bonus.

These rules are authoritative for Phase 1 unless this ADR is superseded or explicitly amended.

## Implementation follow-up

1. Update `GAME_SPEC.md` with the approved cluster definition and bonus formula.
2. Implement a pure reference flood-fill scorer and the required tests.
3. Use the reference scorer to validate any later optimized component index.
4. Integrate cluster scoring only through ADR-006's atomic move commit.
5. Expose structured score events for UI feedback and AI evaluation.

## Amendments

- 2026-09-21: The initial proposal was accepted without changes.
