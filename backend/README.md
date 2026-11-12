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
attests equivalent full-game rules including overtime and push on a tied
outcome. Leave it unset when those rules have not been checked. The price
tools still compare standard full-game markets from unverified books, grouped
by market and number, and each card says the house rules were not
independently verified. Unverified books do not receive the live best-price
badge on the odds comparison screen. Do not set this variable just to remove
the note. The 10 default books are not treated as verified on their own. A
free-tier response may include only 8 of them: Caesars and Fanatics are often
absent, and a missing book is not an error.

The first live adapter requests main NFL moneyline, spread, and total markets
for a list of up to 10 sportsbooks (`ODDS_API_BOOKMAKERS`). Leaving that unset
uses 10 major US books (DraftKings, FanDuel, BetMGM, Caesars, ESPN BET,
Fanatics, BetRivers, Hard Rock, Bally Bet, and Fliff). The Odds API bills a
bookmaker list as one region, so those three markets cost 3 credits. Asking
for both the `us` and `us2` regions instead would cost 6 and is no longer what
this adapter sends. It rejects unknown identities, invalid prices, absent
market times, and unsupported markets. Live props and alternate API requests
are not yet implemented; the UI/domain exercise these using synthetic examples.
New adapters implement `OddsProvider.fetch` and return normalized `OddsBoard`
objects. Pass multiple adapters to `OddsService` to combine feeds; do not mix
demo with real providers in production. Canonical kickoff changes need
reconciliation; ambiguous events are kept separate rather than fuzzy-merged.
Live player props require a stable player-ID registry and exact
stat/threshold/period/rule mapping.

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

- `GET /health`: process mode, and in live mode the saved credit counters,
  reserve, snapshot time, and schedule.
- `GET /v1/odds`: the shared snapshot. Normalized events and quotes,
  source/collection timestamps, provider status notices, and explicit demo
  provenance. `fetchedAt` is when that snapshot was collected.
- `GET /v1/odds?refresh=1`: ask for a new snapshot. Every user shares the
  result. A cooldown (default 10 minutes) and the credit reserve can skip the
  upstream call and return the cached snapshot instead.
- `GET /v1/model`: the Coach's Line file (`assets/nfl-model.json`). Ratings, the logistic fit, and the walk-forward backtest. This route does not call The Odds API and does not use a key. If the file is missing the response is HTTP 404 and the app keeps the copy bundled with the client.
- `GET /v1/lines?event=<event id>`: line movement for one game, built only from odds responses this server already fetched (main lines and props). It does not call The Odds API and does not spend a credit. Each snapshot has `at`, `kind` (`lines` or `props`), the teams, and `prices` (`market`, `outcome`, `point`, `bookId`, `decimal`, `status`, and `player` on a prop). The journal is `backend/data/line-history.jsonl`. It keeps about 45 days, at most 240 snapshots per game, and stays under about 2 MB by rewriting itself. The folder is not committed. An empty `event` is HTTP 400.
- `GET /v1/history?selection=<encoded selection key>&at=<optional ISO time>`:
  collected snapshots for an exact selection. Both source and collection times
  must be at or before `at`. This is not a complete Replay Lab or purchased archive.
- `POST /v1/assistant`: grounded research commentary from the configured model.
  A missing `XAI_API_KEY` returns HTTP 200 with `assistant unavailable` and
  does not call xAI. Invalid JSON returns HTTP 400. Odds routes are unchanged.

Live mode does not poll on a fixed timer. The free The Odds API plan includes
500 credits per month. The backend takes one daily snapshot (default 15:00 UTC)
and, using the free events endpoint for kickoff times, refreshes about one hour
and about 10 minutes before each kickoff. A busy NFL month is about 70–80 of
those planned refreshes, about 240 credits at 3 credits each. Restarting the
server reloads the last saved snapshot instead of spending a credit just to
start. `ODDS_REFRESH_SECONDS` now applies only to demonstration mode (clamped
to 30–3600 seconds) and does not control live polling.

