# GAME_SPEC.md

# Game Specification

## 1. Document Purpose

This document is the source of truth for the approved game design and technical requirements for the project.

The game is a mobile, turn-based 2D tile-placement game inspired by Scrabble and Poker.

The initial launch/demo mode is Human vs AI.

The game is being developed with Godot 4.6.

This document is derived from the project's initial specification document. Where the source specification does not define a detail, that detail is intentionally left unspecified rather than invented.

---

# 2. Core Gameplay

## 2.1 Game Type

- Turn-based 2D tile placement game.
- Inspired by Scrabble and Poker.
- Mobile-first.
- Initial demo: Human vs AI.

## 2.2 Board

- Board size: 12×12.
- The board may be represented using a 2D array or Godot TileMap.
- Tiles may only be placed into empty cells.
- Placement supports snap-to-grid.
- Tile rotation is supported.
- Adjacency must be tracked for edge and cluster bonus calculations.

## 2.3 Objective

The objective is to:

1. Form poker hands using placed tiles.
2. Maximize edge color bonuses.
3. Maximize the resulting score.

## 2.4 Base Scoring

The base game has:

- Poker-hand points based on faces.
- Edge matching bonus: +1 point per matching edge.
- Additional flat points for edge clusters.
- No multipliers in the base game.

---

# 3. Tile System

## 3.1 Tile Properties

Each tile has:

| Property | Values / Notes |
|---|---|
| Face | Ace, King, Queen, Jack |
| Face Color | Red / Black |
| Edges | Top, Right, Bottom, Left |
| Edge Colors | Blue, Red, Green, Yellow |
| Rotation | 0°, 90°, 180°, 270° |

## 3.2 Tile Rotation

Tiles support four orientations:

- 0°
- 90°
- 180°
- 270°

The tile's current orientation determines which edge color occupies each board-facing edge.

The tile system must expose functionality equivalent to:

```gdscript
get_rotated_edges()
```

This returns the tile's edges in its current orientation.

## 3.3 Tile Generation

New tiles are generated using:

- Random face.
- Random edge colors.
- Initial rotation of 0°.

The source specification does not define probability distributions or weighting for faces or edge colors. Do not introduce such weighting without an explicit design decision.

---

# 4. Board System

## 4.1 Grid

The game board is a 12×12 grid.

The board should maintain a representation of:

- Cell occupancy.
- Tile position.
- Tile orientation.
- Adjacency relationships required for scoring.

## 4.2 Placement

A placement must:

- Target an empty cell.
- Snap to the grid.
- Respect the tile's current rotation.
- Update board adjacency information.

Occupied cells cannot receive another tile.

## 4.3 Placement Validation

The board system is responsible for determining whether a proposed placement is valid.

The specification explicitly states that only empty cells are allowed for placement.

Other placement restrictions are not defined in the source specification and must not be invented without a design decision.

## 4.4 Adjacency

The board must track adjacent tiles so that the scoring system can determine:

- Matching edges.
- Edge clusters.
- Affected areas after a tile placement.

## 4.5 Incremental Scoring Support

The board should support identifying the tiles and relationships affected by a placement.

Scoring should recalculate only affected tiles/areas rather than unnecessarily recalculating the complete board after every move.

A full-board scoring path should remain possible for validation/testing.

---

# 5. Scoring System

## 5.1 Overview

Scoring consists of:

1. Poker-hand scoring.
2. Edge-match scoring.
3. Edge-cluster scoring.

The base game does not use multipliers.

## 5.2 Poker Hands

The game evaluates poker-style hands based on tile faces.

The source specification explicitly mentions:

- Pair
- Three-of-a-Kind
- Full House
- Other poker hands

The exact complete poker-hand hierarchy and point values are not defined in the source specification.

Until those values are explicitly approved, do not invent them.

## 5.3 Poker Hand Evaluation

The scoring system must be capable of:

- Identifying applicable poker hands.
- Calculating the associated score once hand values have been defined.
- Supporting the game's tile face values.

The exact definition of which tiles constitute a hand is not specified in the source document and requires an explicit design decision if implementation requires it.

## 5.4 Edge Matching

When adjacent tile edges have matching colors:

- Award +1 point per matching edge.

The edge colors are:

- Blue
- Red
- Green
- Yellow

Matching must use the tiles' current rotated edge positions.

