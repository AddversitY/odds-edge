# Odds Edge capability roadmap

Owner direction, 2026-10-19, expanded 2026-10-20: bring in the major
capabilities of OddsJam, Outlier, Rithmm, Unabated, and Pikkit, and make each
one easier to use. Action Network, BettingPros, and Props.Cash were checked
the same day. This is a feature matrix, not a claim that Odds Edge already
matches anyone's live product, data depth, or results.

Reviewed 2026-10-20 from public product and help pages. Vendor marketing is
not audited profitability. Odds Edge does not copy layouts, private formulas,
or proprietary data. A number in the app is a calculation on data we have, or
it is left blank.

No purchase, signup, account linking, scraping, or extra live-odds refresh is
authorized. The free Odds API budget is unchanged: the new tools read snapshots
the computer has already saved.

## How to read the matrix

| Word | Meaning |
|---|---|
| Have | You can do this job today with data the app already has. Limits are in the same row. |
| Partial | A useful piece exists. A major part of the competitor feature does not. |
| Missing | Not built. |

**Blocked** means the missing piece needs something the owner has not approved:
a paid odds feed, a live scores or injury feed, or linking a sportsbook
account. "No" means we could build the rest without those.

Phase 1, in the app now, is the **Tools** tab (phone label **Tools**; on the
home screen, **Price, parlays, and bet log**). Overview, Research, and Odds
comparison are unchanged.

## What phase 1 added

| Tool | Where | What you are looking at |
|---|---|---|
| Best price | Tools → Best price | Best number in the current snapshot, sportsbook fee, vig-free market chance, and a market comparison. The list opens in that comparison order, or you can switch it to lowest fee. Sharp-book column stays empty until a sharp book is actually in the snapshot. A card says when the house rules were not independently verified. |
| Arbitrage and middles | Tools → Arbitrage and middles | Two-sided prices that cross, with a stake split, and windows where both bets can win. A middle shows the profit if the window hits, the result if it misses, and the break-even hit rate. Not a guaranteed profit. |
| Line movement | Tools → Line movement | Change between snapshots this computer already saved. Does not spend Odds API credits. |
| Parlay price | Tools → Parlay price | Multiplied ticket price. Fair price only when the legs are separate games, or from one chance you type for a same-game ticket. |
| My bets | Tools → My bets | Bets you type. Profit, ROI, record, and closing-line value from a close you type. |
| Stake size | Tools → Stake size | Full, half, and quarter Kelly from a win chance you type. |
| Prop history | Tools → Prop history | How often a recorded NFL stat cleared a line you type: last 5, last 10, last 20, the season, and one opponent. |

Every one of those screens says when the snapshot was taken. Tap the info
icon next to a figure for a plain-language explanation. None of them tells you
to place a bet.

## What a real free snapshot does

A free-tier The Odds API snapshot checked with this phase (14 games, 582
prices) returned 8 of the 10 default books. Caesars and Fanatics were not in
the response. A missing book is left out of the board. It is not a failed
request, and the app does not spend another credit to go looking for it.

`VERIFIED_NFL_RULE_BOOKS` is optional and is unset in the usual setup. Books
that are not on that list are stored as unverified. Best price, arbitrage, and
middles still compare their full-game moneylines, spreads, and totals. Prices
are grouped by market and number, including snapshots that were saved with an
older per-book rules label. Each of those cards says house rules are not
independently verified. That is the honest choice: labeling the 10 default
books as "includes overtime, push on a tie" would claim a check that has not
been done.

Put a book on `VERIFIED_NFL_RULE_BOOKS` only after that book's full-game
moneyline (including overtime, push on a tie), spread, and total are confirmed.
Those books use that rules label, they are not mixed into the unverified
group, and they do not show the note. Unverified prices still cannot win the
live best-price badge on Odds comparison.

