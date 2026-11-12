"""Download free nflverse files, fit the Coach's Line, and write JSON.

No Odds API key and no Odds API request. Closing spreads and totals come
from the nflverse schedule file. Play-by-play supplies EPA, success rate,
turnover rate, and explosive-play rate. Injury reports, when the file is
there, are only a count of players listed Out.

Run from the repository root:

    python model/train.py
"""

from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

import pandas as pd
import pyarrow.parquet as pq

from nfl_model import (
    HALF_LIFE_DAYS,
    LOGISTIC_C,
    MIN_EXPECTED_VALUE,
    PRIOR_PLAYS,
    SPREAD_EDGE_POINTS,
    TEAM_NAMES,
    TOTAL_EDGE_POINTS,
    OffenseLine,
    ScheduleGame,
    TeamGame,
    build_rated_games,
    canon_team,
    current_ratings,
    nflverse_home_spread,
    plain_english,
    walk_forward,
)

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path(__file__).resolve().parent / ".cache"
OUTPUT = ROOT / "assets" / "nfl-model.json"
FIRST_SEASON = 2014
USER_AGENT = "odds-edge-coach-model"


def download(url: str, dest: Path) -> bool:
    if dest.exists() and dest.stat().st_size > 0:
        return True
    dest.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    temporary = dest.with_suffix(dest.suffix + ".part")
    try:
        with urllib.request.urlopen(request, timeout=180) as response, temporary.open("wb") as handle:
            while True:
                chunk = response.read(1024 * 256)
                if not chunk:
                    break
                handle.write(chunk)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            if temporary.exists():
                temporary.unlink()
            return False
        raise
    temporary.replace(dest)
    return True


def _number(value) -> float | None:
    if value is None or (isinstance(value, float) and pd.isna(value)):
        return None
    text = str(value).strip()
    if text == "" or text.lower() == "nan":
        return None
    return float(text)


def load_schedule() -> pd.DataFrame:
    path = CACHE / "games.csv"
    download(
        "https://github.com/nflverse/nflverse-data/releases/download/schedules/games.csv",
        path,
    )
    frame = pd.read_csv(path, low_memory=False)
    frame["season"] = frame["season"].astype(int)
    frame["week"] = frame["week"].astype(int)
    frame["home"] = frame["home_team"].map(canon_team)
    frame["away"] = frame["away_team"].map(canon_team)
    frame["played_on"] = pd.to_datetime(frame["gameday"]).dt.date
    return frame


def load_offense(seasons: list[int]) -> pd.DataFrame:
    frames = []
    columns = [
        "game_id",
        "season",
        "week",
        "season_type",
        "play_type",
        "posteam",
        "epa",
        "success",
        "yards_gained",
        "interception",
        "fumble_lost",
        "qb_kneel",
        "qb_spike",
    ]
    for season in seasons:
        path = CACHE / f"play_by_play_{season}.parquet"
        url = (
            "https://github.com/nflverse/nflverse-data/releases/download/pbp/"
            f"play_by_play_{season}.parquet"
        )
        if not download(url, path):
            print(f"No play-by-play for {season}", file=sys.stderr)
            continue
        print(f"Reading play-by-play {season}", flush=True)
        schema = set(pq.read_schema(path).names)
        use = [name for name in columns if name in schema]
        table = pq.read_table(path, columns=use)
        frame = table.to_pandas()
        del table
        if "season_type" in frame.columns:
            frame = frame[frame["season_type"].isin(["REG", "POST"])]
        frame = frame[frame["play_type"].isin(["pass", "run"])]
        frame = frame[frame["epa"].notna() & frame["posteam"].notna()]
        frame = frame[frame["posteam"].astype(str).str.len() > 0]
        if "qb_kneel" in frame.columns:
            frame = frame[frame["qb_kneel"].fillna(0).astype(float) == 0]
        if "qb_spike" in frame.columns:
            frame = frame[frame["qb_spike"].fillna(0).astype(float) == 0]
        frame["team"] = frame["posteam"].map(canon_team)
        frame["explosive"] = (frame["yards_gained"].fillna(0).astype(float) >= 20).astype(float)
        turnover = frame["interception"].fillna(0).astype(float).eq(1)
        if "fumble_lost" in frame.columns:
            turnover = turnover | frame["fumble_lost"].fillna(0).astype(float).eq(1)
        frame["turnover"] = turnover.astype(float)
        frame["success"] = frame["success"].fillna(0).astype(float)
        grouped = frame.groupby(["game_id", "team"], as_index=False).agg(
            plays=("epa", "size"),
            epa_sum=("epa", "sum"),
            success_sum=("success", "sum"),
            explosive_sum=("explosive", "sum"),
            turnover_sum=("turnover", "sum"),
        )
        frames.append(grouped)
        del frame
    if not frames:
        raise SystemExit("No play-by-play files could be read.")
    return pd.concat(frames, ignore_index=True)


