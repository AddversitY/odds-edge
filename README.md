# Odds Edge

NFL odds intelligence for Windows and iOS, built with Flutter.

Current continuation notes: [handoff](docs/HANDOFF.md),
[14 November product review](docs/PRODUCT_REVIEW_2026-11-14.md). For project-local Windows
setup, run `.\tools\setup.ps1`, then `.\tools\flutter.ps1 run -d windows`.
Older feature descriptions below refer to earlier development stages.

The first development version includes a responsive dashboard, matchup explorer,
exact-selection multi-sportsbook comparisons, best-price calculations, a
probability/EV calculator, explicit quote freshness and source times, and a
backend with interchangeable odds providers and persistent collected snapshots.

It starts with clearly labeled synthetic data. It does not contain a validated
prediction model or claim a profitable betting strategy.

## Try it

From this folder in a new PowerShell window:

```powershell
flutter run -d windows
```

The main navigation is Overview, Research, and Odds comparison. Research groups
Matchups, Players, and Proof Lab into tabs, preserving all analysis tools.
Overview's **Investigate a bet** action starts a player-yardage workflow:
choose a player, inspect recent evidence, replay workload/efficiency scenarios,
save a frozen prediction, and review the manual outcome. This uses bundled
historical records and user-entered prices without refreshing live odds.
Methodology: [Player simulation](docs/PLAYER_SIMULATION.md). Broader target scope:
[Competitor capability roadmap](docs/COMPETITOR_CAPABILITIES.md).
Refresh generates
new demonstration observations. Stale and suspended examples are deliberately
included so exclusions are visible. My accessible books applies a session-only
allowlist; it does not verify legal access in a jurisdiction.

To exercise the shared backend, open another terminal:

```powershell
dart run backend/server.dart
```

Then choose Connect local backend in the app. This remains demonstration mode
until a licensed feed is explicitly configured on the server.

## Free Odds API key

A free account from [The Odds API](https://the-odds-api.com/) is enough for
saved NFL snapshots. It is not a live stream. The app shows when the snapshot
was taken.

1. Create a free account and copy the key.
2. On the computer that runs the backend, set `ODDS_PROVIDER` to `the-odds-api`
   and `THE_ODDS_API_KEY` to that key. The other settings are listed in
   `.env.example`.
3. Start `dart run backend/server.dart` again and choose Connect local backend.

Do not put the key in the app, in a screenshot, or in git. The free plan is
500 credits a month. The backend spends them on a daily snapshot plus refreshes
about an hour and about 10 minutes before kickoff. Details and the optional
$30/month upgrade are in [docs/PROVIDERS.md](docs/PROVIDERS.md).

## Verify

```powershell
flutter analyze
flutter test
```

See [PRODUCT_PLAN.md](PRODUCT_PLAN.md), [provider research](docs/PROVIDERS.md),
and [backend setup and limitations](backend/README.md). No subscription or
hosting purchase has been made. iOS compilation requires macOS and Xcode.
