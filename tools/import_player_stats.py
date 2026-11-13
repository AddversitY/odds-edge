#!/usr/bin/env python3
"""Rebuild assets/nfl-player-stats.json from nflverse box scores.

The files are the public nflverse releases, CC BY 4.0. This script does
not call The Odds API and does not scrape a sportsbook. The Tuesday
workflow runs it so the bundled snapshot is not left on an old cutoff.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = ROOT / "assets" / "nfl-player-stats.json"
CACHE = ROOT / "model" / ".cache" / "player-stats"

RELEASES = "https://github.com/nflverse/nflverse-data/releases/download"
GROUPS = {
    "passing": [
        "completions",
        "attempts",
        "passing_yards",
        "passing_tds",
        "passing_interceptions",
        "sacks_suffered",
    ],
    "rushing": [
        "carries",
        "rushing_yards",
        "rushing_tds",
        "rushing_fumbles_lost",
    ],
    "receiving": [
        "targets",
        "receptions",
        "receiving_yards",
        "receiving_tds",
        "receiving_yards_after_catch",
        "receiving_fumbles_lost",
    ],
    "defense": [
        "def_tackles_solo",
        "def_tackles_with_assist",
        "def_tackle_assists",
        "def_sacks",
        "def_interceptions",
        "def_pass_defended",
        "def_tds",
        "def_fumbles_forced",
    ],
    "kicking": ["fg_made", "fg_att", "pat_made", "pat_att"],
    "punting": ["pt_att", "pt_yards"],
}
METRICS = sorted({metric for group in GROUPS.values() for metric in group})
POST = {"WC", "DIV", "CON", "SB", "POST"}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--cutoff",
        default=date.today().isoformat(),
        help="Inclusive game date. Later games, and games without a score, are left out.",
    )
    parser.add_argument("--current-season", type=int, default=2026)
    args = parser.parse_args()
    cutoff = date.fromisoformat(args.cutoff)
    seasons = list(range(args.current_season - 3, args.current_season + 1))
    schedule_path = _download(
        f"{RELEASES}/schedules/games.csv",
        CACHE / "games.csv",
    )
    schedule = _schedule(schedule_path)
    rows: list[dict[str, object]] = []
    sources: list[dict[str, object]] = []
    seen: set[str] = set()
    excluded = 0
    unattributed = 0
    for season in seasons:
        url = f"{RELEASES}/stats_player/stats_player_week_{season}.csv"
        path = _download(url, CACHE / f"stats_player_week_{season}.csv")
        sources.append(
            {
                "season": season,
                "url": url,
                "sha256": _sha256(path),
            }
        )
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            missing = [metric for metric in METRICS if metric not in (reader.fieldnames or [])]
            if missing:
                raise SystemExit(f"{path.name} is missing {', '.join(missing)}")
            count = 0
            for record in reader:
                count += 1
                if not record.get("player_id") or not record.get("player_display_name"):
                    unattributed += 1
                    continue
                game = schedule.get(record["game_id"])
                if game is None:
                    raise SystemExit(
                        f"Unmatched game {record['game_id']}; refresh the schedule before importing."
                    )
                played = date.fromisoformat(game["gameday"])
                if played > cutoff or game["home_score"] == "" or game["away_score"] == "":
                    excluded += 1
                    continue
                season_type = _season_type(game["game_type"])
                if (
                    season_type != record["season_type"]
                    or int(game["season"]) != int(record["season"])
                    or int(game["week"]) != int(record["week"])
                ):
                    raise SystemExit(f"Mismatched game metadata {record['game_id']}")
                if record["team"] == game["home_team"]:
                    opponent = game["away_team"]
                elif record["team"] == game["away_team"]:
                    opponent = game["home_team"]
                else:
                    raise SystemExit(f"Team does not match game {record['game_id']}")
                if opponent != record["opponent_team"]:
                    raise SystemExit(f"Opponent does not match game {record['game_id']}")
                key = f"{record['player_id']}|{season}|{record['season_type']}|{record['week']}"
                if key in seen:
                    raise SystemExit(f"Duplicate player game {key}")
                seen.add(key)
                stats = [_number(record[metric], metric) for metric in METRICS]
                rows.append(
                    {
                        "playerId": record["player_id"],
                        "name": record["player_display_name"],
                        "position": record["position"] or "Unknown",
                        "team": record["team"],
                        "opponent": record["opponent_team"],
                        "season": int(record["season"]),
                        "week": int(record["week"]),
                        "date": game["gameday"],
                        "seasonType": record["season_type"],
                        "stats": stats,
                    }
                )
        if count < 500:
            raise SystemExit(f"Unexpected player source size for {season}")
    latest = max((row["date"] for row in rows), default=args.cutoff)
    bundle = {
        "schema": 1,
        "sport": "american_football",
        "league": "NFL",
        "currentSeason": args.current_season,
        "cutoff": latest if isinstance(latest, str) else args.cutoff,
        "retrievedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
        "source": "nflverse contributors — player box scores and schedules",
        "sourceUrl": "https://github.com/nflverse/nflverse-data/releases/tag/stats_player",
        "dictionaryUrl": "https://nflreadr.nflverse.com/articles/dictionary_player_stats.html",
        "license": "CC BY 4.0",
        "licenseUrl": "https://creativecommons.org/licenses/by/4.0/",
        "sourceFiles": sources,
        "scheduleSha256": _sha256(schedule_path),
        "scheduleUrl": f"{RELEASES}/schedules/games.csv",
        "changes": (
            "Selected four NFL seasons through the latest completed game on or before the cutoff; "
            "joined completed schedules by game ID; retained identity, historical teams, dates and "
            "additive box-score counts. All source zeroes retained; missing values stay null. "
            "Packed numeric arrays use statKeys to preserve metrics compactly. No headshots, odds, "
            "rates, injuries or projections. Regular season and postseason kept distinct."
        ),
        "coverage": (
            "Recorded player box-score rows, not a complete participation or DNP log. "
            "Current season and current week can be incomplete. Historical revisions may be present; "
            "not point-in-time replay."
        ),
        "excludedFutureOrUnfinished": excluded,
        "excludedUnattributedRows": unattributed,
        "statKeys": METRICS,
        "rows": rows,
    }
    DESTINATION.write_text(json.dumps(bundle, separators=(",", ":")), encoding="utf-8")
    players = len({row["playerId"] for row in rows})
    print(
        json.dumps(
            {
                "rows": len(rows),
                "players": players,
                "bytes": DESTINATION.stat().st_size,
                "cutoff": bundle["cutoff"],
                "excluded": excluded,
            }
        )
    )


def _download(url: str, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "odds-edge-player-stats"})
    with urllib.request.urlopen(request, timeout=120) as response:
        path.write_bytes(response.read())
    return path


def _schedule(path: Path) -> dict[str, dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return {row["game_id"]: row for row in csv.DictReader(handle)}


def _season_type(game_type: str) -> str:
    if game_type == "REG":
        return "REG"
    if game_type in POST:
        return "POST"
    return game_type


def _number(raw: str, metric: str) -> int | float | None:
    if raw is None or raw == "" or raw == "NA":
        return None
    value = float(raw)
    if value != value or value in (float("inf"), float("-inf")):
        raise SystemExit(f"Nonfinite statistic {metric}")
    if value.is_integer():
        return int(value)
    return value


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


if __name__ == "__main__":
    main()
