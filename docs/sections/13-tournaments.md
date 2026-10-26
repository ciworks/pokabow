# 13 - Tournaments

**Status:** Gameplay and economy requirements Decided by the owner on
2026-10-26. Implementation, integration and testing are pending.

**Related:** [Game modes](06-game-modes.md), [Gems and match pots](11-gems-and-match-pot.md),
[online play](../ONLINE_PLAY.md), and [Modern Tabletop](../DESIGN_SYSTEM.md).

## 1. Confirmed product rules

- Tournaments use server-authoritative online matches in a single-elimination
  bracket and are intended to run live in one session. The first release
  supports 4, 8, or 16 participants and does not need initial byes. Entrants are
  placed into the bracket by a random draw at the start.
- An administrator configures each tournament in the backend through a web
  interface, including its registration opening time, start date and time,
  participant limit, entry stake, champion prize, eligibility requirements,
  and tournament-only turn limit. Registration closes automatically at the
  published start time, when the server forms and starts the bracket. A
  published start time cannot be changed; staff cancel with full refunds and
  create a new tournament instead. Eligibility, stake, prize, and capacity are
  also locked at publication; rule changes require cancellation and recreation.
- A tournament may require a minimum Table Level, a minimum count of completed
  server-verified online wins, a minimum confirmed Gem balance, or any
  combination of these. An entrant must meet **all** configured requirements.
  The minimum balance is checked before the stake is deducted. The confirmed
  wallet must also hold enough Gems to pay the stake. Verified tournament wins
  count toward later tournaments' online-win requirement. Historical
  server-verified online wins from before tournaments launch also count.
  Eligibility is locked when registration succeeds and is not rechecked at
  the scheduled start.
- Registration reserves one place and deducts the configured Gem stake in one
  server transaction. A retry or concurrent registration cannot take a second
  stake or exceed capacity. A player can withdraw before registration closes
  and receive the full stake back. Leaving after registration closes forfeits
  the player's place without a stake refund. A player may have at most one
  registered or live tournament entry at a time. An unfinished ordinary
  untimed online match may remain resumable during tournament participation.
- A cancelled tournament refunds the stake to every existing account that paid
  it, including a player who forfeited after registration closed. A deleted
  account cannot receive a later refund. If all places are not filled at the
  published start time, the tournament cancels and refunds all existing
  entrants rather than starting with byes.
  Otherwise, entry stakes are spent; they do not form the prize pool. The
  administrator sets a fixed, system-funded Gem prize for the champion only. A
  confirmed champion prize is never reversed, even if staff later cancel the
  tournament. Staff may cancel after play starts as an emergency action, with
  entry-stake refunds under the account rule above. Completed match results,
  Table Level XP, and online rating updates remain valid after cancellation.
  If every remaining player forfeits, the tournament ends without a champion
  or prize, and the stakes remain spent. If both finalists forfeit, the
  leaderboard shows them as joint eliminated finalists with no first-place
  entry.
- Tournament matches have a configurable, tournament-only turn timer and
  forfeit on timeout. Ordinary online and AI matches retain their untimed-turn
  rule. Admins choose a 1, 2, or 5 minute limit. The server clock continues
  while the active player is disconnected or has backgrounded the app. A player
  who fails to join a ready match within five minutes forfeits. The first turn
  clock begins when both players join. If neither joins within five minutes,
  both forfeit and the next opponent advances if possible. A drawn tournament
  match is replayed immediately without a new entry stake, with a fresh
  five-minute join window. Replays continue until the pairing has a decisive
  result.
- Tournament matches grant the ordinary Table Level XP and online skill rating
  update only for the deciding match in each pairing. A draw followed by a
  replay grants no XP or rating change for the drawn match. Tournament matches
  do not grant the ordinary online match Gem pot or completion Gems. The
  champion prize is credited once after the bracket result is final, including
  when the champion advanced through an opponent timeout or forfeit. Winning
  a match that already started through an opponent timeout or resignation
  counts as a verified win and grants the usual tournament-match XP and rating
  change. Advancing because an opponent never joined is a bracket advancement
  only: it does not count as a win or award XP or rating.
- Each tournament has its own live bracket and leaderboard. The champion is
  first; players eliminated in the same round share the same placement. A
  later-round match becomes ready as soon as both of its entrants are known;
  it does not wait for unrelated matches in the previous round. Entrants appear
  by their public display name and public avatar. Before the draw, the player
  sees the filled-place count but not the other entrants' identities.
- A player who leaves after registration closes keeps their assigned bracket
  slot as a forfeit. Their opponent advances without a bracket redraw.
