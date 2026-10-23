# 05 - Mobile UX & Feedback

**Status:** Specified interaction and feedback; staged-line presentation decided by ADR-011 and the owner's 2026-09-22 direction, then implemented; Modern Tabletop visual standard Decided on 2026-10-17 (ADR-020); hub/settings adopted, other screen migrations pending.
**Source of truth:** `docs/GAME_SPEC.md` section 7, `AGENTS.md` section 8, ADR-011 section 11, owner direction of 2026-09-22.

---

## Approved visual standard

[Modern Tabletop](../DESIGN_SYSTEM.md) governs new and redesigned UI elements,
pages and layouts. [ADR-020](../decisions/ADR-020-modern-tabletop-design-system.md)
records owner approval. The historical implementation notes below describe what
was built and tested at their stated dates; older colours, artwork, fonts and
layout styling are not an alternative standard. Preserve their functional
behaviour while applying the new visual guidance. Current adoption is recorded in [the design system](../DESIGN_SYSTEM.md#runtime-adoption);
the hub and its settings have now migrated. Historical notes below retain their
original implementation context.

## 1. Device Target

- The game is mobile-first.
- Readability and usability on mobile screens are requirements, not polish.
- Desktop input may exist as a development convenience, but mobile interaction
  remains the design priority (`AGENTS.md` section 8).
- Portrait-only (owner decision, 2026-10-05): fixed portrait device orientation,
  a 540x960 reference canvas, and aspect-preserving scaling. Responsive portrait
  update (2026-10-12): window/stretch/aspect="keep_width" lets taller phones
  expand the logical canvas vertically without top/bottom letterboxing or
  distorted tiles. Wide windows show a portrait play area with side bars. The game screen never enables sensor
  rotation or restores a landscape orientation on exit.
  Android export fix (2026-10-12): Godot 4 requires the integer orientation enum
  (`window/handheld/orientation=1`, `DisplayServer.SCREEN_PORTRAIT`). The previous
  string `"portrait"` produced an APK manifest requesting landscape (`0`). The
  regression check now validates both the setting type and the portrait value.
  Validation: the updated check failed against the old setting; after the fix,
  245 scene assertions and six portrait configuration assertions passed. A signed
  debug APK exported successfully and its manifest requests portrait (`1`).
  Responsive validation: 54 additional assertions passed headlessly and with
  rendering at 540x960, 360x800, 540x1200, 720x1600, 1080x2400, and 1280x720,
  including a return to tall portrait and a return from a match to the hub.
  The 1080x2400 window uses a 540x1200 logical canvas; board proportions, rack
  visibility, bottom navigation, drawer bounds, and game-over coverage passed.
  Tall portrait gameplay, hub, and game-over captures were visually checked.
  Physical Redmi 10 display/cutout and device-rotation QA remain open; install
  the newly exported APK to apply the settings.

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
The game screen shows **6 columns**, with the visible row count following the
available board-window height (reference-layout redesign, 2026-10-15). Cells stay
square. Zooming out fits the complete 12x12 board. Standalone board views retain
the earlier 6x8 default.
The 6x8 change passed 116 geometry and gesture assertions on Godot 4.6, with
the rendered 360x800 screen confirmed to show exactly six columns and eight rows.
Two fingers starting on the board smoothly pinch between 1x (the full 12x12
board) and 2x, keeping the board point between the fingers anchored as they move,
subject to board-edge clamping. The top-left plus/minus buttons were removed
by owner request (2026-10-15). A pinch cancels tile-drag
feedback without changing staged tiles; all fingers must lift before another
tile gesture starts. Navigation remains available outside the human turn.
The configured `mouse_wheel_zoom_in` and `mouse_wheel_zoom_out` actions use the
adaptive close-view and full-board 1x steps. At either zoom limit, the
corresponding wheel action leaves the view unchanged.
Placement focus (owner direction, 2026-10-17; implemented): an accepted tile
drop in the full-board 1x view switches immediately to the widest close view
that fits the viewport while keeping at least 64 logical pixels per cell, up to
2x, and centers the placed tile as far as board-edge clamping allows. This includes
moving an already staged tile to a new cell. The camera changes after release
and acceptance, never while aiming. Refused drops, rotation, and rack returns
leave the camera alone. Placements at 2x or an intermediate pinch zoom retain
the player's current zoom and pan.
After a hand commits, the camera waits for score highlights, point popups, and
tile redistribution to finish, then returns to the centered 1x overview
(owner direction, 2026-10-17). Both players' committed hands use this behavior;
the opening deal and swaps alone do not trigger it. Partial/empty-pot refills
and reduced motion use the same completion check. Starting a new placement
supersedes any pending reset, and restarting clears it.
Restoring a saved match from the hub opens at the centered full-board 1x
overview; starting a new match retains the close view.
After the player's score and any replacement tiles have settled, the centered
overview remains visible for three seconds with “Rival is thinking...” before
the AI starts its move. Rival placement animation keeps the camera on the full
board overview rather than focusing the rival's tiles (owner direction,
2026-10-17).
The close view shows as many columns as the available viewport width allows at
that cell size, capped at the board's 12 columns. Wider and narrower layouts
therefore adapt their visible column count instead of always using six.
Hand-completion validation: 2,256 regression assertions passed on Godot 4.6,
including both scoring/refill completion orders, rival flights, partial and
empty refills, reduced motion, and reset cancellation. Rendered 540x960 frames
confirmed the close scoring view followed by a centered full-board overview.
Physical-device touch verification remains outstanding.
Placement-focus validation: 2,206 assertions passed on Godot 4.6 across the
game-screen, online-play, board-geometry, and rack-input suites. Tests cover
accepted/refused drops, staged-tile movement, rotation, corner clamping at
three viewport sizes, and preservation of close/intermediate views. Rendered
540x960 frames verified center and corner placements. Physical-device touch
verification remains outstanding.
Validation: 27 synthetic-touch assertions and 243 focused UI assertions passed
on the installed Godot 4.7.2 engine, plus 47 board-geometry assertions. The wider
game-screen suite still reports startup/save-state issues and an obsolete
`LineResult.is_legal()` test call. Godot 4.6 execution and physical-device
multi-touch verification remain outstanding.

