# 02 - Board System

**Status:** Specified, with one open placement decision listed in section 8.
**Source of truth:** `docs/GAME_SPEC.md` section 4.
**Related decisions:** ADR-006 (Board Placement Rules), ADR-007 (Incremental
Scoring Architecture).

---

## 1. Grid (Specified)

- The board is a 12x12 grid of cells.
- The board tracks cell occupancy, tile position, tile orientation, and the
  adjacency relationships required for scoring.
- The board may be represented as a 2D array or a Godot TileMap. The
  representation is an implementation choice; game state must not depend on
  visual nodes.

### 1.1 Coordinate Convention (implementation detail)

Use `(x, y)` with:

- `x` = column, 0..11, increasing left to right.
- `y` = row, 0..11, increasing top to bottom.

Origin (0, 0) is the top-left cell. This is a pragmatic convention.

---

## 2. State and Source of Truth

- `BoardState` is the authoritative record of the game board.
- The board stores which cell holds which tile, and each tile's rotation.
- Presentation nodes render from `BoardState`; they never become the source of
  truth for rules (see `AGENTS.md` sections 6 and 19).

### 2.1 Cell artwork (Implemented)

`BoardTileLayer` uses `assets/board/board_cell_default.png` for ordinary cells.
Each board view scatters 1-5 copies of each blue, red, green and yellow cell
sprite into distinct random positions; all remaining cells use the default.
The count range is a cosmetic interpretation of the requested maximum of five
per alternate sprite. Positions stay fixed through moves and resizing, and are
regenerated when the view receives a different board. This decoration uses its
own random generator, has no scoring or placement effect, and is not saved with
the match. Committed tiles and existing feedback layers draw over the artwork.

The board is framed by `assets/board/game_border.png` in a `NinePatchRect`.
Its 128px source corner slices scale uniformly into the existing 14px board
padding, while the side rails stretch to follow the square grid. The center is
not drawn, and the frame ignores pointer input. Board cell geometry and hit
testing continue to use the inner grid rectangle.

---

## 3. Placement (Specified)

A valid placement must:

- Target an **empty** cell.
- Snap to the grid.
- Respect the tile's current rotation.
- Update board adjacency information.

Occupied cells cannot receive another tile.

---

## 4. Placement Validation

Specified restriction:

- The target cell must be empty.

Undecided restriction (see section 8 and ADR-006):

- Whether tiles must connect to existing tiles (connectivity).
- Any first-tile rule (for example, a fixed starting cell).

`GAME_SPEC.md` section 4.3 explicitly says no other placement restriction may be
invented without a design decision.

---

## 5. Adjacency (Specified)

The board must track adjacent tiles so scoring can determine matching edges,
edge clusters, and the areas affected by a placement.

### 5.1 Neighbourhood (implementation detail)

Use the four-neighbour (orthogonal) neighbourhood. Touching edge pairs are:

| Cell | Its edge | Touches | Neighbour edge |
|---|---|---|---|
| `(x, y)` | Top | `(x, y-1)` | Bottom |
| `(x, y)` | Right | `(x+1, y)` | Left |
| `(x, y)` | Bottom | `(x, y+1)` | Top |
| `(x, y)` | Left | `(x-1, y)` | Right |

Comparisons must use each tile's rotated edges (`get_rotated_edges()`), not the
tile's base orientation.

Edge pairs where the two colors are equal are "matching edges" and feed edge
scoring. Diagonal adjacency is not part of the base game.

---

## 6. Incremental Scoring Support (Specified)

After a placement, the board must be able to identify the tiles and
relationships affected, so scoring recalculates only the affected region.

A placement affects at least:

- The placed cell itself.
- Its four orthogonal neighbours.
- Connected groups that include the placed tile (relevant to hand and cluster
  detection once those rules are decided).
- Any previously-scored region that overlaps the above.

`GAME_SPEC.md` section 4.5 requires a **full-board** scoring path to remain
available for validation and testing, in addition to the incremental path.

---

## 7. Incremental vs. Full Equivalence (Specified)

- Incremental scoring and full-board scoring must produce equivalent results for
  the same board state.
- This equivalence must be testable. See ADR-007.

---

## 8. Open Items

- **Connectivity / first-tile rule** - owned by ADR-006.
- **Affected-region definition** - the exact set of cells considered "affected"
  depends on the eventually-decided hand and cluster rules (sections 03 and the
  related ADRs).

---

## 9. Testing Requirements

Per `AGENTS.md` section 16, the board system should be covered by tests:

- Valid placement into an empty in-bounds cell.
- Rejection of placement into an occupied cell.
- Rejection of out-of-bounds placement.
- Adjacency computed correctly for edge and corner cases.
- Incremental score equals full-board score for the same board state.

---

## 10. Status Summary

| Area | Status |
|---|---|
| 12x12 grid, occupancy and orientation tracking | Specified |
| Empty-cell placement, snap-to-grid, rotation respect | Specified |
| Orthogonal adjacency tracking | Specified |
| Incremental affected-region identification | Specified |
| Full-board scoring path | Specified |
| Coordinate convention | Proposed (pragmatic) |
| Connectivity / first-tile rule | Open - ADR-006 |
| Exact affected-region set | Dependent on ADR-003 / ADR-009 |
