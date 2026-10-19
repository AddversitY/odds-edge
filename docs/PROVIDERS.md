# Odds provider assessment

Research date: October 18, 2026. Advertised coverage is not an entitlement,
an uptime measurement, or confirmation of rights for this product. No account,
trial, subscription, or vendor contact has been initiated.

## Scope governing this comparison

NFL is the prototype only. The intended published product covers college
football, tennis, combat sports, and the broadest practical range of additional
sports/leagues. Evaluate all candidates against that goal. Request a full
multi-sport quote, with an optional separately priced NFL pilot. Do not select
an NFL-only contract as if it meets the launch requirement.

| Candidate | Multi-sport assessment |
|---|---|
| OpticOdds | Advertises 200+ books across multiple sports, streaming delivery and broad market depth. Custom quote required; verify college football, ATP/WTA and lower-tier tennis, MMA/boxing promotions, every requested book and commercial analytical-app rights. No adapter implemented yet. |
| The Odds API | Public catalog spans multiple sports/leagues. Verify specific college, tennis and combat competitions and book/market depth. Existing adapter currently fetches NFL only; that is our code's scope, not a claim that the provider is NFL-only. |
| SportsDataIO | Evaluate its league-specific feeds and aggregated odds as separate entitlements; request actual multi-sport odds coverage and pricing. Do not infer odds coverage from availability of scores or statistics. |
| SportsGameOdds | Plan-dependent league counts and update cadence; compare its actual league/book/market matrix and commercial terms with the full launch scope. |