Manual refresh is shared. It waits out the cooldown and stops after the daily
cap (`ODDS_ON_DEMAND_DAILY_CAP`, default 6). It also leaves enough credits for
the scheduled snapshots still left in the billing month, plus
`ODDS_CREDIT_RESERVE` (default 50) as a cushion. Scheduled snapshots may use
that cushion, but nothing is requested when the remaining credits cannot pay
for the call. Each planned snapshot is attempted at most twice. If The Odds
API reports a charge, that slot is finished even when the body cannot be
parsed. The screen keeps showing the cached snapshot. Credit headers
`x-requests-remaining`, `x-requests-used`, and `x-requests-last` are stored in
`backend/data/credits.json` and returned by `/health`. The free events call
does not overwrite the last odds cost.

The app shows `Snapshot as of <time>` so a saved price is not presented as a
live stream. Quotes older than 120 seconds before kickoff, or 20 seconds after
kickoff, still do not earn a live best-price badge.

Player props are a second, smaller budget. `GET /v1/props` returns the saved
prop snapshot and does not spend a credit. `GET /v1/props?refresh=1` may
request passing yards and receptions for the next two upcoming games. That is
2 markets × 2 games = 4 credits, and only when the saved snapshot is older
than 18 hours, today's prop spend is still under 4, the month is still under
60, and the call would not eat the credits held back for the regular
moneyline, spread, and total schedule (`ODDS_CREDIT_RESERVE`, default 50).
The one-minute timer does not refresh props. The events list used to pick
those two games is free. The actual charge is whatever The Odds API reports
in `x-requests-last`. A busy main-line month is about 240 credits; props add
at most 60, so the pair stays near 300 of the 500 free credits. The cache
file is `backend/data/props-snapshot.json` and is not committed. Sample mode
does not call this route for the Props screen: the sample board already
includes one passing-yards example. `ODDS_API_KEY` is accepted when
`THE_ODDS_API_KEY` is empty. The key is never written into an error.

Pinnacle is a third, smaller budget, and only for NFL spreads and totals.
`GET /v1/sharp` returns the saved snapshot and does not spend a credit.
`GET /v1/sharp?refresh=1` may spend. The request uses the eu region and
`bookmakers=pinnacle`, which The Odds API bills as one region, so spreads
and totals cost 2 credits. The cache lasts 8 hours. A day allows 3 pulls
and 6 credits. A month allows 18 pulls and 36 credits. A pull is skipped
when the credits left would fall below the regular-snapshot hold
(`ODDS_CREDIT_RESERVE`, default 50) plus those 2 credits. The one-minute
timer asks for this board, and a fresh cache does not call the network.
A missing or zero `x-requests-last` header still counts as 2 credits, so
a pull cannot be retried for free. The cache file is
`backend/data/sharp-snapshot.json` and is not committed. Sample mode does
not call the network: the sample board already includes a Pinnacle price
on the spread and the total. The key is never written into an error, a
log line, or the cache file. About 200 free credits were left when this
cap was added. The regular board and props still come first. Pinnacle
adds at most 36 credits in a month.

The Odds API's $30/month plan includes 20,000 credits, which is enough to
refresh about every 60 seconds during games. That upgrade is not turned on
here. A 60-second poll of three markets would use up the free 500 credits in
about 80 minutes.

Concurrent requests share a pending refresh. HTTP 429 responses trigger bounded
backoff; request failures do not inject a demo fallback. Cached observations
keep original timestamps and receive an unavailable status on provider failure.
Missing quotes disappear on the next successful full response.

Freshness requires **both** source and collection ages <=120 seconds before
kickoff and <=20 seconds after kickoff. Suspended/unverified/error quotes and
timestamps >5 seconds in the future are excluded. The client rechecks every
15 seconds and before rendering a best price. These thresholds measure observed
freshness, not guaranteed executable availability. With no final-status feed,
events past kickoff conservatively retain the stricter threshold.

Snapshots append to an ignored per-provider journal,
`backend/data/snapshots-<provider>.jsonl`, on successful collection. Demo and
live odds never share a file. Restart reloads the latest line only when its
provider id and demo flag match the running mode; a mismatch fetches again
instead of showing sample prices as live. Provider notices, including the
settlement-rules warning, are kept. The older shared `snapshots.jsonl` file is
not read. Charts show first/latest observed prices, never inferred
opening/closing prices. Local demo history is synthetic and must never be mixed
with actual market history. Storage is a single-process development journal;
migrate to indexed database storage, retention controls and scheduler before
deployment. The server also checks the schedule once a minute while it is
running. Caesars and Fanatics are on the default book list, but a free-tier
response may omit them. A missing book is left out of the board and is not
reported as a failure.

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
