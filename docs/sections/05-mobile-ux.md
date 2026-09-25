# 05 - Mobile UX & Feedback

**Status:** Specified interaction and feedback; staged-line presentation decided by ADR-011 and the owner's 2026-09-22 direction, then implemented; visual style remains open.
**Source of truth:** `docs/GAME_SPEC.md` section 7, `AGENTS.md` section 8, ADR-011 section 11, owner direction of 2026-09-22.

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
| Difficulty picker (HUD) | Choose the rival's policy (Easy, Medium, or Hard) - `04-ai-system.md` section 2 and ADR-005 sections 4 to 6. |

Supporting behaviors (Specified):

- Placement snaps to the grid.
- Valid placements are highlighted.
- Feedback confirms the tile's current position before committing.

---

## 3. Placement Feedback (Specified)

- Highlight valid placements.
- Provide clear feedback for tile positioning.
- Support snap-to-grid behaviour.

### Current staged-line interaction (Decided, implemented, headless tested)

- Nothing is selected straight after the deal. A dealt hand is the player's own to
  choose from, so the row draws no tile as selected until the player taps one, and
  no tile is armed for a staging command. Tapping a deck tile selects it; a second
  tap on the tile already selected turns it one quarter-turn, so the player can see
  the orientation before placing it.
- A tile reaches the board only by being dragged there from the hand. Tapping an
  empty board cell stages nothing, because the tile that lands on a cell is always
  one the player lifted from their own hand: a misplaced tap can no longer spend a
  tile the player never chose.
- A staged tile is drawn at its board cell even when the pending line is not yet
  legal. The incomplete or illegal line keeps its validity marker and reason.
- The visible deck row shows only tiles that have not been staged. The player
  selects which held tile a further board tap stages.
- A tile already on the board but not yet confirmed can be adjusted by picking it up.
  Pressing a staged board cell and releasing on the same cell turns that tile one
  quarter-turn; releasing on a different free cell moves it there, keeping the tile
  and its rotation; releasing off the board removes that one tile from the pending
  line and shows it in the deck row again. The gesture is resolved on release,
  because at press time it could still become any of the three. Cancel removes the
  entire pending line and restores the visible deck row.
- Staging and un-staging do not commit a board tile or consume a turn. The match
  deck retains the tile until the complete line is confirmed atomically.

This behavior is implemented in `GameSessionController`, `GameScreen`, and
`BoardPreviewLayer`. The headless game-screen integration tests cover the staged
tile identity, visible deck counts, un-staging, cancel, and unchanged board
revision. Visual appearance on a device has not been manually verified.

---

## 4. Edge and Cluster Feedback (Specified, style open)

- The game must visually communicate edge matches.
- The game must visually communicate edge clusters.
- The source specification suggests animation and particle effects.
- The exact visual style is **not specified**.

### Current implementation (Implemented, headless tested, device visual QA open)

`ScoreRevealLayer` draws the award itself rather than only its point value:

- every scoring group is outlined around its tiles' outer perimeter in one
  high-contrast colour, so the tiles that earned are unmistakable against the
  tile art. The outline traces the outside of the group rather than boxing each
  tile, so an adjacent pair reads as one joined shape and a cluster reads as one
  region;
- the three categories are covered: an edge match outlines the pair that matched,
  a paying cluster outlines the whole connected component, and a poker hand
  outlines the hand's tiles. The first version dashed a bar across the join
  between two tiles and omitted poker hands entirely, which the owner reported as
  too unclear to read;
- a poker hand's tiles also bounce in sequence - each tile lifts and settles in
  turn - because the outline alone does not convey the order the hand reads in;
- the marks are driven by the committed `ScoreEvent`s, so the reveal and the
  floating points always describe the same award and neither can recompute a
  rule (section 7);
- the reveal holds, fades, and clears, and is dropped when the board is torn
  down, so nothing outlives the match or an interrupted animation.

The marks are transient - they answer "what did that move score" as the move
lands.

### Persistent cluster display (Implemented, Phase 2, device visual QA open)

The transient reveal is now joined by a persistent one. `ClusterDisplayLayer`
outlines every connected same-colour region the committed board holds, at all
times rather than only when a move lands, so the player can read the regions they
are building toward instead of reconstructing them from memory.

