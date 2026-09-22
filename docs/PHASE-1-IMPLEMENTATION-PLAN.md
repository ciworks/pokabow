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
* Board-full and tile-exhaustion end conditions.
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

## Milestone 7: Persistence, recovery, and diagnostics

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

### Exit criter
