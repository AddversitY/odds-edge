"""Turn cached nflverse files into the rows version 2 trains on.

No Odds API call. Weather comes from model/weather.py.
"""

from __future__ import annotations

import sys
from datetime import date
from pathlib import Path

import pandas as pd
import pyarrow.parquet as pq

from nfl_model import canon_team, nflverse_home_spread
from nfl_model_v2 import (
    GameContext,
    OutAppearance,
    QbAppearance,
    SnapAppearance,
    no_vig_probability,
)
from weather import forecast_games, historical_weather, open_roof

FIRST_SEASON = 2014


def _clock(value) -> tuple[int, int]:
    text = str(value or "").strip()
    if ":" not in text:
        return 13, 0
    hour, minute = text.split(":", 1)
    try:
        return int(hour), int(minute[:2])
    except ValueError:
        return 13, 0


def _finite(value) -> float | None:
    try:
        if value is None or pd.isna(value):
            return None
    except TypeError:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number != number:
        return None
    return number


def load_quarterbacks(cache: Path, seasons: list[int]) -> list[QbAppearance]:
    rows: list[QbAppearance] = []
    columns = [
        "game_id",
        "season",
        "week",
        "season_type",
        "posteam",
        "passer_player_id",
        "passer_player_name",
        "qb_dropback",
        "epa",
    ]
    for season in seasons:
        path = cache / f"play_by_play_{season}.parquet"
        if not path.exists():
            continue
        print(f"Reading quarterback dropbacks {season}", flush=True)
        schema = set(pq.read_schema(path).names)
        use = [name for name in columns if name in schema]
        if "passer_player_id" not in use or "epa" not in use or "qb_dropback" not in use:
            continue
        frame = pq.read_table(path, columns=use).to_pandas()
        if "season_type" in frame.columns:
            frame = frame[frame["season_type"].isin(["REG", "POST"])]
        frame = frame[frame["qb_dropback"].fillna(0).astype(float) == 1]
        frame = frame[frame["epa"].notna() & frame["posteam"].notna() & frame["passer_player_id"].notna()]
        frame["team"] = frame["posteam"].map(canon_team)
        frame["player_id"] = frame["passer_player_id"].astype(str)
        frame = frame[frame["player_id"].str.len() > 0]
        if "passer_player_name" not in frame.columns:
            frame["passer_player_name"] = ""
        grouped = frame.groupby(["season", "week", "team", "player_id"], as_index=False).agg(
            dropbacks=("epa", "size"),
            epa_sum=("epa", "sum"),
            name=("passer_player_name", "first"),
        )
        for row in grouped.itertuples(index=False):
            rows.append(
                QbAppearance(
                    season=int(row.season),
                    week=int(row.week),
                    team=str(row.team),
                    player_id=str(row.player_id),
                    name=str(row.name or ""),
                    dropbacks=float(row.dropbacks),
                    epa_sum=float(row.epa_sum),
                )
            )
        del frame
    return rows


def load_snaps(cache: Path, seasons: list[int]) -> list[SnapAppearance]:
    rows: list[SnapAppearance] = []
    for season in seasons:
        path = cache / f"snap_counts_{season}.csv"
        if not path.exists():
            continue
        frame = pd.read_csv(path, low_memory=False)
        if "player" not in frame.columns or "team" not in frame.columns:
            continue
        for row in frame.itertuples(index=False):
            offense = _finite(getattr(row, "offense_pct", None)) or 0.0
            defense = _finite(getattr(row, "defense_pct", None)) or 0.0
            share = max(offense, defense)
            if share > 1.5:
                share = share / 100.0
            if share <= 0:
                continue
            rows.append(
                SnapAppearance(
                    season=int(row.season),
                    week=int(row.week),
                    team=canon_team(str(row.team)),
                    name=str(row.player),
                    position=str(getattr(row, "position", "") or ""),
                    snap_share=share,
                )
            )
    return rows


