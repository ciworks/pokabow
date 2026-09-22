# 05 - Mobile UX & Feedback

**Status:** Specified (interaction and feedback), visual style unspecified.
**Source of truth:** `docs/GAME_SPEC.md` section 7, `AGENTS.md` section 8.

---

## 1. Device Target

- The game is mobile-first.
- Readability and usability on mobile screens are requirements, not polish.
- Desktop input may exist as a development convenience, but mobile interaction
  remains the design priority (`AGENTS.md` section 8).

---

## 2. Input Model (Specified)

| Interaction | Purpose |
|---|---|
| Tap | Select a tile (from the hand or the board). |
| Drag | Move the selected tile across the board. |
| Rotation button and/or gesture | Change the tile's orientation. |

Supporting behaviors (Specified):

- Placement snaps to the grid.
- Valid placements are highlighted.
- Feedback confirms the tile's current position before committing.

---

## 3. Placement Feedback (Specified)

- Highlight valid placements.
- Provide clear feedback for tile positioning.
- Support snap-to-grid behaviour.

---

## 4. Edge and Cluster Feedback (Specified, style open)

- The game must visually communicate edge matches.
- The game must visually communicate edge clusters.
- The source specification suggests animation and particle effects.
- The exact visual style is **not specified**.

---

## 5. Score Feedback (Specified)

- Floating score popups for poker-hand points.
- Floating score popups for edge bonuses.

Score popups and effects respond to game events; they must not calculate whether
a move is valid or how much it is worth (`AGENTS.md` section 19).

---

## 6. Haptics (Specified)

- Optional haptic feedback is supported.
- Haptics must not be required for the core game to be playable.

---

## 7. UI Architecture Boundary

UI reflects game state rather than duplicating game rules:

```
Game State -> Turn Manager -> UI Controller -> HUD / Board UI / Score UI
```

(`AGENTS.md` section 19)

---

## 8. Open Items

- Exact visual style (colors, tile art, animation language) - unspecified.
- Screen orientation policy (portrait vs. landscape) - unspecified.
- Exact rotation gesture vocabulary - unspecified beyond "button and/or gesture".
- Thresholds for drag-to-commit vs. drag-to-cancel - unspecified.

These are UX/visual details. They do not change game rules but should be
captured before implementation polish.

---

## 9. Status Summary

| Area | Status |
|---|---|
| Tap / drag / rotate input model | Specified |
| Snap-to-grid and valid-placement highlighting | Specified |
| Edge and cluster visualization (requirement) | Specified |
| Floating score popups | Specified |
| Optional haptics | Specified |
| Visual style, orientation, exact gestures | Open - not specified |
