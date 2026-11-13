# Handoff

Odds Edge is an NFL odds app. It compares a price with the app's own chance. It does not tell the user to bet. The footer line is **Comparison, not a pick.**

This branch does not add the correlated parlay simulator or the automatic "Our record" log. Both were left out. Nothing unfinished is hidden behind a flag. The next-steps list at the bottom is the spec.

## Architecture

- **Flutter app** (`lib/`). iPhone-simple screens on top (Home, Props, Games, Parlays, My Bets, More) and the older research tools underneath. Web, Windows, and iOS share one codebase. `lib/main.dart` sets `debugShowCheckedModeBanner: false`.
- **Dart backend** (`backend/server.dart`). Loopback only, port 8787. The Flutter app never holds an API key. `BackendRepository` talks to `ODDS_API_BASE_URL` (default `http://127.0.0.1:8787`; a remote host must be HTTPS).
- **Python model** (`model/train.py`, `model/nfl_model.py`, `model/nfl_model_v2.py`, `model/build_features.py`). Downloads nflverse into `model/.cache/` (gitignored), fits Coach's Line, and writes `assets/nfl-model.json`. The Dart file `lib/domain/coach_line_v2.dart` must stay in step with the Python formulas. No Odds API call.
- **Bundled data** (committed, keep it small): `assets/nfl-model.json`, `assets/nfl-history.json`, `assets/nfl-player-stats.json`, `assets/nfl-matchup.json`. nflverse, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). License copy: `assets/NFLVERSE-LICENSE.md`. Odds Edge is not affiliated with nflverse.
- **Caches, not committed:** `backend/data/` (odds snapshots, `line-history.jsonl`, `props-snapshot.json`, `sharp-snapshot.json`, `credits.json`, `injuries.json`) and `model/.cache/` (nflverse downloads and the Open-Meteo archive). The app's own notes (research, bets, saved plays) are a local journal, file on VM/desktop and local storage on web. No account and no paid database.

Odds come from The Odds API when the server is in live mode. Injuries: ESPN's public file, checked against the NFL.com injury page, with the nflverse season file as backup. Weather for version 2: Open-Meteo archive at the kickoff hour for the backtest; live US forecasts try the National Weather Service, then Open-Meteo. No key for weather.

## Run it

Demo mode is the default. No key, no account, sample prices, labeled example.

```bash
flutter pub get
flutter run -d chrome
```

Windows: `flutter run -d windows`. The app opens on the sample board.

Backend, still demo, from the repo root:

```bash
dart run backend/server.dart
```

Then choose **Connect local backend** in the app. The demo badge stays until `ODDS_PROVIDER` is `the-odds-api` and a key is set in the server environment. Do not put the key in Flutter, in `--dart-define`, in a screenshot, or in git.

Checks:

```bash
flutter analyze
flutter test
python -m unittest discover -s model -t .
python model/train.py
```

CI (`.github/workflows/nfl-model.yml`) runs the Python tests, the trainer, `flutter analyze`, `flutter test`, and a web build on pull requests. `.github/workflows/ios-build.yml` also analyzes, tests, and builds iOS (no codesign) and Windows. Flutter in CI is 3.47.7.

## Environment variables

Names only. Values stay in the server environment. `.env.example` is a comment; the server does not read that file.

`ODDS_PROVIDER`, `THE_ODDS_API_KEY`, `ODDS_API_KEY` (alias for the key), `ODDS_API_BOOKMAKERS`, `ODDS_API_MARKETS`, `ODDS_CREDIT_RESERVE`, `ODDS_ON_DEMAND_DAILY_CAP`, `ODDS_BILLING_RESET_DAY`, `ODDS_ON_DEMAND_COOLDOWN_SECONDS`, `ODDS_DAILY_SNAPSHOT_UTC`, `ODDS_KICKOFF_LEADS`, `ODDS_SCHEDULE_GRACE_MINUTES`, `ODDS_SLOT_COALESCE_MINUTES`, `ODDS_EVENTS_REFRESH_HOURS`, `VERIFIED_NFL_RULE_BOOKS`, `ODDS_REFRESH_SECONDS` (demo polling only), `XAI_API_KEY`, `XAI_MODEL`, `XAI_REASONING_EFFORT`.

The Flutter define `ODDS_API_BASE_URL` is the backend address, not a secret.