def load_outs(seasons: list[int]) -> pd.DataFrame:
    frames = []
    for season in seasons:
        path = CACHE / f"injuries_{season}.csv"
        url = (
            "https://github.com/nflverse/nflverse-data/releases/download/injuries/"
            f"injuries_{season}.csv"
        )
        if not download(url, path):
            continue
        frame = pd.read_csv(path, low_memory=False)
        if "report_status" not in frame.columns or "team" not in frame.columns:
            continue
        status = frame["report_status"].fillna("").astype(str).str.strip().str.lower()
        frame = frame[status.eq("out")].copy()
        if frame.empty:
            continue
        frame["team"] = frame["team"].map(canon_team)
        frame["season"] = frame["season"].astype(int)
        frame["week"] = frame["week"].astype(int)
        if "game_type" not in frame.columns:
            frame["game_type"] = "REG"
        player = frame["gsis_id"] if "gsis_id" in frame.columns else frame.get("full_name")
        if player is None:
            frame["player"] = frame.index.astype(str)
        else:
            frame["player"] = player.astype(str)
        counts = (
            frame.groupby(["season", "week", "team", "game_type"], as_index=False)["player"]
            .nunique()
            .rename(columns={"player": "players_out"})
        )
        frames.append(counts)
    if not frames:
        return pd.DataFrame(columns=["season", "week", "team", "game_type", "players_out"])
    return pd.concat(frames, ignore_index=True)


def _rest(value) -> float:
    number = _number(value)
    # A blank rest day is treated as a normal week. Week 1 is usually filled in.
    return 7.0 if number is None else number


def assemble(schedule: pd.DataFrame, offense: pd.DataFrame, outs: pd.DataFrame):
    offense = offense[offense["plays"] >= 10]
    rates = {}
    for row in offense.itertuples(index=False):
        plays = int(row.plays)
        rates[(row.game_id, row.team)] = OffenseLine(
            plays=plays,
            epa=float(row.epa_sum) / plays,
            success=float(row.success_sum) / plays,
            explosive=float(row.explosive_sum) / plays,
            turnover=float(row.turnover_sum) / plays,
        )
    out_lookup = {}
    for row in outs.itertuples(index=False):
        out_lookup[(int(row.season), int(row.week), row.team, str(row.game_type))] = float(
            row.players_out
        )
    kept = schedule[schedule["season"] >= FIRST_SEASON].copy()
    kept = kept[kept["game_type"].isin(["REG", "WC", "DIV", "CON", "SB"])]
    team_games: list[TeamGame] = []
    games: list[ScheduleGame] = []
    for row in kept.itertuples(index=False):
        home_off = rates.get((row.game_id, row.home))
        away_off = rates.get((row.game_id, row.away))
        if home_off is None or away_off is None:
            continue
        kind = "REG" if row.game_type == "REG" else str(row.game_type)
        home_out = out_lookup.get((int(row.season), int(row.week), row.home, kind), 0.0)
        away_out = out_lookup.get((int(row.season), int(row.week), row.away, kind), 0.0)
        if kind != "REG":
            # Playoff reports use the playoff label when it exists, otherwise 0.
            home_out = out_lookup.get(
                (int(row.season), int(row.week), row.home, kind),
                out_lookup.get((int(row.season), int(row.week), row.home, "POST"), 0.0),
            )
            away_out = out_lookup.get(
                (int(row.season), int(row.week), row.away, kind),
                out_lookup.get((int(row.season), int(row.week), row.away, "POST"), 0.0),
            )
        home_score = _number(row.home_score)
        away_score = _number(row.away_score)
        raw_spread = _number(row.spread_line)
        played_on = row.played_on
        if not isinstance(played_on, date):
            played_on = pd.Timestamp(played_on).date()
        game = ScheduleGame(
            season=int(row.season),
            week=int(row.week),
            played_on=played_on,
            game_id=str(row.game_id),
            home=row.home,
            away=row.away,
            home_score=home_score,
            away_score=away_score,
            spread_line=None if raw_spread is None else nflverse_home_spread(raw_spread),
            total_line=_number(row.total_line),
            home_rest=_rest(row.home_rest),
            away_rest=_rest(row.away_rest),
            regular=row.game_type == "REG",
            home_out=home_out,
            away_out=away_out,
        )
        if home_score is None or away_score is None:
            continue
        games.append(game)
        team_games.append(
            TeamGame(
                season=game.season,
                week=game.week,
                played_on=played_on,
                game_id=game.game_id,
                team=game.home,
                off=home_off,
                defense=away_off,
            )
        )
        team_games.append(
            TeamGame(
                season=game.season,
                week=game.week,
                played_on=played_on,
                game_id=game.game_id,
                team=game.away,
                off=away_off,
                defense=home_off,
            )
        )
    return team_games, games


