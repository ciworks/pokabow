# Architecture & Design Decision Records (ADRs)

This folder records the explicit decisions that resolve the open items in
`docs/GAME_SPEC.md` section 13 and establish the project's technical
architecture.

## Why ADRs exist here

`GAME_SPEC.md` section 18 and `AGENTS.md` sections 2 and 20 both forbid silently
inventing unspecified game rules. When a rule is undefined, the required process
is:

1. Identify the missing rule.
2. Explain why it is required.
3. Propose one or more interpretations.
4. Obtain an explicit decision.
5. Record the decision (an ADR).
6. Update `GAME_SPEC.md` where appropriate.
7. Implement against the approved decision.

An ADR is the record produced by steps 5-6.

## Status vocabulary

An ADR uses the same vocabulary as the rest of the documentation
(`GAME_SPEC.md` section 14): **Specified**, **Decided**, **Implemented**,
**Tested**, **Proposed**, **Future**. An ADR is only binding once its status is
**Decided**.

## ADR template

```markdown
# ADR-NNN - Title

- Status: Proposed | Decided | Superseded
- Date: YYYY-MM-DD
- Resolves: GAME_SPEC section(s)

## Context
What is undefined and why it matters.

## Options considered
The candidate interpretations.

## Decision
The chosen rule, stated precisely enough to implement and test.

## Consequences
Effects on scoring, AI, turn flow, tests, and future features.

## Verification
How the decision is tested (per AGENTS.md section 16).
```

## Index

| ADR | Title | Resolves | Status |
|---|---|---|---|
| ADR-001 | Poker Hand Formation and Scoring | GAME_SPEC 13.1, 13.2 | Accepted |
| ADR-002 | Edge Cluster Definition and Bonus | GAME_SPEC 13.3, 13.4 | Accepted |
| ADR-003 | Turn Rules and Game End | GAME_SPEC 13.5, 13.9 | Accepted; superseded in part by ADR-010 |
| ADR-004 | Tile Distribution and Generation | GAME_SPEC 13.6 | Accepted; section 6 superseded by ADR-010 |
| ADR-005 | AI Evaluation and Search | GAME_SPEC 13.7 | Accepted; amended by ADR-010 |
| ADR-006 | Board Placement Rules | GAME_SPEC 13.8 | Accepted |
| ADR-007 | Incremental Scoring Architecture | Technical (GAME_SPEC 4.5, 12.3) | Accepted; section 5 superseded by ADR-010 |
| ADR-008 | Godot Project Architecture | Technical (GAME_SPEC 9, 12.1, 12.2) | Proposed; technical approval open in ADR |
| ADR-010 | Deck of Six and Multi-Placement Turns | GAME_SPEC 13.5, 13.6 | Accepted |
| ADR-011 | Line Placement and Hand Legality | GAME_SPEC 13.5, 13.8 | Decided; supersedes parts of ADR-006, ADR-007, and ADR-010 |
| ADR-012 | Valid Hand List | GAME_SPEC 5.3 | Accepted |
| ADR-013 | Tile Scoring Multipliers | GAME_SPEC 5.7 | Accepted |
| ADR-014 | Joker Supply Cap | GAME_SPEC 13.6 | Accepted |
| ADR-015 | Account Achievements | GAME_SPEC 8.3, 14 | Decided |
| ADR-016 | Earned and Premium Cosmetic Currencies | GAME_SPEC 8.5, 13.10 | Proposed; currency separation and cosmetic-only direction confirmed |
| ADR-017 | Sixty-second turns | GAME_SPEC 13.5; Mobile UX | Decided; implemented |
| ADR-018 | Resignation | GAME_SPEC 13.5, 13.9 | Decided; implemented |

ADR-007 and ADR-008 are technical/architectural decisions; they do not change
game rules. ADR-001 through ADR-006, ADR-010, and ADR-011 change game rules
and required an explicit owner decision before implementation. ADR-011 records the later owner
decision that makes a move one legal line or one swap.

`ADR-009` is not used. That number was reserved here for the edge-cluster
decision, which was delivered as `ADR-002` instead; the reservation is left
recorded so the number is never silently reused.

## Current file state

Every ADR listed in the index above has a file. ADR-008 and ADR-016 remain
Proposed in their own status fields; the other listed ADRs are accepted or decided:

- `ADR-001-poker-hand-formation-and-scoring.md`
- `ADR-002-edge-cluster-definition-and-bonus.md`
- `ADR-003-turn-rules-and-game-end.md`
- `ADR-004-tile-distribution-and-generation.md`
- `ADR-005-ai-evaluation-and-search.md`
- `ADR-006-board-placement-rules.md`
- `ADR-007-incremental-scoring-architecture.md`
- `ADR-008-godot-project-architecture.md`
- `ADR-010-deck-of-six-and-multi-placement-turns.md`
- `ADR-011-line-placement-and-hand-legality.md`
- `ADR-012-valid-hand-list.md`
- `ADR-013-tile-multipliers.md`
- `ADR-014-joker-supply-cap.md`
- `ADR-015-achievements.md`
- `ADR-016-cosmetic-currencies.md`
- `ADR-017-turn-timer.md`
- `ADR-018-resignation.md`

Where an ADR has been partly superseded, the amendment entry at the end of that
ADR names the new decision. Read the amendment before implementing any
superseded section.

## Blocking chain

No decision currently blocks Phase 1 implementation. The original blockers were
resolved as follows:

1. Board placement rules - ADR-006. Generated tiles remain playable while board
   space exists.
2. Hand formation and values - ADR-001.
3. Edge clusters - ADR-002, which also covers the open item the index once
   reserved as ADR-009.
4. Turn rules and game end - ADR-003, superseded in part by ADR-010.
5. AI evaluation and search - ADR-005, amended by ADR-010.
6. Project architecture - ADR-008.
