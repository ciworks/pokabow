# ADR-016 - Earned and Premium Cosmetic Currencies

- **Status:** Historical proposal, superseded in part on 2026-10-22 by [Gems and Online Match Pot](../sections/11-gems-and-match-pot.md). Earned Credits and cosmetic-only earned use are no longer owner direction; the accounting ideas below remain proposals.
- **Date:** 2026-10-05
- **Resolves:** GAME_SPEC 8.5 and 13.10 (proposed economy); implications for sections 11.5 and 14.
- **Related:** ADR-007 (score events), ADR-003/010/011 (match lifecycle), ADR-012 (hand categories), ADR-015 (achievements).
- **Detailed proposal:** [Credits and Cosmetic Economy](../sections/10-credits-and-cosmetics.md).

## Context

The owner wants persistent cosmetic progress from wins, losses, achievements,
daily logins, and particular hands, with optional paid currency in a later shop.
On 2026-10-05 the owner explicitly selected separate earned and premium
currencies. Neither may provide a gameplay advantage.

The game already exposes stable match identity, committed `ScoreEvent` records,
and final `MatchResult` outcomes through `GameSessionController`. Achievement
unlocks have account persistence and retries. There is no wallet or cosmetic
currency system in the inspected client source.

Current achievements trust submitted IDs; game sync stores client-supplied
snapshots and does not authoritatively score or validate play. These interfaces
provide integration points, not proof of reward eligibility. See
[API integration](../API_INTEGRATION.md) and ADR-015.

## Constraints

- Preserve gameplay rules, deterministic scoring, incremental updates, and AI.
- Keep currency transactions separate from gameplay score events.
- Preserve account isolation and reward identity across devices and retries.
- Gameplay must continue when currency services are unavailable.
- Premium purchasing and shop implementation remain future work.
- This record cannot promote proposed values or architecture to approved rules.

## Options considered

| Choice | Benefits | Costs / disposition |
|---|---|---|
| One earned-and-purchased currency | Simple balance and pricing | Owner selected separate currencies instead. |
| Separate earned and premium currencies | Clear reward and purchase sources; distinct pricing | Owner-selected direction; requires clear labels and a worthwhile earned catalog. |
| Local balances with fully offline spending | Immediate offline use | Save editing, rollback, and multi-device reconciliation complicate future purchases; not recommended. |
| Server wallet with offline pending claims | Atomic accounting, recovery, cross-device consistency | Recommended; confirmation/spending needs connectivity and fact validation remains a separate concern. |
| Fully validated reward facts before any launch | Stronger control of match-based issuance | Requires backend gameplay/provenance work absent from current sync. |
| Client-trusted earned-only pilot | Smaller first delivery | Forged facts remain possible; explicit restricted pilot decision needed. No premium economy is implied. |

## Proposed decision

### 1. Two balances and one accounting boundary

Use earned Credits and a separately named premium currency, both account-owned
integer balances. Recommend no conversion or transfer. A dedicated reward
service evaluates entitlements; a wallet service records currency transactions;
a later cosmetic inventory owns purchased appearance entitlements. These may be
modules within the existing API, not separate deployed services.

`ScoreLedger` remains exclusively about match points. Currency grant failures
cannot reject a legal move, change a result, or trigger a second scoring commit.
Godot UI consumes wallet/reward state and does not mint currency.

### 2. Durable entitlement identity and atomic transactions

Minimum conceptual records, with schema/API names to be finalized:

- Transaction: server ID, account ID, currency, signed integer amount, reason,
  source entitlement key, reward policy version, server timestamp, and optional
  reversal reference.
- Wallet: account and currency, confirmed balance, revision. Its balance must
  reconcile to the transaction history.
- Reward claim: stable source identity, account owner, required evidence,
  eligibility decision, and pending/accepted/rejected state.
- Cosmetic entitlement (later): unique account/item ownership and its purchase
  transaction; equipped selection is separate from ownership.

Illustrative unique grant keys are `(account, match, completion)`,
`(account, match, hand_reward_key)`, `(account, achievement_id)`, and
`(account, UTC_date, daily_login)`. Qualify keys by currency/reward program where
needed. Do not add policy version to a key in a way that allows a previously
rewarded source to pay again after a configuration update.