Games that have already started are left out of those three tools. Kickoff is
checked against the snapshot time and against the clock when the screen is
opened, so a pre-kickoff snapshot opened after kickoff is left out too. So is a
price whose source time is more than 30 minutes older than the moment it was
saved. An in-game line and a stale pregame line are not treated as an edge.
Neither check requests new odds. If nothing usable remains, the empty state
says why, instead of blaming suspended lines.

## Price shopping

| Feature | Who documents it | Status | Simpler version | Data and cost | Blocked |
|---|---|---|---|---|---|
| Best price across books | OddsJam odds screen; Unabated odds screen; Outlier odds tracking; Rithmm line shopping; Pikkit line shopping | Have | One card per market shows the best price in the snapshot and the book. If those house rules were not independently verified, the card says so. Odds comparison still has the full book-by-book table, and an unverified price still cannot win the live badge there. | Saved Odds API snapshot. The request asks for 10 US books; a checked free-tier response included 8 (no Caesars, no Fanatics). Moneyline, spread, total. $0 beyond the free 500 credits/month. | Live prices, 100+ books, and props need a paid feed. |
| Sportsbook fee (hold / synthetic hold) | OddsJam low-hold tool; Unabated best-line and synthetic hold; Unabated no-vig page | Have | "Fee at the best prices" is how far the best prices add up past 100%. A negative fee is the arbitrage case. "Typical book fee" is the middle book, so one long price does not set it. | Same snapshot. $0. | No. |
| Vig-free fair price | Unabated no-vig calculator (proportional method); Outlier devig / no-vig; Pikkit no-vig CLV option | Have | Each book that posted every side is fee-removed in proportion, then averaged. If equal-slice removal would move a chance by more than 1 percentage point, the card says so. | Same snapshot. $0. | No. |
| Sharp-book reference (Pinnacle and similar) | Unabated "Unabated Line"; Outlier Pro sharp-book odds; OddsJam "Pinny"; Pikkit no-vig and best-available close | Partial | The math runs when a snapshot contains Pinnacle, Circa, Bookmaker, BetCRIS, or LowVig. The free US list does not include them, so the column says they are absent instead of substituting FanDuel or DraftKings. | Needs those books in an approved feed. Not in the free 10. | Paid odds feed. |
| Custom-weighted consensus | OddsJam odds screen | Missing | Not built. A plain average of every complete book is easier to explain than hidden weights. | Would use the same snapshot. $0 to build. | No. |
| Alternate lines | OddsJam; Unabated alternate calculator and prop alts | Partial | If both sides of an alternate are in the snapshot, the same fee and fair-price math runs. The free snapshot asks only for the main line. | Main-line request is already scheduled. Alternates cost more credits or a paid plan. | Paid odds feed if we request them. |
| Player-prop prices | OddsJam; Outlier Prop Finder; Unabated prop screen; Rithmm props | Missing | Prop history works from box scores and a line you type. The app does not download prop prices. | The Odds API props/alternates are outside the free three-market request. | Paid odds feed. |
| Futures, quarters, halves | OddsJam futures; Unabated partial-game and futures simulators | Missing | Not built. Main-line math does not transfer to season-long rules. | Separate markets and, for futures, a season simulator. | Paid odds feed. |
| Prediction markets and exchanges | Rithmm lists Kalshi, Polymarket, Novig; Unabated lists exchanges and prediction markets | Missing | Left out on purpose. The free feed requests 10 US books. In testing, the free tier returned 8 (no Caesars, no Fanatics). | A different feed and a rules review. | Paid odds feed. |
| One-click bet placement or deep link | Outlier homepage; Pikkit autofill; Rithmm "send the slip" | Missing | You place the bet at the sportsbook. Linking accounts is out of scope. | Account linking or book-specific URLs. | Account linking. |
| Reorder books and colors | OddsJam odds-screen guide | Missing | "My accessible books" already hides books you cannot use. Colors are not needed for that. | $0. | No. |

## Value, hedges, and promotions

