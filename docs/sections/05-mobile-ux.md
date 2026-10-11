# 05 - Mobile UX & Feedback

**Status:** Specified interaction and feedback; staged-line presentation decided by ADR-011 and the owner's 2026-09-22 direction, then implemented; visual style remains open.
**Source of truth:** `docs/GAME_SPEC.md` section 7, `AGENTS.md` section 8, ADR-011 section 11, owner direction of 2026-09-22.

---

## 1. Device Target

- The game is mobile-first.
- Readability and usability on mobile screens are requirements, not polish.
- Desktop input may exist as a development convenience, but mobile interaction
  remains the design priority (`AGENTS.md` section 8).
- Portrait-only (owner decision, 2026-10-05): fixed portrait device orientation,
  a 540x960 reference canvas, and aspect-preserving scaling. Wide windows show
  a portrait play area with side bars. The game screen never enables sensor
  rotation or restores a landscape orientation on exit.
  Validation: 243 scene assertions and five portrait configuration assertions
  passed. Rendering checks passed at five phone/wide-window sizes; the portrait
  canvas remained 540x960 throughout. Android device-rotation QA is still open;
  re-export and reinstall the APK to apply the orientation setting.

---

## 2. Input Model (Specified)

| Interaction | Purpose |
|---|---|
| Tap | Select a tile (from the hand or the board). |
| Drag | Move the selected tile across the board. |
| Rotation button and/or gesture | Change the tile's orientation. |
| Difficulty picker (slide-out menu) | Choose the rival's policy (Easy, Medium, or Hard) - `04-ai-system.md` section 2 and ADR-005 sections 4 to 6. |

Supporting behaviors (Specified):

- Placement snaps to the grid.
- Valid placements are highlighted.
- Feedback confirms the tile's current position before committing.

Board navigation (owner direction, 2026-10-06; implemented): the board opens
at 2x, with one-finger dragging away from staged tiles panning the clipped grid.
Two fingers starting on the board smoothly pinch between 1x (the full 12x12
board) and 2x, keeping the board point between the fingers anchored as they move,
subject to board-edge clamping. The existing plus/minus buttons retain their
2x/1x steps and reflect the current zoom limits. A pinch cancels tile-drag
feedback without changing staged tiles; all fingers must lift before another
tile gesture starts. Navigation remains available outside the human turn.
The configured `mouse_wheel_zoom_in` and `mouse_wheel_zoom_out` actions use the
same 2x and 1x steps as the plus/minus buttons. At either zoom limit, the
corresponding wheel action leaves the view unchanged.
Validation: 27 synthetic-touch assertions and 243 focused UI assertions passed
on the installed Godot 4.7.2 engine, plus 47 board-geometry assertions. The wider
game-screen suite still reports startup/save-state issues and an obsolete
`LineResult.is_legal()` test call. Godot 4.6 execution and physical-device
multi-touch verification remain outstanding.

---

## 3. Placement Feedback (Specified)

### Hub destination buttons (implemented, 2026-10-10)

Achievements, My Profile, and Shop share a responsive horizontal container with
16px outer margins, 8px gaps, and 64px-tall touch targets. Label sizes adapt from
14px to 24px to keep the complete text visible as the viewport changes. Layout
and existing button actions were checked on Godot 4.7.2 at 320x568, 360x800,
540x960, 844x390, and 1280x720; the 320px and 540px renders were visually reviewed.
Physical-device touch testing remains outstanding.

### New-match rival reveal (implemented)

Selecting **New Game** opens a pre-match scene with the player's default avatar,
a centered **vs** title styled like the game-over title, a difficulty picker,
and a rival portrait. After choosing Easy, Medium, or Hard and starting the
selection, the portrait cycles quickly through all images in the matching
`rival/easy`, `rival/medium`, or `rival/difficult` folder, then eases to a random
image. After a short reveal, the board opens with that portrait and the selected
AI difficulty. **Resume** skips the reveal and restores the saved match. Empty
difficulty folders fall back to the existing shared rival portraits until new
art is imported.

Suggested portrait filenames use a descriptive character slug and a zero-padded
sequence, such as `rival_easy_copper_001.png`, `rival_medium_sable_001.png`, and
`rival_difficult_onyx_001.png`. The loader sorts filenames for stable spin order;
it selects by folder and does not require a particular filename pattern.