The server derives amount and policy version. Entitlement consumption, ledger
insertion, and balance update commit together. Timeouts return the same durable
result on retry. Duplicate conflicting claims must be rejected or reconciled
against the authoritative source, never summed. New reward configuration does
not rewrite historical transactions. A match's reward policy should be pinned
to trusted match registration; offline policy assignment requires an approved
issuance scheme rather than trusting a client timestamp.

Future redemption atomically checks balance and ownership, debits the selected
currency, and grants the cosmetic. The original transaction remains in history
after any correction; append a linked adjustment instead. Spending cannot make
the confirmed balance negative. Refund handling after currency was already
spent requires a separate shop policy and must not silently create debt here.

### 3. Integrate existing events without trusting presentation

Use `GameSessionController.get_match_id()`, committed human `score_awarded`
events, and `match_ended(MatchResult)` as client evidence sources. Durable claims
must also be recoverable from saved facts: correctness cannot depend on whether
a transient signal or popup was delivered. Preserve existing achievement IDs
and unlock conditions; add a separate once-only reward entitlement.

The detailed proposal owns reward amounts and eligibility recommendations; do
not duplicate the sample tables in code or this ADR. An economy configuration
must eventually be a single versioned source independent of poker score rules.

### 4. Offline and account lifecycle

Recommend queued offline evidence and visibly pending awards, followed by server
confirmation before spending. Cache confirmed balances and owned cosmetics for
display/use; a cached balance does not authorize an offline purchase. Persist
pending evidence independently of match saves and pin it to its originating
account. Clearing a match or deleting its sync record cannot erase transaction
history or allow its awards to be claimed again.

Authentication expiry pauses claims without interrupting play. Retries preserve
identity. Account switching cannot drain one account's queue under another
account's token. Match-cache cleanup must retain any evidence needed to settle
already earned claims. A brand-new offline match's eligibility remains subject
to the approved issuance/provenance policy.

### 5. Trust and premium readiness

Server accounting does not verify that gameplay happened. Choose explicitly
between a documented client-trusted earned-only pilot and stronger backend
validation of provenance, legal history, scoring, lifecycle, and eligibility.
Neither a submitted `completed` flag nor an authenticated achievement ID is
sufficient proof for the stronger path. Validating replay alone does not prevent
invented match histories or client-controlled seeds.

Before premium purchases, verify store receipts server-side and deduplicate by
provider transaction identity. Keep purchased and promotional premium sources
identifiable for later recovery/refund rules even if they share one displayed
premium balance. Catalog overlap and premium reward grants require assessing
whether client-trusted earned activity could obtain premium entitlements.

No wallet endpoints, migrations, payment integrations, or backend validation are
claimed to exist as a result of this ADR.

## Consequences

This design preserves the current gameplay domain and reuses its committed
facts. It introduces account storage, configuration, claim recovery, transaction
history, and later inventory responsibilities. It needs backend work and
connectivity for confirmation and purchases. A limited pilot can reduce initial
scope but retains an explicit forgery risk.

Affected areas include the application event wiring, API clients, account state
storage, match-cache cleanup, achievements, hub/profile/results presentation,
and the external Tiletopia backend. Turn rules, scoring, AI search, and tile
generation consume no wallet data. No runtime changes are made by this record.

## Open decisions and acceptance

Currency separation and cosmetic-only use are confirmed. Remaining decisions
are tracked in [proposal section 9](../sections/10-credits-and-cosmetics.md#9-review-decisions-still-needed):
catalog overlap, premium grants/conversion, names, reward values and eligibility,
daily reset, hand settlement, legacy achievement backfill, offline policy,
issuance trust, and delivery sequencing.

Review against GAME_SPEC section 20 before marking this ADR Decided. Sample
amounts need balancing evidence or explicit provisional approval; silence is
not acceptance. The future shop requires its own design before implementation.

## Verification

The detailed proposal's acceptance criteria cover reward eligibility, retries,
concurrency, daily boundaries, save recovery, account isolation, migration,
forgery boundaries, cosmetic readability, and unchanged gameplay. Backend
transaction tests and client integration tests are required alongside manual
mobile checks. Premium purchase/refund tests belong to the later shop work.

For this draft, verification is limited to source/document inspection, checking
references, and reviewing proposal consistency. There is no credits code to run.
