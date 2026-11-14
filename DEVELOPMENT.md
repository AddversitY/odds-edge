# Odds Edge development

## Set up a fresh checkout

On Windows, Git and Python are the only prerequisites for project-local setup:

```powershell
.\tools\setup.ps1
.\tools\flutter.ps1 run -d windows
```

This installs Flutter 3.47.7 under `.tools/flutter` and Python packages under
`.venv`; neither is committed. The wrapper works without changing PATH.
Windows desktop builds also need Visual Studio's C++ desktop workload. Web
development can use Chrome. No Android SDK is needed for these targets.
For checks with this setup, use `.\tools\flutter.ps1 analyze --no-pub` and
`.\tools\flutter.ps1 test --no-pub`.

For a browser preview, run `.\tools\flutter.ps1 build web --release --no-pub`,
then `.\tools\preview.ps1`. It serves the built app at
`http://127.0.0.1:8765/` in a hidden background Python process, bound to
loopback only. This URL works on the computer running it; it is not public
hosting. The PID is in `.tools/preview.pid`; logs are in `build/review`.
The app starts in explicitly labeled sample mode without provider keys.

Alternatively, use a separately installed Flutter 3.47.7 on PATH. The SDK path
below is from the original development computer; it is not portable.
From the repository root in PowerShell, prepare an isolated Python environment:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r model/requirements.txt
.\.venv\Scripts\python.exe -m unittest discover -s model -t model
flutter pub get
flutter analyze
flutter test
```

The Python tests use `model` as the discovery root because the trainer and
tests import sibling modules directly. They do not need live odds or API keys.
Read [the current handoff](docs/HANDOFF.md) for the current navigation,
model results, and next feature specifications; older notes below describe
earlier versions of the app.

Flutter SDK: `C:\Users\vince\flutter`, added to the user PATH. Reopen terminals
after changing PATH. Initial installed versions: Flutter 3.47.7, Dart 3.13.5.

Free Visual Studio 2022 Build Tools 17.14.42 and Windows SDK 10.0.26100.0 are
installed; Flutter doctor passes Windows toolchain checks. Android SDK and Chrome
were absent and are not needed for this Windows build. An earlier optional Edge
debug launch failed to connect.

From `C:\Users\vince\development\odds_edge`:

```powershell
flutter doctor -v
flutter run -d windows
flutter test
flutter analyze
dart run backend/server.dart
```

The counter starter has been replaced by the Odds Edge MVP. The app launches in
explicit offline demonstration mode. The separate backend also defaults to demo;
choose Connect local backend to exercise its cache and persistent history.
Provider credentials belong only in backend environment settings.

Tests cover odds conversions, EV with pushes, exact selection matching, best
prices, stale/suspended/future observations, provider normalization, outages,
cache coalescing, history persistence, replay timestamp boundaries, and mobile
and desktop interaction/layout.

See `backend/README.md` for real-feed activation, refresh limits, HTTPS deployment,
iOS endpoint configuration, and known MVP gaps. No paid services are configured.

The generated application identifiers still use example defaults. Choose
production identifiers before distribution. iOS builds require macOS and Xcode:
https://docs.flutter.dev/platform-integration/ios/setup.

GitHub Actions (`.github/workflows/ios-build.yml`) builds the app on a Mac in
the cloud on every push and pull request to `main`, and when someone starts
the workflow by hand. It uses Flutter stable 3.47.7, which ships Dart 3.13.5
and satisfies the `sdk: ^3.13.5` constraint in `pubspec.yaml`. The job runs
`flutter pub get`, `flutter analyze`, `flutter test`, then
`flutter build ios --release --no-codesign` and a simulator build. It also
builds the Windows app. Downloadable artifacts are an unsigned iPhone app, a
simulator app, and the Windows release. No Apple certificate, provisioning
profile, or API key is used. The unsigned iPhone app cannot be installed on a
phone.

The iOS project already sets the deployment target to 15.0, which is what the
Flutter 3.47 engine requires. The app has no native iOS plugins, so nothing
asks for a newer target. The bundle id is still the example placeholder
`com.example.oddsEdge` (and `com.example.oddsEdge.RunnerTests` for the empty
Xcode test target). Do not invent a production id in the repo; replace that
placeholder with an id you own before any store upload.

## Later: TestFlight

TestFlight is not wired up. To put a build on a phone later you will need:

- An Apple Developer Program account, and an app created in App Store Connect.
- A unique bundle identifier. Replace `com.example.oddsEdge`. Apple rejects
  `com.example`.
- An App Store Connect API key (a `.p8` file plus its key id and issuer id),
  saved only as GitHub Actions secrets. Suggested names:
  `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and
  `APP_STORE_CONNECT_API_KEY_BASE64`. Do not commit the key.

