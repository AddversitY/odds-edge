# Guided player investigation and empirical scenario replay

Entry points: **Overview → Investigate a bet**, or **Research → Players →
Investigate a bet** on a quarterback, running back, receiver or tight end.
The guided screen has Evidence, Simulate, Save and Review steps. **Review saved
predictions** on Overview opens frozen player investigations across players.
Existing odds comparisons, Proof Lab, AI panel and statistical explorers remain.

## Method

`paired-game-replay-v1` supports passing, rushing and receiving yards. Each
observation contains a whole historical (yards, attempts/carries/targets) pair.
Evidence is regular season only, filtered by chosen game-date cutoff and window
(last 20, last 10, or current season). Zero opportunities with zero yards remain
an observation. Missing values, negative opportunity and impossible nonzero
yards with zero opportunity are excluded and counted. At least five valid pairs
and some recorded opportunity are required.

One replay samples a whole pair uniformly, then computes:

`adjusted yards = (opportunity × workload factor) × (yards / opportunity × efficiency factor)`

A zero-opportunity pair yields zero. This retains each game's observed pairing;
volume and rate are not independently shuffled. Adjusted production rounds to
whole yards to match NFL yardage settlement. Both controls are explicit,
uniform scaling assumptions, not fitted injury/weather effects. Negative
yardage remains negative. The app generates 10,000 draws using a defined
32-bit xorshift sequence, seeded at 42, and saves the inputs/seed/trial count.
The method is deliberately simple and unvalidated for future forecasting.

Win/loss/push are mutually exclusive at the exact entered threshold. Conditional
EV is `p(win) × (decimal odds − 1) − p(loss)`. Fair decimal price, when p(win)>0,
is `(1 − p(push)) / p(win)`. Quantiles describe simulated outcomes, not model
confidence intervals. More trials reduce Monte Carlo noise, not historical
sampling uncertainty or model error. No betting recommendation is generated.

Stress cases vary workload and efficiency in directions adverse to the chosen
Over/Under. Clamped controls are disclosed by their actual values. A sign
reversal is described as assumption-sensitive, never as a validated edge.

## Evidence and identity

Recent form compares the latest three nonmissing paired records against the
separate earlier sample in the selected window. Yardage/game, opportunity/game
and pooled yards/opportunity are shown. The interpretation uses a descriptive
10% change threshold; it is not a significance test. The screen also shows the
recent mean with the highest-yardage game left out, and raw hit counts at the
same fixed threshold over recent and prior seasons. Those are descriptive
checks, not historical sportsbook prices or forecasts. Opponent quality, injuries,
snaps, routes and weather are not inferred. Source box scores are retrospective
and may contain corrections. Date filtering is not strict point-in-time replay.

The source snapshot currently ends 2026-10-18. Player IDs persist across trades.
Historical teams/opponents stay attached to each row. The new flow never fetches
odds; starting price/line values are examples. User-entered prices/books/game
dates are explicitly manual and unverified. A future adapter may attach a real,
precisely matched quote, but none is manufactured here.

## Persistence and review

`player-investigations.jsonl` stores immutable evidence records, manual price,
thesis, cutoff, optional target date, source attribution/digest and scenario
version. `player-investigation-reviews.jsonl` appends manual final production,
optional opportunity, source reference, notes and corrections. Existing research
is not overwritten. Corrupt lines remain preserved and readable records recover.

Review compares the original conditional forecast with manual final outcomes,
computes win/loss/push probability error (half summed squared error, 0 best),
and compares actual versus assumed opportunity when supplied. Voids have no
probability error. These unverified manual diagnostics do not establish model
skill. No automated CLV or aggregate validated accuracy is claimed. Entered
future game dates prevent early outcome entry; settlement still needs confirmation.

Portable research exports now include investigations and latest reviews. Raw
backup writes sidecars for their append-only journals alongside the existing
research/review backups. Import validates inputs before writes, skips identical
records and preserves local review corrections. No account sync or purchases.

## Not yet provided

A calibrated next-game model, live player props, injury/usage feeds, fully
coherent game simulation, rigorous historical odds replay, automatic settlement,
verified kickoff/closing prices, and competitor-wide feature parity remain
development work. See `docs/COMPETITOR_CAPABILITIES.md` for the complete scope.
