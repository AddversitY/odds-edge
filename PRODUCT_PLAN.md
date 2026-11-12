# Odds Edge product direction

## Recovered original vision

**2026-10-19 update:** The owner approved a guided investigation as the primary
experience and wants the major competitor capabilities incorporated over time,
with clearer presentation and original implementation. The concrete delivery
matrix is `docs/COMPETITOR_CAPABILITIES.md`; current scenario methodology is
`docs/PLAYER_SIMULATION.md`. This expands the eventual capability target without
approving subscriptions, signup, extra live API refreshes or prematurely claiming
feature parity. The first connected player-yardage workflow uses frozen public
data and explicit conditional replay; broad sport coverage remains the end goal.

The actual original platform and niche replies are now readable from the shared
conversation. See `docs/ORIGINAL_BRAINSTORM.md` for the source-linked reference.
Its five pillars are Deep Statistical Explorer, Advanced Simulation Engine,
Sportsbook Odds Laboratory, Parlay Correlation Analyzer and Transparent AI
Research Assistant. The proposed signature is Proof Lab: a connected workflow
for point-in-time replay, reliability testing and prediction autopsy, with game
script simulation and market-quality checks.

Windows should become the full analytical workstation with multiple charts,
customizable panels and detailed tables. iOS retains equal analytical depth
through touch-friendly tabs and expandable views. These are target capabilities,
not a description of the current MVP's implementation.

Latest explicit direction: return to the original analytical vision and keep
arbitrage out of the initial phase. This resolves the earlier tentative budget
discussion below. Keep broad multi-sport scope and affordable, licensed odds
comparison. No new spending or vendor outreach is approved.

## Decision reference — read before product or architecture changes

This document is the working reference for the owner's original application
request and subsequent explicit requirements. Evaluate feature priorities,
provider selection, pricing research, and architectural decisions against the
complete goal below. Do not silently narrow the product to the prototype.

**End goal:** a professional sports betting analytics application for iOS and
Windows, offering deep statistical analysis, live multi-sportsbook aggregation,
exact-selection comparison, history, and evidence-based analytical tools across
the broadest practical range of legally supported sports and leagues.

**Scope clarification, October 18, 2026:** NFL is only the first demonstration
and implementation slice. The published product is intended to be multi-sport,
including college football, tennis, combat sports (MMA/boxing), and as many
additional sports and leagues as reliable licensed feeds support. NFL-only
coverage does not fulfill the intended launch scope. Maintain an explicit
sport/league/book/market coverage matrix; agree any launch exclusions rather
than assuming universal coverage or quietly omitting sports.

The owner's latest direction also favors a free download with a potential paid
research/arbitrage tier. Monetization is exploratory: no pricing, payment flow,
subscription, or provider purchase is approved. Preserve original design and
analysis rather than copying competitors. Arbitrage detection is proposed, not
implemented, and must not be presented as guaranteed profit.

**Pending budget discussion, October 18, 2026:** the owner subsequently asked to
pause before confirming the sequencing change below. Treat it as a proposed
low-cost path, not a finalized removal or deferral of requirements. No provider
purchase, vendor outreach or scope change is authorized by this discussion.

The owner explicitly cannot
justify roughly $300/month in data costs before earning revenue. Defer arbitrage
scanning and premium low-latency feeds to a later phase. Return immediate work
to the original deep statistical analytics product, matchup research,
probability/EV tools and transparent odds comparisons. Keep the multi-sport
end goal and modular multi-book architecture. Do not interpret this sequencing
decision as permission to remove live comparison from the core MVP or quietly
turn sample/stale observations into current data.

Use demonstration data and suitable public statistical datasets while building;
evaluate free or inexpensive licensed odds access with explicit quotas and
refresh schedules. No exact monthly spending cap is set and no purchase is
approved. Any initial missing books, markets, slower update cadence or limited
sport rollout must be visible and agreed, not represented as universal coverage.
Research/data quality still requires suitable historical records and rights;
deferring arbitrage does not make those requirements disappear.

Revisit premium feeds only when an approved budget and sustainable operating
plan justify them. Revenue is uncertain; do not assume the app will fund a
subscription by any particular date. Preserve the option for optional paid
analytical features that provide value independently of an arbitrage scanner.

Read the full confirmed requirements, flagship contracts and safeguards below
when considering changes. If a proposed shortcut conflicts with them, make the
tradeoff explicit before treating it as a scope change.

## Confirmed requirements

- Multi-sport end product; NFL first for the demonstration. Deep statistical
  analysis of sports betting odds across supported leagues.
- iOS is the primary experience, with a native Windows application.
- Compare as many sportsbooks as practical through authorized data feeds.
- Live multi-sportsbook aggregation, comparison, and analysis are core MVP
  functionality, built alongside the dashboard, not deferred enhancements.
- Differentiate through transparent analysis and useful statistical niches.
- No purchases or paid subscriptions without the owner's approval.

The earlier brainstorming replies were initially unavailable but were recovered
through the later shared link. The reference above now anchors this working
plan; subsequent explicit user requirements take precedence over old proposals.

## Proposed central experience: an evidence report for every opportunity

Show the best available price, comparable sportsbook quotes, market-implied
probability, a clearly identified model estimate, uncertainty, freshness,
supporting evidence, counterarguments, and the price at which value disappears.
Separate market disagreement from a validated predictive advantage.

## First working version

1. Responsive NFL analytical dashboard and matchup explorer.
2. Interactive probability, fair-price, and expected-value calculator with pushes.
3. Exact-selection sportsbook comparison for NFL moneylines, spreads, totals,
   and player props/alternate lines when provider coverage is available.