## Odds API free plan

500 credits a month. A main-board snapshot (moneyline, spread, total, up to 10 books) costs 3 credits: one daily snapshot plus about an hour and about 10 minutes before kickoff. A busy month is about 240 of those credits.

Props are separate and smaller. `GET /v1/props` reads the cache and spends nothing. A refresh is passing yards, receptions, rushing yards, and receiving yards for the next game: **4 credits**, at most **4 per day** and **60 per month**, and only when the cache is older than 18 hours. It is skipped if it would eat the credits held for the main board. That hold is `ODDS_CREDIT_RESERVE` (default 50) plus the cost of the call. The one-minute timer does not refresh props.

Pinnacle spreads and totals (`GET /v1/sharp`) are a third budget: 2 credits a pull, cache 8 hours, at most 6 credits a day and 36 a month, same reserve. About **200 free credits were left this month** when that cap was added (`backend/README.md`). Do not spend them on a new feed. The live remaining count is the `x-requests-remaining` header stored in `backend/data/credits.json` and shown by `GET /health`. Reading stored snapshots does not spend a credit.

The $30/month, 20,000-credit plan is not turned on.

## Modeling

**No-vig.** When one book posts both sides, the fee comes off in proportion to the two prices. Otherwise the cards average the books that did post both sides. That chance is the market, not a prediction.

**Market prior plus residual.** Coach's Line version 2 starts at the no-vig number (Pinnacle when both sides are in the snapshot, otherwise the books; the closing number in the backtest, because the free schedule has no earlier line). A walk-forward residual may then add a quarterback change, outs weighted by position and snaps, open-roof weather, rest, and travel. Scales are ridge-shrunk (`RIDGE_LAMBDA` 40). The margin residual is capped at 4 points and the total residual at 6. A normal week, a closed roof, and the usual quarterback add zero. The chance is a normal draw around that number (`sigma` 13), then a Platt map fit on earlier weeks only.

**Props.** Version 1 is a record shrunk toward the no-vig with a 32-game prior, then capped (10 points, opening toward 15 only after 30 games and a small standard error). Version 2 projects the stat from usage (target, carry, or dropback share), efficiency, team pass rate, snaps, defense, the implied team total, and teammates listed Out. Yards are normal. Receptions are negative binomial. An isotonic recalibration is fit on earlier weeks only, after 200 earlier forecasts, in bins of 80. The same 32-game shrink and cap are applied after that. The past test uses the previous season's median as the line and a fair 50% as the anchor. It does not use a closing spread.

**Walk-forward.** A week is scored only with earlier weeks. Same-week games are not used. The split is not random.

**Adoption, set before the run.** A new chance replaces the old one only when both Brier and log loss are strictly lower, on the same games, at least 1,000 of them. Recalibration replaces raw usage only when it beats both raw usage and the record. The "Differs from books" mark needs the moved-line slice to beat a -110 price on at least 200 decided games. Profit is a separate bar: positive return and a hit rate that clears 52.4% by two standard errors. Missing either bar, the number can still be shown, and the screen says there is no edge.

## Current results

From `assets/nfl-model.json`, generated 2026-11-13, scored through 2026-11-09. Version 2 is the number on the game cards (`v2.adopted` true) because its Brier and log loss beat version 1. It has **no betting edge** (`v2.hasEdge` false, `differsHelped` false).

| | Version 1 | Version 2 (live) |
| --- | ---: | ---: |
| Games | 2,885 | 2,885 |
| Hit rate at the close, -110 | 50.8% (1,428–1,382–75) | 50.5% (1,418–1,392–75) |
| Return | -2.9% | -3.6% |
| Brier | 0.251 | 0.250 |
| Log loss | 0.695 | 0.694 |
| Closer than the close | 42.4% | 46.8% |

Break-even at -110 is about 52.4%. Average miss is 9.8 points, the same as the close. The 2.5-point slice is 16 decided games (11–5, +31%). That is under the 200-game bar, so the games do not say "Differs from books." Totals in the same test hit 53.0% and returned +1.1%. That is not an edge either. Version 1 totals were 49.3% and -5.8%.