| Feature | Who documents it | Status | Simpler version | Data and cost | Blocked |
|---|---|---|---|---|---|
| Positive EV versus a vig-free market | OddsJam +EV; Outlier Premium+ badge and Pro feed; Unabated edge versus its line | Have | "Versus that market" is the profit per $1 if the vig-free chance were right. Positive means the snapshot price is longer than that chance. It is labeled as a market comparison, not a prediction and not a pick. | Same snapshot. $0. | A live scanner still needs a paid, faster feed. |
| Positive EV versus a prediction model | Rithmm Edge; Unabated prop simulator | Partial | Proof Lab and player investigation still take a chance you type, or a conditional replay. There is no validated model, so the app does not rank "best bets." | Needs a tested model and point-in-time history. $0 until a feed is required. | No for the manual version. A real model may later need paid history. |
| Arbitrage with stake split | OddsJam arbitrage; Outlier Pro arb feed; marketed by OddsJam as guaranteed | Have | Shows the dollars of a $100 combined stake and the return if both bets were accepted at the snapshot prices. Same-book gaps, missing draw prices, and whole-number pushes are spelled out. The word "guaranteed" is not used. | Same snapshot. $0. | Live arbs, props, and futures need a paid feed. |
| Middles | OddsJam middles, including live; Outlier Pro middling with profit/loss; Unabated negative synthetic hold | Have | Names the whole-number scores where both bets win. Shows the profit if the window hits, the result if it misses and both bets are decided, and the hit rate that breaks even. A whole-number push returns that stake. It is not described as a win on one side and a loss on the other. No profit is promised. | Spreads and totals already in the snapshot. $0. | Live middles need a paid feed. |
| Low-hold finder as its own feed | OddsJam low-hold tool | Have | The fee is on every Best price card. The list opens ordered by the market comparison. Choose Lowest fee to put the smallest fee first, including a negative fee. | Same snapshot. $0. | Live board needs a paid feed. |
| Bonus-bet / promo converter | OddsJam bonus conversion; Outlier Pro boosted parlays | Missing | A converter needs the promotion's exact stake, odds, and hedge rules. No promo feed is connected, and none is scraped. | Could later be a calculator you fill in. $0. A live promo board needs a feed or hand entry. | No for a manual calculator. A scanner would need promo terms we do not have. |
| Free-bet and site-credit workflows | OddsJam; Pikkit promotions center | Missing | Not built. Same reason as promos. | Hand entry later. $0. | No. |

## Parlays and pick'em

| Feature | Who documents it | Status | Simpler version | Data and cost | Blocked |
|---|---|---|---|---|---|
| Parlay price calculator | OddsJam parlay builder; Rithmm AI parlay builder; Pikkit SGP line shopping | Have | You type the legs. The multiplied price is shown. The fair price multiplies win chances only when you say the legs are different games. | Numbers you type. $0. | No. |
| Same-game fair price | Pikkit SGP line shopping; OddsJam and Rithmm parlay tools | Partial | Same-game legs are not multiplied. You can type the book's ticket price and one chance for the whole ticket. There is no correlation model. | A joint model needs play-by-play or a paid simulator. Not in the bundle. | Paid data if we want a real same-game model. |
| AI that builds or swaps legs | Rithmm AI parlay builder and Scout | Missing | Not built. The assistant in Proof Lab explains a frozen research note. It does not assemble tickets. | Would spend the existing xAI key if used. No new vendor. | No, but it must not become a pick service. |
| DFS / PrizePicks / Underdog optimizer | OddsJam fantasy optimizer; Unabated DFS slips; Outlier prop screen used for DFS | Missing | Pick'em prices are not in the free odds snapshot. | A licensed DFS price feed. | Paid odds feed. |
| Correlated props | Props.Cash homepage describes correlated player props | Missing | Not estimated. Multiplying related props is exactly what the parlay screen refuses to do quietly. | Needs joint frequencies from a large play log. | Paid data for a real correlation model. |

## Research and props