### Game screen layout (owner direction, 2026-09-29)

Implemented from `assets/images/game_design_screens_with_accordian_sidemenu.png`:

- Toast notices are vertically centered and span the full game viewport width
  (owner direction, implemented 2026-10-11). They use `assets/ui/toast_banner.png`
  with preserved top/bottom borders, centered wrapping text, and a fade around
  the existing four-second hold. The banner grows with its text and ignores
  pointer input. Wide windows retain the portrait canvas and side bars.

- The game background uses `assets/ui/default_background.png` in a full-screen
  TextureRect behind the interface. It preserves aspect ratio and crops to fill
  portrait or landscape, and ignores pointer input.

- The title is the straight **POKABOW** logo from
  `assets/branding/pokabow-header-logo-v2.png` (implemented 2026-10-05). An
  AtlasTexture excludes transparent margins without changing the source image.
  A 48px header row reserves equal space on both sides, including the settings
  button on the right, so the aspect-fitted logo centers on the screen. The row
  stays visible in the portrait canvas, which scales uniformly to the available
  window without distorting the board or rack.

- Header: red player score, one shared Tile Pot panel containing the pile and a
  single remaining-tile count, then blue rival score. The active player's card
  retains its turn outline. The human score card always uses the label "You".
- The human score panel uses `assets/ui/avatar_panel_default.png` with
  `assets/board/characters/avatar_default.png` overlapping its left side,
  following the player card in `assets/images/board_game_design.png`. The live
  "You" label and live score sit to the right, with an extra 5px of padding
  above the label and below the score; the portrait scales to the available width,
  and the active-turn outline follows the score plate. Implemented 2026-10-01.
- The rival score panel mirrors this composition using
  `assets/ui/avatar_panel_rival.png` and
  `assets/board/characters/avatar_default_rival.png`: the portrait overlaps the
  right edge, with "Rival" and the live score on the left. Both panels share the
  responsive layout, extra vertical padding and active-turn outline behavior.
- The shared tile pot uses `assets/ui/tile_pot.png`, following
  `assets/images/tile_pot_example.png`. A NinePatchRect using the human avatar
  panel texture holds the live remaining-tile count, with "tiles left" below.
  Transparent source margins are excluded for sizing; deals originate at the
  bag opening. The pictured cards are decorative and do not reveal bag contents.
  Deal animation endpoints follow the live pot opening and deck-slot rectangles
  throughout flight, hold, and flip. Container layout changes and scaling therefore
  cannot leave a tile below the rack before its face is revealed (2026-10-10 fix).
  Validation: 856 focused assertions passed on Godot 4.7.2. The reproduced 146px
  landing offset became 0px across five rendered startup frames, and the face-down
  tiles were visually verified inside the rack. Physical-device testing remains open.
- The bag art is drawn 25% larger than its header slot, cropped to the artwork's
  visible pixels so the source's empty margins do not shrink it. Its base is
  shifted slightly below the slot: at that size the bag is taller than the slot,
  and the slot ends 12px above the board's outer border, so the shift is what
  keeps the whole bag clear of that border without pushing its top off screen.
  `assets/ui/tile_pot_shadow.png` is drawn beneath it, centred on the bag's base,
  so the shadow's upper half sits behind the bag and its lower half crosses onto
  that border.
  The pot sprite is drawn 25% larger than its slot and sits 25% of its own height
  below the slot's top, so its lower quarter crosses the game board's top border.
  The slot panel paints no background of its own (`StyleBoxEmpty`) and the header
  container does not clip, so the enlarged sprite is drawn whole, over the board
  frame, and never intercepts board input.
- The square 12×12 board occupies the central play area; the tile rack sits below.
  All empty cells use a solid `#333333` fill with rounded corners; colored
  decorative cells are removed (owner direction, 2026-10-06). The backing/grid
  lines use `#17212b`. Gameplay highlights still overlay the cells as needed.
  The game preserves the portrait canvas when the physical window is wide.
  Closing the game screen restores the shell's portrait canvas settings.