def _round(value: float, places: int = 6) -> float:
    return float(round(float(value), places))


def _fit_json(fit) -> dict | None:
    if fit is None:
        return None
    return {
        "features": list(fit.names),
        "mean": [_round(value) for value in fit.mean],
        "scale": [_round(value) for value in fit.scale],
        "coefficients": [_round(value) for value in fit.coefficients],
        "intercept": _round(fit.intercept),
    }


def _score_json(score) -> dict:
    return {
        "games": score.games,
        "decided": score.decided,
        "wins": score.wins,
        "losses": score.losses,
        "pushes": score.pushes,
        "hitRate": None if score.hit_rate is None else _round(score.hit_rate),
        "roi": None if score.roi is None else _round(score.roi),
    }


def upcoming_outs(schedule: pd.DataFrame, outs: pd.DataFrame) -> dict[str, float]:
    future = schedule[
        (schedule["season"] >= FIRST_SEASON)
        & (schedule["home_score"].isna())
        & (schedule["game_type"] == "REG")
    ]
    if future.empty or outs.empty:
        return {}
    season = int(future["season"].min())
    week = int(future.loc[future["season"] == season, "week"].min())
    slate = outs[(outs["season"] == season) & (outs["week"] == week) & (outs["game_type"] == "REG")]
    return {row.team: float(row.players_out) for row in slate.itertuples(index=False)}


def build_document(team_games, schedule_frame, outs, result, as_of: date) -> dict:
    ratings = current_ratings(team_games, as_of)
    out_counts = upcoming_outs(schedule_frame, outs)
    league_off = sum(rating.off_epa for rating in ratings.values()) / len(ratings)
    league_def = sum(rating.def_epa for rating in ratings.values()) / len(ratings)
    teams = []
    for abbreviation, rating in ratings.items():
        name = TEAM_NAMES.get(abbreviation)
        if name is None:
            continue
        offense_points = result.final_margin_scale * (rating.off_epa - league_off)
        defense_points = result.final_margin_scale * (league_def - rating.def_epa)
        teams.append(
            {
                "abbr": abbreviation,
                "name": name,
                "offEpa": _round(rating.off_epa),
                "defEpa": _round(rating.def_epa),
                "netEpa": _round(rating.net_epa),
                "strengthPoints": _round(result.final_margin_scale * rating.net_epa),
                "offensePoints": _round(offense_points),
                "defensePoints": _round(defense_points),
                "successRate": _round(rating.success),
                "explosiveRate": _round(rating.explosive),
                "turnoverRate": _round(rating.turnover),
                "formEpa": _round(rating.form_epa),
                "playersOut": int(out_counts.get(abbreviation, 0)),
                "lastGame": None if rating.last_game is None else rating.last_game.isoformat(),
                "samplePlays": _round(rating.sample_plays, 1),
            }
        )
    teams.sort(key=lambda team: team["strengthPoints"], reverse=True)
    for rank, team in enumerate(teams, start=1):
        team["rank"] = rank
    has_edge, summary = plain_english(result)
    favorite_rate = (
        None
        if result.favorite_decided == 0
        else _round(result.favorite_wins / result.favorite_decided)
    )
    home_rate = (
        None if result.home_decided == 0 else _round(result.home_wins / result.home_decided)
    )
    played = [game.played_on for game in team_games]
    through = max(played).isoformat() if played else None
    return {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "source": {
            "name": "nflverse",
            "license": "CC BY 4.0",
            "url": "https://github.com/nflverse/nflverse-data",
            "licenseUrl": "https://creativecommons.org/licenses/by/4.0/",
            "licenseFile": "assets/NFLVERSE-LICENSE.md",
            "changes": (
                "Play-by-play was summed into team rates for each game. "
                "Those rates were turned into team strength and the Coach's Line. "
                "Odds Edge is not affiliated with nflverse."
            ),
        },
        "asOf": through,
        "settings": {
            "spreadEdgePoints": SPREAD_EDGE_POINTS,
            "totalEdgePoints": TOTAL_EDGE_POINTS,
            "minExpectedValue": MIN_EXPECTED_VALUE,
            "halfLifeDays": HALF_LIFE_DAYS,
            "priorPlays": PRIOR_PLAYS,
            "logisticC": LOGISTIC_C,
        },
        "projection": {
            "marginScale": _round(result.final_margin_scale),
            "homeFieldAdvantage": _round(result.final_home_field),
            "totalIntercept": _round(result.final_total_intercept),
            "totalScale": _round(result.final_total_scale),
            "leagueOffEpa": _round(league_off),
            "leagueDefEpa": _round(league_def),
        },
        "coverModel": _fit_json(result.final_cover),
        "totalModel": _fit_json(result.final_total),
        "teams": teams,
        "backtest": {
            "method": (
                "Walk-forward by week. Each week is scored by a model trained only on "
                "earlier weeks. Same-week games are not used. The split is not random."
            ),
            "seasons": result.seasons,
            "stake": "1.10 staked to win 1.00, the usual -110 price",
            "breakEvenHitRate": _round(110 / 210),
            "games": result.primary.games,
            "decided": result.primary.decided,
            "wins": result.primary.wins,
            "losses": result.primary.losses,
            "pushes": result.primary.pushes,
            "hitRate": None if result.primary.hit_rate is None else _round(result.primary.hit_rate),
            "roi": None if result.primary.roi is None else _round(result.primary.roi),
            "brier": None if result.brier is None else _round(result.brier),
            "calibration": [
                {
                    "from": _round(bin_["from"], 2),
                    "to": _round(bin_["to"], 2),
                    "games": int(bin_["games"]),
                    "predicted": _round(bin_["predicted"]),
                    "actual": _round(bin_["actual"]),
                }
                for bin_ in result.calibration
            ],
            "clvBeatRate": None if result.clv_beat_rate is None else _round(result.clv_beat_rate),
            "clvGames": result.clv_games,
            "meanModelError": None
            if result.mean_model_error is None
            else _round(result.mean_model_error),
            "meanMarketError": None
            if result.mean_market_error is None
            else _round(result.mean_market_error),
            "favoriteHitRate": favorite_rate,
            "homeHitRate": home_rate,
            "flagged": {
                **_score_json(result.flagged),
                "rule": (
                    f"Bet only when our number and the closing number differ by "
                    f"{SPREAD_EDGE_POINTS:.1f} points or more."
                ),
            },
            "totals": _score_json(result.overs),
            "hasEdge": has_edge,
            "plainEnglish": summary,
        },
    }