| Feature | Who documents it | Status | Simpler version | Data and cost | Blocked |
|---|---|---|---|---|---|
| Prop hit rate, last 5 / 10 / 20, season, versus opponent | Outlier Prop Finder; Rithmm hit rates on the card | Partial | Prop history, for NFL box scores already on the device. You type the line. Postseason is not mixed in. Missing stats are skipped, not treated as misses. Last season is not a separate row. | Bundled nflverse snapshot. $0. No odds request. | Other sports, live prop lines, and opponent defensive ranks need more data. |
| Traffic-light coloring and opposition rank | Outlier Prop Finder | Missing | The count and the rate are written out instead of a color. Rankings are not in the bundle. | Rankings need a defensive-stats feed. | No for colors. Ranks need more public data. |
| Filters by league, book, odds, prop type on a live prop board | Outlier Prop Finder | Missing | Player search, stat, over/under, and opponent abbreviation. There is no live prop board to filter. | Paid prop odds. | Paid odds feed. |
| Injury and lineup context | Outlier injury reports; Props.Cash roster intel; Rithmm downgrade reasons | Missing | Not invented from a missing player row. The player page already says a missing game is not an injury. | A licensed injury or participation feed. | Live scores or injuries. |
| Public betting percentages and "sharp action" | Not on the pages read above for the five main products. Often sold by media apps. | Missing | Not inferred from our slow snapshots. A line move is shown as a price change only. | A paid betting-percent feed. | Paid odds feed. |
| Matchup research and scenario replay | Rithmm model context; our own investigation | Have | Research → Players → Investigate a bet. Evidence, scenario replay, saved prediction, manual result. Unchanged by phase 1. | Bundled history. $0. | Richer context later needs more data, not a new tab. |
| Team form windows | Unabated and Outlier game views, in broader form | Have | Research → Matchups. Season, last three weeks, latest week. Unchanged. | Bundled schedules. $0. | No. |

## Models and the assistant

| Feature | Who documents it | Status | Simpler version | Data and cost | Blocked |
|---|---|---|---|---|---|
| Full-slate projections and an "edge" badge | Rithmm; Unabated prop projections | Missing | Not built. Shipping a badge without a tested model would be a pick list. | Point-in-time features and a chronological test. | No until the model needs a paid history feed. |
| Custom model builder and backtest | Rithmm model builder | Partial | Proof Lab stores a chance you type and compares two saved notes. It does not reweight pace, usage, or defense, and it does not walk a model forward through old odds. | $0 for the manual version. | Paid historical odds if the backtest must use old prices. |
| Community models | Rithmm | Missing | Not planned until there are accounts, privacy rules, and a way to stop cherry-picked records. | Accounts. | Account linking, in the sense of user accounts. |
| Monte Carlo prop distributions and milestone prices | Unabated props simulator, 10,000 trials | Missing | Player investigation replays historical games under a workload and efficiency assumption. It does not price every alternate. | A distribution model. $0 to start from public stats. Not started. | No. |
| Futures simulators | Unabated NFL and college football futures | Missing | Not built. Needs standings, schedule, and futures prices. | Paid futures odds plus a season model. | Paid odds feed. |
| Research assistant | Rithmm Scout; our Grok assistant | Partial | Proof Lab → Explain / challenge this research. The key stays on the server. It explains the note on screen. It is not on the new Tools screens, and it does not pick bets. | Existing xAI key, only if the owner sets it. Odds tools do not call it. | No. |
| Player-impact and injury toggles | Rithmm Premium | Missing | The scenario replay has a workload and efficiency scale, not a named-player on/off switch tied to live news. | Injury feed plus a tested adjustment. | Live scores or injuries. |

## Tracking, closing line, and stake size