- The bottom tile rack uses `assets/ui/board_deck.png`, preserving its artwork
  proportions, rails, and base. An AtlasTexture excludes only transparent outer
  margins so the visible tray matches the stationary board frame's width,
  including during pan/zoom (owner direction, 2026-10-06). Height follows that
  width instead of limiting the artwork to a fixed height. Square tiles sit in
  the wood recess with equal horizontal gaps, including the left/right gaps,
  and equal top/bottom padding. Tile size is calculated for a full six-tile hand
  and stays the same as tiles leave the rack; remaining tiles redistribute evenly.
  Touch targets fill the deck row's full height, including space around the tiles.
  Gaps are split at the midpoint between neighboring tile centers; outer tiles
  extend to the row edges, and a single remaining tile owns the whole row.
  A press in that surrounding space selects the tile and can begin its drag
  (owner direction, 2026-10-10). Targets stay inside the deck row.
  Expanded-target validation: 772 focused assertions passed on Godot 4.7.2,
  covering one-to-six-tile hit regions at three sizes, padding-to-board drags,
  rotation, interaction gating, and the 60-second timer. Physical-device touch
  verification remains outstanding.
  Validation: rendered checks passed at five phone/wide-window sizes, including
  board/tray width alignment, square tiles, equal spacing for one through six
  tiles, and matching tap targets. The 320x568 and 540x960 captures were visually
  inspected; 270 focused interaction assertions passed on Godot 4.7.2.
  Physical-device touch verification remains outstanding.
- Only the top settings icon opens the command menu; there is no right-edge tab.
- The active avatar panel's yellow border is the 60-second turn timer (ADR-017).
  One equal-length perimeter segment disappears each second, clockwise from the
  top-left straight edge. At expiry the remaining yellow disappears and the next
  player's border becomes full. Opening settings does not pause the clock.
  From 10 seconds remaining, the active avatar and score panel shake together
  once per displayed second (10 through 1), stopping at zero. Duplicate updates
  in the same second do not restart it. Reduced-motion mode suppresses the shake.
  The drawer starts below the score cards;
  commands scroll on shorter screens while its title and close button stay visible.
  Close, an outside tap, or Escape dismisses it. Covered board input is consumed.
  The close button uses `assets/ui/close.png` with a 44-pixel minimum tap target.
- The drawer contains move preview, status, and match settings. Play move,
  Rotate tile, Swap tiles, and Clear placement are not drawer buttons. During a
  swap it offers Return selected tiles and Keep tiles. Tile rotation remains
  available by tapping the selected rack tile or a staged tile.
- Move preview reports the controller's read-only hand, edge, cluster, and total
  points. It uses the same scorer as committing. Invalid or absent hands show
  dashes. Card and edge multipliers are already included in the hand score.
- Rival difficulty, New match, Resign, and Back to hub are shown in the drawer,
  with no Match settings toggle. Resign opens a confirmation dialog that asks
  "Are you sure you want to end the game?" and warns "This will be marked as a
  Loss." Yes ends the match and records the rival as winner; No dismisses the
  dialog. Resign is disabled after the match ends.
- The game screen has a classic bottom tab bar (owner direction, implemented
  2026-10-06): a flat, full-width surface anchored to the bottom of the portrait
  canvas, with a subtle top divider and five equal-width touch targets. Each
  icon sits above its label; hover, press, and keyboard focus have distinct
  feedback. The content reserves space above the bar so the rack stays clear.
  The bar retains the existing action commands, with icons above Play,
  Skip, Swap, Undo, and Quit. Play uses Play move; Swap starts tile selection.
  While selecting, Swap stays disabled and the settings icon opens the menu's
  Return selected tiles / Keep tiles controls. Undo uses Clear placement (all
  unplayed tiles, never a committed move).
  Quit uses Back to hub. Skip has no corresponding menu command and stays disabled
  with no action connected. Availability follows controller state and inactive items
  appear gray and dimmed.
  Validation: 270 focused interaction assertions passed on Godot 4.7.2. Rendered
  layout checks passed at 320x568, 360x800, 540x960, 1280x720, and 844x390;
  the 320x568 and 540x960 captures were visually inspected. Device touch QA
  remains open.
- Interface text uses Bahnschrift with Segoe UI and DejaVu Sans fallbacks.
  Tile artwork, tile fonts, and tile painting are unchanged by this layout.

Validation: focused scene/controller tests and rendered portrait/landscape
captures are covered by `tools/check_game_layout.gd` and
`tools/preview_game_layout.gd`. Physical-device touch QA remains open.