- The regions come from `GameSessionController.current_edge_clusters()`, which
  enumerates them with `EdgeClusterScorer.components_for_color` - the same tested
  flood fill and vertex test the ledger is scored from. The layer compares no edge
  colour and floods nothing, so the regions it draws cannot disagree with the
  regions that score (`AGENTS.md` section 19).
- Each region is drawn as one merged perimeter in that region's own edge colour,
  taken from `TilePainter.edge_color_for`, over a faint wash of the same colour.
  The perimeter leaves internal boundaries unstroked, so a two-tile region reads
  as one area rather than as two outlined cells.
- It is deliberately subordinate to the transient reveal: a thinner stroke, a
  lower alpha, and an earlier position in the draw order, so the reveal always
  paints over it. The two answer different questions and can be on screen at once.

### Rotation hints (Implemented, Phase 2, device visual QA open)

The staged line's rotatable tile now carries a hint about what rotating would
change: a short mark on each of its edges that currently matches the adjacent
committed tile, and nothing on the edges that do not. It is a read-out of the
adjacencies that exist right now, not a score prediction - no points are shown and
no rotation is recommended, because recommending one would invent a rule the
specification does not contain (`AGENTS.md` section 3).

The verdicts come from `GameSessionController.staged_edge_matches()`, derived from
`EdgeMatchScorer.matching_color`, so the hint and the scoring rule cannot drift.

Both features are presentation over existing state: neither adds a point, advances
a turn, or mutates a board cell, and no file under `scripts/domain/` was changed.

Visual appearance of either on a device has not been manually verified.

Visual appearance on a device has not been manually verified.

---

## 5. Score Feedback (Specified)

- Floating score popups for poker-hand points.
- Floating score popups for edge bonuses.

Score popups and effects respond to game events; they must not calculate whether
a move is valid or how much it is worth (`AGENTS.md` section 19).

### Current implementation (Implemented, not heard on a device)

`FloatingScores` plays one popup per committed `ScoreEvent`, in the deterministic
order the ledger recorded them, so the popups and the edge/cluster reveal both
describe the same award from the same list. A move that scores several categories
staggers its popups rather than overlapping them into one.

The score moment also carries a sound and a vibration (section 6). Both follow the
committed event, not the button press.

Floating-score sequencing - exact timings, staggering, and easing - is not tuned.

---

## 6. Haptics and Sound (Specified)

- Optional haptic feedback is supported.
- Haptics must not be required for the core game to be playable.

### Current implementation (Implemented, headless-safe, device QA open)

Both channels live in one injected service, `FeedbackAdapter`, created by `AppRoot`
and handed to the screen (`ADR-008` section 5). It is the platform feedback adapter
the architecture already named, so nobody reaches for a global.

Five moments cue: selecting a deck tile, placing or committing a line, being
awarded points, a refused gesture, and the end of the match. Each carries a
vibration length and a short one-shot sound.

- **Optional, as specified.** Haptics and sound are separately switchable at
  runtime and by project setting (`feedback/haptics`, `feedback/audio`), and each
  falls back to a silent no-op. No rule, score, or turn path reads either channel,
  so a match plays identically with both off. That is what makes them optional
  rather than required.
- **Only the player's own actions cue.** The controller emits `line_committed` and
  `score_awarded` for the rival's move too, and a subscriber would therefore buzz
  the player's phone for something they did not do. The screen calls the cues at
  the point a human gesture resolved instead.
- **Sounds are loaded once** and cached, never inside a cue, because a cue fires
  while the player is mid-tap. A missed or absent sound caches as silence rather
  than being retried or logged as a fault.
- **The sound pool holds six voices.** A single player would cut each score chime
  off with the next one, which hears as a clipped click rather than a reward.

The five one-shots are a few tens of KB each. Whether they sound right in play,
and whether the vibrations read well on a real handset, has not been verified -
neither channel can be judged from a headless run or a still frame.

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
| Staged-line board/deck transfer | Decided by ADR-011; implemented and headless tested |
| Edge and cluster visualization (requirement) | Implemented: transient reveal on award plus a persistent cluster display; exact visual style still open |
| Floating score popups | Implemented; sequencing not tuned |
| Optional haptics | Implemented via `FeedbackAdapter`; device feel unverified |
| Cue sound | Implemented for all five cues; not heard on a device |
| Rival difficulty selection | Implemented - HUD picker writing to `set_ai_difficulty()`; device QA open |
| Visual style, orientation, exact gestures | Open - not specified |