| Feature | Who documents it | Status | Simpler version | Data and cost | Blocked |
|---|---|---|---|---|---|
| Manual bet log | OddsJam free tracker; Pikkit tracker; Rithmm tracking | Have | Tools → My bets. Description, book, odds, stake, result, notes. Stored on this device with the other research files. Proof Lab's portable backup includes the log. | $0. | No. |
| Automatic sync from sportsbook accounts | Pikkit BookSync; OddsJam one-click add and auto grading | Missing | Not built. Account passwords and book logins stay out of the app. | Would require account linking. Rejected for now. | Account linking. |
| ROI, record, profit | Pikkit dashboard; Rithmm ROI by sport and bet type | Have | ROI is profit divided by stake on settled bets. Pushes count as zero profit. Pending and void bets are left out. | Your entries. $0. | Charts by sport need more tags. Not blocked. |
| Closing-line value | Pikkit CLV (best price, no-vig, one book, or the book you used); OddsJam CLV from a sharp book | Partial | You type the closing American price. The figure is the close's implied chance minus your price's implied chance. It is not no-vig, not the best close in the market, and not downloaded. | A verified close needs the snapshot nearest kickoff for that exact selection, which our schedule only sometimes has, and only for main lines. | Paid odds feed for an automatic close. |
| Units and Kelly stake | Common bankroll tool; Unabated calculators mention hedge sizing. Rithmm says its edge does not size the bet. | Have | Tools → Stake size. Full, half, and quarter Kelly, in dollars and in units of 1% of bankroll. Zero when the price is not better than the chance you typed. | Numbers you type. $0. | No. |
| Hedge an existing bet | Unabated hedge calculator; Pikkit hedging | Partial | The arbitrage card is the two-sided stake split for a market in the snapshot. It does not yet start from a bet already in My bets. | $0 to connect later. | No. |
| Exposure, tags, calendars, social copying | Pikkit Pro list | Missing | The log is a list. Tags, a calendar, and copying someone else's bet are not built. | Accounts for anything social. | Account linking for social features. |

## Alerts, live games, and coverage

| Feature | Who documents it | Status | Simpler version | Data and cost | Blocked |
|---|---|---|---|---|---|
| Line movement from our own snapshots | OddsJam line history; Unabated line history; Outlier movement charts; Rithmm movement with a reason | Partial | Tools → Line movement reads the snapshot file already on disk. First saved is not the open. Latest saved is not the close. No reason such as "injury" is attached. | $0. No new Odds API call. | A true open-to-close archive needs a paid history product. |
| Push alerts, Discord, Slack, market-open alerts | OddsJam alerts; Outlier alerts; Pikkit odds alerts | Missing | Not built. Alerts on a 500-credit schedule would mostly say the daily snapshot arrived. | A push service plus a faster feed. | Paid odds feed. |
| Live in-game odds | OddsJam live (about one-second refresh on their paid plan); Unabated in-game | Missing | The freshness rule is still 120 seconds before kickoff and 20 seconds after, and the free plan does not poll that fast. In-game prices are shown as stale or as a snapshot, never as live. | Far more credits than 500/month, or a streaming vendor. | Paid odds feed. |
| Scores, weather, play-by-play on the odds screen | OddsJam odds screen | Missing | Not placed next to prices. Game results in Research are the bundled history, not a live score. | A live stats feed. | Live scores or injuries. |
| Many sports | Rithmm lists eight; Outlier lists NFL, MLB, NBA, NHL, college, WNBA | Partial | The app's working slate is NFL. The provider catalog is broader. The adapter still requests NFL only, so credits stay inside the free plan. | Turning on another league spends the same credits faster. | Paid odds feed if coverage grows past the free budget. |
| Web app | Pikkit Pro web access | Missing | Separate work. This phase does not add a web target or change CORS. | Hosting, not approved. | No for a later technical pass. Paid if it needs a server. |
| Subscriptions and accounts | All five sell plans | Missing | No payment and no login. | Not approved. | No. |
| Responsible-gambling note | Not a competitor feature. Required here. | Have | Best price, hedges, the bet log, and stake size show the 1-800-GAMBLER note. | $0. | No. |

## Pages this matrix is based on

Read 2026-10-20 unless noted.