## 5.5 Edge Clusters

Connected groups of relevant matching edges can produce an additional flat bonus.

Cluster detection should use an adjacency search such as:

- Flood-fill
- Equivalent adjacency traversal

The exact cluster bonus value and the precise definition of a cluster are not specified in the source document and must be explicitly defined before final implementation.

## 5.6 Incremental Scoring

Incremental scoring is required and is intended to be suitable for mobile.

After a placement, the scoring system should recalculate only affected scoring regions.

The system should support comparison between:

- Incremental score calculation.
- Full-board score calculation.

These should produce equivalent results for the same board state.

---

# 6. AI System

## 6.1 AI Players

The initial game includes AI opponents.

Three difficulty levels are specified:

- Easy
- Medium
- Hard

## 6.2 Easy

Easy AI behavior:

- Select a random valid placement.
- Select a random valid rotation.

The source specification does not define additional Easy AI behavior.

## 6.3 Medium

Medium AI behavior:

- Prioritize poker-hand opportunities.
- Consider edge matches.

The exact evaluation weights and search depth are not specified.

## 6.4 Hard

Hard AI behavior:

- Plan approximately 1–2 turns ahead.
- Attempt to block the player.
- Attempt to maximize its own score.

The exact search algorithm, evaluation function, tie-breaking behavior, and computational budget are not specified.

## 6.5 AI Integration

AI should operate against game-state and game-rule systems rather than directly depending on visual presentation.

AI decisions should produce valid game actions such as:

- Placement.
- Rotation.

The board/game systems remain responsible for validating and applying those actions.

---

# 7. Mobile UX & Feedback

## 7.1 Input

The mobile interaction model includes:

- Tap to select.
- Drag to move.
- Rotation button and/or gesture.

## 7.2 Placement Feedback

The UI should:

- Highlight valid placements.
- Provide clear feedback for tile positioning.
- Support snap-to-grid behavior.

## 7.3 Edge and Cluster Feedback

The game should visually communicate:

- Edge matches.
- Edge clusters.

The source specification suggests:

- Animation.
- Particle effects.

The exact visual style is not specified.

## 7.4 Score Feedback

The UI should provide floating score popups for:

- Poker-hand points.
- Edge bonuses.

## 7.5 Haptics

Optional haptic feedback is supported.

Haptics should not be required for the core game to be playable.

---

# 8. Game Modes & Engagement

## 8.1 Base Mode

The base game mode is:

**Human vs AI**

This is the initial/demo mode.

## 8.2 Optional Engagement Features

The source specification identifies the following as optional/future engagement features:

- Timed challenges.
- Pre-set boards.
- Daily/weekly events.
- Streak rewards.

These are not required for the base game unless separately approved.

## 8.3 Future Features

Future features identified by the specification include:

- Multipliers.
- Special/power tiles.
- PvP multiplayer.
- Cosmetic unlocks.
- Leaderboards.

These should not be treated as part of the base game.

---

# 9. Godot Scene & Node Structure

The project targets Godot 4.6.

The source specification requires the eventual technical specification to define:

- Scene hierarchy.
- Node structure.
- Incremental scoring integration.
- Tile placement notes.

The initial source document does not prescribe a final scene/node hierarchy.

Therefore, the implementation should establish a clear Godot architecture while documenting significant architectural decisions.

Gameplay state and scoring logic should be kept sufficiently separate from visual presentation to allow independent testing where practical.

---

# 10. Feature Roadmap

## Phase 1 — Core Base Game

Required priorities:

- Tiles.
- Board.
- Placement.
- Rotation.
- Poker scoring.
- Edge bonuses.
- Cluster scoring.
- AI.
- Mobile UX.
- Incremental scoring.

## Phase 2 — Engagement

Planned/optional features:

- Tile preview.
- Rotation hints.
- Cluster visualization.
- Challenges.
- Streaks.

## Phase 3 — Advanced

Planned/optional features:

- Multipliers.
- Power tiles.
- Timed mode.
- Campaign.
- PvP.
- Cosmetic unlocks.

## Phase 4 — Polish & Optimization

Planned focus:

- Animations.
- Performance.
- Haptics.
- General polish.

---

# 11. Future Expansion

The specification identifies the following possible expansion areas.

## 11.1 Scoring

- Optional multipliers.
- Power tiles.
- Board multipliers.
- Combo bonuses.