Signing and the TestFlight upload stay out of the workflow until those exist.

Proof Lab now includes a synthetic Detroit–Green Bay moneyline exercise, editable percentage-point assumptions, sensitivity comparisons, and immutable local research snapshots. Records use LOCALAPPDATA on Windows; the iOS sandbox support-folder approach still requires validation on macOS/iOS. No native storage plugin or Windows Developer Mode change is required. The live fixture and model remain unconnected; all lab numbers are explicitly illustrative.
# Saved research comparison

Proof Lab now offers a comparison after two research snapshots have been saved.
Choose Snapshot A and Snapshot B to compare notes, input assumptions, assumed
win probability, and hypothetical EV. Differences are B minus A, expressed in
percentage points. The view identifies when EV crosses break-even without
claiming that a higher estimate improves forecast accuracy. It uses the same
fixed synthetic Detroit–Green Bay exercise and leaves saved records unchanged.
Selectors stack on narrow screens; the comparison needs no new package or feed.

# Connected workflow and field theme

Current implementation details: [Research workflow](docs/RESEARCH_WORKFLOW.md) and
[NFL field theme](docs/FIELD_THEME.md). NFL matchups now includes real scoring and
results evidence, with side-by-side season-to-date, last-three-week and latest-week
windows. Odds remain demo until a licensed feed is connected. The new
`ResearchWorkspace` replaces the original Proof Lab screen and adds draft recovery,
named/searchable snapshots, backup/export/import, captured quote provenance and
a sticky conclusion. The old `proof_lab.dart` is retained but no longer routed.

Verification: 23 automated tests passed, including the real dataset on a narrow
phone layout with larger text, week boundaries, byes, storage recovery and the
quote-to-research journey. Windows build and visual inspection completed. iOS
hardware verification and native 4K artwork remain outstanding; the generated
field asset is 1672 x 941. No paid provider or validated forecast model is enabled.

## Individual player research

The primary Overview action now opens a guided player investigation. Profiles
offer Investigate a bet, then Evidence → Simulate → Save → Review. The separate
frozen-prediction journal and manual review support portable backups alongside
existing Proof Lab research. Read [methodology](docs/PLAYER_SIMULATION.md) and the
[competitor capability roadmap](docs/COMPETITOR_CAPABILITIES.md) before extending
the model. It is conditional historical replay, not a calibrated next-game model.

Navigation now has three main destinations: Overview, Research, and Odds
comparison. Research contains Matchups, Players, and Proof Lab tabs and remembers
the last selected research tab. On phones the same grouping appears as Home,
Research, and Odds. Quote-to-lab navigation still opens the exact captured price;
saved research and all analysis tools retain their existing workflows.

Research → Players provides searchable
stable player identities, last-three-recorded-game box scores, current-season
totals and the previous three completed seasons. Regular season and postseason
stay distinct. Totals/averages show observed-statistic counts and unavailable
history stays explicit. Source and refresh details: [Player explorer](docs/PLAYER_STATS.md).

## Transparent research assistant

Proof Lab can explain or challenge the research on screen. The wording is
labeled AI-generated and is saved apart from your notes and assumptions. The
Windows and iOS app never calls xAI and never holds the key. Only the backend
reads `XAI_API_KEY`.

You can ignore this feature. Odds research still runs, and the panel then says
assistant unavailable.

When you want it, create an API key at <https://console.x.ai/>. Using the key
can create charges on your xAI account. Then open PowerShell and run these
commands. Replace the quoted key with the one you copied. The first command
moves into the project folder. The second remembers the key only until you
close this window. The third starts the backend:

```powershell
cd C:\Users\vince\development\odds_edge
$env:XAI_API_KEY = "paste-your-key-here"
$env:XAI_MODEL = "grok-4.7"
& C:\Users\vince\flutter\bin\dart.bat run backend/server.dart
```

