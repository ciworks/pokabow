# 11 - Gems and Match Pots

**Status:** Core direction Decided on 2026-10-22; AI pot extension approved on 2026-10-23. Online wallet rules were approved on 2026-10-24: every normal completed online match receives the 10 Gem completion grant, including short matches, with no backfill; resignation pays the opponent the pot only. The owner also approved spendable, capped AI pot grants on 2026-10-24 for newly completed server-verified matches, with no completion grant or backfill. On 2026-10-24 the owner chose to require server-controlled AI for spendable payouts, leaving locally played AI matches ineligible. Online and AI settlement, account balance, and server-owned AI play are Implemented; production migration and device checks remain. [Tournament spending](13-tournaments.md) was Decided on 2026-10-26 but is not Implemented. Achievement/ad grant details remain Proposed or Future.

**Related:** [GAME_SPEC section 8.5](../GAME_SPEC.md), [ADR-007](../decisions/ADR-007-incremental-scoring-architecture.md), [ADR-012](../decisions/ADR-012-valid-hand-list.md), [ADR-015](../decisions/ADR-015-achievements.md), [ADR-016](../decisions/ADR-016-cosmetic-currencies.md), [ADR-019](../decisions/ADR-019-live-online-play.md).

**Verification:** The API build, payout tests, and 13 disposable PostgreSQL integration tests passed, including concurrent replay, pending settlement retry, and exclusion of older AI matches. Godot result and pot scene assertions, server AI moves at all three difficulties, and a headless app launch passed with the available Godot 4.7.2 executable. A working Godot 4.6 executable and mobile device check were unavailable.

## 1. Owner decisions

- **Gems replace the proposed earned Credits.** A separately named premium currency remains a future proposal, not part of this release.
- Gems have no monetary value. A match pot is system-funded from qualifying play; players do not ante, wager, transfer or lose existing wallet Gems when a match starts or ends.
- Online and human-vs-AI matches each show a system-funded Gem pot. AI matches have a separate capped policy described in section 2.1; they have no completion grant and the AI never receives Gems.
- Both players' hands can grow one shared pot. At a win, the winner receives the pot. At a draw, the players split it evenly.
- **Every distinct committed poker-hand score event** grows the pot, including multiple distinct hands scored by one move. A hand category is not limited to one contribution per match. Duplicate delivery of the same event contributes nothing further.
- A player who resigns receives no completion bonus; the opponent receives the pot **only**, without a completion bonus. The same reward outcome applies if a future rule introduces a match-ending timeout/forfeit. Current turns have no timer or automatic forfeit.
- A player who completes a normal online match receives a fixed completion reward, independent of the pot: **10 Gems per player**, including short matches. Newly completed verified matches qualify; historical matches are not backfilled.
- Achievement and optional rewarded-ad grants are desired Gem sources. Their amounts, eligibility and release timing are open.
- **Tournament entry will spend Gems** when tournaments launch. The owner has chosen a configurable stake deducted at registration, a fixed system-funded champion prize, and full refunds for withdrawal before registration closes or tournament cancellation for existing accounts. The [tournament specification](13-tournaments.md) records the complete rules, including account deletion. Standard online matches do not charge an entry fee. Entry Gems do not form the tournament prize pool.

The earlier [Credits and Cosmetic Economy proposal](10-credits-and-cosmetics.md) is superseded where it names earned Credits or restricts earned currency to cosmetics. Its wallet and idempotency ideas remain candidates, not approved implementation.

## 2. Earning and settlement rules

The server should derive a Gem contribution from each distinct, **committed poker-hand score event** in an eligible online match. Use the existing closed hand categories in ADR-012; do not run a second hand evaluator in the wallet or derive Gems as a percentage of score points. The contribution table should be versioned and locked for the match. Preview, undo, invalid moves, edge and cluster score events, and replay of the same event must not grow the pot. Distinct events of the same hand category each contribute. The online pot has no cap; the AI pot uses the separate whole-match caps below.

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

These are Gem awards, not poker point values. All contributions are even, so any draw pot splits into whole Gems with no remainder. A normal completed **online** match projects 10 Gems for each player outside the pot; this also applies to a draw. The values should be reviewed against observed match duration, hand frequency, win/loss rate and time to reach a tournament entry price before release.

### 2.1 AI match pot (Decided; verified settlement Implemented)

The AI match uses the same per-hand contribution table, but stops the whole pot at **20 Gems for Easy, 40 for Medium, and 80 for Hard**. Each distinct committed hand from either player contributes once, limited by the remaining capacity. A human win projects the full pot, a draw half, and a loss or resignation zero. The AI receives nothing; unclaimed Gems disappear. AI matches have no completion grant. Players never ante or lose existing Gems.

The reward ceiling starts at the selected difficulty and follows the **lowest difficulty used during that match**. Raising difficulty later cannot raise the ceiling; a downgrade immediately lowers the projection and persists through save/resume. Older saves with no reward-tier field use the Easy ceiling. Difficulty still controls AI decisions normally. These caps and the hand amounts are provisional; tune them against observed rewards per minute and win rates before wallet release.

