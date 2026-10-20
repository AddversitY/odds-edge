# Odds Edge capability roadmap

Owner direction, 2026-10-19: incorporate the major capabilities of OddsJam,
Outlier, Rithmm, Unabated and Pikkit while making research clearer and more
reproducible. This is the product target, not a statement that feature parity
already exists. Broad multi-sport coverage remains the end goal. No purchase,
signup, account linking, paid AI call or extra live-odds refresh is authorized.

## Purpose and primary journey

Help users investigate a betting idea, test what could invalidate it, freeze
the reasoning, and learn from the result. The first complete journey is:

**Overview → Investigate a bet → choose player → evidence → scenario replay →
save prediction → review final production.**

Player/game data, actual quotes, user assumptions and model output must retain
separate provenance. AI explains attached evidence; deterministic calculations
produce results. A confident narrative is not evidence of forecasting skill.

## Public feature comparison

Reviewed primary product pages on 2026-10-19. These are vendor descriptions,
not exhaustive hands-on audits, independently verified profitability claims,
or proof that a competing product lacks a feature.

| Product | Documented capabilities to cover | Primary source |
|---|---|---|
| OddsJam | EV scanning, arbitrage, parlay builder, promotion conversion, tracking | https://oddsjam.com/betting-tools/positive-ev |
| Outlier | Props/game research, recent/season hit rates, player/team filters, opponent context, best-price shopping; wider product also advertises alerts and movement | https://help.outlier.bet/en/articles/6711738-research-player-propositions-with-outlier-s-prop-finder and https://www.outlier.bet/ |
| Rithmm | Custom and community models, backtesting, predictive outputs, AI explanations, line shopping, tracking, player-impact adjustments and parlays | https://www.rithmm.com/ai-sports-betting |
| Unabated | Odds screens, no-vig market reference, custom props distributions/simulations, alternate pricing, futures/pool tools | https://unabated.com/tools/tools-summary and https://www.unabated.com/tools/core/props-simulator |
| Pikkit | Account-synced bet tracking, performance/CLV analysis, line shopping and execution conveniences | https://pikkit.com/closing-line-value and https://pikkit.com/autofill |

We use the underlying general capabilities, our own interface and calculations,
and licensed/public data. Vendor designs, private methods and proprietary data
are not copied. "Better" needs evidence from user tasks and model evaluation.

## Delivery matrix

| Capability | Current status | Requirement before completion |
|---|---|---|
| Player and team explorer | Implemented NFL public-data snapshots, three-game form, prior seasons, game logs | Scheduled licensed/public refresh, richer opponent/participation context, verified additional sports |
| Guided investigation | Implemented first NFL yardage journey, frozen evidence and manual outcome review | Usability testing, further market models and normalized live-prop matching |
| Scenario simulator | Implemented paired historical game replay with explicit workload/efficiency scaling | Chronological evaluation, calibrated distributions and coherent game-state/injury/role models |
| Best-price comparison | NFL moneyline/spread/total provider layer, exact selection matching, freshness labels and quota-aware snapshots | Verify actual book/region/market rights and availability; props/alternate markets need additional adapter support |
| No-vig market reference | Core odds/probability arithmetic exists; no complete market-reference product | Named removal method, complete opposing outcomes, rules/line matching, source/freshness and uncertainty |
| Positive-EV scanning | Conditional EV calculator/replay exists; no validated opportunity scanner | Tested predictive probability or explicitly named market-based estimate; no probability invented to fill gaps |
| Arbitrage scanner | Deferred live scanner; roadmap restored as eventual competitor capability | Exact exhaustive outcomes, aligned settlement, current accessible quotes, fees/stakes/limits and approved feed budget |
| Promotions / boosts / hedges | Planned | Explicit promotion/settlement terms, validated payout arithmetic, original implementation; no profit guarantees |
| Model builder | Manual probability assumptions and versioned player scenario inputs | Validated sport/market models, source snapshots, train/validation separation, parameter constraints and saved versions |
| Historical replay/backtesting | Retrospective date filtering and educational holdout baseline | Authentic point-in-time input/odds history; leakage prevention, walk-forward evaluation, uncertainty and baselines |
| Research AI | Backend-only xAI Explain/Challenge exists for frozen quotes/assumptions and optional evidence | Attach actual relevant evidence throughout journeys, request/token/concurrency budgets, no automatic paid requests |
| Bet and forecast journal | Local research, investigations, manual results, export/import and probability-error diagnostics | Approved sync provider/accounts for actual bets; record all forecasts, not just placed or winning bets |
| CLV and performance analytics | No verified automated closing feed; manual outcomes supported | Actual exact-selection closing quote, named no-vig method, acquisition times; ROI distinct from calibration and CLV |
| Movement history / alerts | Collected odds history; no push alert service | Licensed storage, comparison with previous snapshots, account preferences, duplicate suppression, rate/cost limits |
| Correlated parlays / DFS | Planned; independence must never be silently assumed | Validated joint game/player model, correlation tests, platform-specific payouts/rules and exact leg identities |
| Futures / survivor / pick'em | Planned | Schedules, standings, contest rules and sport-specific validated simulation models |
| Social/community models | Planned later | Accounts, privacy, moderation, full performance histories and controls against cherry-picked results |
| Subscription / accounts / distribution | No payment or account system activated; native Windows prototype, iOS CI | User-approved service costs, entitlements, signing/unique bundle ID; TestFlight remains on hold |
| Web version | Separate workstream | Inspect open PRs before web/ or CORS changes; this investigation work does not change either |

## Quality criteria

1. A new user can complete and save one investigation without needing to
   understand every tool in the application. Test that with actual users.
2. Every displayed statistic has a date/window and source. Missing data remains
   missing; player IDs and precise lines determine identity.
3. Saved reports reproduce from their frozen records, model version and random
   seed. New data does not rewrite an old forecast.
4. Scenario probabilities remain explicitly conditional until evaluated on
   unseen games. More simulation trials do not create more observations.
5. Every claimed improvement is evaluated: task completion/time and clarity for
   UX; calibration/proper scores and chronological baselines for models.
6. No feature expansion silently increases the live polling schedule or signs
   up for a feed. Budget constraints are part of the architecture.

## Sequence

Known backend hardening remains part of this work queue: dispatch slow assistant
requests without blocking odds/health requests; cap AI requests/tokens/concurrency;
attach relevant evidence to AI requests; conservatively reserve credits for
kickoff weeks not yet listed by the provider's events feed; expose absent-book
coverage; and provide an explicit migration path for the old shared snapshot
journal. The new player investigation is offline and does not require those
services or change their current refresh schedule. No web/CORS changes are made.

Complete and test the guided player investigation first. Then add market
reference/price tools and richer statistical context, validate probability
models and replay, and only then expand scanners, alerts, joint simulations,
account sync and additional leagues as their inputs and budgets are approved.
NFL is the initial implementation slice; launch coverage must be agreed rather
than silently narrowed to NFL.