Leave the window open while you use the app. You should see a line that the
research assistant is configured. It does not print the key. `XAI_MODEL` is
optional; without it the server uses `grok-4.7`. `XAI_REASONING_EFFORT` is
also optional and defaults to `low` (`none`, `low`, `medium`, or `high`).
Low keeps the reply shorter and cheaper. The panel shows **thinking…** while
it waits; a reply can take about a minute.

In the app, choose **Connect local backend**, open Proof Lab, and use
**Explain / challenge this research**. Ask it to explain or challenge the
frozen quote, your assumptions, and any team or player evidence that screen
was given. It is not supposed to invent statistics or promise a winning bet.

If you would rather not paste the key every time, search Windows Settings for
"environment variables", open **Environment Variables**, and add a user
variable named `XAI_API_KEY`. Close PowerShell, open it again, and run only
the `cd` and `dart.bat` commands above. A user variable is readable by anyone
who can sign in to this Windows account. Do not put the key in the project
folder, in the Flutter app, or in a message.

More route detail is in `backend/README.md`. Copy `.env.example` only as a
reminder of the names; do not commit a file that contains the real key.


## Empirical parlay research

Run `.venv\Scripts\python.exe model/parlay_simulation.py` to reproduce `assets/parlay-calibration.json` from the two bundled source datasets, without a network request or odds credits. The report records source SHA-256 hashes and season cutoffs. Python tests cover the analytical copula, sparse/capped correlations, covariance repair and future-season exclusion; Flutter tests cover seeded simulation, normal/count marginals, under-side direction, projection eligibility, ticket invalidation and quote correction.

The simulator supports 2–8 projected player-yard/reception legs and half-point lines. It is an experimental statistical script, not a physical football simulation or a validated profitability model. Whole-number push handling and other prop metrics are excluded explicitly. Report-card scoring is a dependence-layer comparison, not a test of live sportsbook offers.

Phone verification: `.\tools\flutter.ps1 test --no-pub test/simulator_flow_test.dart`. Optional visual checks: set `SCREENSHOT=1` and run `test/screen_shots_test.dart`; review `build/review/simulation-390.png` and `build/review/parlay-validation-390.png` as well as the existing research screenshots. The screenshots are gitignored.

## Hosted research prototype

Public preview: https://addversity.github.io/odds-edge/ . `.github/workflows/publish-preview.yml` builds and publishes from `main` and twice daily (10:20 and 22:20 UTC). It uploads only `build/web`, never backend storage or credentials. A failed schedule fetch/build leaves the previous deployment intact. `version.json` records the deployed commit/run. This is a noncommercial prototype preview; a commercial service needs an appropriate production host and data plan. GitHub Pages is static hosting, not the existing Dart backend.

Hosted builds use `--base-href /odds-edge/ --dart-define=ODDS_SNAPSHOT_PATH=data/snapshot.json`. Local desktop and default builds retain sample mode. Never use this define for a secret or put a provider key in Flutter. The hosted app does not call the optional loopback backend.

`tools/publish_snapshot.py --output build/web/data/snapshot.json` retrieves the public, attributed nflverse schedule and exports known kickoffs in the next 14 days. It translates Eastern game time to UTC, excludes completed games and unknown kickoffs, and exports no historical closing lines as current prices. There are no odds calls or odds credits. The browser checks the published snapshot at most every five minutes, validates its schema/provenance, rejects mixed demonstration/price data, and labels a schedule older than 24 hours. Failed requests retain the last loaded real schedule with an update warning; they never switch to examples automatically.

Public mode starts on actual scheduled games with prices explicitly unavailable. Sample props is a separate, user-selected mode for reviewing the existing research UI and simulator. Historical player/model files keep their own cutoffs. Source, license and refresh explanations are in About this data.

No Odds API credential was found in the supported local environment scopes or GitHub Actions secrets during setup. Real sportsbook quotes are not activated by this release. A provider credential and a separately tested, quota-controlled quote publication/backend integration are still required. Do not add raw keys to commits, chat, browser storage or public data files. The current schedule-only schema deliberately rejects quotes until that integration is implemented.

Checks: 284 Flutter tests, 43 model tests, 4 schedule-export tests; clean analyzer. The public deployment workflow repeats app checks and schedule tests before publishing. Official hosting references: https://docs.github.com/en/get-started/start-your-journey/deploying-your-website-automatically and https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits .
