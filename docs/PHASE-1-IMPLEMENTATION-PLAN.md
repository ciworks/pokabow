# Phase 1 Implementation Plan

* **Status:** Ready for implementation
* **Target:** Godot 4.6, landscape mobile, Human vs AI
* **Source of truth:** `GAME_SPEC.md`, `AGENTS.md`, and accepted ADR-001 through ADR-008

## Goal

Deliver a playable vertical slice in which a human and AI alternately draw, rotate, preview, confirm, and place tiles on a 12 x 12 board; receive poker, edge-match, and cluster points; save/resume; and reach a deterministic final result.

## Delivery principles

1. Build domain rules before presentation.
2. Keep every milestone runnable and tested.
3. Use accepted ADR behavior without inventing additional rules.
4. Implement pure reference logic before performance caches.
5. Keep UI, AI, and replay on the same validation/scoring APIs.
6. Add a regression test for every core-logic bug.

## Milestone 0: Repository foundation

### Deliverables

* Minimal Godot 4.6 project that opens without errors.
* Directory structure from ADR-008.
* Typed GDScript conventions and formatting rules.
* Headless test runner and one passing smoke test.
* Versioned rules resources with placeholder approved values.
* CI or repeatable local commands for headless tests and project validation.

### Exit criteria

* Project starts in the required landscape orientation.
* Headless tests run with one command.
* No active match state is stored in an autoload.

## Milestone 1: Tile domain

### Deliverables

* `TileRank`, `FaceColor`, and `EdgeColor` enums.
* Immutable `TileData` and placed `TileSnapshot` types.
* `get_rotated_edges()` for four quarter-turn rotations.
* Versioned `TileGenerationRules`.
* Seeded `TileSource` that creates the accepted 144-tile bag.
* Deterministic tile IDs and save DTOs.

### Required tests

* Rotation mappings for all four orientations.
* Valid ranks, colors, and four edges.
* Zero initial rotation.
* Same seed produces the same bag.
* Unique IDs and permitted duplicate configurations.
* Draw, exhaustion, and save/resume behavior.

### Exit criteria

* A headless test can generate, draw, serialize, restore, and verify all 144 tiles.

## Milestone 2: Board and placement

### Deliverables

* `BoardState` with 12 x 12 typed storage.
* Coordinate/bounds and occupancy queries.
* Legal frontier index and rebuild function.
* `PlacementRequest`, rejection enum, and pure `PlacementValidator`.
* Hypothetical placement view.
* Atomic board commit without scoring.

### Required tests

* Four central opening cells.
* Orthogonal connection and diagonal-only rejection.
* Occupied/out-of-bounds rejection.
* Mismatched colors remain legal.
* Frontier updates and rebuild equivalence.
* Preview/cancel causes no mutation.

### Exit criteria

* A headless script can legally fill a seeded board while every invalid placement returns a structured reason.

## Milestone 3: Reference scoring

### Deliverables

* `PokerHandEvaluator` and versioned point resource.
* `EdgeMatchScorer`.
* Reference flood-fill `EdgeClusterScorer`.
* `ScoreEvent`, `ScoreLedger`, and deterministic identifiers.
* Preview `ScoreTransaction` generation.
* Full static audits and ordered replay verifier.

### Required tests

* Every poker frequency pattern and score.
* Horizontal/vertical five-cell windows and one-time scoring.
* Edge matches in every direction and rotation.
* Single-color cluster components and four-tile milestones.
* Cluster growth/merge entitlement deltas.
* Multiple scoring categories from one placement.
* Incremental results equal full replay.

### Exit criteria

* Random seeded placement sequences produce identical incremental and replayed board, ledger, and totals.

## Milestone 4: Atomic turns and match lifecycle

### Deliverables

* `GameSessionState`, `TurnState`, and phase enum.
* `TurnManager` implementing Human-first alternation.
* Atomic `MoveCommitter` spanning board, scores, indexes, and turn state.
* End the match when neither current deck has a legal placement; retain the
  board-full and tile-exhaustion checks for completeness (ADR-011 amendment).
* Winner/draw calculation and score breakdown.
* Save/resume at stable transaction boundaries.

### Required tests