Logo integration validation (2026-10-05): `tools/preview_header_logo.gd` rendered
320x568, 360x800, 540x960, 1280x720, and 844x390, including a return to portrait.
Centering, preserved logo aspect ratio, settings clearance/click routing, board
squareness, major control bounds, and visible rack tiles passed. Rendered
screenshots were visually inspected. Existing layout checks passed 152
assertions. These checks use the desktop engine; physical-device touch testing
has not been performed.

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
- While dragging from the deck, the source tile and moving preview use 90% of
  the deck tile's normal width and height (owner direction, 2026-10-10). The nearest cell
  under the pointer uses the gold frame from `assets/tiles/tile_highlight.png`,
  replacing the red border (owner direction, 2026-10-10). Its opaque center is
  omitted so existing tiles remain visible, including over occupied cells;
  the existing legal/illegal fill still shows whether the drop is accepted.
  The preview follows the pointer continuously in a screen-level overlay, including
  the space between the deck and board. It keeps the same size across board zoom
  levels. Leaving the board clears only the target; the tile stays under the pointer.
  An accepted release snaps the tile into the highlighted cell at normal board size.
  Invalid/off-board releases and cancellation clear the overlay without placing it.
  Validation: 838 focused assertions passed on Godot 4.7.2, including fractional
  pointer movement within a cell, movement outside the board, and cleanup on drop
  or cancellation. A 540x960 rendered frame confirmed the freely positioned tile
  and grid-aligned gold artwork with a transparent center. Physical-device touch
  testing remains outstanding.
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

- every scoring group is outlined in green around its tiles' outer perimeter,
  using a stroke half as thick as the previous per-tile outline. Shared sides
  between adjacent tiles are left unstroked, so an edge group reads as one area;
- paying clusters outline the whole connected component. Edge-match scoring does
  not outline matched pairs, either during preview or after play. Poker hands
  bounce after play without a tile outline;
- cluster marks are driven by committed `ScoreEvent`s, so the reveal and
  combined floating total describe the same awards and neither recomputes a rule
  (section 7). Edge-match points and poker-hand points remain visible in the
  floating score UI without outlining played tiles;
- the reveal holds, fades, and clears, and is dropped when the board is torn
  down, so nothing outlives the match or an interrupted animation.

The edge/cluster marks are transient - they answer "what did that move score"
as the move lands. Played-line outlines are not drawn.

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

- One total score popup per played move, including all poker-hand points,
  edge matches, and cluster bonuses (owner direction, 2026-10-11).

Score popups and effects respond to game events; they must not calculate whether
a move is valid or how much it is worth (`AGENTS.md` section 19).

### Current implementation (Implemented, not heard on a device)

`FloatingScores` shows one total per move, without a `+` prefix, by summing the committed `ScoreEvent`
points. The popup and edge/cluster reveal describe the same awards; scoring rules
are not recalculated. The value uses the game screen font at 55 points (half
the previous 110), white with an 8-pixel black outline. It flashes once,
briefly holds, then fades away while rising, over 1.15 seconds. Its measured
bounds keep it inside the screen. Reduced motion holds the value without flashing
or moving, then removes it after the same duration. Moves with no points show
no popup.

The score moment also carries a sound and a vibration (section 6). Both follow the
committed event, not the button press.

Validation (2026-10-11): 31 focused assertions passed on Godot 4.6, covering
combined awards, separate moves, empty awards, styling, and a real committed
move. A rendered preview verified the flash, disappearance, large-total bounds,
and reduced motion; the white outlined value was visually inspected. The broader
game-screen suite still reported app-startup and save-related issues.
Physical-device visual verification remains open.

### Match-end celebration (Implemented, device visual QA open)

When a match ends, `ConfettiLayer` streams confetti down the screen while the
summary panel is up. The screen starts it in `_on_match_ended`, the same call that
shows the summary, so the stream runs because a match ended rather than because
the layer decided one had; a new session clears it.

The layer draws beneath the summary overlay and ignores the pointer, so the panel
that reports who won stays readable and keeps every tap. Its pieces are a fixed
pool recycled above the top rather than nodes added per frame, and its colours are
its own set - deliberately not `TilePainter.EDGE_COLORS`, so a celebration cannot
be read as an edge match.