These are future features and are not part of the base scoring system.

## 11.2 AI

- Adaptive difficulty.
- More advanced turn planning.

## 11.3 Content

- Campaign/puzzle boards.
- New tile faces.
- New edge patterns.

## 11.4 Multiplayer

- PvP multiplayer mode.

## 11.5 Meta / Cosmetics

- Cosmetic unlocks.
- Additional visual effects.

---

# 12. Technical Design Principles

The following principles are derived from the requirements in the source specification.

## 12.1 Separation of Concerns

Keep the following concerns logically separated where practical:

- Tile data.
- Tile presentation.
- Board state.
- Board presentation.
- Placement validation.
- Adjacency.
- Poker-hand evaluation.
- Edge scoring.
- Cluster detection.
- AI decision-making.
- UI.
- Visual effects.
- Haptics.

## 12.2 Data-Driven Game State

Game rules should operate on game-state data rather than relying unnecessarily on scene-tree presentation nodes.

This supports:

- Testing.
- AI decision-making.
- Incremental scoring.
- Future feature expansion.

## 12.3 Mobile Performance

The specification explicitly calls for incremental scoring suitable for mobile.

Avoid unnecessary full-board recalculation after every move.

Prefer localized updates based on affected tiles and adjacency relationships.

## 12.4 Extensibility

The architecture should not unnecessarily prevent future additions such as:

- Multipliers.
- Power tiles.
- Advanced AI.
- Campaign boards.
- PvP.
- Cosmetic systems.
- Additional tile faces.
- Additional edge patterns.

Future extensibility should not introduce unnecessary complexity into the base game.

---

# 13. Specification Gaps Requiring Explicit Decisions

The source specification intentionally leaves several implementation/game-design details open.

These should be resolved through explicit design decisions rather than silently invented by an AI coding agent.

Each gap is owned by an Architecture Decision Record (ADR). The gap-to-ADR mapping, the review requirements an ADR must satisfy before it is part of this specification, and the current status of every gap are recorded in section 19.

## 13.1 Poker Scoring Values

Need to define:

- Complete list of poker hands.
- Point value for each hand.
- Whether multiple hands can score from one placement.
- How hands are selected when multiple interpretations are possible.

## 13.2 Hand Formation

Need to define:

- What constitutes a poker hand on the 12×12 board.
- Whether hands are rows, columns, connected groups, fixed lengths, or another structure.
- Whether hands may overlap.
- Whether existing hands can score again after subsequent placements.

## 13.3 Edge Cluster Definition

Need to define:

- What constitutes a cluster.
- Minimum cluster size.
- Whether a cluster consists of matching edges, tiles, or colors.
- Whether clusters are color-specific.
- How cluster boundaries are determined.

## 13.4 Cluster Bonus

Need to define:

- Flat bonus value.
- Whether bonus varies by cluster size.
- Whether a cluster can score repeatedly.
- Whether one placement can create multiple cluster bonuses.

## 13.5 Turn Rules

Need to define:

- Tile source/deck behavior.
- Number of tiles available to a player.
- Whether a player draws a new tile after placement.
- Pass behavior.
- Game-end conditions.
- Starting player rules.

## 13.6 Tile Distribution

Need to define:

- Whether tile generation is truly random or uses a controlled bag/deck.
- Face probabilities.
- Edge-color probabilities.
- Whether duplicate tiles are unrestricted.

## 13.7 AI Evaluation

Need to define:

- Medium AI evaluation method.
- Hard AI search method.
- Search depth interpretation.
- AI score evaluation.
- Blocking behavior.
- Time/performance budget.

## 13.8 Board Placement Rules

Need to define any restrictions beyond:

- Cell must be empty.
- Tile must occupy a valid grid cell.

For example, the source document does not specify whether tiles must connect to existing tiles.

## 13.9 Game End

Need to define:

- Win condition.
- Loss condition.
- Draw condition.
- Maximum turn count, if any.
- What happens when no valid placements remain.

---

# 14. Implementation Status Vocabulary

Use the following terminology when updating project documentation:

- **Specified** — explicitly defined in this specification.
- **Decided** — explicitly agreed as a project decision.
- **Implemented** — present in the codebase.
- **Tested** — verified through automated or documented manual testing.
- **Proposed** — suggested but not yet approved.
- **Future** — intentionally deferred.

