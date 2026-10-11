# ADR-018 - Resignation

- Status: Decided; implemented
- Date: 2026-10-10
- Resolves: GAME_SPEC 13.5, 13.9

## Context

The game had no early-ending action. The owner requested a settings-menu option
that ends the active match and marks the rival as winner, and requested that the
final game information reach the API.

## Decision

- The human may choose **Resign** in the game settings drawer while a match is
  active, including while the rival is thinking.
- Choosing it opens a confirmation dialog: "Are you sure you want to end the
  game? This will be marked as a Loss." **Yes** confirms resignation;
  **No** dismisses the dialog and leaves the match active.
- Resignation ends the match immediately. The rival wins regardless of the
  committed score; the scores and move history do not change.
- The local result uses outcome `AI_WIN` and end reason `RESIGNATION`. The
  normal match-ended event sends the completed status and final snapshot through
  `PATCH /games/{gameId}`. The snapshot records the winner outcome and reason.
- Resign is disabled once the match is over. Resignation does not introduce a
  score penalty, bonus, or separate reward rule.

## Consequences

The result screen still reports the committed score breakdown and identifies
resignation as the end reason. The client API sync stores the supplied result in
the local snapshot; the current API does not independently validate the winner,
so this is not server-authoritative adjudication.

## Verification

The transition is integrated with the same terminal-state path used by regular
match endings. Automated or manual runtime verification was not performed for
this change.
