# Coach's Line

Odds Edge has its own NFL number. It is a team-strength rating plus a small logistic regression. The app shows it as **Coach's Line** on the Games list and the game page, and the full write-up is under More → Coach's model.

The number is not a tip. The model page repeats the past-seasons test, including when that test lost money. A difference from the books is marked "Differs from books". That mark is a comparison, not a pick.

## What it uses

All of the history is free nflverse data, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The license copy in this repo is `assets/NFLVERSE-LICENSE.md`. Odds Edge is not affiliated with nflverse.

- Schedules, including the closing spread and total, scores, and days of rest: [nflverse schedules](https://github.com/nflverse/nflverse-data/releases/tag/schedules).
- Play-by-play, summed to EPA per play, success rate, turnover rate, and explosive-play rate (20 yards or more): [nflverse play-by-play](https://github.com/nflverse/nflverse-data/releases/tag/pbp). Kneel-downs and spikes are left out.
- A count of players listed Out on the nflverse injury report, when that file exists. It is not a judgment about which stars are playing. A missing report is stored as zero.

No Odds API call is made. The free plan is already used by the odds snapshot. Current prices in the app are the snapshot the app already fetched. In sample mode the prices are the bundled sample board, and the ratings are the bundled model file.

In the schedules file, `spread_line` moves with the home team's final margin (positive means the home team was favored). The trainer turns that into the betting number, so home -3.5 means the home team lays 3.5. After every run, the favorite's cover rate is checked. A real closing line is near one half. If that check fails, the spread sign is wrong and the run stops.

## How the number is made

Each team has an offensive EPA per play and a defensive EPA per play (EPA allowed). Recent games count more. A game from 42 days ago counts half as much. Two hundred plays of league-average football are mixed in so a short sample cannot swing the rating.

Projected home margin = (home net EPA − away net EPA) × a points scale + home field. The scale and home field are an ordinary line fit on past games only. Home field is whatever that line produces. It is not typed in afterward.

Projected total uses the same kind of line on the sum of both offenses and both defenses. Defense here is EPA allowed, so a higher number means more points, not a better defense.

Two logistic regressions, with a fixed L2 strength (C = 1) and no search, estimate:

- the chance the home team covers the spread
- the chance the over hits

The inputs are the gap between our number and the line, plus both teams' offense, defense, last few games, rest, success rate, explosive rate, turnover rate, and players listed Out. Training rows drop pushes.

## The past test

Walk-forward by week. To score week 10, the fit uses only weeks before week 10. Same-week games are not used, so Thursday does not train Sunday. The split is not random.

For every scored game the test bets the side the model likes, at the closing number, at the usual -110 price (stake 1.10 to win 1.00). Pushes return the stake. Hit rate ignores pushes. Profit is divided by the amount staked.

"Closer than the close" is how often our number was nearer the final margin than the closing number was. The historical file only has the closing number, not the number from earlier in the week, so this is not a bettor's closing-line value. My Bets records the number on the ticket when you log the bet. After kickoff, the closing number is filled from line history when that game was already saved. You can still type a close. That comparison is the bettor's version. The report card, opened from Home or More, shows this past test, the calibration table, the prop-chance test, and whatever closing-line value the saved prices can support.

A separate line in the report counts only games where our number and the close differed by 2.5 points or more. That slice is easier to overread. The headline is the test that bets every game.

The "Differs from books" mark on a current game uses the books in the snapshot, not a new download. It appears when our number and those books differ by at least the setting (default 2.5 points) or the best price is at least 2% ahead of our chance per dollar, if our chance were right. The setting is on the model page. Moving it does not rewrite the past test. The mark is a comparison, not a pick. The past test of this number lost money.

## Run it

From the repository root, with Python 3.11 or newer:

```bash
pip install -r model/requirements.txt
python -m unittest discover -s model -t model
python model/train.py
```

`python model/train.py` downloads the nflverse files into `model/.cache/` (not committed), refits, and writes `assets/nfl-model.json`. The Flutter app bundles that file. The Dart server serves the same file at `GET /v1/model`. That route does not call The Odds API and does not need a key.

The GitHub Actions workflow `.github/workflows/nfl-model.yml` runs the unit tests, the trainer, `flutter analyze`, `flutter test`, and a web build on pull requests. It also runs on Tuesdays at 14:00 UTC and when someone starts it by hand. The Tuesday run commits a changed `assets/nfl-model.json`. Offseason runs just rebuild the same history.

## Where it shows up

- Games list and game page: Coach's Line, the books' number, the chance the favorite covers, the chance the over hits, and "Differs from books" when the setting is cleared. Each spread, total, and moneyline also gets Bet, Lean, or Skip from the price against our chance. A moneyline is Skip because this model has no moneyline chance. Pinnacle's fee-free chance, when the snapshot has it, is extra context for spreads and totals only.
- More → Coach's model: the strength table, a plain-language explanation, the past test, the difference setting, and the nflverse credit.
- Ask Coach: when the local backend is connected, the same numbers are included in the note the assistant is allowed to see. It still cannot invent a number that is not in that note, and it is told not to treat the model as a guarantee.
- My Bets → Bet log: the number on the ticket is saved when you log the bet. The closing number is what you enter after the game. The line says whether you beat the close, and by how many points.