4. Working best-price selection, accessible-book filters, implied probabilities,
   price differences, source and collection timestamps, stale/error states.
5. Backend provider adapters, shared cache, batching, rate-limit handling,
   normalized identities, and timestamped snapshot storage from the outset.
6. Movement history that distinguishes collected snapshots from vendor archives.
7. Automated odds conversion, matching, freshness, best-price and UI tests.
8. Clearly labeled demonstration mode until approved licensed credentials exist;
   never call it live data, and never silently fall back to demonstration prices.

Saved watchlists and a bet journal follow the odds MVP. Market-based price
comparison is available before predictive models; model EV stays unavailable
until validation. User-entered hypothetical EV is labeled separately.

## Flagship analysis integration contracts

- Edge Reliability Analyzer: compare validated model probabilities with each
  exact eligible sportsbook quote, including fair odds, break-even and EV.
- Historical Replay Lab: retrieve only point-in-time odds and features available
  at that instant. Current prices cannot stand in for missing history.
- Prediction Autopsy: freeze quote, book, timestamps, prediction and model version
  when saving; later attach actual outcome and independently sourced closing price.
- Game Script Simulator: scenario changes recompute model value against current
  selections and freshness; hypothetical results are separate from forecasts.
- Closing-line value needs actual closing observations and compatible lines;
  first collected and last collected are not automatically opening and closing.
- Significant-movement alerts are a future iteration.

## Priority coverage and safeguards

Target FanDuel, DraftKings, BetMGM, Caesars, bet365, Fanatics, ESPN BET or its
current successor identity, Hard Rock Bet, and reliable licensed regional and
international sources. Coverage is provider/market/region dependent. Compare
providers before purchase; see `docs/PROVIDERS.md`. No prohibited scraping.

Use exact event, player, market, period, side, threshold and settlement-rule
identity. Unknown mappings fail closed. Track suspension, missing quotes,
duplicates, outages, API limits and regional variants. Price freshness must meet
the documented policy (120 seconds pregame / 20 seconds after kickoff in this
initial implementation), otherwise show stale/unavailable with original times.
Jurisdiction availability needs verified data before claiming legal coverage;
the first UI offers a clearly identified user-selected sportsbook allowlist.

## Statistical research roadmap

- Remove bookmaker margin using documented methods; show method sensitivity.
- Compare equivalent markets only: event, selection, period, line, and rules.
- Model expected value with push probability where appropriate; distinguish
  moneyline, spread, total, and prop settlement rules.
- Study the value of NFL key numbers, especially 3 and 7, from historical
  margin distributions. Compare line value and price together.
- Explain matchup efficiency: expected points added per play, success rate,
  explosive plays, pace, and opponent-adjusted performance.
- Study rest, travel, weather, offensive-line availability, quarterback changes,
  and player role changes where suitable historical data exists.
- Build scenario analysis: show how an injury assumption or weather forecast
  changes an estimate, rather than presenting one overconfident probability.
- Track line movement with timestamps, provider latency, and missing history.
  Do not label movement as professional betting activity without evidence.
- Study player-prop distributions and role stability, then correlated parlays
  with joint simulations; never multiply dependent probabilities blindly.
- Track closing-line value separately from realized profit and loss.
- Evaluate calibration, Brier score/log loss, chronological holdouts, sample
  sizes, uncertainty, and simple market baselines before claiming model skill.
- Test trends against multiple-comparison bias and avoid future-data leakage.
- Support a clear 'no reliable edge' result when evidence is weak.

## Data and service design

The current `NflEvent`, NFL registry, UI and first adapter are prototype-specific.
Before expanding ingestion, introduce normalized sport, league, event and
competitor identifiers and sport-specific market/settlement registries. Do not
apply NFL overtime/tie, push, period, or key-number assumptions to other sports.
Tennis retirement/walkover rules and combat-sport draw/no-contest outcomes need
explicit handling; sport coverage and predictive-model validation are separate
capabilities. No NFL model is assumed valid for another sport.

Use interchangeable provider adapters behind a backend so provider credentials
are never shipped inside the Flutter application. Normalize teams, players,
events, markets, rules, odds formats, and timestamps. Deduplicate overlapping
feeds; track source attribution, freshness, coverage, and missing quotes.

Choose feeds based on actual NFL coverage, update frequency, historical depth,
display/redistribution rights, and cost. Do not promise every sportsbook or
market. Store snapshots only as permitted by provider terms. Book availability
can vary by region; ask the owner for target jurisdiction before feed selection.

Potential sources to evaluate, with no account creation or purchase authorized:

- The Odds API: https://the-odds-api.com/liveapi/guides/v4/
- nflverse availability: https://nflreadr.nflverse.com/articles/nflverse_data_schedule.html

Check current data availability before promising injury, participation, or
real-time features. Historical access and broader coverage may require paid
plans. Validate licensing and source suitability before production integration.

## Delivery sequence

Player research includes searchable NFL profiles, last-three-recorded-game analysis
and the previous three completed seasons, with current-season results separate.
The default recent view can cross seasons; explicit season and regular/postseason
filters remain available. Missing rows and metrics are never filled with zeroes.
See `docs/PLAYER_STATS.md` for the current bundled source and coverage.

Build the dashboard, comparison UI, backend provider layer, matching, freshness,
history and tests together using demo data. Connect an approved licensed feed
without restructuring; verify actual provider data before calling it operational.
Then expand statistical evidence and validate models before edge rankings.
Build iOS releases on macOS with Xcode after shared Flutter flows work.

Provider evaluation must compare broad multi-sport commercial coverage and
costs, not just an NFL-only quote. A limited NFL pilot can be separately priced
for testing, but it does not replace the full product requirement.
