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

## Presentation update — 2026-10-18
Implemented the owner-approved category overview and six-badge pages. This
presentation change does not expand the five initial achievement triggers.
Catalogue names, requirements and unlocks remain server-supplied. Optional
category metadata is accepted (a name string, or an object with name/id);
known initial IDs retain local presentation grouping, and unknown ungrouped IDs
appear under Milestones instead of being dropped.

The browser provides All/Unlocked/Locked filters, category search, paginated
category and badge grids, and readable locked/unlocked detail panels.
Unlock timestamps (unlockedAt or unlocked_at) are optional; without them,
the overview labels its three featured unlocked badges "Unlocked highlights".
Catalogue fetch errors are exposed with Retry; cached in-memory rows remain
visible on refresh failure. No new persistence or unlock-granting path is added.
See docs/DESIGN_SYSTEM.md for the visual rules and validation record.

## Progress achievements — 2026-10-20

The account catalogue now also supports achievements backed by named progress
metrics. `two_pair_10` counts ten distinct human-attributed committed Two Pair
score events across matches. `perfect_match` recognizes one committed five-tile
Full House whose tiles contain all four suits and whose four internal hand
boundaries have matching rotated edge colours. These checks do not alter
placement, hand scoring, or match outcome.

The client queues stable event IDs locally and submits them to
`POST /achievements/progress`. The API records each ID once per account and
unlocks threshold achievements in the same transaction. New catalogue entries
count events received by the API after their creation; an offline event from
earlier play can count when submitted later. Existing account unlocks and the five
initial triggers remain intact. The API still trusts client-reported evidence;
progress records are retry-safe, not server-verified gameplay.

The API admin page at `/admin/achievements` can add achievements for registered
metrics and edit presentation metadata. Admin authorization uses the
`ADMIN_EMAILS` allowlist. A new predicate requires a tested client detector and
registration in the API metric allowlist. Badge keys resolve only to art shipped
with the client; unfamiliar keys use the milestone star. AppRoot hosts a queued
achievement toast on its persistent OverlayLayer, and the collection shows
current progress. The toast can be announced from locally projected progress;
server synchronization may complete later when offline.