def validate(document: dict) -> None:
    backtest = document["backtest"]
    if backtest["decided"] < 500:
        raise SystemExit(f"Backtest scored only {backtest['decided']} games. The download looks short.")
    hit = backtest["hitRate"]
    if hit is None or hit < 0.35 or hit > 0.65:
        raise SystemExit(
            f"ATS hit rate {hit} is outside 35–65%. That usually means a sign error, not a real result."
        )
    favorite = backtest.get("favoriteHitRate")
    if favorite is None or favorite < 0.45 or favorite > 0.55:
        raise SystemExit(
            f"Favorites covered {favorite} of games. A real closing line is near one half. "
            "The spread sign is probably backwards."
        )
    if len(document["teams"]) != 32:
        raise SystemExit(f"Expected 32 teams, found {len(document['teams'])}.")
    if document["coverModel"] is None or document["totalModel"] is None:
        raise SystemExit("The logistic models did not fit.")
    home_field = document["projection"]["homeFieldAdvantage"]
    print(f"Home field advantage fit at {home_field:.2f} points.")


def main() -> None:
    schedule = load_schedule()
    latest = int(schedule["season"].max())
    seasons = list(range(FIRST_SEASON, latest + 1))
    print(f"Seasons {seasons[0]}–{seasons[-1]}", flush=True)
    offense = load_offense(seasons)
    outs = load_outs(seasons)
    team_games, games = assemble(schedule, offense, outs)
    print(f"Completed games with play-by-play: {len(games)}", flush=True)
    rated = build_rated_games(team_games, games)
    print(f"Rated games: {len(rated)}. Walking forward...", flush=True)
    result = walk_forward(rated)
    document = build_document(team_games, schedule, outs, result, date.today())
    validate(document)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    backtest = document["backtest"]
    print("Wrote", OUTPUT)
    print("Seasons", backtest["seasons"])
    print(
        "Games",
        backtest["games"],
        "decided",
        backtest["decided"],
        "hit",
        backtest["hitRate"],
        "roi",
        backtest["roi"],
        "clv",
        backtest["clvBeatRate"],
        "edge",
        backtest["hasEdge"],
    )
    print(backtest["plainEnglish"])


if __name__ == "__main__":
    main()