Resume layout fix (2026-10-14): the rack minimum height and available board
height formed a resize feedback loop. Container rounding alternated the rack
between 118 and 119 logical pixels, preventing the layout queue from draining
after the saved match had already loaded. Rack sizing now retains its current
size when both requested adjustments are at most one logical pixel.
`tools/validate_resume_layout.gd` exercises Resume, tile selection, window
resizing, and three zoom levels across actual frames using its own temporary
save. All 57 assertions passed headlessly on Godot 4.6 and 4.7.2 and with
rendering on 4.7.2. The previously freezing copied save also resumed and ran
for ten seconds with uninterrupted diagnostic heartbeats. The player's actual
save was not modified. Physical-device verification remains outstanding.

---

## 3. Placement Feedback (Specified)

### Modern Tabletop hub (implemented, 2026-10-17)

The hub follows [DESIGN_SYSTEM.md](../DESIGN_SYSTEM.md#runtime-adoption): ivory
canvas, teal typography/resume cards, honey primary actions, Fredoka fonts (updated 2026-10-18), shared
outline icons and a dedicated illustration. A container layout gives short
screens scrollable content and persistent Home / Achievements / Profile
navigation. The previous Shop placeholder is removed; account, achievements,
AI, online and per-game resume routing are retained.

Play AI is primary with no saves; Resume takes priority when games are available.
Saved-game cards keep real opponent/score data and their exact resume targets.
Settings and notices share the theme. Settings resets to the top on reopening,
and audio state is distinguished by on/off icons. Existing account deletion,
preference and server-address behaviour is retained.

Godot 4.6 validation: 332 headless and 340 rendered hub assertions passed, plus
the existing settings layout and account-deletion confirmation check. Captures
at 360×800 and 540×960, and the real 540×1200-to-360×800 stretch, were visually
inspected. Device touch and cutout testing remain open. Run
`tools/validate_hub_design.gd`; set HUB_QA_DIR to an existing output directory
for screenshots with a rendering display.

### Compact match activity and completed results (implemented, 2026-10-21)

The hub's **Your tables** panel now shows one active match and the most recently
completed result. Additional active matches and completed matches are reached
through View all. Details opens a read-only result with the outcome, final
scores, poker/edge/cluster breakdown, end reason and move count. The section
uses the approved reference and the status-dot/chevron rules in the
[design system](../DESIGN_SYSTEM.md#your-tables-and-match-history-approved-2026-10-21).

Finished AI matches are recorded from `MatchResult`; completed online responses
are converted through `OnlineSessionView` and recorded with the local player's
seat. Records are account-scoped on the device and capped at 50, with duplicate
match IDs ignored. An online-history API is still needed to populate results
completed on another device. The hub omits the latest-result row when no real
record exists. Phone layout and device touch verification remain open.

### Fredoka interface typography (implemented, 2026-10-18)

The owner selected Fredoka to replace Dosis and match the approved concept's
rounded letterforms. The shared theme uses real Regular/Medium/Semibold/Bold
variations; the existing gameplay theme uses Medium. The hub's wordmark and
headline are approximately 30px and 40px at the 390px design reference width.
The [design system](../DESIGN_SYSTEM.md#typography) records exact role sizes and
[font provenance](../../assets/fonts/fredoka/README.md) records licensing.

494 rendered hub assertions passed, including text fit and renderer weight
resolution. Gameplay board/menu captures were inspected; five gameplay-suite
failures reproduce under the previous Dosis font. See the design system's
typography adoption note for the baseline comparison and remaining device QA.

### Earlier hub destination buttons (implemented, 2026-10-10; styling superseded)

Achievements, My Profile, and Shop share a responsive horizontal container with
16px outer margins, 8px gaps, and 64px-tall touch targets. Label sizes adapt from
14px to 24px to keep the complete text visible as the viewport changes. Layout
and existing button actions were checked on Godot 4.7.2 at 320x568, 360x800,
540x960, 844x390, and 1280x720; the 320px and 540px renders were visually reviewed.
Physical-device touch testing remains outstanding.

### Profile avatar selector (visual migration, 2026-10-18)

My Profile now follows the Modern Tabletop direction: an ivory canvas, centered
cartoon avatar and account name, deep-teal controls, a three-column avatar grid,
and a honey **Save changes** action. The selected portrait has a teal outline and
checkmark. Username can be edited and saved to the authenticated account; email
remains read-only, with Refresh available for account details. The page's single
Save changes action submits the username and normalized avatar image together.
The existing Edit photo flow opens a separate Photo Avatar view with a dashed
upload target; choosing a photo switches it to a circular preview and Change
photo / Use photo actions. Back discards unsaved photo changes and returns to
the profile. Browsing and uploading only change the preview until Save changes
is pressed.
Invalid uploads preserve the current choice; failed saves keep the photo editor
open for retry. Achievement details appear only on the dedicated Achievements
page. Profile colors, typography and buttons use the shared Modern Tabletop
tokens.

Uploads accept JPG/JPEG/PNG extensions (case-insensitive), validate the actual
image content, and require at most 2 MiB with each side between 195 and 2048
pixels. Dimensions are checked before decoding. Images are center-cropped to a
square and resized to 195x195; the crop is shown before saving. The native file
picker uses both extension and MIME filters, with Godot's embedded fallback
([Godot 4.6 FileDialog](https://docs.godotengine.org/en/4.6/classes/class_filedialog.html)).

Avatar selection is preview-only until the profile's Save changes action
uploads the normalized PNG through `PUT /auth/me/avatar` and updates the
username through `PATCH /auth/me`. The existing API stores avatar bytes in
PostgreSQL and serves them to the signed-in account through
`GET /auth/me/avatar`. These are separate writes; if the username update fails
after avatar upload, the profile explains the partial success and allows retry.
The selected picture appears in the pre-match screen, game HUD, and match
results. It is not sent to online opponents.

The profile uses the Modern Tabletop cartoon roster's own circular backdrops
without an extra frame; the selected item gets a deep-teal outline and checkmark.
`FramedPlayerAvatar` continues to provide circular crops for uploaded photos and
wherever another screen enables its optional ring. Stored images and avatar
selections stay intact, and rival portraits keep their existing artwork.
Both game-screen portraits use 1.25 node scale, enlarged together by 25% from
their preceding 1.0 scale. Their centered pivots preserve vertical alignment
while retaining the circular fit. Other avatar views retain their existing
sizes. The enlargement/alignment passed
166 rendered layout assertions across five viewport sizes on Godot 4.6; the
540x960 and 360x800 previews were visually inspected.
Frame verification: 500 focused frame/profile/game-screen assertions passed on
Godot 4.6. Rendered profile and game layouts were checked at 540x960 and 360x800,
with pre-match, uploaded-photo, and results previews also inspected. Physical
device verification remains outstanding. The circular-fit revision passed all 66
frame checks, including equal opening/portrait diameters at square, tall, and
wide sizes; the rendered game, profile, and results previews were inspected.

Validation: Godot 4.6 focused avatar/profile checks pass (60 assertions), covering
format/content validation, size boundaries, crop, persistence, account cleanup,
selector wraparound, preview/save behavior, save failures, and pre-match/HUD/results
integration. Rendered profile layouts were checked at 540x960 and 360x800.
Run `godot --headless --path . --script res://tools/validate_player_avatar.gd`.
Physical-device native picker testing remains outstanding.

Design revision verification: all three states and the mobile profile were
rendered and visually checked at 540x960 and 360x800 on Godot 4.7.2. The focused
`tools/validate_profile_design.gd` runner checks default selection, photo preview,
cancellation, saving/reopening, save failures, and account refresh. It avoids
the older image-format suite's Windows-invalid trailing-dot filename fixture.

### New-match rival reveal (implemented)

Selecting **New Game** opens a pre-match scene with the player's saved avatar,
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

### Game screen layout (owner direction, 2026-10-15)

The dated layout notes below record earlier implementations. Current gameplay
layout and controls follow `docs/DESIGN_SYSTEM.md` and the Pot amendment above.

Implemented using `assets/images/scrabble_idea.png` for placement and relative
sizing only; the existing background, red/blue player artwork, wooden rack,
and charcoal board palette are retained.

- Notifications use the existing top turn-status label (owner request,
  2026-10-15). There is no toast overlay, banner texture, or toast fade. The
  latest notification is shown for four seconds, then the current turn status
  returns. Messages wrap inside the header and do not intercept board input.
  State refreshes and timeout handover preserve the visible message. Correcting
  a placement clears its obsolete warning; starting or ending a match clears
  pending notifications. Existing suppression of incomplete poker-hand notices
  remains in place. General action guidance is still available in the drawer.
  Validation: 557 focused interaction, portrait, and rendered layout assertions
  passed on Godot 4.6, including actual message expiry and no-valid-move
  handover. The notification was visually checked at 360x800; physical-device
  verification remains outstanding.

  Achievement unlocks are a separate app-wide event and use the persistent
  OverlayLayer toast specified in ADR-015, so they can appear on the hub,
  profile or game screen without replacing turn-status guidance.

- The game background uses `assets/ui/default_background.png` in a full-screen
  TextureRect behind the interface. It preserves aspect ratio and crops to fill
  portrait or landscape, and ignores pointer input.

- A top-left back chevron returns to the main hub through the existing hub
  navigation signal (owner request, 2026-10-15). A matching empty right-hand
  spacer keeps the turn-status banner centered. Its font is 11px, reduced by
  50% from 22px. Settings remains the first bottom action, Menu. The banner mirrors controller
  turn state, including rival turns and match end.
- Two tall player cards sit side by side. Each stacks a portrait, name, and score
  toward the outer edge, leaving the middle clear for the pot. The human remains
  labeled "You". Existing portraits, score plates, and warning
  feedback are reused.
- The supplied tile-pot artwork is centered between the two score summaries,
  with a small plain `N left` count directly below it. No ring or count badge is
  used. Deals still originate at the live bag opening and track the live
  rack-slot rectangles.
- A row of face-down rival tiles sits in the compact turn-information row above
  the board. Only the
  controller's public opponent tile count reaches this view. Online responses
  supply that count separately from the concealed opponent hand; no opponent
  tile identities or faces are synthesized or exposed.
  AI moves animate the publicly committed tiles from this rack into their board
  cells, turning face-up during flight and retaining their committed rotations.
  Each destination stays hidden until its tile lands. The rack then receives
  face-down replacements from the pot using the actual before/after hand counts;
  a depleted pot supplies only the available replacements. Flight endpoints track
  live layout and board zoom, and off-screen destinations are brought into view.
  Human move input waits for the short sequence; scoring feedback starts after
  placement, and final results wait for the sequence to finish. A completed match
  then keeps the final board and scores visible for two seconds before opening
  results, whether the last move was human or rival. Resignation and recovery
  errors still open results immediately. The existing turn
  clock continues normally. Restart cancels the presentation cleanly, and reduced
  motion shows the committed board and refilled rack immediately. Online snapshots
  continue to update the rival count without synthesizing concealed tile faces.
  Validation: 466 focused game-screen/portrait assertions passed on Godot 4.6,
  covering full/partial/empty-pot refills, per-tile landing, input gating, restart,
  reduced motion, and final-results timing. An actual Easy AI move was rendered
  through departure, face reveal, refill, and completion at 540x960 and 360x800.
  Physical-device animation testing remains outstanding.

### Result exit interstitial (implemented, 2026-10-22)

For a completed win or loss, the game preloads one AdMob interstitial when the
match ends, after the Mobile Ads SDK reports initialization complete. Pressing
the results screen's **Back to hub** shows it only if ready;
the result remains behind the ad until dismissal, then the hub opens. A load or
show failure, an ad that is not ready, or a missing native plugin never delays
navigation. Draws and incomplete matches do not request an ad. Other hub exits
remain unchanged. Starting a new match or leaving the screen releases a loaded
ad; closing a shown ad destroys it before navigation. If the native plugin does
not acknowledge a show within five seconds, the game returns to the hub. Once
shown, a missing dismissal callback has a 90-second safety timeout. Hub
navigation is deferred out of the plugin callback so the screen is released
after ad cleanup finishes.
An Android logcat from 2026-10-23 showed a native crash when interstitial
loading raced ahead of SDK initialization; waiting for the completion callback
is required before calling the loader.

The Android and iOS ad-unit IDs are editable at `pokabow/ads_android_interstitial_unit_id`
and `pokabow/ads_ios_interstitial_unit_id` in Project Settings. Both currently use
Google test units. Live serving still requires production ad-unit and app IDs,
the app's consent setup, and testing on Android/iOS devices. Desktop routing
checks use a stand-in ad; they do not prove native ad delivery.
- The square 12×12 board occupies the central play area; the tile rack sits below.
  All empty cells use the supplied rounded sage artwork with deep-teal gaps.
  Colored decorative cells are omitted. The board is surrounded by a substantial
  deep-teal frame with rounded corners that meets the outer cells without a
  gap. Gameplay highlights still overlay the cells as needed.
  The game preserves the portrait canvas when the physical window is wide.
  Closing the game screen restores the shell's portrait canvas settings.
- The human tiles float directly below the board, with no tray artwork
  (owner direction, 2026-10-15). An invisible layout control reserves only the
  square tile height plus 8px touch padding above and below, returning the
  former tray rails/base space to the board. The row keeps its side margins
  and equal horizontal gaps. Its size remains independent of board zoom and
  height, avoiding resize feedback loops. Tile size is calculated for a full six-tile hand
  and stays the same as tiles leave the rack. Removed tiles leave vacant slots;
  remaining tiles keep their positions (owner direction, 2026-10-17).
  Touch targets fill the deck row's full height, including space around the tiles.
  Targets are split at the midpoint between slot centers; outer slots
  extend to the row edges. Vacant slots do not select a neighboring tile.
  A press in that surrounding space selects the tile and can begin its drag
  (owner direction, 2026-10-10). Targets stay inside the deck row.
  Tray removal validation: 617 focused interaction, portrait, and rendered
  layout assertions passed on Godot 4.6. Five viewport sizes retained the compact
  floating row; 540x960 and 320x568 previews were visually inspected. Physical
  device touch testing remains outstanding.
  Expanded-target validation: 772 focused assertions passed on Godot 4.7.2,
  covering one-to-six-tile hit regions at three sizes, padding-to-board drags,
  rotation, interaction gating, and the 60-second timer. Physical-device touch
  verification remains outstanding.
  Validation: rendered checks passed at five phone/wide-window sizes, including
  board/tray width alignment, square tiles, equal spacing for one through six
  tiles, and matching tap targets. The 320x568 and 540x960 captures were visually
  inspected; 270 focused interaction assertions passed on Godot 4.7.2.
  Physical-device touch verification remains outstanding.
- The first bottom action, Menu, opens the command menu. It uses a three-line
  burger SVG with the same stroke, 80px icon size, and enabled colour as the
  other bottom actions. The top-right settings button and bottom Undo action
  have been removed (owner request, 2026-10-15). Closing the drawer returns
  keyboard focus to Menu.
- The 60-second timer is plain `m:ss` text, aligned right in the row under the
  score header; the active-turn label is at left and the compact rival rack sits
  between them. Turn text uses 16px Fredoka Regular; the 16px timer uses
  Fredoka Semibold. Both remain deep teal, as in the Modern
  Tabletop concept. A rounded soft-sage panel (`#DFEAE4`) wraps the three
  elements, gently separating them from the ivory canvas. The surrounding score cards and avatar timer borders are
  removed to match the concept. Avatar portrait borders are also omitted on
  this screen. The avatar remains still throughout the turn, including the
  final ten seconds. Opening settings does not pause the clock.
  The drawer starts below the score header;
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
  Loss." Yes, resign ends the match and records the rival as winner; Keep
  playing dismisses the dialog. Resign is disabled after the match ends.
- The current gameplay action bar also offers Resign immediately after Swap,
  with a flag icon. It opens the same confirmation, remains available off-turn,
  and is disabled after the match ends. A filled sack Pot action replaces the
  bottom Menu action and shows the live remaining count. It opens a scrollable
  bottom sheet of face-up remaining tiles, including all four edges. Tile IDs
  and future draw order are not displayed. The top-right menu still opens
  settings, and Share appears on the results screen.
- Historical bottom tab bar (owner direction, implemented
  2026-10-06): a flat, full-width surface anchored to the bottom of the portrait
  canvas, with a subtle top divider and five equal-width touch targets. Each
  80px icon sits above its label in a 112px-high bar (2026-10-15); hover, press, and keyboard focus have distinct
  feedback. The content reserves space above the bar so the rack stays clear.
  The bar contains Menu, Play, Skip, Swap, and Quit in that order. Menu opens
  settings and remains available during either player's turn. Play uses Play
  move; Swap starts tile selection.
  While selecting, Swap stays disabled and Menu opens the drawer's
  Return selected tiles / Keep tiles controls.
  Quit uses Back to hub. Skip has no corresponding menu command and stays disabled
  with no action connected. Availability follows controller state and inactive items
  appear gray and dimmed.
  Validation: 270 focused interaction assertions passed on Godot 4.7.2. Rendered
  layout checks passed at 320x568, 360x800, 540x960, 1280x720, and 844x390;
  the 320x568 and 540x960 captures were visually inspected. Device touch QA
  remains open.
- Interface text uses Bahnschrift with Segoe UI and DejaVu Sans fallbacks.
  Tile artwork, tile fonts, and tile painting are unchanged by this layout.

Shared-pot timer validation (2026-10-15, Godot 4.6): 387 focused interaction
assertions, six portrait configuration checks, and 137 rendered layout/state
assertions passed. Full, half-full, ten-second, and empty rings were visually
inspected. Coverage includes both players, per-second updates without board
rebuilds, timeout handover, match-end clearing, restart, warning feedback, and
reduced motion. Physical-device testing remains outstanding.

Reference-layout validation (2026-10-15, Godot 4.6): 125 rendered geometry
assertions passed at 540x960, 360x800, 320x568, 1080x2400, and 1280x720.
Phone captures at 540x960, 360x800, and 320x568 were visually inspected.
The focused interaction runner passed 300 assertions plus six portrait checks,
including play, undo, swap, settings, timer feedback, dealing, dragging, and
pinching. Resume/resize regression checks passed 57 assertions. Online play,
board geometry, and rack touch-target suites passed 50, 89, and 625 assertions.
The broader game-screen suite was not clean: its pre-existing no-valid-move test
calls the missing LineResult.is_legal() method, and a later boot test reported
an unexpected nonempty board. These are not counted as passing validation.
Physical-device touch and cutout testing remain open. Reproduce the new visual
checks with tools/validate_reference_layout.gd; captures go to .tmp/.

Validation: focused scene/controller tests and rendered portrait/landscape
captures are covered by `tools/check_game_layout.gd` and
`tools/preview_game_layout.gd`. Physical-device touch QA remains open.

Historical logo-layout validation (superseded by the turn banner, 2026-10-15): `tools/preview_header_logo.gd` rendered
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
- Selected deck tiles have no surrounding highlight (owner direction, 2026-10-14).
  Their slight lift and tap-to-rotate interaction remain; swap marks retain their outline.
- Unselected tiles resting in the player's deck receive a one-third-second,
  45-degree glimmer sweep from left edge to right edge at randomized intervals.
  Selected, concealed, or dragged tiles do not show the effect, and board tiles
  never receive it. The glimmer image is included in the startup art warm-up.
- A tile reaches the board only by being dragged there from the hand. Tapping an
  empty board cell stages nothing, because the tile that lands on a cell is always
  one the player lifted from their own hand: a misplaced tap can no longer spend a
  tile the player never chose.
- While dragging from the deck, the source slot is vacant and the moving preview
  uses 90% of the deck tile's normal width and height. The nearest cell
  under the pointer uses the gold frame from `assets/tiles/tile_highlight.png`,
  replacing the red border (owner direction, 2026-10-10). Its opaque center is
  omitted so existing tiles remain visible, including over occupied cells;
  the existing legal/illegal fill still shows whether the drop is accepted.
  The preview follows the pointer continuously in a screen-level overlay, including
  the space between the deck and board. It keeps the same size across board zoom
  levels. Leaving the board clears only the target; the tile stays under the pointer.
  An accepted release snaps the tile into the highlighted cell at normal board size.
  Invalid/off-board releases and cancellation clear the overlay without placing it.
  An online match poll that leaves the hand and turn unchanged keeps the active
  press or drag; a changed hand, lost turn, or interaction lock cancels it.
  Each visible tile in the player's deck has the supplied soft shadow beneath it;
  the shadow is drawn only in the deck row, so it disappears with the vacant source
  slot during a drag and returns when the tile is restored to the row.
  Validation: 838 focused assertions passed on Godot 4.7.2, including fractional
  pointer movement within a cell, movement outside the board, and cleanup on drop
  or cancellation. A 540x960 rendered frame confirmed the freely positioned tile
  and grid-aligned gold artwork with a transparent center. Physical-device touch
  testing remains outstanding.
- A staged tile is drawn at its board cell even when the pending line is not yet
  legal. The incomplete or illegal line keeps its validity marker and reason.
- The visible deck row shows only tiles that have not been staged, preserving
  their slots. Dropping a rack tile or returning a staged tile between tiles or
  at either end inserts it there and shifts the intervening slots. Dropping it
  into its original vacancy restores the original order. Cancel and other
  off-board returns restore tiles to their reserved slots. New dealt tiles fill
  vacancies without moving surviving tiles. This order is local presentation
  state for the current screen, not saved match state.
  Live rack drags now preview insertion before release: neighboring tiles ease
  into the open position, and leaving the rack or cancelling eases them back.
  The insertion commits only when released in the rack. A regression checks the
  intermediate movement and final order; Godot execution remains pending because
  the engine is unavailable in this environment.
  Validation (2026-10-17): 2,005 assertions passed on Godot 4.6 across the
  game-screen, online-play, board-geometry, and rack-input suites. Coverage
  includes every insertion boundary, vacant-slot hit testing, refill placement,
  refresh stability, and touch/mouse returns from the board. Rendered 540x960
  frames verified the gap and reordered rack; physical-device touch testing
  remains outstanding.
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

## 4. Edge and Cluster Feedback (Specified; visual direction Decided)

- The game must visually communicate edge matches.
- The game must visually communicate edge clusters.
- The source specification suggests animation and particle effects.
- Visual treatment follows [Modern Tabletop](../DESIGN_SYSTEM.md); exact effect timing and device tuning remain to be validated.

### Current implementation (Implemented, headless tested, device visual QA open)

`ScoreRevealLayer` identifies each scored poker hand with a small staggered tile
lift and a thin honey line tracing the outside of the hand. Full House and Four
of a Kind also receive a brief honey chip stamp naming the hand. The layer reads
committed `ScoreEvent`s; it does not calculate a score. The existing move-total
popup remains. Edge-cluster and edge-match awards continue to use the floating
score UI without a poker-hand trace. The trace fades over two seconds and clears
on replacement or board teardown. In online play, Gems begin travelling to the
pot after the ripple, and their count still updates on arrival. Reduced motion
holds the complete trace and high-hand label without movement and updates Gems
immediately. Device visual QA remains open.

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
- The top game-screen label reports the scorer and combined points for every
  move with a positive award (owner direction, 2026-10-17).

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
The top header uses the same committed events to show “You scored N points” or
“Rival scored N points” for four seconds.

The score moment also carries a sound and a vibration (section 6). Both follow the
committed event, not the button press.

Validation (2026-10-11): 31 focused assertions passed on Godot 4.6, covering
combined awards, separate moves, empty awards, styling, and a real committed
move. A rendered preview verified the flash, disappearance, large-total bounds,
and reduced motion; the white outlined value was visually inspected. The broader
game-screen suite still reported app-startup and save-related issues.
Physical-device visual verification remains open.

### Match-end patterned background (Implemented, device visual QA open)

The blue match-end panel uses `assets/ui/match_end_pattern.png`, copied from the
provided reference. Its 200-pixel squares render at 100 logical pixels, rotated
45 degrees, and drift diagonally at 36 logical pixels per second. The shader
repeats the reference's four-suit sequence with shifted rows, avoiding the seam
that repeating the original three-row image would introduce. The pattern follows
the existing blue panel boundary during the reveal and remains below confetti,
portraits, scores and actions. The red loss panel retains its existing behavior.
Scrolling continues after the reveal, stops while hidden, resets for a new result,
and stays still with reduced motion enabled.

Validation (2026-10-12): Godot 4.7.2 rendered the reveal, win and loss screens;
23 existing match-end assertions passed. Preview checks verified ongoing scroll,
phase wrapping, reduced motion and hidden-panel processing. Physical-device
visual verification remains open.

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

Player actions cue: selecting a deck tile, placing or committing a line, being
awarded points, a refused gesture, and the end of the match. Each carries a
vibration length and a short one-shot sound. The deal-card sound also plays for
each animated card flight from the pot into either player's rack.

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

The one-shots are cached by the adapter. Whether they sound right in play,
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

- `ScoreRevealLayer` still marks which hand scored and holds the trace and any
  high-hand label for two seconds without fading or tile movement;
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

**Text size.** The approved scale and essential-copy legibility floor are now
specified in [the design system](../DESIGN_SYSTEM.md#typography). The earlier
15–34px gameplay and 20–56px splash inventory at a 1280×720 target is historical,
not the new mobile target. Apply the approved screen-space scale through the
540px logical canvas and verify at phone widths. Runtime font migration and
physical-device legibility checks remain pending.

---

## 8. UI Architecture Boundary

UI reflects game state rather than duplicating game rules:

```
Game State -> Turn Manager -> UI Controller -> HUD / Board UI / Score UI
```

(`AGENTS.md` section 19)

---

## 9. Open Items

- Remaining screen migrations and physical-device validation of Modern Tabletop are pending; the hub/settings migration is implemented.
- Exact rotation gesture vocabulary - unspecified beyond "button and/or gesture".
- Thresholds for drag-to-commit vs. drag-to-cancel - unspecified.

The remaining gesture and device-tuning details do not change game rules.
Resolve them within the approved design system and existing input contracts.

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
| Accessibility - text size | Approved scale and legibility floor in DESIGN_SYSTEM.md; runtime adoption and device checks pending |
| Rival difficulty selection | Implemented - HUD picker writing to `set_ai_difficulty()`; device QA open |
| Screen orientation | Decided and implemented: portrait-only; device validation pending |
| Visual style | Modern Tabletop Decided (ADR-020); hub/settings implemented and rendered; remaining screens pending |
| Exact gestures and thresholds | Remaining details open within the existing input contract |
