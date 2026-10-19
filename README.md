# Odds Edge

NFL odds intelligence for Windows and iOS, built with Flutter.

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

Use Overview, NFL matchups, Odds comparison, or Probability lab. Refresh generates
new demonstration observations. Stale and suspended examples are deliberately
included so exclusions are visible. My accessible books applies a session-only
allowlist; it does not verify legal access in a jurisdiction.

To exercise the shared backend, open another terminal:

```powershell
dart run backend/server.dart
```

Then choose Connect local backend in the app. This remains demonstration mode
until a licensed feed is explicitly configured on the server.

## Verify

```powershell
flutter analyze
flutter test
```

See [PRODUCT_PLAN.md](PRODUCT_PLAN.md), [provider research](docs/PROVIDERS.md),
and [backend setup and limitations](backend/README.md). No subscription or
hosting purchase has been made. iOS compilation requires macOS and Xcode.
