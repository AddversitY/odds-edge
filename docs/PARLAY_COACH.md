# Parlay Coach screens

Odds Edge keeps the research tools and adds six everyday screens: Home, Props, Games, Parlays, My Bets, and More. More is the older research and calculator workspace. Ask Coach stays on every screen. It only talks about a price that is already on screen. With no backend, or no priced side, it says the coach is unavailable instead of inventing a number.

Every chance, edge, and hit rate on these screens is computed from a snapshot or from the bundled box scores. A missing input is shown as a blank, not as zero.

## What each screen shows

**Home.** The time of the snapshot, the prices closest to the books' fee-free chance, and a Check my slip box. A price is called a play only when it pays more than that fee-free chance. If none do, the closest gaps are still listed and labeled as gaps. The slip multiplies the prices you type. The real chance stays blank until you type a chance for every leg.

**Props.** One card per player Over or Under in the snapshot. The bar is the books' fee-free chance, not a model confidence. The four blocks are the best open price, what that one price implies, expected profit if the fee-free chance were right, and the history gap (this season's clear rate minus the fee-free chance). L5, L10, L20, head-to-head, and season are counted from regular-season box scores. A missing stat is skipped. Tapping a card opens the book ladder, best price first, plus the recorded game bars. A price chart is drawn only when at least two collected prices exist. Double-tap, or the bookmark, saves the card to My Bets. It does not place a bet.

**Games.** All, today, and upcoming. A card can show a price-gap count (both sides priced so the stakes would lock a difference), a longer-price count (a side paying more than the fee-free chance), and a ticket count (how often the game appears in the short pre-built parlay list). The game page shows the fee-free moneyline split, labeled as the books averaged after the fee, and Spread, Moneyline, and Total with every open book from best price to worst. There is no button that places a bet.

**Parlays.** Pre-built 2-leg or 3-leg tickets from the existing parlay pricer. Each ticket uses one book and one side per game, and only games that are not the same game. The sentence under the ticket is the multiplied fee-free chance, the break-even rate of the price, and the gap between them (the house cut when the price is shorter). The filter sheet chooses the book, 2 or 3 legs, moneyline / spread / total, and an optional minimum American price.

**My Bets.** Saved plays, and the existing bet log as a local-date calendar plus settled and at-risk cards. An empty log says nothing is settled and nothing is pending. It does not show a fake $0 profit.

**More.** Odds comparison, research, the proof lab, player stats, and the calculators (best price, arbitrage and middles, line movement, parlay price, Kelly stake, prop history).

## Hit rates: nflverse only

NFL hit rates use the bundled file `assets/nfl-player-stats.json`. It comes from the nflverse player summary stats joined to schedules. nflverse publishes that data under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The license copy in this repo is `assets/NFLVERSE-LICENSE.md`. Odds Edge is not affiliated with nflverse. The import and the cutoff (2026-10-18) are described in `docs/PLAYER_STATS.md`. The file is a snapshot shipped with the app. It is not a live stats feed, and it has no snap share, usage rate, injuries, or headshots. Those lines stay blank.

A name is used only when exactly one player id is stored under that name. Josh Allen is one id in this file. Two players with the same name leave the hit rate blank. Last 5, 10, and 20 can cross seasons. Season is the current season in the file only. Head-to-head needs the player's latest recorded team to match one side of the game. That latest team is not a confirmation they are starting.

NBA, NHL, and MLB hit rates are not fetched. balldontlie's free tier still requires an account. Official NBA and NHL endpoints are a poor fit for a browser app (terms and browser access). No new signup and no sportsbook page is scraped. Other leagues show the hit rate as unavailable.

## Prop prices and the free credit budget

The Odds API free plan includes 500 credits a month. A main-line snapshot of moneyline, spread, and total, with a list of up to 10 books, costs 3 credits. The schedule is one daily snapshot plus about an hour and about 10 minutes before kickoff. A busy NFL month is about 70–80 of those, about 240 credits. Details are in `backend/README.md`.

Each of those responses, and each prop response, is also appended to `backend/data/line-history.jsonl` with the time it was fetched. `GET /v1/lines?event=<event id>` reads one game back. That read does not spend a credit. The file drops snapshots older than about 45 days and compacts so it stays small. There is no line chart in the app yet.

Player props are priced per event. The server requests only `player_pass_yds` and `player_receptions` (both can be counted from the box scores), for the next 2 games that have not started. With a bookmaker list, that is 2 markets × 2 games = **4 credits per refresh**.

Guards, all in `backend/prop_odds.dart`:

- Cache for 18 hours. A refresh inside that window returns the saved file.
- Daily cap: 4 credits. One refresh, then the day is done.
- Monthly cap: 60 credits.
- The refresh is skipped when remaining credits would fall below the scheduled main-line hold (`ODDS_CREDIT_RESERVE`, default 50) plus the prop cost.
- The events list that chooses the two games does not bill a credit.
- The one-minute maintenance timer does not refresh props.
- The charge added to the counters is the `x-requests-last` header, not a guess.
- At most two markets from the box-score list can be configured. Three markets cannot be turned on by an environment variable.

60 prop credits plus about 240 main-line credits is about 300 of 500. The rest is unused cushion. If the cache file is deleted, the monthly cap and the remaining-credit check are what stop a second spend.

`GET /v1/props` reads the cache. `GET /v1/props?refresh=1` may spend, inside those caps. Keys are `THE_ODDS_API_KEY` or, if that is empty, `ODDS_API_KEY`. They stay in the server environment. They are not printed and not committed.

Each prop row keeps the book's `last_update` time. The card says how old that time is. A price with no time is dropped, not shown as live.

## Coach's Line

The Games list and the game page show Coach's Line: our spread and total next to the books, the chance the favorite covers, the chance the over hits, and an Edge badge when the gap clears the setting on More → Coach's model. The number is this app's own past-seasons model. It reads the odds already on the screen. It does not spend Odds API credits. Sample mode uses the bundled model file with the sample prices. How to refresh it, and what the past test means, is in `docs/MODEL.md`. The history is nflverse, CC BY 4.0, the same license file as the hit rates. Odds Edge is not affiliated with nflverse.

My Bets saves the number on the ticket when a bet is logged. After the game, the closing number can be typed on that bet. The log says whether that number beat the close. The model page states the past test in plain language, including when there is no edge. A model does not guarantee the result.

## Words on the screen

- Fee-free chance: each book that posted both sides has its fee removed in proportion to the two prices, then those chances are averaged. It is the books agreeing after the fee. It is not a prediction.
- Expected profit: profit per $1 if that fee-free chance were exactly right. Positive means this price pays more than that chance.
- History gap: season clear rate minus the fee-free chance.
- Price gap: the older arbitrage math. The screen does not call it guaranteed profit.
- House cut, on a ticket: break-even rate of the multiplied price minus the multiplied fee-free chance, when the price is the shorter one.

The info button on a number opens that explanation.
