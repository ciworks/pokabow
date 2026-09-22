# AGENTS.md — Game Development Instructions

## 1. Project Overview

This repository contains a mobile, turn-based 2D tile-placement game built with **Godot 4.6**.

The game is inspired by the combination of:

* Scrabble-style grid placement
* Poker-style hand formation
* Tile edge/color matching

The initial playable mode is:

**Human vs AI**

The core board is a **12×12 grid**.

The primary objective is to form poker hands using placed tiles while maximizing edge color bonuses.

---

# 2. Source of Truth

When making implementation decisions, use the following priority order:

1. Current source code and tests
2. `docs/GAME_SPEC.md`
3. Relevant documents in `docs/sections/`
4. Architecture/technical decisions in `docs/decisions/`
5. This `AGENTS.md`
6. Existing implementation assumptions
7. General knowledge or personal assumptions

Do not invent game rules that are not specified.

If the specification is ambiguous or contradictory:

* Do not silently choose an interpretation.
* Identify the ambiguity.
* Explain the implementation options.
* Ask for clarification when the decision materially affects gameplay or architecture.

Small implementation details may be chosen pragmatically when they do not alter the specified game rules.

---

# 3. Core Game Rules

The following rules are part of the base game and must not be changed without an explicit specification update.

## Board

* Board size: 12×12.
* The board consists of individual grid cells.
* Only empty cells may receive a tile.
* Tiles snap to the grid.
* Tile rotation is supported.
* Tile adjacency must be tracked.
* Edge and cluster scoring should be calculated from affected areas rather than unnecessarily recalculating the entire board.

## Tiles

Each tile has:

* A face
* Four edges
* A rotation

Faces are:

* Ace
* King
* Queen
* Jack

Faces have a Red/Black property.

Edges have four positions:

* Top
* Right
* Bottom
* Left

Edge colors are:

* Blue
* Red
* Green
* Yellow

Tile rotation is limited to:

* 0°
* 90°
* 180°
* 270°

Tile generation uses random face and edge values.

Newly generated tiles begin at 0° rotation.

The canonical tile API should provide functionality equivalent to:

```gdscript
get_rotated_edges()
```

This method should return the tile's edge colors in their current orientation.

---

# 4. Scoring Rules

The base game has two major scoring components.

## Poker scoring

Placed tiles form poker-style hands.

The scoring system must support poker hand evaluation including, at minimum:

* Pair
* Three-of-a-Kind
* Full House
* Other hands defined by the game specification

Poker scoring is based on the faces of the relevant tiles.

## Edge scoring

Adjacent matching edges provide:

* +1 point per matching edge

Connected edge groups/clusters may provide an additional flat bonus.

The base game does **not** use multipliers.

Do not introduce multipliers, combo systems, power tiles, or other score modifiers unless they are explicitly part of a later approved feature.

---

# 5. Incremental Scoring

Scoring should be designed for incremental updates.

When a tile is placed or changed:

1. Determine the affected board cells.
2. Determine affected adjacent tiles.
3. Determine affected poker hands.
4. Determine affected edge matches.
5. Determine affected edge clusters.
6. Recalculate only the affected scoring regions.
7. Update the player's score.
8. Update any relevant UI feedback.

Avoid recalculating the entire 12×12 board after every move unless there is a clear technical reason.

The architecture should allow full-score recalculation for:

* Debugging
* Testing
* Validation
* Save/load verification

An incremental calculation and a full calculation should be capable of producing the same result.

---

# 6. Architecture Principles

Prefer a modular architecture.

Separate:

* Tile data
* Tile presentation
* Board state
* Board presentation
* Placement validation
* Adjacency
* Poker hand evaluation
* Edge scoring
* Cluster detection
* Turn management
* AI decision-making
* UI
* Effects/audio/haptics

Game rules should not depend unnecessarily on visual nodes.

Prefer data-driven game logic that can be tested independently of the Godot scene tree.

For example:

```text
TileData
   ↓
BoardState
   ↓
PlacementValidator
   ↓
ScoringSystem
   ├── PokerEvaluator
   ├── EdgeScorer
   └── ClusterDetector
```

