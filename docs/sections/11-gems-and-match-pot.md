# 11 - Gems and Online Match Pot

**Status:** Core direction Decided on 2026-10-22; initial reward values approved provisionally for balancing. The online gameplay pot projection, gain animation, and pending result payout panel are Implemented and tested in Godot validation. Wallet settlement, account balance, achievement/ad grants, tournament spending and remaining policy details are Proposed or Future.

**Related:** [GAME_SPEC section 8.5](../GAME_SPEC.md), [ADR-007](../decisions/ADR-007-incremental-scoring-architecture.md), [ADR-012](../decisions/ADR-012-valid-hand-list.md), [ADR-015](../decisions/ADR-015-achievements.md), [ADR-016](../decisions/ADR-016-cosmetic-currencies.md), [ADR-019](../decisions/ADR-019-live-online-play.md).

## 1. Owner decisions

- **Gems replace the proposed earned Credits.** A separately named premium currency remains a future proposal, not part of this release.
- Gems have no monetary value. A match pot is system-funded from qualifying play; players do not ante, wager, transfer or lose existing wallet Gems when a match starts or ends.
- The first match-pot release applies to **online matches only**. Human-vs-AI matches do not generate a Gem pot or completion Gems under this decision.
- Both players' hands can grow one shared pot. At a win, the winner receives the pot. At a draw, the players split it evenly.
- **Every distinct committed poker-hand score event** grows the pot, including multiple distinct hands scored by one move. A hand category is not limited to one contribution per match. Duplicate delivery of the same event contributes nothing further.
- A player who resigns receives no completion bonus; the opponent receives the pot **only**, without a completion bonus. The same reward outcome applies if a future rule introduces a match-ending timeout/forfeit. The current turn timer merely passes a turn on timeout and does not forfeit a match; this document does not change that rule.
- A player who completes a normal online match receives a fixed completion reward, independent of the pot. The provisional amount is **10 Gems per player**.
- Achievement and optional rewarded-ad grants are desired Gem sources. Their amounts, eligibility and release timing are open.
- **Tournament entry will spend Gems** when tournaments launch. Entry price, eligibility alongside Table Level, cancellation/refund rules and tournament prizes remain open. Standard online matches do not charge an entry fee. No tournament prize pool funded by entry Gems is defined or implied.

The earlier [Credits and Cosmetic Economy proposal](10-credits-and-cosmetics.md) is superseded where it names earned Credits, restricts earned currency to cosmetics, or proposes AI match rewards. Its wallet and idempotency ideas remain candidates, not approved implementation.

## 2. Proposed earning and settlement rules

The server should derive a Gem contribution from each distinct, **committed poker-hand score event** in an eligible online match. Use the existing closed hand categories in ADR-012; do not run a second hand evaluator in the wallet or derive Gems as a percentage of score points. The contribution table should be versioned and locked for the match. Preview, undo, invalid moves, edge and cluster score events, and replay of the same event must not grow the pot. Distinct events of the same hand category each contribute. There is no per-match hand cap in this initial proposal; a cap would conflict with the chosen every-distinct-hand rule and would need a separate decision.

Provisional contribution table, approved for a first balancing pass on 2026-10-22:

| Existing hand category | Gems added to shared pot |
|---|---:|
| Pair | 2 |
| Two Pair | 4 |
| 3-straight | 6 |
| Three-of-a-Kind | 8 |
| 4-straight | 10 |
| Full House | 12 |
| 4-of-a-Kind | 14 |

These are Gem awards, not poker point values. All contributions are even, so any draw pot splits into whole Gems with no remainder. A normal completed match adds 10 Gems to **each** player's wallet outside the pot; this also applies to a draw. The values should be reviewed against observed match duration, hand frequency, win/loss rate and time to reach a tournament entry price before release.

The pot belongs to the match until settlement. A visible pot total is a projection of accepted contributions, not wallet currency. On a server-verified terminal result, atomically record pot settlement and each eligible completion grant in the account transaction ledger. Retry, reconnect, result replay and concurrent requests must have no second economic effect. If the settlement service is temporarily unavailable, retain a pending entitlement and retry without changing the game's result.

Settlement summary, including remaining open details:

| Topic | Recommended starting rule | Open detail |
|---|---|---|
| Hand frequency | Every unique committed poker-hand event contributes once, including multiple distinct hands from one move. The provisional even-value table above applies with no per-match cap. | Tune values after playtesting; any later cap needs a new decision. |
| Normal completion | Grant 10 Gems to both participants after a normal win, loss or draw. | Eligibility for unusually short matches. |
| Draw | Give each player exactly half of the pot; even-only contributions prevent a remainder. | None for the initial reward table. |
| Resignation | Opponent takes the accumulated pot only; neither player receives a completion grant. This treatment is decided. | None for the reward outcome. |
| Timeout | Existing turn timeout only passes a turn and has no special Gem effect. If a future match-ending timeout/forfeit is added, the opponent takes the pot only and neither player receives completion Gems. | Whether and how to introduce a match-ending timeout/forfeit is a separate gameplay decision. |
| Unfinished match | No wallet grant while in progress. | Recovery and administrative cancellation policy. |

No base pot, standard-match entry fee, score multiplier, difficulty adjustment or player balance deduction is approved. Tournament entry is a separate future Gem spend and needs its own atomic debit and refund rules.

## 3. Other earning sources

An achievement grant should be a separate, once-per-account entitlement keyed by achievement ID. The present achievement API accepts some client-reported unlocks; a server wallet must not mistake an authenticated claim for verified gameplay. Decide eligibility and any legacy backfill before awarding spendable Gems.

Ad grants should use an optional **rewarded ad** and verified reward evidence, with a per-account claim policy. The existing result-exit interstitial is not a rewarded ad and must not grant Gems. A failed, skipped or duplicate reward claim must not pay.

## 4. Accounting and presentation

Keep match score, Table Level XP and Gems separate. The backend owns an integer Gem balance, immutable transaction history, source identities and a versioned reward policy. Use unique source keys such as `(match, score_event_id)` for contributions and `(account, match, settlement_kind)` for wallet grants. A pot contribution is not itself an account transaction. Never accept a client-supplied Gem amount as authority.

Show the live pot unobtrusively during an online match. The result screen can separate `Pot won` or `Draw share` from `Completion Gems`, while the hub/profile can show confirmed balance and pending awards. New UI must follow [DESIGN_SYSTEM](../DESIGN_SYSTEM.md), including its semantic palette, typography, compact mobile layout and icon treatment. The centered online HUD placement follows the owner-approved concept; device-level visual tuning remains.

Implemented on 2026-10-22: the online game HUD computes the live pot from the
server's committed ledger with `GemPotRules`, replacing the centered tile stack
for online play. Newly received distinct poker-hand events show `+N GEMS` near
the hand and a short faceted-gem flight into the pot; the count rises on
arrival. Repeated event IDs cannot animate twice. Resume/reconnect initializes
the view from the full ledger. Reduced motion skips travel and pulse. Human-vs-AI
retains the tile stack. This is an in-match visual projection, **not a spendable
wallet grant** or a claim that the backend settled the prize.

The online result screen now shows a compact pending payout projection from
that same committed ledger: pot plus completion for a normal winner, completion
for the loser, equal pot shares on a draw, and pot only for the opponent after
resignation. It is hidden for AI and incomplete matches. This display does not
credit a wallet; confirmed balance and idempotent backend settlement remain
unimplemented.

The first release should use server-authoritative online match events and terminal results. Do not issue spendable Gems from locally saved AI games or client-submitted match snapshots without a separate trust decision. Gem settlement must not alter a legal move, score, turn result or matchmaking rating. A future tournament entry debit must be atomic with confirmed registration, with retry-safe identity and an explicit cancellation/refund policy; this is not part of the match-pot implementation.

## 5. Verification required before release

- Each hand category maps to its configured contribution; stronger hands give more; one event cannot add twice.
- Multi-hand moves, retries, reconnects, restoring results and concurrent settlement produce the same pot and one payout.
- Win, draw, resignation and unfinished-match paths pay only the approved entitlements; ordinary turn timeout remains a turn pass.
- Both account balances reconcile to transaction history, and no player balance is debited by a match pot.
- Achievement and rewarded-ad claims cannot pay twice or pay from unverified evidence under the selected trust policy.
- Mobile UI clearly distinguishes the match pot, pending rewards and confirmed balance.

## 6. Decisions still needed

1. Eligibility for unusually short matches; tune provisional hand and completion values after playtesting.
2. Achievement reward amounts, eligibility and legacy backfill; rewarded-ad amount, daily limit and verification method.
3. Tournament entry price, optional Table Level requirement, registration/debit timing, withdrawal/cancellation refunds and tournament prizes.
4. What players can redeem Gems for at launch besides future tournament entry, if anything.