* Exactly one committed tile per turn.
* Invalid/canceled actions do not advance turns.
* Duplicate move IDs are idempotent.
* Rollback at every pre-commit failure point.
* The 144th placement ends a full-board match.
* Draw and win outcomes.
* Resume during an uncommitted preview.

### Exit criteria

* A complete two-scripted-player match runs headlessly to a verified result.

## Milestone 5: Minimal playable UI

**Implementation note (2026-09-22):** ADR-011 supersedes the original
single-tile turn shape. The current interface stages a line before confirmation.
Each staged tile is visible on the board and absent from the visible deck row;
un-staging a cell or cancelling restores it to the row. The underlying match deck
is changed only by the atomic line commit. Headless game-screen integration tests
cover these transitions. Manual mobile viewport verification remains open.

### Deliverables

* `AppRoot`, splash screen, and `GameScreen` hierarchy.
* Responsive 12 x 12 `BoardView` for landscape safe areas.
* Active-tile view, touch drag/tap, rotate, confirm, and cancel.
* Valid-placement and invalid-reason feedback.
* Score panels, turn indicator, and remaining tile count.
* Basic committed placement and floating-score animation.

### Required checks

* UI submits commands and never calculates rules.
* Human input is disabled during AI turns.
* Preview matches committed points on an unchanged board revision.
* Interrupted animations resynchronize to session state.
* Mouse development input follows the same command path as touch.

### Exit criteria

* A human can complete a local scripted-opponent match on desktop and a representative mobile viewport.

## Milestone 6: AI difficulties

### Deliverables

* Shared legal move generator with rotation deduplication.
* Easy seeded random strategy.
* Medium exhaustive immediate-score strategy.
* Hard representative-tile sample and bounded two-ply strategy.
* Cancellation, stale-result rejection, retry, and diagnostics.
* Thinking-state presentation.

### Required tests

* Every returned move is legal.
* AI randomness never changes tile draw order.
* Easy distribution sanity.
* Medium selects maximum immediate score.
* Hard demonstrates a blocking choice in a fixed fixture.
* Same inputs/seed produce the same move.
* Full matches finish without deadlock.

### Exit criteria

* Human vs Easy, Medium, and Hard matches complete correctly and remain responsive on target-class hardware.

**Implementation note (2026-09-25):** All three difficulties were implemented and
tested, but nothing exposed them: the game ran the configured default and the
exit criterion above was unreachable, because the player could not reach Easy or
Hard. `GameScreen` now carries a `DifficultyPicker` in the HUD, built from
`AiEnums.Difficulty` and wired to `GameSessionController.set_ai_difficulty()`,
which was already documented as safe mid-match (it cancels an analysis in flight
and re-schedules the rival rather than stranding it). "New match" now carries the
chosen difficulty into the new match instead of letting it fall back to the
default. Manual device verification of the three difficulties remains open.

## Milestone 7: Persistence, recovery, and diagnostics

**Implementation note (2026-09-24):** Automatic save and resume are implemented
and unit tested (`tests/unit/test_match_persistence.gd` drives a real controller
through the commit boundary, then resumes it into a second controller and compares
board, history, score, and pot). Saving happens at the commit boundary in
`GameSessionController._after_state_change()`, with a suspend/shutdown save behind
it, and `AppRoot` resumes a saved match instead of starting a new one.

**All six deliverables are now implemented.** The recovery screen is a panel in
`game_screen.tscn` (`RecoveryOverlay`): a refused restore emits
`GameSessionController.recovery_failed`, the screen shows the reason and the
player explicitly starts a fresh match, and the unreadable save is deliberately
left on disk so the last valid transaction stays recoverable rather than being
destroyed by the refusal. The development overlays are one `DebugOverlay` control
on the board (`scripts/presentation/debug_overlay.gd`), off unless the
`debug/overlays` project setting is on and toggled with F3; it draws cell
coordinates, the legal frontier, the last move's cells, and a panel of board
revision, pot, move count, and the last award's score events. The replay/export
deliverable is `GameSessionController.export_fixture()`, bound to F4, which writes
the same versioned snapshot the autosave writes - bag, decks, board, ledger, and
ordered move history - to `user://match_fixture.json` so the domain replay
verifier can consume it. None of the three mutates match state.

### Deliverables