Presentation systems should consume game state rather than becoming the source of truth.

---

# 7. Godot Version

Target:

**Godot 4.6**

Do not introduce APIs or syntax that are incompatible with Godot 4.6.

When implementing Godot systems:

* Prefer typed GDScript.
* Use signals for appropriate event-driven communication.
* Keep gameplay logic testable without requiring visual scenes.
* Avoid unnecessary dependencies between scenes.
* Use resources/data classes where appropriate.
* Keep mobile performance in mind.

---

# 8. Mobile-First Requirements

The game is designed for mobile devices.

Input should support:

* Tap to select
* Drag to move
* Rotation through a button and/or gesture
* Valid placement highlighting

Important feedback includes:

* Valid placement indicators
* Edge-match visualization
* Cluster visualization
* Animations
* Particle effects where appropriate
* Floating score notifications
* Optional haptic feedback

UI should remain readable and usable on mobile screens.

Do not assume mouse/keyboard input is the primary interaction model.

Desktop input may be provided as a development convenience, but mobile interaction must remain the design priority.

---

# 9. AI Difficulty

The initial game includes three AI difficulty levels.

## Easy

Behavior:

* Select a random valid placement.
* Select a random valid rotation.

The AI should not perform unnecessary strategic analysis at this level.

## Medium

Behavior:

* Evaluate potential poker-hand benefits.
* Evaluate edge matches.
* Prefer placements that improve the AI's score.

## Hard

Behavior:

* Consider approximately 1–2 turns of planning.
* Consider blocking the player's opportunities.
* Attempt to maximize its own score.

Keep AI decision-making separate from board rendering and UI.

The AI should operate against game-state/data interfaces rather than manipulating visual nodes directly.

---

# 10. Feature Boundaries

## Phase 1 — Core Game

Prioritize:

* Tiles
* Board
* Placement
* Rotation
* Poker scoring
* Edge scoring
* Cluster scoring
* Incremental scoring
* AI
* Mobile interaction

## Phase 2 — Engagement

Potential features include:

* Tile preview
* Rotation hints
* Cluster visualization
* Challenges
* Streaks

## Phase 3 — Advanced Features

Potential features include:

* Multipliers
* Power tiles
* Timed mode
* Campaign
* PvP
* Cosmetic unlocks

## Phase 4 — Polish

Focus on:

* Animations
* Performance
* Haptics
* Visual polish
* UX refinement

Do not implement future-phase features prematurely when they complicate the Phase 1 architecture.

---

# 11. Future Features

The architecture should avoid unnecessarily preventing future features such as:

* Score multipliers
* Power tiles
* Combo bonuses
* Advanced/adaptive AI
* Campaign/puzzle boards
* PvP
* Cosmetic unlocks
* Additional tile faces
* Additional edge patterns

However, future extensibility must not over-engineer the initial implementation.

Implement the simplest architecture that supports the current requirements cleanly.

---

# 12. Development Workflow

When implementing a feature:

1. Read the relevant specification.
2. Inspect the existing implementation.
3. Identify dependencies.
4. Explain the intended implementation if the change is substantial.
5. Implement the smallest coherent change.
6. Run relevant tests/checks.
7. Verify that existing functionality has not regressed.
8. Update documentation if the implementation changes an established design decision.
9. Summarize what changed.

Do not make unrelated refactors while implementing a feature unless they are necessary.

---

# 13. Specification-First Development

Before implementing a significant gameplay system, verify that the corresponding specification exists.

The specification is organized into these major areas:

1. Tile System
2. Board System
3. Scoring System
4. AI System
5. Mobile UX & Feedback
6. Game Modes & Engagement
7. Godot Scene & Node Structure
8. Feature Roadmap
9. Future Expansion

Use the relevant section as the primary design reference.

If a section has not yet been finalized, do not assume that an unfinished design is final.

---

# 14. Implementation Status

Documentation should distinguish between:

* **Specified** — defined by the game specification
* **Decided** — explicitly decided during development
* **Implemented** — exists in the codebase
* **Tested** — verified by automated or manual testing
* **Proposed** — suggested but not yet approved
* **Future** — intentionally deferred

Do not describe a proposed feature as implemented.

Do not describe an implementation as tested unless it has actually been tested.

---

# 15. Change Management

When a gameplay rule changes:

1. Update the relevant specification.
2. Identify affected systems.
3. Update implementation.
4. Update tests.
5. Update documentation.
6. Check for downstream effects.

Avoid encoding important game rules in multiple unrelated locations.

There should be a clear single source of truth for important gameplay rules.

---

# 16. Testing Requirements

Gameplay logic should be testable independently of visual presentation.

Prioritize tests for:

### Tiles

* Rotation
* Edge ordering
* Random generation
* Face values
* Edge values

### Board

* Valid placement
* Invalid placement
* Occupied cells
* Grid boundaries
* Adjacency

### Scoring

* Poker hand recognition
* Poker score calculation
* Edge matches
* Cluster detection
* Incremental scoring
* Full-score vs incremental-score equivalence

### AI

* Valid placement generation
* Difficulty-specific behavior
* AI never selecting invalid moves

Whenever a bug is found in core game logic, add a regression test when practical.

---

# 17. Debugging and Development Tools

Development builds should make it possible to inspect:

* Board coordinates
* Tile faces
* Tile rotations
* Edge colors
* Valid placements
* Adjacency
* Poker hands
* Edge matches
* Clusters
* Score calculations
* AI decisions

Debug tooling should not be required by the final player experience.

---

# 18. Code Quality

Prefer:

* Small focused classes
* Clear names
* Typed GDScript
* Explicit data flow
* Pure functions for calculations where practical
* Reusable game-state objects
* Automated tests for deterministic logic

Avoid:

* Giant manager classes
* Gameplay logic embedded directly in UI scripts
* Hard-coded board positions
* Hidden global state
* Duplicated scoring rules
* Magic numbers where named constants would be clearer
* Tight coupling between AI and scene nodes

---

# 19. UI Architecture

UI should reflect game state rather than independently calculating game rules.

For example:

```text
Game State
	↓
Turn Manager
	↓
UI Controller
	↓
HUD / Board UI / Score UI
```

Score popups, animations, edge highlighting and similar effects should respond to game events.

They should not become responsible for determining whether a move is valid or how many points a move is worth.

---

# 20. AI Agent Behaviour

When asked to implement something:

* First inspect the repository.
* Read the relevant specification.
* Reuse existing systems where possible.
* Do not recreate functionality that already exists.
* Do not change game rules without explicit approval.
* Prefer incremental changes.
* Keep gameplay logic deterministic where practical.
* Add tests for important new logic.
* Keep the project runnable after each coherent change.

If the request conflicts with the specification, identify the conflict before implementing it.

If the requested feature is ambiguous but low-risk, make the smallest reasonable assumption and document it.

If the ambiguity affects game rules, architecture, save compatibility, scoring, or player experience, ask for clarification instead.

---

# 21. Completion Criteria

A feature is not considered complete merely because its code exists.

Where applicable, completion requires:

* Implementation
* Integration
* Relevant tests
* Manual verification
* Documentation update
* No known regression in existing core functionality

Before declaring a feature complete, report:

* What was implemented
* What was tested
* What was not tested
* Any assumptions made
* Any remaining limitations

---

# 22. Do Not

Do not:

* Invent unspecified game rules.
* Change scoring rules casually.
* Add multipliers to the base game without approval.
* Implement future features ahead of their priority without approval.
* Couple gameplay logic unnecessarily to UI nodes.
* Rewrite working systems without justification.
* Claim that something has been tested when it has not.
* Claim that something is specified when it is only an assumption.
* Replace the specification with personal design preferences.

---

# 23. Guiding Principle

Build the smallest clean, testable and extensible implementation that faithfully represents the approved game specification.

When there is a choice between adding complexity and keeping the implementation simple, prefer simplicity unless the additional complexity is justified by a concrete requirement.