- Account deletion follows the same timing rules: before registration closes it
  withdraws the entry and refunds the stake; after closing it forfeits the
  bracket place without a stake refund. Deletion during a started match is a
  verified resignation win for the opponent, including tournament-match XP
  and rating change. Retained bracket and leaderboard results are anonymised
  rather than removed. The deletion confirmation must explain that a deleted
  account cannot receive a refund if the tournament is cancelled later.

## 2. Player and administrator flows

The mobile Tournaments destination should list upcoming, entered, live, and
completed tournaments from the backend. A detail view should show localised
start time, registration deadline, available places, entry stake, fixed prize,
eligibility and the player's specific eligibility status. Registration must
show the stake and confirmed wallet effect before submission. The same view
should show withdrawal while it is allowed, then the bracket, next match,
turn deadline, leaderboard, and final result. Loading, full, ineligible,
insufficient-Gems, cancelled, and offline states need plain explanations.

The first web interface is for administrator management. A player-facing web
experience may follow later; tournament participation at launch is in the
mobile game. The administrator web UI should allow authorised staff to create drafts,
configure and preview rules, publish registration, inspect entrants and wallet
effects, start a bracket, monitor matches, cancel with refunds, and inspect an
audit trail. Admin changes after publication need explicit restrictions so a
player cannot pay under one set of terms and play under another.

All tournament configuration, eligibility decisions, registration, bracket
state, timekeeping, results, leaderboard, wallet debits/refunds/prizes, and
admin actions are server-owned. The Godot client displays server decisions and
submits authenticated actions; it does not calculate eligibility or awards.

## 3. Backend requirements

The backend needs persistent tournament definitions and a versioned published
rules snapshot, registrations, bracket rounds and matches, leaderboard
placements, admin audit entries, and tournament wallet transactions. Schedule
instants should be stored in UTC and shown to players in their local time with
an explicit time-zone label. Server time controls registration, scheduled start,
and turn expiry; starting a tournament cannot depend on an open admin browser.

Registration must recheck level, verified-online-win count, confirmed balance,
time window, capacity, and prior registration while holding the required
database locks. Stake debit, seat reservation, and an idempotency record commit
together. Withdrawal and cancellation refunds also commit atomically and only
once. Tournament Gem transactions need signed debits and credits, a nonnegative
wallet invariant, source identities, and a visible history entry. The current
wallet schema accepts positive credits only, so spending requires a migration;
client-side subtraction is insufficient.
Tournament start, no-show and turn expiry must be processed by the backend even
when no mobile client or admin browser is connected.

Tournament matches should reuse the existing server-authoritative game rules
and private player views while adding tournament identity, bracket progression,
and the approved timer policy. They must bypass public matchmaking. Accepted
terminal results advance the bracket once, even after retries or reconnects.
A drawn match creates a replay rather than advancing either player. The final
champion prize must be idempotent and auditable.

The backend API should cover tournament list/detail, player eligibility,
registration/withdrawal, bracket and leaderboard reads, tournament match
recovery/actions, and restricted admin lifecycle actions. The admin web UI and
Godot client should consume the same backend state.

## 4. Delivery order

1. Add database migrations, server domain logic, wallet debits/refunds/prize
   credits, admin authentication/audit, and concurrency tests.
2. Build the admin web workflow for publishing and managing tournaments.
3. Connect tournament matches to the online game engine and build bracket,
   timing, draw replay, and leaderboard tests.
4. Replace the mobile Tournaments placeholder with list/detail, registration,
   match entry, and results screens using the design system; verify on devices.

## 5. Implementation boundaries

No gameplay or Gem payout rule remains open for the initial tournament mode.
The tournament-only clock is an explicit exception to
[untimed ordinary turns](../decisions/ADR-023-untimed-turns.md). Engineering work
still needs database migrations, admin authorization, reliable server jobs,
tournament-specific match recovery, and mobile device verification. These
choices must preserve the decided rules above.

No tournament logic, Gem debit, or web management interface has been
implemented yet.

## 6. Verification targets

- Concurrent entrants cannot take the last place twice, register twice, or
  spend more Gems than the confirmed wallet holds.
- Withdrawal and cancellation return each eligible stake exactly once; a
  normal entry is debited exactly once and a champion prize is credited once.
- Server time controls published start, no-show and turn expiry despite client
  clock changes, disconnects, retries and process restarts.
- Draw replays do not charge another stake or grant extra XP, rating or Gems.
- Every terminal match result advances the bracket at most once, and the
  leaderboard agrees with the stored bracket.
- Tournament-only timing and Gem rules do not change ordinary online or AI
  matches. Admin-only actions reject unauthorised accounts and are audited.