Props, from the walk-forward on the bundled box scores (PR #17, 17,097 paired player-games, fair 50% line, no sportsbook prop price):

| | Brier | Log loss |
| --- | ---: | ---: |
| Record | 0.241 | 0.675 |
| Usage, live | 0.238 | 0.669 |
| Usage, recalibrated | 0.239 | 0.672 |

`propLiveChance` in `lib/domain/prop_model.dart` is `usage`. Recalibration was tested and not adopted. This is not a profit test. Recompute with `comparePropModels` before quoting a newer file; the scores are not hardcoded.

## Design

Night ink and one chartreuse mark. `lib/theme/edge_theme.dart`: background `#100E0C`, surface `#1B1814`, text `#F7F2E9`, accent `#D6F25C`. Fraunces for display numbers and titles, Outfit for everything else. Green, amber, and coral are only for the value check (Bet, Lean, Skip), not for chrome.

The value rail is `ValueCheck` (`lib/ui/value_check.dart`): our chance, the book's no-vig, the gap, and one word. Bet is at least 3 cents of expected profit per dollar. Lean is any smaller profit. Skip is zero, a loss, or a missing chance. A likely side can still be Skip when the price is short.

iPhone width is the layout that matters (390px). One idea on the card, the math behind a tap. **Comparison, not a pick** once per screen, in the footer, with the responsible-gambling note. No Flutter debug banner.

## Rules

- Free data and free local files only. No new signup and no paid service unless the owner says so.
- Do not scrape sportsbooks. Odds come from The Odds API or the labeled sample board.
- Never commit or print a key. `backend/data/` and `model/.cache/` stay gitignored. Do not commit a big stats dump.
- Do not call a past loss an edge. The 16-game slice is not an edge. A prop test without sportsbook prices is not an edge.
- Same-game parlay prices the app builds are estimated. A payout the user pastes is the real price.

## What this branch did not ship

Left out, not flagged off:

1. **Correlated parlay simulator.** Today `lib/domain/parlay_value.dart` uses a fixed same-game correlation (about 0.15, 0.30 for a quarterback and a receiver on the same team, -0.95 for the two sides of one line) and a closed-form joint. There is no Monte Carlo game script, no empirical correlation from nflverse, no shrink-and-cap of those correlations, no weakest-leg, no "most likely way this loses," and no backtest of joint chance against the independent product. Same-game payouts are already labeled estimated.
2. **Self-tracking ("Our record").** My Bets saves a play only when the user taps save. After kickoff, a logged bet can pick up a closing number from line history. The app does not automatically store every Bet, Lean, and Skip it shows, and the report card has no weekly review of those suggestions by market and spot.
3. **Screenshots** of a simulated ticket, the weakest leg, parlay calibration, and a weekly record. Not produced, because those screens do not exist.

## Next

1. **Finish the two features above, or do not start them halfway.** A solid cut is: walk-forward correlations from earlier seasons only, shrunk toward zero and capped; a seeded simulation (on the order of 10,000 draws) of margin and total, then team pass and rush, then each player's stat from the prop projection; joint chance versus the product of the legs versus the book's implied chance, with same-game prices labeled estimated; weakest leg and the usual swap (same line at another book, an alternate line, or another leg); a historical Brier and log loss of the joint against the independent product, shown on the report card, with no claim of an edge and no extra Odds API credits. Self-tracking: append each shown suggestion (time, book, line, price, our chance, no-vig) to a local or `backend/data/` file, grade it from scores and closing lines already stored, and put CLV, hit rate versus the chance we stated, and thin-sample slices on the report card. Tests before UI. No sportsbook scraping.
2. **Elo plus a gradient-boosted ensemble** (XGBoost or LightGBM) for the game residual, with the anti-overfit rules fixed before any run: week-based walk-forward, shallow trees, regularization, early stopping, a stable feature set, permutation importance and a noise-feature check, monotone constraints where the direction is known, and one locked holdout season that is not used to pick anything. Same adoption rule as version 2: both Brier and log loss strictly better on at least 1,000 games, and no "edge" unless the -110 test clears the existing profit bar. Keep `coach_line_v2.dart` matched to whatever the trainer ships. Do not search the ridge, the caps, or the tree depth after seeing the holdout.
3. **A stable public link and edge alerts.** Free permanent hosting, and a ping when a price is ahead of our chance. This needs the owner's approval before any signup, host account, or paid tier. The loopback server has no auth and should not be put on the public internet as it is.
