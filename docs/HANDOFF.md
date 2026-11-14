# Handoff

Odds Edge is an NFL odds app. It compares a price with the app's own chance. It does not tell the user to bet. The footer line is **Comparison, not a pick.**

The empirical parlay research simulator is implemented and explicitly experimental. Owner direction on
14 November: personal bet logging, outcome entry and a record-led experience
are not product priorities. The new automatic observation journal was removed,
along with the Bets navigation destination, My bets tool and save-to-bet-log
actions. Existing stored data remains intact for backward compatibility.

Read the [14 November product review](PRODUCT_REVIEW_2026-11-14.md) before
starting another feature. Focus on a simple, deep NFL research experience:
find a prop, compare its price and understand the evidence. Model-quality
backtests stay in secondary methodology tools. Today, Research and Tools are
the primary destinations. Research groups Props/Games and preserves search
and list state across navigation. Filters persist locally. Prop details lead
with price and evidence; Performance, Matchup, Prices and Model/math disclose
depth progressively. Assessment labels are Review, Thin margin and Pass;
legacy value enums remain compatible. Prop pricing enforces historical cutoffs and current availability. Nothing unfinished is
hidden behind a flag.

## Architecture

- **Flutter app** (`lib/`). Today, Research (Props/Games), and Tools, with a parlay builder and older research tools underneath. Web, Windows, and iOS share one codebase. `lib/main.dart` sets `debugShowCheckedModeBanner: false`.
- **Dart backend** (`backend/server.dart`). Loopback only, port 8787. The Flutter app never holds an API key. `BackendRepository` talks to `ODDS_API_BASE_URL` (default `http://127.0.0.1:8787`; a remote host must be HTTPS).
- **Python model** (`model/train.py`, `model/nfl_model.py`, `model/nfl_model_v2.py`, `model/build_features.py`). Downloads nflverse into `model/.cache/` (gitignored), fits Coach's Line, and writes `assets/nfl-model.json`. The Dart file `lib/domain/coach_line_v2.dart` must stay in step with the Python formulas. No Odds API call.
- **Bundled data** (committed, keep it small): `assets/nfl-model.json`, `assets/nfl-history.json`, `assets/nfl-player-stats.json`, `assets/nfl-matchup.json`, `assets/parlay-calibration.json`. nflverse, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). License copy: `assets/NFLVERSE-LICENSE.md`. Odds Edge is not affiliated with nflverse.
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
python -m unittest discover -s model -t model
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

Cool graphite and a pale-blue interaction accent. `lib/theme/edge_theme.dart`: background `#0C1017`, surface `#151C25`, text `#F3F6FA`, accent `#A8C7FA`. Fraunces stays on the wordmark; Outfit is used for interface headings and figures. Mint, amber and coral describe labeled value states, separate from navigation. Full direction: [product review](PRODUCT_REVIEW_2026-11-14.md).

The value rail is `ValueCheck` (`lib/ui/value_check.dart`): our chance, the book's no-vig, the gap, and one word. Bet is at least 3 cents of expected profit per dollar. Lean is any smaller profit. Skip is zero, a loss, or a missing chance. A likely side can still be Skip when the price is short.

iPhone width is the layout that matters (390px). One idea on the card, the math behind a tap. **Comparison, not a pick** once per screen, in the footer, with the responsible-gambling note. No Flutter debug banner.

## Rules

- Free data and free local files only. No new signup and no paid service unless the owner says so.
- Do not scrape sportsbooks. Odds come from The Odds API or the labeled sample board.
- Never commit or print a key. `backend/data/` and `model/.cache/` stay gitignored. Do not commit a big stats dump.
- Do not call a past loss an edge. The 16-game slice is not an edge. A prop test without sportsbook prices is not an edge.
- Same-game parlay prices the app builds are estimated. A payout the user pastes is the real price.

## November research and simulator milestone

Implemented in this milestone:

- Sample matchups use clubs confirmed in the bundled box scores through 2026-11-09; fixtures and prices remain invented, and do not represent the actual schedule or live rosters. The old demo-min-gb ID is retained for selection compatibility; its teams are Detroit and Green Bay.
- Player histories are indexed by stable player ID rather than rescanning the whole dataset for each window. Historical identity and projection inputs respect the Eastern game-date cutoff (including Sunday night UTC crossover); a recorded club outside the selected matchup disables the usage projection. Stale/stored/future injury reports do not add current teammate-out adjustments. Historical player positions use the last allowed observation.
- Prop details explain workload, opponent, game-script, availability, supporting and opposing inputs. The compact summary leads into full context under Matchup. Weather is explicitly not a prop-model input. Exact-line book rows show freshness, break-even probability, hypothetical return and model EV; alternate lines remain separate.
- `game_script_simulation.dart` fits rank-normal correlations from strictly earlier seasons. Minimum 12 paired observations, shrink n/(n+40), cap at ±0.65, then covariance repair. Seed 1729, 10,000 draws. Latent draw order is margin/total, team pass/rush, player stats. This is a statistical copula, **not** a physically constrained or play-by-play football simulation. Receptions use a nonnegative negative-binomial curve; quantile transforms preserve displayed, market-shrunk marginal chances. Supported player yards and receptions only; whole-number push lines, duplicate exposures and inconsistent alternate lines are rejected.
- The builder shows joint versus product, a Wilson Monte Carlo interval (excluding model uncertainty), lowest individual chance, the most common complete losing pattern, and a higher-chance alternate replacement when available. Book quote entry is optional decimal odds for the exact ticket. Changed ticket/model inputs invalidate the old result and quote; clock ticks and identical quote refreshes preserve them. No wager or outcome is recorded.
- Primary-builder same-game probabilities no longer fall back to fixed correlation coefficients. Unsupported spread/total joint estimates in legacy game-ticket comparisons are blank. The old math helpers remain for compatibility. Same-game illustrative payouts disclose their assumed 4.5% hold and product cap; they are not scored as an available edge without a user-entered quote. Cross-game payout comparisons use a common book's actual leg-price product when available.
- `model/parlay_simulation.py` evaluates the dependence layer with prior-season QB/leading-target-receiver pairs and median half-lines, on identical cases for joint and product. It uses analytical two-leg copula integration to avoid Monte Carlo noise in scores. Live usage marginals, availability selection and sportsbook profitability are **not** validated by this exercise.
- Committed report: 903 cases / 575 unique games. Joint Brier 0.19955 vs product 0.19960; log loss 0.58894 vs 0.58908. Below the 1,000-unique-game gate: adopted false, hasEdge false. Season splits, bins, cutoff and source hashes are reproducible in `assets/parlay-calibration.json`, shown on the report card and beneath simulator methodology. CI regenerates it after data refreshes. Zero odds credits.
- Phone checks cover 390×844, text scaling to 1.8, reduced motion, labeled semantic tap targets and keyboard activation. Large-text price headers, summary rows and section headings now wrap. Optional screenshot checks include simulation and validation views. These are automated checks, not a human assistive-technology usability study or a guarantee of performance on every device.
- Personal bet tracking remains intentionally absent. Legacy data compatibility is preserved.

Verification: 277 Flutter tests and 43 Python tests passed; Flutter analyzer clean; web and Windows release builds passed. Phone screenshot review includes simulation and calibration. Validation and preview instructions are in DEVELOPMENT.md. The local preview is http://127.0.0.1:8765/; it is only accessible on this computer. A hosted research prototype has since been added; see the deployment section below. No new account was created.

## Hosted prototype milestone

- Permanent preview: https://addversity.github.io/odds-edge/ . GitHub Pages uses the existing public repository. The publish-preview workflow runs checks, builds the web app under /odds-edge/, fetches the free NFL schedule, and deploys only the static artifact. Source commit is exposed in version.json for verification. No localhost dependency, key, journal or unauthenticated Dart server is published.
- Actual schedule and Sample props are explicit separate modes. Real games have no fabricated prices; they open research with prices unavailable. Free schedule refreshes run twice daily, while the browser rechecks the published file at most every five minutes. Date, source, attribution, stale/failed-update and unknown-price states are implemented. A failed source fetch does not replace the deployed artifact; a browser failure retains its last real snapshot with a warning.
- Snapshot schema forbids example flags or sportsbook quotes. Date normalization includes Eastern Sunday-night UTC crossover. In-flight requests cannot overwrite an explicit change to sample mode. Phone tests include enlarged text.
- No supported Odds API key was present locally or in repository secrets. Real odds publication remains blocked on that credential and a separately tested, quota-controlled integration. This release intentionally publishes only the attributed free schedule. Do not claim the quote feed is connected or describe scheduled data as a live stream.
- Latest local verification: 284 Flutter tests, 43 model tests, 4 schedule tests and a clean analyzer. The deployment workflow repeats relevant checks. Full operating instructions and constraints: DEVELOPMENT.md.

## Next

Collect owner feedback on the research flow and data freshness. The public prototype is in place. A provider credential and the real-price pipeline are the next product priorities. The proposed ensemble below is separate future work, not part of this milestone. Do not add bet journals or outcome-based engagement.

2. **Elo plus a gradient-boosted ensemble** (XGBoost or LightGBM) for the game residual, with the anti-overfit rules fixed before any run: week-based walk-forward, shallow trees, regularization, early stopping, a stable feature set, permutation importance and a noise-feature check, monotone constraints where the direction is known, and one locked holdout season that is not used to pick anything. Same adoption rule as version 2: both Brier and log loss strictly better on at least 1,000 games, and no "edge" unless the -110 test clears the existing profit bar. Keep `coach_line_v2.dart` matched to whatever the trainer ships. Do not search the ridge, the caps, or the tree depth after seeing the holdout.
3. **Production data and optional alerts.** The public research prototype is hosted. Connect an approved provider credential through a quota-controlled production integration before adding opt-in price alerts. The loopback development server must remain private. New accounts or paid tiers still need the owner's approval.