- OddsJam tools: https://oddsjam.com/betting-tools
- OddsJam odds screen: https://dev.oddsjam.com/odds-screen and https://oddsjam.com/betting-education/how-to-use-the-oddsjam-odds-screen-advanced-tips-tricks
- OddsJam plan contents (parlay builder, middles, promo suite): https://oddsjam.com/subscribe/positive-ev-global and https://oddsjam.com/
- Outlier plans: https://help.outlier.bet/en/articles/12556823-choosing-the-right-outlier-plan-for-your-betting-style
- Outlier Prop Finder: https://help.outlier.bet/en/articles/6711738-research-player-propositions-with-outlier-s-prop-finder
- Outlier product page: https://www.outlier.bet/
- Rithmm: https://www.rithmm.com/ai-sports-betting
- Unabated tools: https://unabated.com/tools/tools-summary
- Unabated odds screen: https://unabated.com/tools/core/odds
- Unabated prop screen and simulator: https://unabated.com/tools/core/props-tool and https://www.unabated.com/tools/core/props-simulator
- Unabated no-vig calculator: https://unabated.com/tools/calculators/no-vig-odds
- Pikkit CLV: https://pikkit.com/closing-line-value
- Pikkit tracker and BookSync: https://pikkit.com/bet-tracker and https://pikkit.com/blog/how-to-connect-sportsbooks-to-pikkit
- Pikkit Pro feature list: https://pikkit.com/pro
- Props.Cash homepage only (the readable text named a prop finder, roster and injury context, expected value, filters, and correlated props): https://props.cash/

Action Network (https://www.actionnetwork.com/) returned a server error, and
BettingPros (https://www.bettingpros.com/) refused the request. No feature row
above is attributed to them. A later pass can add rows after those pages are
readable. Nothing from a review article is treated as a vendor's feature list.

## What phase 2 needs

Phase 2 is the part that cannot be done honestly on the free snapshot and the
bundled NFL stats.

1. **Paid odds, still not approved.** Player-prop prices, alternate lines,
   futures, live in-game prices, and a sharp book such as Pinnacle. That is
   what turns Best price and the market comparison into a live board, and what
   makes arbitrage and middles something other than a snapshot check. The
   current free plan is 500 credits a month and is already fully scheduled.
   Do not add markets without raising that budget on purpose.
2. **Automatic closing line.** CLV that updates itself needs the closing price
   of the exact bet. Our own last snapshot is not that price. Pikkit's
   no-vig close also needs both sides of the close.
3. **Injuries, lineups, and live scores.** Outlier's research view and
   Props.Cash's roster notes. A missing stat row must stay a missing row.
4. **Same-game parlay model.** The calculator already refuses to multiply
   related legs. A fair same-game price needs a joint model, not a faster
   refresh.
5. **Account linking stays out** unless the owner explicitly wants sportsbook
   logins in the product. Auto-grading, BookSync, one-click bets, and social
   copying are all in that bucket.
6. **More leagues** after NFL is solid and the credit cost of each league is
   written down. The product goal is still multi-sport. The working app is NFL.

## Quality criteria

1. A new user can open Tools and read one price without learning the whole app.
   Overview → Investigate a bet still works for a player-yardage question.
2. Every statistic has a window and a source. Snapshot time is on the price
   tools. The prop tool names the bundled stats snapshot. Missing data stays
   missing.
3. Saved research and saved bets reproduce from the files on the device. A new
   snapshot does not rewrite an old bet or an old prediction.
4. Market EV is the vig-free price, not a forecast. Scenario probabilities
   stay conditional. Kelly uses the chance the user typed.
5. No screen calls a profit guaranteed. Arbitrage, middles, and positive
   comparisons say what would have to be true.
6. No new screen spends Odds API credits. History is read from the snapshot
   file. Keys stay in the backend.

## Build notes that are still open

Slow assistant requests should not block odds or health requests. Cap AI
requests. The player investigation does not call the assistant. The new Tools
screens do not call it either, and they do not change the refresh schedule.
Web and CORS are untouched.