The authenticated AI match API owns the seed, AI turns, authoritative state and terminal result. Matches created after the wallet migration are eligible for an idempotent account grant on server-verified completion. The older game sync API still stores client-supplied snapshots, and locally saved or older AI matches remain ineligible. Their result labels AI Gems **Not credited**; eligible verified matches show **Pending** until settlement is confirmed. There is no historical backfill. This also applies to new offline matches: replaying client-submitted moves can verify legality and scoring, but cannot attest that the offline AI actually selected its recorded moves. The owner chose server-controlled AI as the requirement for spendable payouts.

The pot belongs to the match until settlement. A visible pot total is a projection of accepted contributions, not wallet currency. On a server-verified terminal result, atomically record pot settlement and each eligible completion grant in the account transaction ledger. Retry, reconnect, result replay and concurrent requests must have no second economic effect. If the settlement service is temporarily unavailable, retain a pending entitlement and retry without changing the game's result.

Settlement summary, including remaining open details:

| Topic | Recommended starting rule | Open detail |
|---|---|---|
| Hand frequency | Every unique committed poker-hand event contributes once, including multiple distinct hands from one move. The provisional even-value table above applies with no per-match cap. | Tune values after playtesting; any later cap needs a new decision. |
| Normal completion | Grant 10 Gems to both participants after a normal win, loss or draw, including short matches. | None for the first release. |
| Draw | Give each player exactly half of the pot; even-only contributions prevent a remainder. | None for the initial reward table. |
| Resignation | Opponent takes the accumulated pot only; neither player receives a completion grant. This treatment is decided. | None for the reward outcome. |
| Timeout | No move deadline or automatic timeout exists. If a future match-ending timeout/forfeit is added, the opponent takes the pot only and neither player receives completion Gems. | Whether and how to introduce a match-ending timeout/forfeit is a separate gameplay decision. |
| Unfinished match | No wallet grant while in progress. | Recovery and administrative cancellation policy. |

No base pot, standard-match entry fee, score multiplier or player balance deduction is approved. The AI difficulty cap above does not change the online pot or match score. Tournament entry is a separate future Gem spend and needs its own atomic debit and refund rules.

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
the view from the full ledger. Reduced motion skips travel and pulse. AI matches
reuse that presentation with a visible cap and `POT FULL` state. This is an in-match visual projection, **not a spendable
wallet grant** or a claim that the backend settled the prize.

The online result screen shows a compact payout from
that same committed ledger: pot plus completion for a normal winner, completion
for the loser, equal pot shares on a draw, and pot only for the opponent after
resignation. It marks server-confirmed online settlement as confirmed and leaves
pending settlement as a projection. AI results show the human's pot only,
without an AI payout column or completion grant. The status distinguishes
confirmed, pending and ineligible local results. Incomplete matches hide the panel.
The hub Gem chip opens a read-only history of confirmed wallet transactions. My Profile
does not duplicate the balance or history. The current account wallet endpoint returns
the latest 50 transactions, which the history screen identifies when that limit is hit.
After a verified online or server-controlled AI result confirms settlement, the
client refreshes that wallet. A refresh requested during an earlier balance
read is queued so the confirmed award is not hidden by a stale response.

The first release uses server-authoritative online match events and terminal results. Spendable AI Gems require server-controlled AI turns; locally saved games and client-submitted snapshots are ineligible, including after reconnect. Gem settlement must not alter a legal move, score, turn result or matchmaking rating. A future tournament entry debit must be atomic with confirmed registration, with retry-safe identity and an explicit cancellation/refund policy; this is not part of the match-pot implementation.

The Shop screen presents 20 Gems for an optional rewarded ad, and four preview packs of 100/340/800/1,800 Gems labelled £0.99/£2.99/£5.99/£9.99. A completed ad is granted only after AdMob's signed server-side callback passes verification. The server enforces a rolling 24-hour limit per account; the panel disables the action and shows when it becomes available again. Production Android/iOS rewarded ad unit IDs, their 20-Gem reward setting, and their server-side callback URL must be configured before the offer is enabled. The four purchase buttons remain previews and cannot debit or credit the wallet.

The hub header now shows a faceted Gem chip using that same confirmed wallet balance. Its outline follows the Shop Gem artwork and the other header icons. It shows a dash until data arrives, never a projected match-pot amount. The chip opens account Gem history; the adjacent Shop icon opens the offer preview. Tournaments replaces Shop in bottom navigation as a coming-soon destination; it has no Gem spend or reward behaviour yet.

## 5. Verification required before release

- Each hand category maps to its configured contribution; stronger hands give more; one event cannot add twice.
- AI pot caps bind the entire match at 20/40/80, downgrade cannot raise a later payout, and the AI never receives Gems.
- Multi-hand moves, retries, reconnects, restoring results and concurrent settlement produce the same pot and one payout.
- Win, draw, resignation and unfinished-match paths pay only the approved entitlements; waiting never settles or forfeits a match.
- Both account balances reconcile to transaction history, and no player balance is debited by a match pot.
- Achievement and rewarded-ad claims cannot pay twice or pay from unverified evidence under the selected trust policy.
- Mobile UI clearly distinguishes the match pot, pending rewards and confirmed balance.

## 6. Decisions still needed

1. Tune provisional hand and completion values after playtesting for future policy versions.
2. Achievement reward amounts, eligibility and legacy backfill; rewarded-ad amount, daily limit and verification method.
3. What players can redeem Gems for at launch besides tournament entry, if anything.
