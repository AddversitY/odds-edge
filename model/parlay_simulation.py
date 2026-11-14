"""Prior-season Gaussian-copula validation. No odds request or key.

The predeclared exercise pairs the QB with the leading prior-season target
receiver on each side, uses prior-season median half-lines and record-shrunk
marginals. It validates dependence, not live usage forecasts or profitability.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np
from scipy.integrate import quad
from scipy.special import ndtr, ndtri
from scipy.stats import rankdata

ROOT = Path(__file__).resolve().parents[1]
PRIOR = 40
CAP = 0.65
MIN_PAIRS = 12
FEATURES = ["margin", "total", "home_pass", "home_rush", "away_pass", "away_rush"]


def team(value):
    return {"LA": "LAR", "OAK": "LV", "SD": "LAC", "STL": "LAR"}.get(value, value)


def game_key(row):
    return (row["date"][:10], *sorted([team(row.get("home", row.get("team"))), team(row.get("away", row.get("opponent")))]))


def fit_matrix(rows):
    values = np.asarray(rows, dtype=float)
    size = values.shape[1]
    normal = np.full(values.shape, np.nan)
    for c in range(size):
        valid = np.isfinite(values[:, c])
        n = valid.sum()
        if n:
            normal[valid, c] = ndtri((rankdata(values[valid, c], method="average") - 0.5) / n)
    matrix = np.eye(size)
    counts = np.zeros((size, size), dtype=int)
    for i in range(size):
        for j in range(i):
            valid = np.isfinite(normal[:, i]) & np.isfinite(normal[:, j])
            n = int(valid.sum())
            counts[i, j] = counts[j, i] = n
            if n < MIN_PAIRS:
                continue
            x, y = normal[valid, i], normal[valid, j]
            if np.var(x) < 1e-10 or np.var(y) < 1e-10:
                continue
            rho = np.clip(np.corrcoef(x, y)[0, 1] * n / (n + PRIOR), -CAP, CAP)
            matrix[i, j] = matrix[j, i] = rho
    scale = 1.0
    while True:
        try:
            lower = np.linalg.cholesky(matrix)
            if np.min(np.diag(lower) ** 2) < 1e-8:
                raise np.linalg.LinAlgError()
            return matrix, counts, scale
        except np.linalg.LinAlgError:
            matrix = np.eye(size) + (matrix - np.eye(size)) * 0.8
            scale *= 0.8


def training_rows(players, games, selected, event_home, before_season):
    by_game = {}
    for row in players:
        if row["season"] < before_season and row["seasonType"] == "REG":
            by_game.setdefault(game_key(row), []).append(row)
    selected = sorted(selected, key=lambda s: s["id"] + ":" + s["metric"])
    result = []
    for game in games:
        if game["season"] >= before_season:
            continue
        rows = by_game.get(game_key(game))
        if not rows:
            continue
        home, away = team(game["home"]), team(game["away"])
        margin = game["homeScore"] - game["awayScore"]
        for leg in selected:
            anchor = [r for r in rows if r["playerId"] == leg["id"]]
            if len(anchor) != 1:
                continue
            if (team(leg["team"]) == team(event_home)) != (team(anchor[0]["team"]) == home):
                home, away, margin = away, home, -margin
            break
        def total(club, metric):
            observed = [r["stats"][metric] for r in rows if team(r["team"]) == club and r["stats"].get(metric) is not None]
            return sum(observed) if observed else np.nan
        vector = [margin, game["homeScore"] + game["awayScore"], total(home, "passing_yards"), total(home, "rushing_yards"), total(away, "passing_yards"), total(away, "rushing_yards")]
        for leg in selected:
            club = home if team(leg["team"]) == team(event_home) else away
            matched = [r for r in rows if r["playerId"] == leg["id"] and team(r["team"]) == club]
            stat = matched[0]["stats"].get(leg["metric"]) if len(matched) == 1 else None
            vector.append(np.nan if stat is None else stat)
        result.append(vector)
    return result


def joint_over(p1, p2, rho):
    a, b = ndtri(1-p1), ndtri(1-p2)
    density = lambda x: math.exp(-x*x/2) / math.sqrt(2*math.pi) * ndtr((rho*x-b)/math.sqrt(1-rho*rho))
    return float(quad(density, a, 10, epsabs=1e-10)[0])


def scores(rows, field):
    if not rows:
        return {"count": 0, "brier": None, "logLoss": None}
    chances = np.clip([r[field] for r in rows], 1e-9, 1-1e-9)
    actual = np.array([r["hit"] for r in rows], dtype=float)
    return {"count": len(rows), "brier": float(np.mean((chances-actual)**2)),
            "logLoss": float(-np.mean(actual*np.log(chances)+(1-actual)*np.log(1-chances)))}


def build_report(players, games):
    episodes = {}
    histories = {}
    for row in players:
        if row["seasonType"] != "REG":
            continue
        episodes.setdefault(game_key(row), []).append(row)
        histories.setdefault((row["season"], row["playerId"]), []).append(row)
    forecasts, dropped, cache = [], 0, {}
    for game in sorted(games, key=lambda g: (g["season"], g["week"], g["date"])):
        season = game["season"]
        current = episodes.get(game_key(game), [])
        for club in [team(game["home"]), team(game["away"])]:
            candidates = [r for r in current if team(r["team"]) == club and (season-1, r["playerId"]) in histories]
            def volume(row, metric):
                return sum(r["stats"].get(metric) or 0 for r in histories[season-1, row["playerId"]])
            qbs = sorted([r for r in candidates if r["position"] == "QB" and volume(r, "attempts") >= 40], key=lambda r: (-volume(r, "attempts"), r["playerId"]))
            receivers = sorted([r for r in candidates if r["position"] in ["WR", "TE", "RB"] and volume(r, "targets") >= 20], key=lambda r: (-volume(r, "targets"), r["playerId"]))
            if not qbs or not receivers:
                dropped += 1
                continue
            selected, chances, hits = [], [], []
            for row, metric in [(qbs[0], "passing_yards"), (receivers[0], "receiving_yards")]:
                earlier = [r["stats"][metric] for r in histories[season-1, row["playerId"]] if r["stats"].get(metric) is not None]
                if len(earlier) < 8 or row["stats"].get(metric) is None:
                    break
                line = math.floor(float(np.median(earlier))) + 0.5
                chances.append((sum(v > line for v in earlier)+16)/(len(earlier)+32))
                hits.append(row["stats"][metric] > line)
                selected.append({"id": row["playerId"], "metric": metric, "team": club})
            if len(selected) != 2:
                dropped += 1
                continue
            key = (season, team(game["home"]) == club, *(s["id"] for s in selected))
            if key not in cache:
                training = training_rows(players, games, selected, game["home"], season)
                cache[key] = fit_matrix(training) if training else (np.eye(8), np.zeros((8,8)), 1)
            matrix, counts, scale = cache[key]
            forecasts.append({"season": season, "event": "|".join(game_key(game)), "hit": all(hits),
                "joint": joint_over(*chances, matrix[6,7]), "independent": chances[0]*chances[1],
                "paired": int(counts[6,7]), "psdScale": scale})
    unique_games = len({r["event"] for r in forecasts})
    joint, independent = scores(forecasts, "joint"), scores(forecasts, "independent")
    adopted = bool(unique_games >= 1000 and forecasts and joint["brier"] < independent["brier"] and joint["logLoss"] < independent["logLoss"])
    return {"schema": 1, "exercise": "Prior-season QB plus leading target receiver; previous-season median half-lines; record marginals with 32-game fair-50% prior.",
        "method": "Rank-normal Gaussian copula; n/(n+40) shrink, 0.65 cap, 12-pair minimum, PSD repair. Two-leg validation integrates the fitted copula analytically; live simulation uses 10,000 seeded draws.",
        "scope": "Dependence-layer test only, conditional on participants with recorded box scores. Not validation of live usage marginals or sportsbook profitability.",
        "correlated": joint, "independent": independent, "uniqueGames": unique_games,
        "adopted": adopted, "hasEdge": False, "omitted": dropped,
        "minimumEarlierPairedGames": min((r["paired"] for r in forecasts), default=0),
        "seasons": [{"season": y, "trainedThrough": y-1, "correlated": scores([r for r in forecasts if r["season"] == y], "joint"), "independent": scores([r for r in forecasts if r["season"] == y], "independent")} for y in sorted({r["season"] for r in forecasts})],
        "calibration": [{"from": lo, "to": lo+.1, "count": len(part), "meanChance": sum(r["joint"] for r in part)/len(part) if part else None, "observed": sum(r["hit"] for r in part)/len(part) if part else None} for lo in [0,.1,.2,.3,.4,.5,.6,.7,.8,.9] for part in [[r for r in forecasts if lo <= r["joint"] < lo+.1]]],
        "sources": ["nflverse bundled player box scores", "nflverse bundled final scores"], "creditsUsed": 0}


def main():
    player_path, game_path = ROOT/"assets/nfl-player-stats.json", ROOT/"assets/nfl-history.json"
    raw = json.loads(player_path.read_text(encoding="utf-8-sig"))
    players = [dict(r, stats=dict(zip(raw["statKeys"], r["stats"]))) for r in raw["rows"]]
    games = json.loads(game_path.read_text(encoding="utf-8-sig"))["games"]
    report = build_report(players, games)
    report["dataCutoff"] = raw.get("cutoff")
    report["sourceHashes"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [player_path, game_path]}
    (ROOT/"assets/parlay-calibration.json").write_text(json.dumps(report, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    print(json.dumps({k:report[k] for k in ["correlated","independent","uniqueGames","adopted"]}))


if __name__ == "__main__":
    main()
