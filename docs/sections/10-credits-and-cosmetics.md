# 10 - Credits and Cosmetic Economy

**Status:** Proposed specification, 2026-10-05. No currency implementation or economy testing is claimed.
**Related:** [GAME_SPEC section 8.5](../GAME_SPEC.md#85-credits-and-cosmetic-economy-proposed-2026-10-05), [ADR-016](../decisions/ADR-016-cosmetic-currencies.md), [ADR-015](../decisions/ADR-015-achievements.md).

## 1. Purpose and confirmed direction

Give players lasting cosmetic progress from playing Pokabow, including losing a match. Achievements, daily logins, and particular hands are candidate additional reward sources. A later shop proposal will cover real-money purchases.

The owner explicitly chose **separate earned and premium currencies** on 2026-10-05. Both are restricted to cosmetics: there must be no pay-to-win mechanics. This refines the original idea of buying additional credits into buying a separate premium currency. It does not approve any reward amounts, shop prices, conversion rules, or catalog exclusivity.

Everything below is a recommendation for review unless explicitly identified as owner direction. In particular, sample values are balancing inputs, not approved game rules.

## 2. Relevant patterns in other games

Research checked on 2026-10-05. These are selected examples, not an exhaustive survey or evidence that one model maximizes retention. Historical announcements are identified as such; their old values are not presented as current prices.

| Example and primary source | Documented pattern | Possible application to Pokabow |
|---|---|---|
| [Fall Guys currency announcement, 15 June 2022](https://www.fallguys.com/news/upcoming-fall-guys-currency-changes?lang=en-US) | The 2022 design separated Kudos and Show-Bucks, differentiated their cosmetic catalogs, and offered currency through challenges/progression. It explicitly removed end-of-match Kudos at that launch. | Separate balances and clear catalog labels are useful. Pokabow's requested win/loss rewards deliberately retain match earnings. Avoid making the earned catalog feel neglected. |
| [Rocket League Credits support](https://www.epicgames.com/help/c-37599050/a17019170?lang=en-US) | Credits are purchased in packs, spent on cosmetics/content, and can be earned back through Rocket Pass Premium progression. | A premium currency can have controlled reward sources, but pass-based earn-back is not equivalent to free match earnings. A pass would add a separate progression/content commitment and is deferred. |
| [Guild Wars 2 Wizard's Vault support](https://help.guildwars2.com/hc/en-us/articles/19617357502867-Secrets-of-the-Obscure-Wizard-s-Vault) | Objectives award Astral Acclaim, which cannot be bought with money or gems. Players choose specific rewards; cosmetic rewards remain available through a legacy catalog. | Let players save for a chosen cosmetic and retain access to older cosmetics. Borrow these features only; this is not a claim that Guild Wars 2's entire economy is cosmetic-only. |

The resulting recommendation is two currencies, direct selection of known cosmetics, a useful permanent earned catalog, modest recurring rewards, and no initial paid pass or random reward boxes. These are design judgments, not conclusions established by the examples.

## 3. Currency and cosmetic boundaries

| Property | Earned Credits | Premium currency (name to be decided) |
|---|---|---|
| Main source | Eligible matches and approved engagement rewards | Verified real-money purchases in a later release |
| Launch scope | Proposed first economy release | Future shop proposal |
| Balance | Separate account-wide integer balance | Separate account-wide integer balance |
| Spend | Explicitly priced cosmetics | Explicitly priced cosmetics |
| Free award sources | Defined below | None assumed; occasional milestone/event grants remain an option |
| Conversion | No conversion proposed in either direction | No conversion proposed in either direction |

Recommended common rules:

- New balances start at zero. No expiry, seasonal balance reset, player trading, gifting, wagering, or cash-out is proposed.
- Credits do not buy match entry, extra moves, tile selection, rerolls, hints, stronger tiles, score factors, easier AI, or competitive information. Paid earning boosts are also excluded from this proposal.
- Neither currency changes the board, hand rules, scoring, turn order, tile supply, or AI behavior. Existing hand multipliers remain gameplay rules and cannot be bought.
- Cosmetic examples: avatars, profile frames, board surrounds, table backgrounds, decorative tile backs/borders, and score celebrations.
- Tile cosmetics must preserve rank, suit, edge-color semantics, orientation, and readability. Accessibility options and essential visual indicators remain free. Effects must respect reduced-motion settings and must not obscure play.
- Owned cosmetics remain owned when unequipped. Prevent charging twice for the same entitlement.

**Catalog recommendation, still open:** maintain distinct earned and premium collections, with a worthwhile selection and continuing additions for earned Credits. Premium-only appearances may exist, but must have no functional advantage. Whether selected items offer alternative prices in either currency needs approval; separate currencies alone do not decide this. Achievement badges remain earned recognition and cannot be bought.

## 4. Earning Credits

### 4.1 Match completion

Proposed scope: ordinary Human-vs-AI matches, on all three difficulties, at equal reward rates initially. Reward the human account only. Tutorials, debug tools, automated tests, and any future custom or PvP mode are not implicitly eligible.

Use the existing final `MatchResult`, not a UI victory message or a reported API score. A valid match end is `BOARD_FULL`, `TILE_SOURCE_EXHAUSTED`, or `NO_LEGAL_MOVES`, with outcome `HUMAN_WIN`, `AI_WIN`, or `DRAW`.

| Result | Proposed behavior | Illustrative Credits |
|---|---|---:|
| Human win | Completion grant plus win bonus | 40 + 20 = 60 |
| Human loss | Completion grant | 40 |
| Draw | Completion grant plus smaller draw bonus | 40 + 10 = 50 |
| In progress / interrupted | Wait for a valid final result | 0 for now |
| Incomplete / rules failure | No completion grant; recovery can later produce an eligible result | 0 |
| Abandoned match / Clear game cache | No completion grant; these are not match results | 0 |

These are alternative totals, not stackable outcome rewards. A match pays once per account, including after loading its final save or retrying a request. Normal losses never remove Credits.

Recommend no arbitrary minimum duration or number of human placements initially: a legitimate short match or no-legal-moves ending should not be penalized. This includes a valid zero-placement ending if the rules allow one. Monitor rapid completion and seed manipulation before launch; introduce any eligibility threshold only through an explicit amendment. Resignation rewards remain undefined; the local result records the rival as winner, but no separate reward policy is approved.

### 4.2 Achievements

Attach a one-time Credit entitlement to the existing five achievement IDs; do not change their unlock conditions. Example values:

| Existing ID | Illustrative Credits |
|---|---:|
| `first_hand` | 50 |
| `straight` | 75 |
| `full_house` | 100 |
| `edge_cluster` | 75 |
| `ai_victory` | 100 |

The total first-set entitlement in this example is 400 Credits. Grant each once per account, independently of how often its unlock is submitted. An achievement and a match reward may both pay on the same event; their receipts explain the separate reasons.

Recommend a one-time backfill for already unlocked achievements when Credits launch. Record the entitlement separately from the unlock so a migration or retry cannot pay twice. Existing unlocks are client-reported and cannot be retrospectively described as verified gameplay; accepting a bounded legacy backfill is an explicit rollout choice. Backfill amounts and eligibility need approval.

Achievements earned from committed moves remain unlocked if a match is later abandoned. Their one-time currency entitlement follows that existing achievement behavior; repeatable hand bonuses below have a different settlement rule.

### 4.3 Daily login

Recommend 15 Credits once per account per server UTC calendar day, automatically on the first successful authenticated game session that day. This is not a rolling 24-hour cooldown. Display the next reset in the player's local time and a countdown.

No login streak is required; missing a day removes nothing and does not reduce the next day's reward. Multiple devices, app restarts, token refreshes, and clock changes do not create additional claims. An offline launch alone does not establish a trusted login date: reconnecting awards only the current server day's entitlement, without backdating missed days. Daily reset semantics require approval.

### 4.4 Playing particular hands

Recommend small, bounded match bonuses from committed human-attributed poker score events:

| Reward key | Qualifying existing category | Illustrative Credits / match |
|---|---|---:|
| `straight` | Either 3-straight or 4-straight | 10, once across both kinds |
| `full_house` | Full House | 10, once |
| `four_of_a_kind` | 4-of-a-Kind | 10, once |

The example maximum is 30 Credits per match. Previews, cancelled moves, reloaded event history, AI moves, and repeated qualifying hands do not award extra Credits. A line forming several qualifying categories can satisfy several distinct keys. Read hand category evidence from the scoring system; do not duplicate poker recognition or calculate currency as a percentage of points.

Show these bonuses as pending during play and settle them only with an eligible completed match. Abandonment cancels these pending repeatable bonuses. Existing achievement unlocks keep their separate behavior. Whether players prefer immediate hand payouts is an open design choice; settlement at completion discourages repeatedly starting and abandoning matches.

### 4.5 Later engagement ideas

Possible additions include weekly participation goals, milestone achievements, and event objectives. Favor achievable participation and varied play over mandatory win streaks or rare hands on a daily deadline. A seven-login collection that pauses when absent is an alternative to a punitive consecutive-day streak. None of these systems, reward values, or premium grants are approved by this proposal.

## 5. Earning pace and pricing hypotheses

Choose cosmetic effort targets first, then tune earnings and prices together. Starting examples for an earned catalog are 250 Credits for a small cosmetic, 500 for a more elaborate cosmetic, and 1,500 for a larger theme. They are not shop commitments or real-money equivalents.

With 50% wins and 50% losses, no draws, and no additional rewards:

`expected match Credits = 0.5 * 60 + 0.5 * 40 = 50`

| Example price | Wins only, 60 each | Losses only, 40 each | At 50 Credits average |
|---|---:|---:|---:|
| 250 | 5 matches | 7 matches | 5 matches |
| 500 | 9 matches | 13 matches | 10 matches |
| 1,500 | 25 matches | 38 matches | 30 matches |

Counts round upward. Two matches per day at that average plus the sample login grant yield 115 Credits/day before hand bonuses and achievements. A 500-Credit item then takes about five such days from zero. At a hypothetical 15 minutes per match, ten matches represent 150 minutes; actual match duration and hand frequency have not been measured for this proposal. The 400-Credit achievement set intentionally accelerates early progress and must not be included in recurring income forecasts.

Before fixing values, measure match duration, win rate by difficulty, completion rate, bonus frequency, earned/spent Credits, balance distribution, and time to first cosmetic. Check casual players and players who repeatedly lose, not just average or expert players. A modest win bonus can still make rapid losing attractive per minute; evaluate that behavior explicitly. Equal difficulty rewards may favor Easy for farming and should be reviewed against observed play.

Recommend no hard daily match-earning cap initially. The hand cap limits one source only. Address duplication and invalid claims through validation; any broader cap or diminishing returns must be disclosed and approved. Version reward configuration, preserve previously settled awards, and never silently devalue existing balances. Catalog supply and regular earned-cosmetic additions matter as much as numerical balance.

## 6. Wallet, persistence, and trust

Recommended model: account-owned balances and a durable server transaction history, with offline reward claims queued locally. Confirmed balances are spendable; pending claims are shown separately. Offline gameplay continues, and already owned cosmetics remain usable. Fully offline spending is an alternative requiring a different reconciliation design; it is not assumed approved.

Keep currency accounting separate from `ScoreLedger`, `MatchResult`, and match snapshots. Restoring or clearing a match must not roll back a wallet or delete award deduplication records. Keep pending reward evidence in account-scoped storage independent of the match cache; switching accounts must never transfer it to the next authenticated account.

The service derives amounts from versioned reward rules and eligible facts, rather than accepting an arbitrary balance or amount from the client. Granting, recording an entitlement, and updating a balance must be atomic. Requests can be retried; their economic effect occurs at most once. Currency debit and cosmetic ownership must also commit atomically when redemption is later built.

**Existing limitation:** ADR-015 trusts achievement IDs submitted by the client, and the current game sync API stores client snapshots with placeholder server scoring. Authentication and successful sync do not validate a match. A server-owned wallet prevents duplicate transactions and conflicting spending, but does not by itself prevent fabricated wins, hands, or achievements.

Two implementation paths need an explicit choice:

1. A limited earned-only pilot may accept client-reported facts with documented limits, monitoring, and no premium purchases or currency conversion. It remains vulnerable to forged rewards; caps are mitigation, not proof.
2. A stronger release validates match provenance, tile supply, move history, lifecycle, and rewards on the server. Server-issued match identities/seeds or another approved offline issuance scheme are needed to limit fabricated matches. Replaying an arbitrary client-created history proves consistency, not that the claimed human actually played it.

Paid currency requires verified purchase receipts and a durable transaction ledger before launch. The later shop design must also decide whether forged earned claims could unlock shared entitlements or promotional premium grants. Neither path is implemented here. An offline eligibility/provenance policy is a release dependency, not something the existing sync client already solves.

## 7. Player experience

- Show earned Credits by name and icon in the hub/profile. Introduce a clearly distinct premium balance when that currency launches; do not advertise a working purchase action before one exists.
- On match completion, separate game score from Credit rewards: completion, outcome bonus, hand bonuses, and newly earned achievements. Daily rewards are their own account activity and are not added to match score.
- Distinguish confirmed, pending sync, and rejected claims. Pending amounts are excluded from spendable balance. On rejection, show an understandable reason and retry/recovery options where appropriate.
- Automatically award eligible rewards; closing a popup must not lose them. A transaction history provides durable receipts after notices disappear.
- A later catalog shows the currency, price, owned state, preview, and remaining balance before confirmation. Purchases must not silently consume the other currency or mix balances.
- Keep standard cosmetics available permanently where practical. Time-limited events should not erase earned currency or owned items. Do not add loss-screen pressure to purchase premium currency.

## 8. Delivery boundaries

| Stage | Scope | Status |
|---|---|---|
| Design | Review reward rules, trust model, pacing, and ADR | Proposed; this document |
| Earned economy | Credits wallet, completion rewards, transaction history, recovery; achievements/login/hand rewards as approved | Proposed; after core gameplay, no Phase 1 requirement |
| Cosmetic redemption | A small useful earned catalog, ownership, equip flow, atomic redemption | Future; coordinate with wallet release so players have a meaningful use for Credits |
| Premium shop | Premium branding, catalog, payment provider/store integration, packs, receipts, refunds, cross-platform rules | Future; separate proposal |
| Additional engagement | Weekly goals, events, optional premium grants | Future; separate approval |

No real-money pack values or premium cosmetic prices are set here. The shop proposal must define receipt validation, duplicate delivery, pending/cancelled purchases, refunds/chargebacks including already-spent currency, recovery, parental purchase controls, and platform balance portability before monetization is enabled. These are design dependencies, not claims of platform or legal compliance.

## 9. Review decisions still needed

| Question | Recommendation / options |
|---|---|
| Currency structure | **Owner chose separate earned and premium currencies.** Working name Credits for earned; premium name open. |
| Catalog relationship | Recommend useful separate collections; decide premium exclusives and any alternative-currency pricing. |
| Premium earned sources / conversion | Recommend neither initially; milestone premium grants are a later option. |
| Reward pacing | Review illustrative 40/50/60 outcomes, 15 login, achievement values, 30 hand cap, and example prices through playtests. |
| Eligibility | Approve equal difficulty rates, legitimate short endings, and treatment of abandoned/incomplete matches. |
| Daily model | Approve UTC day, automatic online claim, no streak reset, and no offline backdating; local-day alternatives require account timezone rules. |
| Hand settlement | Recommend completion settlement; immediate grants are an alternative with greater abandonment farming risk. |
| Existing achievements | Recommend one-time backfill; decide whether to accept client-trusted legacy unlocks. |
| Offline / authority | Recommend pending claims then online confirmation/spend; choose client-trusted pilot or stronger validated issuance before release. |
| Rollout | Approve earned economy and useful cosmetic redemption sequencing; premium shop stays deferred. |

## 10. Acceptance criteria for later implementation

These are required verification scenarios if the corresponding proposal is approved; they have not been run against a credits implementation.

1. Eligible wins, losses, and draws use their configured totals; incomplete, abandoned, debug, and preview activity cannot claim completion rewards. Legitimate no-legal-moves and short endings follow the approved eligibility policy.
2. Restarts, final-save reloads, repeated callbacks, request timeouts, and concurrent devices cannot duplicate a match, daily, achievement, backfill, or hand entitlement.
3. Hand bonuses come only from committed human events, observe the combined straight key and per-match cap, and settle according to the approved completion policy.
4. UTC boundaries, daylight-saving display changes, altered device clocks, offline reconnects, and multiple devices produce the approved daily behavior.
5. Balances reconstruct from transactions; atomic grants and spends survive crashes and competing requests without losing awards, overspending, or charging twice for an owned cosmetic.
6. Offline pending claims survive restart and match-cache clearing; rejected claims never become spendable. Account switches cannot mix balances, entitlements, or pending evidence.
7. Existing achievements receive only the approved backfill. Re-importing old saves, deleting remote match records, or changing reward versions cannot create new entitlements for the same source.
8. Identical gameplay inputs with different wallets and cosmetics produce identical legal moves, tile generation, AI decisions, scores, and outcomes. Verify mobile readability and reduced-motion behavior visually.
9. Forged amounts and cross-account claims are rejected. The selected trust model is documented accurately; a client-trusted pilot must not claim verified gameplay.
10. Before premium launch, separately verify purchase receipt replay, refunds, recovery, account/platform restrictions, and entitlement consistency against the approved shop design.
