# Public vs sharp

This screen compares two different questions.

**Sharp side.** Which way did the number move, and did the sharp reference move with it? That answer comes from prices this app already saved. It does not spend Odds API credits.

**Public side.** What share of bets (tickets) and what share of dollars (money) are on each side? That answer is shown only when a source allows this app to display it. None of the sources checked below allow that, so the public percentages say they are not available. They are not estimated.

A line on the screen is a signal. It is not a pick.

## Sharp side, from data we already have

The regular NFL board is still the scheduled US snapshot. Pinnacle spreads and totals are still the separate cached pull, with the same hard credit cap (a few pulls a day, and a monthly cap that leaves the rest of the free plan for the regular board). Reading the saved file does not call The Odds API.

For each game the screen looks at the home spread:

- **Open to now.** The US books' number in the earliest saved snapshot, compared with the latest one. Half a point is the smallest move that counts.
- **Pinnacle's own path.** The same comparison for Pinnacle, when an earlier Pinnacle number was saved. A new Pinnacle pull is written into the same line journal. A repeated read of the cache is not written again, and it does not spend a credit.
- **Steam.** Three or more US books move the same way, and each of those moves is between two snapshots that are 20 minutes apart or closer. A move that only shows up across a gap of hours is a move. It is not called a steam.
- **Who moved first.** The book whose number changed in the earliest snapshot. If several books change in that same snapshot, the screen says so. One fetch stamps every book with the same time, so the journal often cannot name a single first book.
- **Pinnacle versus the US books.** The latest Pinnacle spread minus the latest US-book spread. "The US books" here means every other open book in the snapshot. On this app that snapshot is the US board.

The home spread is the number on the screen. A lower number means the home team is more favored. The small sparkline is that number from the open to the latest snapshot. Higher numbers sit higher. The line is blue. It is not a grade.

The game page shows one Sharp row. Tap it for the longer sentences. More → Public vs sharp lists the games with the clearest of those signals first.

## Public side: what was checked

Checked 12 November 2026. A source is used only when its own terms allow this app to display ticket percent and money percent, with attribution, light polling, and caching. Pages that merely show the numbers on their own site were not copied. No scraper was run.

| Source | What it publishes | What the terms say | Used |
|---|---|---|---|
| [Action Network](https://www.actionnetwork.com/public-betting) | Ticket percent on the public page. Money percent is locked. | [Terms](https://www.actionnetwork.com/terms): personal use only. No copying, republication, public display, or scraping without prior written consent. | No |
| [VegasInsider](https://www.vegasinsider.com/terms-of-use/) | Betting percentages on its own pages. | No unauthorized scraping or harvesting. No distributing, republishing, or publicly displaying the content without permission. | No |
| [Covers](https://www.covers.com/terms) | Contest-pick consensus, not sportsbook money. | Non-commercial entertainment. No distributing, republishing, or publicly displaying the content without permission. | No |
| [DraftKings Network](https://dknetwork.draftkings.com/terms-of-use/) | Bets percent and handle percent. | Personal, non-commercial use only. No automated copying or storage. | No |
| [DraftKings Sportsbook](https://sportsbook.draftkings.com/legal/nc-terms-of-use) | Its own customers' betting splits, inside the sportsbook. | Automated harvesting is prohibited. | No |
| [Pregame](https://pregame.com/terms-of-service) | Ticket, cash, and pick percentages. | Personal, non-commercial use. No robot or scraper without express written permission. | No |
| [The Odds API](https://the-odds-api.com/sports-odds-data/betting-markets.html) | Moneylines, spreads, totals, and other prices. | No betting-percentage market. An extra request would spend the free credits this phase is not allowed to spend. | No |
| [Sportradar Insights](https://developer.sportradar.com/insights/reference/betting-splits-nfl) | A betting-splits product. | A paid commercial API, not a free display right. | No |
| [Playbook API](https://api.playbook-api.com/) | A free tier that advertises bet percent and money percent. | The marketing page says its terms allow use in apps. The [terms page](https://www.playbook-api.com/terms-of-service) returned no license text, only an empty site shell. A new account is not approved. | No |
| [MoneyLine API](https://www.moneylineapp.com/terms) | Odds and model output. Its [line-movement note](https://www.moneylineapp.com/docs/endpoints/ai) says it has no bet-percentage data. | Display inside an app is allowed. There is nothing to display for tickets and money. The free key asks for a card. | No |
| [Krok Odds](https://krokodds.com.au/terms) | Its own analyzed market data. | Display in your product needs attribution, and the same terms say not to use the data to run a public odds or betting-analytics service. | No |
| Sports Betting Dime, ScoresAndOdds, VSiN | Pages or apps that show splits to their own readers. | No terms were found that grant this app a display right. Sports Betting Dime's terms URL and ScoresAndOdds' terms URL both returned "not found." VSiN's splits are a subscription, and a [November 2026 comparison](https://www.thebettinginsider.com/guides/best-public-betting-splits-sites) describes them as DraftKings-only. | No |

[Galaxy Sports Edge](https://www.galaxysportsedge.com/data) labels some of these sources as cleared for its own product. The same page says Action Network does not grant commercial use, Pregame needs written permission, Covers restricts redistribution, and DraftKings Network is personal and non-commercial. Those primary terms are what this app follows.

nflverse, which this app already uses for stats, is shared under CC BY 4.0. It does not include ticket or money percentages.

## What the screen says when both sides exist

The sentences are in the app, and tests cover them. They stay hidden until a real public percentage is actually supplied. They are not filled with a sample.

- **Reverse line movement.** Most bets are on one side, and the line moved toward the other. Example: "Most bets are on the Chiefs, but the line moved toward the Bills. That usually means bigger bettors like the Bills."
- **Tickets versus money.** Most of the bets are on one side and most of the dollars are on the other, or the dollars are much more lopsided than the bet count.

"Usually" is the careful word. It is a description of the split, not a claim that the bigger bettors are right.

## What would change this

A written license that allows display, with a name we can print next to the numbers. Until that exists, the public row stays "not available," and the sharp row is the whole story.
