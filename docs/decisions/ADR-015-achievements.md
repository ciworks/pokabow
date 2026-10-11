# ADR-015: Account Achievements

* **Status:** Decided
* **Date:** 2026-09-29
* **Decision scope:** Account-wide engagement milestones
* **Related:** `GAME_SPEC.md` sections 8.3 and 14; ADR-007 (committed score events); ADR-012 (valid hand categories)

## Context

Pokabow's scoring ledger and final match result expose deterministic events that
support achievement milestones without adding gameplay bonuses or changing
match rules. The Tiletopia API provides authenticated accounts and can persist
unlock state across devices.

## Decision

1. The first release contains five permanent, account-wide achievements:
   `first_hand`, `straight`, `full_house`, `edge_cluster`, and `ai_victory`.
2. The client derives the first four from committed score events attributed to
   the human player, and derives `ai_victory` only from a final Human Win result.
3. The Tiletopia API owns the catalog and unique per-user unlock records. The
   authenticated client may submit known IDs; repeated submissions are
   idempotent. `GET /achievements` returns the catalog and caller unlock state;
   `POST /achievements/unlocks` accepts achievement IDs.
4. The hub's Achievements action opens the achievement list. No achievement
   changes game scores, legality, tile generation, or outcome.
5. Unlock IDs are queued in local account state while offline and retried after
   authentication.

## Security limitation

The current API authenticates the caller and validates achievement IDs, but it
does not verify the submitted trigger or replay game history. A modified client
can forge an unlock. These achievements are therefore account-persistent but
not cheat-resistant. Server-authoritative move validation is a prerequisite for
claiming stronger verification.

## Implementation notes

Apply `tiletopia-api/migrations/006_achievements.sql` after the existing API
migrations. Configure the Pokabow API host through the saved Server IP or the
`pokabow/server_ip` project setting (HTTP port 3000). If the API is unavailable, gameplay
continues and pending IDs remain in the local account record.
