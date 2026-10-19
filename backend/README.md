# Odds Edge backend (development MVP)

One Dart backend serves the Windows and iOS clients; provider secrets stay here.
It uses only Dart's standard library. From the repository root:

```powershell
& C:\Users\vince\flutter\bin\dart.bat run backend/server.dart
```

The default is explicit demonstration mode, bound to loopback port 8787.
In the app choose **Connect local backend**. The backend's demonstration badge
remains visible. The app starts in offline demo mode so no account is required.

## Connecting an approved feed

After approving a provider's rights and subscription, supply credentials through
server environment variables (never commit them or put them in Flutter defines):

```powershell
$env:ODDS_PROVIDER = 'the-odds-api'
# Set THE_ODDS_API_KEY securely in the server environment.
# Set VERIFIED_NFL_RULE_BOOKS only after verifying full-game settlement rules.
dart run backend/server.dart
```

Book identifiers for rules verification are normalized IDs such as `fanduel`,
`draftkings`, `caesars`. The comma-separated `VERIFIED_NFL_RULE_BOOKS` setting
attests equivalent full-game rules including overtime and push on a tied outcome.
Unverified books remain inspectable but cannot receive a best-price badge. Do
not set this variable just to remove warnings.

The first live adapter batches main NFL moneyline/spread/total markets across
US and US2. It rejects unknown identities, invalid prices, absent market times,
and unsupported markets. Live props and alternate API requests are not yet
implemented; the UI/domain exercise these using synthetic examples. New adapters
implement `OddsProvider.fetch` and return normalized `OddsBoard` objects. Pass
multiple adapters to `OddsService` to combine feeds; do not mix demo with real
providers in production. Canonical kickoff changes need reconciliation; ambiguous
events are kept separate rather than fuzzy-merged. Live player props require a
stable player-ID registry and exact stat/threshold/period/rule mapping.

## Research assistant (xAI)

The Proof Lab action **Explain / challenge this research** calls this backend.
The Flutter app never calls xAI and never sees the key. Leave the key unset
and the odds server still runs; the assistant answers `assistant unavailable`.

Create a key in the xAI console at <https://console.x.ai/>. Calls can add
charges to that xAI account, so skip this until you want the assistant.

In a PowerShell window, from the project folder, set the key for that window
only and start the backend. This does not save the key on disk:

```powershell
cd C:\Users\vince\development\odds_edge
$env:XAI_API_KEY = "paste-your-key-here"
$env:XAI_MODEL = "grok-4.7"
& C:\Users\vince\flutter\bin\dart.bat run backend/server.dart
```

`$env:XAI_MODEL` is optional. If you omit it, the server uses `grok-4.7`.
`$env:XAI_REASONING_EFFORT` is optional and defaults to `low` (`none`, `low`,
`medium`, or `high`). Closing the window forgets the key. Do not put the key
in the Flutter app, in `--dart-define`, in a screenshot, or in a file you commit.

To keep the key for later PowerShell windows, open Windows Settings, search
for "environment variables", choose **Environment Variables**, and under
**User variables** add `XAI_API_KEY`. Open a new PowerShell window afterward.
Anyone who can use that Windows account can read that variable.

Then in the app choose **Connect local backend**, open Proof Lab, and use
**Explain / challenge this research**. The panel is labeled AI-generated and
shows **thinking…** while a reply is in progress. A reasoning reply can take
about a minute. Its text is stored separately from your notes and assumptions.
It is not a forecast and it does not guarantee a result. With no key, or if the
model cannot be reached, the panel says assistant unavailable and leaves your
research unchanged. Web search is not requested.

`POST /v1/assistant` accepts JSON the app already has: `mode` (`explain` or
`challenge`), an optional `question`, the on-screen `selection`, a frozen
`quote` and `event` when a price was captured, `assumptions`, and optional
`teamEvidence` and `playerEvidence` lists. The reply is
`available`, `answer`, and `cited` (which of those inputs the answer used).
The model is instructed to use only that payload, not to invent stats or odds,
to flag uncertainty, and not to guarantee a wager. The request does not send
web search. The key is sent only on the server, in the Authorization header,
never in the URL. `reasoning.effort` defaults to `low`.

## Service contract and freshness

- `GET /health`: process mode.
- `GET /v1/odds`: normalized events and quotes, source/collection timestamps,
  provider status notices, and explicit demo provenance.
- `GET /v1/history?selection=<encoded selection key>&at=<optional ISO time>`:
  collected snapshots for an exact selection. Both source and collection times
  must be at or before `at`. This is not a complete Replay Lab or purchased archive.
- `POST /v1/assistant`: grounded research commentary from the configured model.
  A missing `XAI_API_KEY` returns HTTP 200 with `assistant unavailable` and
  does not call xAI. Invalid JSON returns HTTP 400. Odds routes are unchanged.

Backend refresh defaults to 60 seconds; `ODDS_REFRESH_SECONDS` is clamped to
30–3600 seconds. Concurrent requests share a pending refresh. HTTP 429 responses
trigger bounded backoff; request failures do not inject a demo fallback. Cached
observations keep original timestamps and receive an unavailable status on
provider failure. Missing quotes disappear on the next successful full response.

Freshness requires **both** source and collection ages <=120 seconds before
kickoff and <=20 seconds after kickoff. Suspended/unverified/error quotes and
timestamps >5 seconds in the future are excluded. The client rechecks every
15 seconds and before rendering a best price. These thresholds measure observed
freshness, not guaranteed executable availability. With no final-status feed,
events past kickoff conservatively retain the stricter threshold.

Snapshots append to ignored `backend/data/snapshots.jsonl` on successful
collection. History is retained on restart; the hot cache is not. Charts show
first/latest observed prices, never inferred opening/closing prices. Local demo
history is synthetic and must never be mixed with actual market history. Storage
is a single-process development journal; migrate to indexed database storage,
retention controls and scheduler before deployment. Collection currently occurs
while clients poll, not continuously when the application is closed.

## Windows and iOS

The same JSON contract is consumed by `BackendRepository`. For a deployed
backend run Flutter with `--dart-define=ODDS_API_BASE_URL=https://your-host`.
Remote endpoints must use HTTPS. On an iPhone, localhost refers to the phone;
use an approved HTTPS development endpoint. No global iOS transport-security
exception has been added. iOS builds still require macOS/Xcode.

This server is not public hosting: it has no user authentication, TLS termination,
per-user access control, deployment rate limiting, jurisdiction verification, or
managed secrets. Add these before exposing it beyond loopback. The accessible-
books UI is a session-only user allowlist, not a verified legal availability map.

No validated probability model, provider historical archive ingestion, true
closing prices, automated CLV, saved forecasts/autopsies or alerts are implemented
yet. Their records must reference immutable selection, quote, source/collection
times, model version and prediction-time feature snapshots.