Sources: [OpticOdds](https://opticodds.com/), [OpticOdds technical guide](https://developer.opticodds.com/docs/odds-api-getting-started-guide),
[The Odds API sports catalog](https://the-odds-api.com/sports-odds-data/sports-apis.html),
[SportsDataIO developer overview](https://sportsdata.io/developers),
[SportsGameOdds plans](https://sportsgameodds.com/pricing).

Obtain exact region, competition, season, market, history and latency coverage;
an aggregate count of sports or books does not mean all combinations exist.
In particular, ask vendors to permit a subscription consumer analytics product
with arbitrage scanning, combined providers, and permitted snapshot retention.

| Candidate | Markets and history | Cadence / cost | Commercial fit and outstanding checks |
|---|---|---|---|
| The Odds API | Main lines; selected props/alternates; historical snapshots advertised back to 2020, varying by market/book | Free 500 credits/month; paid 20K credits $30/month. Featured markets publish 60s pregame / 40s in-play; props/alternates 60s | Terms permit commercial analytical apps and retention, prohibit standalone raw-data resale. Confirm this app's comparison-heavy use, jurisdictions and market-level rules. |
| SportsDataIO | Aggregated sportsbook prices, props, market metadata, listed/unlisted records; historical betting line access requires account enablement | Use-case/volume/sport based quote; get NFL odds endpoint cache and upstream cadence in writing rather than applying live-score cadence to odds | Request operator-by-market matrix, retention/display/combination rights, SLA, latency percentiles, outage handling and sandbox payloads. |
| SportsGameOdds | Main lines, props, alternates; Pro historical coverage generally from Feb 2024; book-level opening/closing fields where available | Free: 10-minute updates; Rookie $99/month: 3 minutes; Pro $299/month: sub-minute updates | Terms restrict standalone redistribution and aggregation for resale; obtain written approval for multi-provider combination and intended analytics before selecting. |

Primary references:

- The Odds API [plans](https://the-odds-api.com/), [cadence](https://the-odds-api.com/sports-odds-data/update-intervals.html), [terms](https://the-odds-api.com/terms-and-conditions.html).
- SportsDataIO [developer plans](https://sportsdata.io/developers), [betting integration](https://sportsdata.io/help/betting-data-integration-guide), [historical integration](https://sportsdata.io/help/historical-data-integration-guide), [NFL endpoint documentation](https://sportsdata.io/developers/api-documentation/nfl).
- SportsGameOdds [plans](https://sportsgameodds.com/pricing), [history FAQ](https://sportsgameodds.com/docs/faq), [terms](https://sportsgameodds.com/terms).

## Requested operator coverage

| Requested operator | The Odds API public list | Other candidates |
|---|---|---|
| FanDuel | `fanduel`, US | Obtain NFL-specific matrix |
| DraftKings | `draftkings`, US | Obtain NFL-specific matrix |
| BetMGM | `betmgm`, US | Obtain NFL-specific matrix |
| Caesars | `williamhill_us`, paid | Obtain NFL-specific matrix |
| Fanatics | `fanatics`, paid | SportsGameOdds Pro lists it; verify NFL markets |
| ESPN BET | `espnbet`, now titled theScore Bet | Resolve legacy names with each vendor |
| Hard Rock Bet | US2, separate AZ/FL/OH entries plus base entry | Confirm geographic variant and rules |
| bet365 | AU entry listed for AFL/NRL; this does not establish US NFL coverage | SportsGameOdds Pro lists Bet365; confirm region, NFL and commercial rights |

Coverage reference: [The Odds API operator list](https://the-odds-api.com/sports-odds-data/bookmaker-apis.html).
Do not add offshore operators simply because an aggregator returns them.
New regional/international adapters need jurisdiction and rights review.

## Proposed decision

### Latest budget decision takes precedence

**Pending confirmation:** the owner asked to pause before finalizing the change
below. It is a cost-conscious proposal, not a confirmed scope decision. Hold
provider purchases and quote outreach; continue to preserve existing requirements.

The owner has deferred arbitrage and cannot justify roughly $300/month before
revenue. The streaming shortlist below is future research, not the immediate
purchase recommendation. Near-term development uses demo data plus suitable
public statistics; evaluate free/low-cost licensed odds tiers with honest quota,
coverage and refresh limits. Keep live odds comparison in the MVP architecture.
Any paid tier still needs explicit approval, even an inexpensive one. Preserve
the broad multi-sport goal while making initial feed gaps explicit.

### Published-price shortlist (October 18, 2026)

These are advertised monthly USD prices, not verified total production costs.
They cannot be called cheaper than OpticOdds until its quote is available.

| Candidate | Published option | Material tradeoff for Odds Edge |
|---|---|---|
| The Odds API | $30 / 20K credits; $59 / 100K; $119 / 5M; $249 / 15M monthly | Broad multi-sport catalog, but market/region/event request costs grow; featured markets refresh around 60s pregame / 40s in-play, not a low-latency arbitrage guarantee. |
| SportsGameOdds Pro | $299/month | Advertises 53 leagues, 82 books, sub-minute updates and history. Verify matrix, actual latency and written permission for provider combination and commercial analytics. |
| BoltOdds Pro | $349/month | Advertises all offered leagues/books/markets, WebSocket delivery, 3 concurrent connections. 'All' means its supported catalog, not every sportsbook worldwide. Historical odds are listed under Custom; confirm commercial end-user rights and history pricing. |
| TheRundown Pro | $149/month | Commercial display with attribution; 30-second delay and 30-day odds history. Not the preferred tier for time-sensitive arbitrage. |
| TheRundown Ultra | $399/month | Real-time delivery, 90-day history, commercial display and one WebSocket connection/three multiplexed subscriptions. Published catalog advertises 25 data sources and 22 leagues plus 9 variants. Model validation/backtesting requires written permission; extended retention needs agreement. |
| OpticOdds | Custom quote | Broad coverage and streaming candidate. Do not invent a price or infer commercial API cost from OddsJam's consumer subscription. |

Price references: [The Odds API](https://the-odds-api.com/),
[SportsGameOdds](https://sportsgameodds.com/pricing),
[BoltOdds](https://boltodds.com/pricing),
[TheRundown](https://therundown.io/pricing/api),
[OddsJam API sales](https://dev.oddsjam.com/odds-api).

Recommendation: benchmark coverage and freshness for SportsGameOdds Pro,
BoltOdds Pro and TheRundown Ultra against an OpticOdds multi-sport quote.
The Odds API remains a low-cost development/general comparison candidate.
Do not select any candidate solely by advertised entry price: our product
also needs historical analysis rights, adequate market depth and data volume.
No trial, account, outreach or purchase has been made.

Use The Odds API as the first implemented adapter, not a purchased commitment.
Its public schema is sufficient to exercise main-market ingestion. Evaluate
SportsDataIO as a complementary source and SportsGameOdds for coverage gaps,
subject to written rights and measured data quality. Only the demo and The Odds
API adapters are implemented; no claims of working adapters for the other two.

Before spending, compare sample NFL responses, match exact selections, measure
missing quotes and timestamp ages during games, verify available/suspended
semantics, establish support/SLA terms, and calculate a realistic monthly budget.
For example, a US+US2, three-market request costs multiple credits; polling
continuously every minute can exceed entry-plan quotas. App refresh uses a
shared backend cache so each user does not trigger independent upstream polling.

The current 20-second in-play freshness requirement is deliberately stricter
than a 40-second upstream cycle: many observations will be marked stale. A
faster feed or an explicit revised policy is needed before claiming reliable
in-play coverage. Do not silently widen the threshold.
