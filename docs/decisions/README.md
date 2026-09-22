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
| ADR-001 | Poker Scoring Values | GAME_SPEC 13.1 | Open - pending decision |
| ADR-002 | Poker Hand Formation | GAME_SPEC 13.2 | Open - pending decision |
| ADR-003 | Turn Rules and Game End | GAME_SPEC 13.5, 13.9 | Open - pending decision |
| ADR-004 | Tile Distribution and Generation | GAME_SPEC 13.6 | Open - pending decision |
| ADR-005 | AI Evaluation and Search | GAME_SPEC 13.7 | Open - pending decision |
| ADR-006 | Board Placement Rules | GAME_SPEC 13.8 | Open - pending decision |
| ADR-007 | Incremental Scoring Architecture | Technical (GAME_SPEC 4.5, 12.3) | Open |
| ADR-008 | Godot Project Architecture | Technical (GAME_SPEC 9, 12.1, 12.2) | Open |
| ADR-009 | Edge Cluster Definition and Bonus | GAME_SPEC 13.3, 13.4 | Open - pending decision |

ADR-007 and ADR-008 are technical/architectural decisions; they do not change
game rules. ADR-001 through ADR-006 and ADR-009 change game rules and require an
explicit owner decision before implementation.

## Current file state

- The following ADR files exist but are empty (0 bytes) and await content:
  `ADR-003`, `ADR-004`, `ADR-005`, `ADR-006`, `ADR-007`, `ADR-008`.
- There is no `ADR-002` file yet; it is listed in the index because hand
  formation (GAME_SPEC 13.2) is a distinct decision from poker scoring values
  (13.1).
- The `ADR-001` file has a corrupted (non-ASCII) filename. It should be renamed
  to `ADR-001-poker-scoring-values.md` when its content is written.
- `ADR-009` does not exist yet; it is added to the index because edge clusters
  (GAME_SPEC 13.3, 13.4) are not covered by any existing ADR number.

## Blocking chain

Phase 1 implementation is blocked on the following decisions, in dependency
order:

1. ADR-006 (placement rules) and ADR-004 (tile generation) - prerequisites for
   the first playable board.
2. ADR-002 and ADR-001 (hand formation and values) - prerequisites for scoring.
3. ADR-009 (clusters) - completes edge scoring.
4. ADR-003 (turn rules and game end) - completes the game loop.
5. ADR-005 (AI evaluation) - completes the Human vs AI mode.
