# Connected research and NFL evidence

## Using the app

1. Open Odds comparison, select the exact market and line, and choose **Investigate in Proof Lab** (best eligible quote) or **Research this price** (individual eligible book).
2. The captured event, selection, line, rules, provider, price, source time and collection time travel into Proof Lab. This observation is not represented as a current offer.
3. Edit the assumed baseline probability and illustrative adjustments. The sticky summary shows the current assumption-based conclusion. Signed bars show negative EV to the left and positive EV to the right; this is not model confidence.
4. Give the research a name and save a snapshot. Drafts autosave locally after a short pause and on navigation. The Research library supports searching, exploring a copy, comparing the same exact selection, export, and restore.
5. Backup/export writes an exact copy of the research journal and provides portable JSON via an explicit Copy action. Restore validates the entire export before adding records, creates a backup first, skips duplicates and preserves originals. Copy exported JSON to an external location for protection against device loss. Local backup alone does not protect against device loss.

## NFL time windows

NFL matchups contains a separate real-data evidence panel. Choose two teams, a season and **Analyze before week**. The season-to-date, last three NFL calendar weeks, and latest NFL calendar week all end before that selected week. Week 19 gives the full completed regular season. A bye or unavailable result is not a zero. This does not mean the last three games; byes can make the count smaller.

Each team shows record, sample size, points scored/allowed per game and average scoring margin. Game-by-game entries include a pregame form summary for both teams, excluding the target game and later weeks.

Trend labels compare weeks 1–3 with the selected recent window (last 3 played games, last 4 played games, or last 3 NFL weeks) using average scoring margin. Windows must not overlap and must contain at least two games each. Changes above +3 points are described as improving, below -3 as declining, otherwise broadly stable. This is a transparent descriptive heuristic, not a significance test or predictive model. Opponent quality is not adjusted for.

Played-game windows skip byes and stay within the selected season and before-week cutoff. Short samples report the actual count rather than filling missing games. Expand "Games in this window" to inspect dates, opponents, scores, outcomes and margins. Season-to-date, latest NFL week and most recent played game remain visible. Each historical game's entering-form summary includes the prior 3 and 4 played games, excluding that game and subsequent results. Current coverage is final-score statistics, not player usage, yardage or injury data.

## Prediction Autopsy

The Research library now supports manual outcome reviews (win, loss, push or void), source references and notes, without modifying original predictions. Corrections append to reviews.jsonl; portable exports include the latest reviews and raw backups preserve the review journal alongside research. Import preserves existing local reviews.

Accuracy uses the earliest pregame, non-demo snapshot per exact selection, chosen before checking whether it was reviewed. Demo, late, missing-event and void entries do not contribute. Probability error is half the squared error across win/loss/push outcomes; with no push probability this is binary Brier error. Manual outcomes remain unverified. Correlated selections are not independent evidence, and this diagnostic does not establish profitability. Closing-line value awaits verified closing quotes.

## Historical source

Source: nflverse contributors, [schedules release](https://github.com/nflverse/nflverse-data/releases/tag/schedules), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). License copy: `assets/NFLVERSE-LICENSE.md`.

`tools/import-history.ps1` transforms the downloaded CSV into `assets/nfl-history.json`: completed 2022–2026 regular-season results through the stated snapshot cutoff, retaining week, date, teams and final scores. Asset metadata includes retrieval time, full-source SHA-256, source URL, attribution and changes. No sportsbook odds columns are imported. The current NFL week may be incomplete. This is a bundled snapshot, not a live score service.

The educational home-win benchmark estimates a constant probability on 2022–2024 non-tied games and evaluates Brier error on 2025 non-tied games. This is chronological holdout evaluation, not a calibrated team model or evidence of betting profitability. Source revisions mean even week-filtered results are **not strict point-in-time replay**. Strict replay still requires publication-time snapshots for every input and authentic historical odds.

## Persistence and compatibility

Version-two research records carry a frozen quote context, names and adjustable probability/push assumptions. Version-one teaching snapshots remain readable. Corrupt or unsupported lines generate warnings while readable records remain accessible; originals stay untouched. Writes are serialized per store instance and incomplete journal tails are separated before later appends. Draft and preference journals remain device-local and currently append-only; compaction and multi-process locking remain future production hardening.

Events now carry sport and league fields through `SportEvent`. A `NflEvent` alias and legacy defaults preserve existing adapters and stored data. This enables other sports structurally; it does not imply additional provider coverage.

## Platform verification limits

The individual-player explorer is documented in `docs/PLAYER_STATS.md`: three recent recorded games, the current season and three completed seasons, with source attribution and missing-value-aware totals/averages.

Windows and responsive Flutter widget tests are available here. iOS storage still needs validation on macOS/Xcode and a device/simulator, including reopening, backgrounding, export/import, larger text and keyboard navigation. The current storage resolver uses the app HOME/Application Support path; hardware validation has not been claimed. No production feed, validated prediction model, account sync, or paid service has been enabled.