def load_outs(cache: Path, seasons: list[int]) -> list[OutAppearance]:
    rows: list[OutAppearance] = []
    for season in seasons:
        path = cache / f"injuries_{season}.csv"
        if not path.exists():
            continue
        frame = pd.read_csv(path, low_memory=False)
        if "report_status" not in frame.columns or "full_name" not in frame.columns:
            continue
        status = frame["report_status"].fillna("").astype(str).str.strip().str.lower()
        frame = frame[status.isin(["out", "doubtful"])]
        for row in frame.itertuples(index=False):
            name = str(getattr(row, "full_name", "") or "").strip()
            if not name:
                continue
            rows.append(
                OutAppearance(
                    season=int(row.season),
                    week=int(row.week),
                    team=canon_team(str(row.team)),
                    name=name,
                    position=str(getattr(row, "position", "") or ""),
                )
            )
    return rows


def _lookup(schedule: pd.DataFrame) -> dict[str, dict]:
    extra = {}
    for row in schedule.itertuples(index=False):
        if int(row.season) < FIRST_SEASON:
            continue
        hour, minute = _clock(getattr(row, "gametime", None))
        played = row.played_on if isinstance(row.played_on, date) else pd.Timestamp(row.gameday).date()
        home_odds = _finite(getattr(row, "home_spread_odds", None))
        away_odds = _finite(getattr(row, "away_spread_odds", None))
        over_odds = _finite(getattr(row, "over_odds", None))
        under_odds = _finite(getattr(row, "under_odds", None))
        cover = None
        over = None
        if home_odds is not None and away_odds is not None:
            cover = no_vig_probability(home_odds, away_odds)
        if over_odds is not None and under_odds is not None:
            over = no_vig_probability(over_odds, under_odds)
        extra[str(row.game_id)] = {
            "home_qb_id": "" if pd.isna(getattr(row, "home_qb_id", None)) else str(row.home_qb_id),
            "away_qb_id": "" if pd.isna(getattr(row, "away_qb_id", None)) else str(row.away_qb_id),
            "home_qb_name": "" if pd.isna(getattr(row, "home_qb_name", None)) else str(row.home_qb_name),
            "away_qb_name": "" if pd.isna(getattr(row, "away_qb_name", None)) else str(row.away_qb_name),
            "roof": "" if pd.isna(getattr(row, "roof", None)) else str(row.roof),
            "stadium": "" if pd.isna(getattr(row, "stadium", None)) else str(row.stadium),
            "temp": _finite(getattr(row, "temp", None)),
            "wind": _finite(getattr(row, "wind", None)),
            "date": played,
            "hour": hour,
            "minute": minute,
            "cover": 0.5 if cover is None else cover,
            "over": 0.5 if over is None else over,
            "home": canon_team(str(row.home_team)),
            "away": canon_team(str(row.away_team)),
            "week": int(row.week),
            "season": int(row.season),
            "game_type": str(row.game_type),
            "home_score": _finite(getattr(row, "home_score", None)),
        }
    return extra


def contexts_for(schedule_games, extra: dict[str, dict], weather: dict) -> list[GameContext]:
    rows = []
    for game in schedule_games:
        info = extra.get(game.game_id)
        if info is None or game.spread_line is None:
            continue
        reading = weather.get(game.game_id)
        wind = info["wind"]
        temp = info["temp"]
        precip = None
        if reading is not None and reading.source != "missing":
            wind = reading.wind if reading.wind is not None else wind
            temp = reading.temp_f if reading.temp_f is not None else temp
            precip = reading.precip
        rows.append(
            GameContext(
                season=game.season,
                week=game.week,
                game_id=game.game_id,
                home=game.home,
                away=game.away,
                regular=game.regular,
                margin=None
                if game.home_score is None or game.away_score is None
                else float(game.home_score - game.away_score),
                total_points=None
                if game.home_score is None or game.away_score is None
                else float(game.home_score + game.away_score),
                market_margin=-float(game.spread_line),
                market_total=None if game.total_line is None else float(game.total_line),
                market_cover=float(info["cover"]),
                market_over=float(info["over"]),
                home_qb_id=info["home_qb_id"],
                away_qb_id=info["away_qb_id"],
                home_qb_name=info["home_qb_name"],
                away_qb_name=info["away_qb_name"],
                home_rest=float(game.home_rest),
                away_rest=float(game.away_rest),
                open_roof=open_roof(info["roof"]),
                wind=wind,
                temp_f=temp,
                precip=precip,
                game_lon=None,
            )
        )
    return rows


