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

`propSideChance` in `lib/domain/prop_chance.dart` is the only prop chance. The card, the other prices on that card, and each parlay leg all use it. The hit-rate chart still shows the recorded games. The chart is the record. The chance is the estimate.
