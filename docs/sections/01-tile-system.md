# 01 - Tile System

**Status:** Specified (model and generation) with open items listed in section 7.
**Source of truth:** `docs/GAME_SPEC.md` section 3.
**Related decisions:** ADR-004 (Tile Distribution and Generation).

---

## 1. Purpose

This section defines the data model and rules for a single tile, independent of
how tiles are drawn, placed, or scored. Tiles are pure data; presentation is a
separate concern (see `07-godot-structure.md`).

---

## 2. Status Vocabulary

Taken from `GAME_SPEC.md` section 14:

- **Specified** - defined by the game specification.
- **Decided** - explicitly agreed as a project decision.
- **Implemented** - present in the codebase.
- **Tested** - verified by automated or manual testing.
- **Proposed** - suggested but not yet approved.
- **Future** - intentionally deferred.

---

## 3. Tile Properties (Specified)

| Property | Values / Notes |
|---|---|
| Face | Ace, King, Queen, Jack |
| Face Color | Red / Black |
| Edges | Top, Right, Bottom, Left |
| Edge Colors | Blue, Red, Green, Yellow |
| Rotation | 0 deg, 90 deg, 180 deg, 270 deg |

Each tile holds exactly four edge colors, one per edge.

---

## 4. Face (Specified)

- The four faces are Ace, King, Queen, Jack.
- Every face carries a Red/Black color property.
- The base scoring rules described in `GAME_SPEC.md` evaluate **faces** only.
- Face rank order (for any rule that needs "highest face") is not stated in the
  source specification. Do not assume a rank order until it is decided.

### 4.1 Face Color - open item

`GAME_SPEC.md` lists Face Color as a property but does **not** state:

- How the Red/Black value is assigned during generation (fixed per face vs.
  random per tile).
- Whether the color affects any base-game scoring rule.

Until decided, Face Color is stored on the tile but is not consumed by any
scoring rule. See section 7.

---

## 5. Edges (Specified)

- Edge colors are Blue, Red, Green, Yellow.
- Each tile has four edge positions: Top, Right, Bottom, Left.
- Matching is evaluated against the tiles' **current rotated** edges.

### 5.1 Edge Ordering Convention (implementation detail)

The specification does not fix an internal edge index order. To keep the code
deterministic and testable, use this convention and lock it with a unit test:

- index 0 = Top
- index 1 = Right
- index 2 = Bottom
- index 3 = Left

The order is clockwise starting from the top. This is a pragmatic implementation
choice and does not change any specified game rule.

---

## 6. Rotation (Specified)

- Tiles support four orientations: 0 deg, 90 deg, 180 deg, 270 deg.
- The tile's current orientation determines which stored edge color faces each
  board-facing edge.
- Newly generated tiles begin at 0 deg.

Rotation is represented internally as an integer turn index `k` in {0, 1, 2, 3}.

### 6.1 Canonical API (Specified)

The tile system must expose functionality equivalent to:

```gdscript
get_rotated_edges()
```

which returns the four edge colors in their current orientation.

### 6.2 Rotation Mapping (Proposed)

The direction of rotation (clockwise vs. counter-clockwise) is not specified.
A proposed, self-consistent mapping for a clockwise rotation by `k` quarter
turns:

```
rotated[i] = base[(i - k + 4) % 4]
```

This convention must be locked with a unit test. The choice of direction does
not change any game rule as long as it is applied consistently to placement and
scoring.

---

## 7. Generation (Specified) and Open Items

Specified generation behavior:

- Random face.
- Random edge colors.
- Initial rotation of 0 deg.

Open items (must be decided, not invented):

- **Face color assignment** - fixed mapping or random per tile (section 4.1).
- **Distribution / weighting** - whether faces and edge colors are uniformly
  random or drawn from a controlled bag, and whether duplicate tiles are
  unrestricted. Owned by ADR-004.
- **Rotation direction convention** - proposed in 6.2.

`GAME_SPEC.md` section 3.3 explicitly says not to introduce probability
weighting without a design decision.

---

## 8. Testing Requirements

Per `AGENTS.md` section 16, the tile system should be covered by tests
independent of the scene tree:

- Rotation: four rotations return the original tile; known fixed vectors.
- Edge ordering: index-to-position mapping is stable.
- Generation: face and edge values always fall in valid ranges.
- Face values: only the four specified faces are produced.

---

## 9. Status Summary

| Area | Status |
|---|---|
| Face set and Face Color property | Specified |
| Four edge positions and colors | Specified |
| Four rotations + `get_rotated_edges()` | Specified |
| Edge ordering convention | Proposed (pragmatic) |
| Rotation direction mapping | Proposed |
| Face color assignment / usage | Open - pending decision |
| Distribution and weighting | Open - ADR-004 |
