# Player explorer

Open **Player stats** on Windows or **Players** in the phone navigation. Search a player by name, latest recorded team abbreviation, or position. Player IDs link records across trades; names do not identify a player by themselves.

The main view defaults to the last three available recorded box-score games, including across seasons. A scope selector can restrict the recent window to a specific season. Individual dates/opponents and totals or per-game averages are visible. The current season is separate from the preceding three completed season labels (2023–2025 for the 2026 snapshot). Regular season and postseason remain separate. The selected-scope game log can be expanded.

## Source and reproducibility

Source: nflverse contributors, [Player Summary Stats release](https://github.com/nflverse/nflverse-data/releases/tag/stats_player), joined to [schedules](https://github.com/nflverse/nflverse-data/releases/tag/schedules) using the original game ID. See the [player dictionary](https://nflreadr.nflverse.com/articles/dictionary_player_stats.html). The repository publishes data under [CC BY 4.0](https://github.com/nflverse/nflverse-data/blob/main/LICENSE.md); the existing license copy is `assets/NFLVERSE-LICENSE.md`. No affiliation or endorsement is implied.

`tools/import_player_stats.py` downloads the nflverse player-week files and the schedule, then writes `assets/nfl-player-stats.json`. The cutoff is the latest completed game on or before the day it runs. Games without a score are left out. Metadata records source URLs, SHA-256 hashes, retrieval time, changes, and excluded rows. The transform validates team/opponent, season, week, and regular/postseason identity against completed schedules. Unattributed rows without player IDs/names are excluded and counted. Duplicate player/season/type/week records stop the import. Source postseason labels WC/DIV/CON/SB normalize to POST.

The Tuesday job in `.github/workflows/nfl-model.yml` runs that script and commits a changed file. It does not call The Odds API. `tools/import-player-stats.ps1` remains for a Windows refresh from CSVs that are already on disk. Its default cutoff argument is only for that local path.

Only additive box-score counts are included: passing, rushing, receiving, selected defense, kicking, and punting. All recorded zeroes are retained, and blank values stay unknown. Numeric arrays follow the asset's `statKeys` field to keep the snapshot compact without discarding zeroes. Rates, advanced metrics, odds, headshots and projections are not imported. No new package or subscription is needed.

## Interpretation

Three recorded games are not necessarily three consecutive team games or NFL weeks. This dataset is not a full participation/DNP log; missing player rows do not establish an injury, bye, retirement, or inactivity reason. Profiles display the date and historical team of each game. Latest recorded team is not a current roster claim.

For each metric, totals use only recorded values and averages divide by the number of nonmissing observations. Coverage denominators are shown. An unavailable statistic displays a dash, and seasons without records show an explicit empty state. Recent-versus-season differences are descriptive and do not prove predictive value.

This is a bundled retrospective snapshot. Current season/week coverage can be incomplete and revised later. The Tuesday job refreshes it from nflverse. It does not support strict point-in-time replay, and it is not a live stats feed. No live odds feed, injuries, participation, or player-prop model is implied.

Windows runtime and responsive widget tests can be checked here. Actual iOS device validation still needs macOS/Xcode.