def attach_longitudes(contexts: list[GameContext], extra: dict[str, dict], cache: Path) -> list[GameContext]:
    from weather import stadium_point

    points: dict[str, float] = {}
    for info in extra.values():
        if info["stadium"] in points or not info["stadium"]:
            continue
        found = stadium_point(info["stadium"], cache)
        if found is not None:
            points[info["stadium"]] = found[1]
    updated = []
    for game in contexts:
        info = extra.get(game.game_id) or {}
        lon = points.get(info.get("stadium") or "")
        updated.append(
            GameContext(
                season=game.season,
                week=game.week,
                game_id=game.game_id,
                home=game.home,
                away=game.away,
                regular=game.regular,
                margin=game.margin,
                total_points=game.total_points,
                market_margin=game.market_margin,
                market_total=game.market_total,
                market_cover=game.market_cover,
                market_over=game.market_over,
                home_qb_id=game.home_qb_id,
                away_qb_id=game.away_qb_id,
                home_qb_name=game.home_qb_name,
                away_qb_name=game.away_qb_name,
                home_rest=game.home_rest,
                away_rest=game.away_rest,
                open_roof=game.open_roof,
                wind=game.wind,
                temp_f=game.temp_f,
                precip=game.precip,
                game_lon=lon,
            )
        )
    return updated


def weather_rows(extra: dict[str, dict], kept: set[str]) -> list[dict]:
    rows = []
    for game_id, info in extra.items():
        if game_id not in kept:
            continue
        rows.append(
            {
                "id": game_id,
                "stadium": info["stadium"],
                "roof": info["roof"],
                "date": info["date"],
                "hour": info["hour"],
                "temp": info["temp"],
                "wind": info["wind"],
            }
        )
    return rows


def upcoming_forecasts(extra: dict[str, dict], cache: Path) -> list[dict]:
    future = [
        info
        for info in extra.values()
        if info["home_score"] is None and info["game_type"] == "REG" and info["season"] >= FIRST_SEASON
    ]
    if not future:
        return []
    season = min(info["season"] for info in future)
    week = min(info["week"] for info in future if info["season"] == season)
    slate = [info for info in future if info["season"] == season and info["week"] == week]
    # The sample board also shows Arrowhead. Fetch it when the Chiefs are not at home.
    homes = {info["home"] for info in slate}
    sunday = next((info["date"] for info in slate if info["date"].weekday() == 6), slate[0]["date"])
    if "KC" not in homes:
        slate.append(
            {
                "home": "KC",
                "away": "BUF",
                "stadium": "GEHA Field at Arrowhead Stadium",
                "roof": "outdoors",
                "date": sunday,
                "hour": 13,
                "minute": 0,
            }
        )
    games = []
    for info in slate:
        games.append(
            {
                "home": info["home"],
                "away": info["away"],
                "stadium": info["stadium"],
                "roof": info["roof"],
                "date": info["date"],
                "hour": info["hour"],
                "minute": info.get("minute") or 0,
            }
        )
    print(f"Forecasts for {len(games)} stadiums", flush=True)
    try:
        return forecast_games(games, cache)
    except Exception as error:  # noqa: BLE001 — a forecast miss must not sink the backtest
        print(f"Forecasts were not available: {error}", file=sys.stderr)
        return []


def weather_counts(weather: dict) -> dict[str, int]:
    counts = {"open-meteo-archive": 0, "nflverse-fallback": 0, "missing": 0}
    for reading in weather.values():
        counts[reading.source] = counts.get(reading.source, 0) + 1
    return counts