The stream is not tuned, and it has not been watched on a device.

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

## 7. Accessibility (Specified, partially implemented)

The specification requires an accessibility pass over colour differentiation, text
size, and reduced motion. Edge-colour matching IS the scoring mechanic, so a
board that signals a match with colour alone is a playability gap rather than a
cosmetic one.

### Current implementation

**Colour.** `TilePainter.EDGE_COLORS` is an Okabe-Ito palette, chosen so the two
colours a red-green colour blindness collapses - the previous red and green -
separate under the common confusion pairs. The palette is the single source of
truth for edge colour and has one consumer, so a region, an outline and a tile
edge can never be drawn in different blues.

The four top-edge overlays under `assets/tiles/edges/` are tinted by that palette
rather than drawn as authored. This is required, not cosmetic: the painter draws
`tile_<colour>_top.png` INSTEAD of the colour band whenever the file exists, so a
palette-only change would have recoloured three sides of every tile and left the
fourth - the most visible one - stale.

Colour remains the only edge channel by owner decision. A redundant pattern
encoding was considered and declined, so this palette helps the red-green
confusion pair but not every vision type; a board readable without colour at all
would need that pattern layer.

**Reduced motion.** `AccessibilitySettings.REDUCED_MOTION_SETTING`
(`accessibility/reduced_motion`, default false, matching how the feedback
channels are switched) is read by each layer that animates, at the point it
starts an animation. With it on:

- `ScoreRevealLayer` still marks which tiles scored and still holds the marks for
  the full `HOLD`, but nothing bounces and nothing fades. The timer is kept as a
  plain wait so the player is not rushed past the information;
- `FloatingScores` still shows every award and still removes it, but the label
  does not drift upward;
- `DealLayer` completes at once, reporting every tile as revealed so the deck row
  unconceals in one step through the row's own path rather than this layer
  painting a deck of its own;
- `ConfettiLayer` stays empty, so the summary reports the same winner with no
  falling pieces.

Reducing motion changes no point awarded, no turn, and no board cell: the same
committed events are shown, only without movement. Nothing reads the setting on a
rule path.

**Text size.** Not yet addressed. The font sizes in use are inventoried - the
game screen runs from 15 to 34 px and the splash from 20 to 56 px at the 1280x720
target viewport - but no legibility floor has been agreed, so none has been
changed. Raising the smallest HUD labels is a visual decision that cannot be
verified from a headless run, and it is deliberately left open rather than
guessed at.

---

## 8. UI Architecture Boundary

UI reflects game state rather than duplicating game rules:

```
Game State -> Turn Manager -> UI Controller -> HUD / Board UI / Score UI
```

(`AGENTS.md` section 19)

---

## 9. Open Items

- Exact visual style (colors, tile art, animation language) - unspecified.
- Exact rotation gesture vocabulary - unspecified beyond "button and/or gesture".
- Thresholds for drag-to-commit vs. drag-to-cancel - unspecified.

These are UX/visual details. They do not change game rules but should be
captured before implementation polish.

---

## 10. Status Summary

| Area | Status |
|---|---|
| Tap / drag / rotate input model | Specified |
| Snap-to-grid and valid-placement highlighting | Specified |
| Staged-line board/deck transfer | Decided by ADR-011; implemented and headless tested |
| Edge and cluster visualization (requirement) | Implemented: transient edge/cluster reveal plus a persistent cluster display; played poker hands receive no board highlight |
| Floating score popups | Implemented; one flashing total per move |
| Optional haptics | Implemented via `FeedbackAdapter`; device feel unverified |
| Cue sound | Implemented for all five cues; confirmed audible in play by the owner |
| Accessibility - colour | Okabe-Ito edge palette governs all four sides; colour remains the only channel by owner decision |
| Accessibility - reduced motion | Implemented via `accessibility/reduced_motion`; changes movement only, never a point or a turn |
| Accessibility - text size | Inventoried (15-34 px at the 1280x720 target); unchanged pending an agreed legibility floor |
| Rival difficulty selection | Implemented - HUD picker writing to `set_ai_difficulty()`; device QA open |
| Screen orientation | Decided and implemented: portrait-only; device validation pending |
| Visual style, exact gestures | Open - not specified |