Do not treat unspecified behavior as approved design.

---

# 15. Change Control

When an approved gameplay rule changes:

1. Update this specification.
2. Identify affected systems.
3. Update the implementation.
4. Update relevant tests.
5. Update affected technical documentation.
6. Record significant architectural decisions separately.

The game specification should remain the authoritative description of approved gameplay behavior.

---

# 16. Development Sequence

The original specification organizes detailed development/specification work in this order:

1. Tile System
2. Board System
3. Scoring System
4. AI System
5. Mobile UX & Feedback
6. Game Modes & Engagement
7. Godot Scene & Node Structure
8. Feature Roadmap
9. Future Expansion

Each area should be sufficiently defined before dependent implementation is treated as final.

---

# 17. Core Requirement Summary

At minimum, the initial playable game must provide:

- A 12×12 board.
- Randomly generated tiles.
- Ace/King/Queen/Jack faces.
- Red/Black face property.
- Four colored edges.
- Four tile rotations.
- Valid empty-cell placement.
- Grid snapping.
- Adjacency tracking.
- Poker-hand scoring.
- +1 edge-match scoring.
- Edge-cluster bonus.
- No base-game multipliers.
- Incremental scoring.
- Human vs AI gameplay.
- Easy, Medium, and Hard AI behavior.
- Mobile-oriented interaction.
- Valid-placement highlighting.
- Edge/cluster visual feedback.
- Floating score feedback.
- Optional haptics.

Anything beyond these requirements should be treated according to its status as specified, decided, proposed, or future.

---

# 18. Specification Integrity Rule

When an AI agent is implementing the game, it must not silently fill specification gaps with invented gameplay rules.

If implementation requires an undefined rule, the agent should:

1. Identify the missing rule.
2. Explain why it is required.
3. Propose one or more possible interpretations if useful.
4. Obtain an explicit decision.
5. Record the decision.
6. Update this specification where appropriate.
7. Implement against the approved decision.

The goal is to keep the implemented game aligned with an explicit, reviewable specification.

---

# 19. Architecture Decision Records (ADRs) and Review

Significant gameplay and technical decisions are recorded as Architecture
Decision Records in `docs/decisions/`. The index, template and review workflow
live in `docs/decisions/README.md`; individual review findings live in
`docs/decisions/reviews/`.

## 19.1 Review requirement

An ADR is part of the design specification only once it has been reviewed
against this document. Review is required before any dependent implementation is
treated as final, and must confirm:

1. The decision does not contradict a rule in this specification.
2. The decision covers the gap it claims to resolve, or states explicitly what it
   leaves open.
3. Constraints inherited from the specification are listed and honoured.
4. Open approval questions are listed explicitly.
5. Required tests and affected systems are identified.
6. Cross-references to other ADRs and to sections of this document are valid and
   not dangling.

A review may recommend amendments; it must not silently alter a decision.

## 19.2 Status discipline

- An ADR marked **Proposed** is not approved gameplay. It must not be described
  as specified, and rules it introduces must not be implemented as final
  (sections 14 and 18).
- An ADR moves to **Accepted** only after its approval questions are answered and
  any amendment is recorded.
- When an ADR is accepted, this specification is updated first; implementation,
  tests and technical documentation follow (section 15).

## 19.3 Gap ownership

| Gap | Topic | ADR | Status |
|---|---|---|---|
| 13.1 | Poker scoring values | ADR-001 | Proposed; reviewed, awaiting gameplay approval |
| 13.2 | Hand formation | ADR-001 | Proposed; reviewed, awaiting gameplay approval |
| 13.3 | Edge cluster definition | ADR-009 | Open - no file yet |
| 13.4 | Cluster bonus | ADR-009 | Open - no file yet |
| 13.5 | Turn rules | ADR-003 | Open - empty placeholder file |
| 13.6 | Tile distribution | ADR-004 | Open - empty placeholder file |
| 13.7 | AI evaluation | ADR-005 | Open - empty placeholder file |
| 13.8 | Board placement rules | ADR-006 | Open - empty placeholder file |
| 13.9 | Game end | ADR-003 | Open - empty placeholder file |
| - | Incremental scoring architecture | ADR-007 | Open - empty placeholder file |
| - | Godot project architecture | ADR-008 | Open - empty placeholder file |

No gap in section 13 may be treated as decided until its ADR is Accepted.
