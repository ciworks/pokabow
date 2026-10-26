# ADR-024 — Tournaments

- **Status:** Decided by owner on 2026-10-26; not implemented.
- **Resolves:** `GAME_SPEC.md` section 8.6 and tournament spending in section 8.5.
- **Detailed rules:** [Tournament specification](../sections/13-tournaments.md).

## Context

The Tournaments destination is currently a placeholder. Table Level, verified
online results and the confirmed Gem wallet exist, but no bracket, Gem spending,
scheduled tournament match or admin management path exists. Tournament matches
need an explicit exception to [ADR-023's untimed ordinary turns](ADR-023-untimed-turns.md).

## Decision

The initial mode is a live, server-authoritative, randomly drawn
single-elimination bracket with 4, 8 or 16 entrants. The backend owns
configuration, eligibility, registration, timekeeping, bracket results,
leaderboard and wallet effects. The first web interface is for administrators;
players enter and play through the mobile game.

Entry may require any combination of minimum Table Level, server-verified
online wins and confirmed Gem balance. All configured thresholds apply. The
server checks them at registration, atomically reserves one place and deducts
the published stake. Only one registered or live tournament per account is
allowed. An unfinished ordinary online match may remain resumable. Published
eligibility, stake, prize, capacity and start time cannot change; staff cancel
and recreate an event if those rules need to change.

Registration closes at the published start time. A full bracket starts
automatically; an underfilled one cancels and refunds existing entrants. A player
who leaves before closing gets a full refund. Leaving after closing keeps a
forfeited bracket slot and no refund. Staff may cancel after play starts in an
emergency, refunding every existing account that paid a stake, including prior
forfeits. Deleted accounts cannot receive a later refund; deletion must warn
about this. Already confirmed prizes and verified match XP/rating updates are
not reversed. If every remaining player forfeits, the event ends without a
champion or prize and stakes remain spent. If both finalists forfeit, they
appear as joint eliminated finalists with no first-place leaderboard entry.

The administrator chooses a one-, two- or five-minute turn limit for that
tournament. Each ready pairing allows five minutes for players to join; the
first turn clock begins when both have joined. Clocks are server-owned and
continue through disconnection. No-shows forfeit; two no-shows eliminate both
and the next opponent advances if one exists. Draws replay immediately, with a
new join window and no new stake, until a decisive result. Later-round pairings
become ready as soon as both entrants are known.

The champion alone receives a fixed, system-funded Gem prize, separate from
entry stakes. Tournament matches grant ordinary Table Level XP and online
rating for the decisive played match but no ordinary match-pot or completion
Gems. An in-match resignation or timeout is a verified win with XP and rating;
an unplayed no-show advancement is not. Verified historical online wins and
decisive tournament wins count toward future entry requirements. The
leaderboard ranks by bracket placement, sharing places for elimination in the
same round. The pre-draw list shows a filled-place count only; after the draw,
the bracket shows public display names and avatars. Deleted accounts are
anonymised in retained results.

## Consequences

The existing wallet schema needs signed debits and refunds with idempotent
source keys and a nonnegative balance constraint. Tournament matches need
separate recovery from ordinary matchmaking, server jobs for scheduled start
and expiry, and admin authorization and audit records. Ordinary online and AI
matches retain their untimed turns and current Gem rewards. The detailed
specification governs all remaining lifecycle and account-deletion behavior.

## Verification

Use database concurrency and idempotency tests for entry, capacity, refunds,
and prize settlement; server-clock tests for no-shows and turn expiry; bracket
and replay tests; and Godot integration and device checks. No tournament
implementation or verification is claimed by this decision record.
