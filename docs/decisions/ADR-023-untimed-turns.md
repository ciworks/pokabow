# ADR-023 — Untimed turns

**Status:** Decided by owner on 2026-10-24; implemented in local, verified AI and online play.

Players have no move deadline. Waiting, closing the app, opening settings and
reconnecting do not pass a turn, discard a staged move, alter a score or forfeit
a match. A turn still ends when its player commits a legal line, swaps, resigns,
or cannot make a legal move under the existing rules. Existing match-end rules
remain unchanged.

This decision supersedes ADR-017's 60-second action timer and the deadline
portions of ADR-019. The gameplay HUD shows the active player without a
countdown. Old local save timing fields are accepted and ignored. Migration 016
clears deadlines on existing server matches; new server matches have no
deadline. Network request timeouts and bounded AI computation remain operational
limits and do not consume a player's turn.

Future push notifications may remind a player about pending moves, but they
will not be used to expire or automatically resolve a turn under this rule.

The later [tournament decision](ADR-024-tournaments.md) adds a tournament-only
server turn clock and forfeits. Ordinary local, verified AI and online matches
remain untimed under this decision.