* Versioned save schema and migrations policy.
* Automatic save after each committed move.
* Background/suspend handling.
* Recovery error screen that preserves the last valid transaction.
* Development overlays for board, scoring, clusters, frontier, and AI evaluation.
* Replay/export fixture support for bug reports.

### Exit criteria

* Forced termination after any committed move resumes to an equivalent verified state.

## Milestone 8: Mobile polish and balance

### Deliverables

* Edge/cluster visualization and refined floating score sequencing.
* Audio and optional haptic adapters.
* Accessibility pass for color differentiation, text size, and reduced motion.
* Seeded balance simulation reports.
* Performance profile on representative mobile hardware.
* Tuned rules resources without changing accepted rule semantics.

**Implementation note (2026-09-25):** Two of the six deliverables have landed.
Edge/cluster visualization is implemented (`ScoreRevealLayer` outlines every
scoring group and sequences the poker-hand bounce), but the refinement of the
floating score sequencing is not finished. The audio and optional haptic adapters
are implemented in `FeedbackAdapter` (ADR-008 section 5), created by `AppRoot` and
injected into the screen, with five cues fired by the screen when a human gesture
resolves. Both channels are switchable and neither is read by any rule, score, or
turn path. The five sounds are confirmed audible and accepted by the owner in play.
Two of the five come from generic asset-store one-shots rather than purpose-matched
effects, and no licence record for them exists in the project yet - worth resolving
before a public build.
**Accessibility is partly done.** The edge palette (`TilePainter.EDGE_COLORS`) is
now an Okabe-Ito set, and the four top-edge overlays under `assets/tiles/edges/`
are tinted by that palette instead of being drawn as authored, so one palette now
governs every edge on every side. Before this the palette paired a red and a green
that sit on the exact axis red-green colour blindness collapses, and the overlays
carried their own colours - so a palette-only change would have recoloured three
sides of a tile and left the top edge stale. Colour remains the only edge channel:
a redundant pattern encoding was offered and declined by the owner, so this helps
the red-green confusion pair but not every vision type. Reduced motion is now
implemented too: `AccessibilitySettings.reduced_motion()` reads the
`accessibility/reduced_motion` project setting (default false) at the point each
animation starts - the reveal, the popup layer and the deal layer each ask it
directly, so nothing is injected and a future settings screen can toggle it
mid-session. With it on, each of those three shows the same events without moving.
The reveal holds its
marks and clears them without bouncing or fading, a score popup appears without
drifting, and a deal completes in one step while still reporting every tile as
revealed so the row unconceals the deck. No setting movement changes a point, a
turn, or a board cell. Text size is inventoried - 15 to 34 px in `game_screen.tscn`
against the 1280x720 target - but deliberately unchanged, because no legibility
floor has been agreed and resizing every HUD label blind would be a guess. The
seeded balance simulation, the mobile performance profile, and the rules tuning
are not started.

One thing to verify on a device: if an edge overlay is coloured rather than
neutral art, tinting multiplies it and the top edge reads a shade darker than the
other three sides. That is recorded in `_paint_edge_layer` but not confirmed by eye.

### Exit criteria

* Every scoring category the ledger records is revealed on the board, and the
  floating popups play in the ledger's recorded event order, so no mark and no
  point value can describe an award the ledger did not record.
* A full headless match plays identically with `feedback/audio` and
  `feedback/haptics` both off: no rule, score, or turn path reads either setting,
  which is what makes both channels optional rather than required.
* A cue fires for each of the five player gestures - select, place, score, refuse,
  match end - at the moment a human gesture resolves and never on the rival's move.
* On a device, every cue that has a sound is audible and every cue vibrates, and
  turning either channel off silences only that channel.
* Matching edges are readable without colour, text is legible at the 1280x720
  target viewport, and a reduced-motion setting suppresses the reveal and bounce
  animations without changing a single point awarded.
* A seeded balance simulation reproduces the same report from the same seed and
  covers all three difficulties.
* A measured frame-time profile on representative mobile hardware meets the stated
  frame budget across a full match.
* Any rules tuning changes values in versioned rules resources only: the whole test
  suite passes unchanged and incremental-versus-replay equivalence still holds, so
  the accepted rule semantics are provably unchanged.
