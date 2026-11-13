# Prop chance

The chance on a player-prop card is not the raw hit rate. Five clears in five games is not a 100% chance, and it is not shown as a 26-point edge. Coach's Line, the team number in [MODEL.md](MODEL.md), is a different estimate and is not used here.

## What is mixed in

The anchor is the book's no-vig chance for that side. When the best open price and the other side of the same line are both posted by that book, the fee is taken off that pair. Otherwise the anchor is the books' consensus no-vig. A missing anchor does not get invented: the chance falls back to an even shrink, `(hits + 2) / (observed + 4)`, and there is then no edge to show.

Fewer than four recorded games stays blank. A missing stat is skipped, the same way the hit-rate windows already work.

With an anchor, the chance is the mean of a binomial record with a prior of 32 games at the market rate:

```
chance = (hits + 32 × market) / (observed + 32)
```

Thirty-two games is about two NFL seasons. One hot month therefore moves the chance only part of the way from the market to the raw rate. Eight clears in ten games against a 49% market lands near 56%, not 80%.

## The cap

The gap between that chance and the market is held to 10 percentage points. The cap opens only when all three of these are true:

- at least 30 recorded games
- the raw rate's standard error is 8 points or smaller
- the raw rate itself is more than 10 points from the market

The opened cap is the raw gap minus two standard errors. It never passes 15 points. A 40-of-50 record against a 50% market can show a 15-point gap. A 5-of-5 record cannot.

Bet, Lean, and Skip use this capped chance against the price. The edge chip is the same gap, in points. A short sample can still be a Bet when the price is long enough, and it can still be a Skip when the record is worse than the market.

## Where it is computed

`propSideChance` in `lib/domain/prop_chance.dart` is the record. The card, the other prices on that card, and each parlay leg use it unless the report card has adopted version 2. The hit-rate chart still shows the recorded games. The chart is the record. The chance is the estimate.

## Version 2, the usage projection

Version 2 starts from playing time instead of from a clear-or-miss record. For a line, it estimates the stat from the player's recent share of targets, carries, or dropbacks, his yards per chance, the team's pass rate, snap share when an earlier week has one, how many yards that defense has allowed lately and over the season, the implied team total, and teammates listed Out. Yards use a normal curve with that player's own game-to-game spread. Receptions use a negative binomial. The resulting chance is then pulled toward the no-vig with the same 32-game prior, and the same cap, as the record above.

The implied team total on a card is the spread and total already on the screen. The past test does not use a closing spread. It uses earlier final scores, so the week being scored cannot set its own number. Snaps and the injury list are the 2026 nflverse files already in the app. Earlier seasons have neither, and those factors stay at neutral. A missing share stays blank. Nothing is scraped, and no new feed is signed up for.

The report card scores version 2 and the record on the same player-games. The line is still the previous-season median and the anchor is still a fair 50%. Version 2 becomes the chance on the card only when it has a lower Brier score and a lower log loss than the record. If it does not, the card keeps the record and the report says version 2 was tested and not adopted. Either result is a forecast check, not a profit test and not a pick. Closing-line value is filled only when a prop price was saved twice. That read does not spend an Odds API credit.

## The past test

The report card runs this same function forward through the bundled box scores. To score a week, only earlier weeks are used. The line for a season is that player's previous-season median, frozen before week 1. The market anchor is a fair 50%, because this repo does not have historical sportsbook prop prices and does not buy or scrape them.

That test reports a Brier score and a log loss against the 50% anchor, plus a calibration table. It does not report profit. A result on a made-up line is not a betting edge. The card says so. Passing yards, receptions, rushing yards, and receiving yards are scored because the box scores already count them. The free plan prices those four on one game.
