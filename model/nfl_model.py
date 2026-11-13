"""Power ratings, logistic probabilities, and walk-forward scoring.

The formulas here are the ones the Dart app reimplements. A change to a
feature name, the decay, or the stake math has to be mirrored in
lib/domain/coach_model.dart and covered by model/test_model.py.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Iterable, Sequence

import numpy as np
from sklearn.linear_model import LogisticRegression

# Six-week half life. A game 42 days ago counts half as much as a game today.
HALF_LIFE_DAYS = 42.0
# Fake plays of league-average football so a short sample cannot swing a rating.
PRIOR_PLAYS = 200.0
# Pre-set before any backtest. Not searched.
SPREAD_EDGE_POINTS = 2.5
TOTAL_EDGE_POINTS = 2.5
MIN_EXPECTED_VALUE = 0.02
LOGISTIC_C = 1.0
# Stake 1.10 to win 1.00, the usual -110 price. Profit on a win is +1.00.
MINUS_110_STAKE = 1.1
MINUS_110_WIN = 1.0
# A -110 bet breaks even at 110/210.
BREAK_EVEN_RATE = 110.0 / 210.0

COVER_FEATURES = (
    "spread_edge",
    "off_diff",
    "def_diff",
    "form_diff",
    "rest_diff",
    "success_diff",
    "explosive_diff",
    "turnover_diff",
    "out_diff",
)
TOTAL_FEATURES = (
    "total_edge",
    "off_sum",
    "def_sum",
    "explosive_sum",
    "success_sum",
    "rest_sum",
    "out_sum",
)

# Historical nflverse abbreviations mapped onto the 32 clubs the app uses.
TEAM_ALIASES = {
    "LA": "LAR",
    "STL": "LAR",
    "OAK": "LV",
    "SD": "LAC",
    "JAC": "JAX",
    "WSH": "WAS",
    "ARZ": "ARI",
}

TEAM_NAMES = {
    "ARI": "Arizona Cardinals",
    "ATL": "Atlanta Falcons",
    "BAL": "Baltimore Ravens",
    "BUF": "Buffalo Bills",
    "CAR": "Carolina Panthers",
    "CHI": "Chicago Bears",
    "CIN": "Cincinnati Bengals",
    "CLE": "Cleveland Browns",
    "DAL": "Dallas Cowboys",
    "DEN": "Denver Broncos",
    "DET": "Detroit Lions",
    "GB": "Green Bay Packers",
    "HOU": "Houston Texans",
    "IND": "Indianapolis Colts",
    "JAX": "Jacksonville Jaguars",
    "KC": "Kansas City Chiefs",
    "LV": "Las Vegas Raiders",
    "LAC": "Los Angeles Chargers",
    "LAR": "Los Angeles Rams",
    "MIA": "Miami Dolphins",
    "MIN": "Minnesota Vikings",
    "NE": "New England Patriots",
    "NO": "New Orleans Saints",
    "NYG": "New York Giants",
    "NYJ": "New York Jets",
    "PHI": "Philadelphia Eagles",
    "PIT": "Pittsburgh Steelers",
    "SF": "San Francisco 49ers",
    "SEA": "Seattle Seahawks",
    "TB": "Tampa Bay Buccaneers",
    "TEN": "Tennessee Titans",
    "WAS": "Washington Commanders",
}


def canon_team(abbreviation: str) -> str:
    raw = (abbreviation or "").strip().upper()
    return TEAM_ALIASES.get(raw, raw)


def decay_weight(days_ago: float, half_life_days: float = HALF_LIFE_DAYS) -> float:
    """How much a past game still counts. Newer games count more."""
    if days_ago < 0:
        raise ValueError("days_ago cannot be negative")
    if half_life_days <= 0:
        raise ValueError("half_life_days must be positive")
    return float(0.5 ** (days_ago / half_life_days))


def shrunk_average(
    samples: Iterable[tuple[float, float, float]],
    prior_value: float,
    prior_plays: float = PRIOR_PLAYS,
) -> float:
    """Play-weighted average with exponential decay and a league-average prior.

    Each sample is (rate, plays, days_ago).
    """
    if prior_plays <= 0:
        raise ValueError("prior_plays must be positive")
    numerator = prior_value * prior_plays
    denominator = prior_plays
    for rate, plays, days_ago in samples:
        if plays < 0:
            raise ValueError("plays cannot be negative")
        weight = plays * decay_weight(days_ago)
        numerator += rate * weight
        denominator += weight
    return float(numerator / denominator)


def ordinary_least_squares(x: Sequence[float], y: Sequence[float]) -> tuple[float, float]:
    """Return (slope, intercept) for y = slope * x + intercept."""
    xs = np.asarray(x, dtype=float)
    ys = np.asarray(y, dtype=float)
    if xs.shape != ys.shape or xs.size < 2:
        raise ValueError("OLS needs two equal-length columns with at least two rows")
    if not np.isfinite(xs).all() or not np.isfinite(ys).all():
        raise ValueError("OLS inputs must be finite")
    x_mean = float(xs.mean())
    y_mean = float(ys.mean())
    variance = float(((xs - x_mean) ** 2).sum())
    if variance < 1e-12:
        return 0.0, y_mean
    slope = float(((xs - x_mean) * (ys - y_mean)).sum() / variance)
    return slope, y_mean - slope * x_mean


def is_before(season: int, week: int, test_season: int, test_week: int) -> bool:
    """True when a game is strictly earlier than the week being scored.

    Same-week games stay out. Thursday does not train Sunday.
    """
    return (season, week) < (test_season, test_week)


def american_to_decimal(american: float) -> float:
    if not np.isfinite(american) or abs(american) < 100:
        raise ValueError("American odds must be at least +100 or at most -100")
    if american > 0:
        return 1.0 + american / 100.0
    return 1.0 + 100.0 / abs(american)


def expected_value(decimal: float, win: float, push: float = 0.0) -> float:
    """Profit per 1 unit staked if `win` is the chance the bet wins."""
    if not np.isfinite(decimal) or decimal <= 1:
        raise ValueError("Decimal odds must be greater than 1")
    if (
        not np.isfinite(win)
        or not np.isfinite(push)
        or win < 0
        or push < 0
        or win + push > 1
    ):
        raise ValueError("Win and push probabilities must sum to at most 1")
    return float(win * (decimal - 1.0) - (1.0 - win - push))


def sigmoid(logit: float) -> float:
    if logit >= 20:
        return 1.0
    if logit <= -20:
        return 0.0
    return float(1.0 / (1.0 + np.exp(-logit)))


def bernoulli_log_loss(probability: float, outcome: float) -> float:
    """Negative log probability of a 0/1 result. Clipped so a 0 or 1 cannot explode."""
    if not np.isfinite(probability) or not np.isfinite(outcome):
        raise ValueError("Log loss inputs must be finite")
    probability = float(min(1.0 - 1e-6, max(1e-6, probability)))
    y = float(outcome)
    return float(-(y * np.log(probability) + (1.0 - y) * np.log(1.0 - probability)))


def logistic_probability(
    features: dict[str, float],
    names: Sequence[str],
    mean: Sequence[float],
    scale: Sequence[float],
    coefficients: Sequence[float],
    intercept: float,
) -> float:
    logit = float(intercept)
    for index, name in enumerate(names):
        logit += coefficients[index] * ((features[name] - mean[index]) / scale[index])
    return sigmoid(logit)


def nflverse_home_spread(spread_line: float) -> float:
    """Turn the nflverse schedule spread into the home team's betting number.

    In the schedules file, ``spread_line`` moves with the home team's final
    margin: the average of the two columns matches, and they are positively
    correlated. A value of +3.5 means the market expected the home team to
    win by 3.5, which is a betting number of -3.5. This is checked again
    after the backtest: the favorite should cover about half the games.
    """
    return -float(spread_line)


def home_covered(margin: float, spread_line: float) -> bool | None:
    """Whether the home team covered. None is a push.

    `spread_line` is the home team's number. Negative means the home team
    is laying points. Home covers when the final margin plus that number
    is greater than zero.
    """
    result = margin + spread_line
    if abs(result) < 1e-6:
        return None
    return result > 0


def over_hit(total: float, total_line: float) -> bool | None:
    result = total - total_line
    if abs(result) < 1e-6:
        return None
    return result > 0


def favorite_cover_probability(home_cover_probability: float, market_margin: float) -> float | None:
    """Chance the side the books favored covers. None when the line is a pick'em."""
    if abs(market_margin) < 1e-9:
        return None
    if market_margin > 0:
        return home_cover_probability
    return 1.0 - home_cover_probability


def projected_margin(home_net: float, away_net: float, scale: float, home_field: float) -> float:
    """Home margin in points. Positive means the home team is expected to win by that many."""
    return scale * (home_net - away_net) + home_field


def combined_scoring_rate(home_off: float, home_def: float, away_off: float, away_def: float) -> float:
    """Sum of the two offenses and the two defenses.

    Defense is points' worth of EPA the defense allows, so a higher number
    means more scoring, not a better defense.
    """
    return home_off + home_def + away_off + away_def


def projected_total(
    home_off: float,
    home_def: float,
    away_off: float,
    away_def: float,
    intercept: float,
    scale: float,
) -> float:
    return intercept + scale * combined_scoring_rate(home_off, home_def, away_off, away_def)


def cover_feature_values(
    *,
    projected: float,
    market_margin: float,
    home_off: float,
    away_off: float,
    home_def: float,
    away_def: float,
    home_form: float,
    away_form: float,
    home_rest: float,
    away_rest: float,
    home_success: float,
    away_success: float,
    home_explosive: float,
    away_explosive: float,
    home_turnover: float,
    away_turnover: float,
    home_out: float,
    away_out: float,
) -> dict[str, float]:
    return {
        "spread_edge": projected - market_margin,
        "off_diff": home_off - away_off,
        "def_diff": away_def - home_def,
        "form_diff": home_form - away_form,
        "rest_diff": home_rest - away_rest,
        "success_diff": home_success - away_success,
        "explosive_diff": home_explosive - away_explosive,
        "turnover_diff": away_turnover - home_turnover,
        "out_diff": away_out - home_out,
    }


def total_feature_values(
    *,
    projected: float,
    market_total: float,
    home_off: float,
    away_off: float,
    home_def: float,
    away_def: float,
    home_rest: float,
    away_rest: float,
    home_success: float,
    away_success: float,
    home_explosive: float,
    away_explosive: float,
    home_out: float,
    away_out: float,
) -> dict[str, float]:
    return {
        "total_edge": projected - market_total,
        "off_sum": home_off + away_off,
        "def_sum": home_def + away_def,
        "explosive_sum": home_explosive + away_explosive,
        "success_sum": home_success + away_success,
        "rest_sum": home_rest + away_rest,
        "out_sum": home_out + away_out,
    }


def roi_at_minus_110(wins: int, losses: int, pushes: int) -> float | None:
    """Profit divided by the amount staked, pricing every bet at -110."""
    bets = wins + losses + pushes
    if bets == 0:
        return None
    profit = wins * MINUS_110_WIN + losses * -MINUS_110_STAKE
    return float(profit / (bets * MINUS_110_STAKE))


@dataclass(frozen=True)
class OffenseLine:
    plays: int
    epa: float
    success: float
    explosive: float
    turnover: float


@dataclass(frozen=True)
class TeamGame:
    season: int
    week: int
    played_on: date
    game_id: str
    team: str
    off: OffenseLine
    defense: OffenseLine


@dataclass(frozen=True)
class ScheduleGame:
    season: int
    week: int
    played_on: date
    game_id: str
    home: str
    away: str
    home_score: float | None
    away_score: float | None
    spread_line: float | None
    total_line: float | None
    home_rest: float
    away_rest: float
    regular: bool
    home_out: float
    away_out: float


@dataclass(frozen=True)
class RatedGame:
    season: int
    week: int
    played_on: date
    game_id: str
    home: str
    away: str
    regular: bool
    home_off: float
    away_off: float
    home_def: float
    away_def: float
    home_net: float
    away_net: float
    home_form: float
    away_form: float
    home_success: float
    away_success: float
    home_explosive: float
    away_explosive: float
    home_turnover: float
    away_turnover: float
    home_rest: float
    away_rest: float
    home_out: float
    away_out: float
    margin: float | None
    total: float | None
    spread_line: float | None
    total_line: float | None


@dataclass(frozen=True)
class TeamRating:
    team: str
    off_epa: float
    def_epa: float
    net_epa: float
    success: float
    explosive: float
    turnover: float
    form_epa: float
    sample_plays: float
    last_game: date | None


@dataclass(frozen=True)
class ScoreLine:
    wins: int = 0
    losses: int = 0
    pushes: int = 0

    @property
    def decided(self) -> int:
        return self.wins + self.losses

    @property
    def games(self) -> int:
        return self.wins + self.losses + self.pushes

    @property
    def hit_rate(self) -> float | None:
        if self.decided == 0:
            return None
        return self.wins / self.decided

    @property
    def roi(self) -> float | None:
        return roi_at_minus_110(self.wins, self.losses, self.pushes)

    def add(self, won: bool | None) -> "ScoreLine":
        if won is None:
            return ScoreLine(self.wins, self.losses, self.pushes + 1)
        if won:
            return ScoreLine(self.wins + 1, self.losses, self.pushes)
        return ScoreLine(self.wins, self.losses + 1, self.pushes)


@dataclass(frozen=True)
class Fold:
    season: int
    week: int
    train_last: tuple[int, int] | None
    train_games: int


@dataclass(frozen=True)
class LogisticFit:
    names: tuple[str, ...]
    mean: tuple[float, ...]
    scale: tuple[float, ...]
    coefficients: tuple[float, ...]
    intercept: float

    def predict(self, features: dict[str, float]) -> float:
        return logistic_probability(
            features,
            self.names,
            self.mean,
            self.scale,
            self.coefficients,
            self.intercept,
        )


def _empty_priors() -> dict[str, float]:
    return {
        "off_epa": 0.0,
        "def_epa": 0.0,
        "success": 0.45,
        "explosive": 0.10,
        "turnover": 0.03,
    }


def league_priors(games: Sequence[TeamGame]) -> dict[str, float]:
    if len(games) < 50:
        return _empty_priors()

    def mean(attr: str, side: str) -> float:
        numerator = 0.0
        denominator = 0.0
        for game in games:
            line = game.off if side == "off" else game.defense
            value = getattr(line, attr)
            numerator += value * line.plays
            denominator += line.plays
        if denominator == 0:
            return _empty_priors()["off_epa" if attr == "epa" else attr]
        return numerator / denominator

    return {
        "off_epa": mean("epa", "off"),
        "def_epa": mean("epa", "def"),
        "success": mean("success", "off"),
        "explosive": mean("explosive", "off"),
        "turnover": mean("turnover", "off"),
    }


def rate_team(
    games: Sequence[TeamGame],
    as_of: date,
    priors: dict[str, float],
) -> TeamRating:
    usable = [game for game in games if (as_of - game.played_on).days >= 0]

    def series(side: str, attr: str, prior_key: str) -> float:
        samples = []
        for game in usable:
            line = game.off if side == "off" else game.defense
            samples.append(
                (getattr(line, attr), float(line.plays), float((as_of - game.played_on).days))
            )
        return shrunk_average(samples, priors[prior_key])

    off_epa = series("off", "epa", "off_epa")
    def_epa = series("def", "epa", "def_epa")
    sample_plays = 0.0
    for game in usable:
        sample_plays += game.off.plays * decay_weight((as_of - game.played_on).days)
    recent = usable[-4:]
    if recent:
        form = sum(game.off.epa - game.defense.epa for game in recent) / len(recent)
    else:
        form = 0.0
    return TeamRating(
        team=usable[-1].team if usable else "",
        off_epa=off_epa,
        def_epa=def_epa,
        net_epa=off_epa - def_epa,
        success=series("off", "success", "success"),
        explosive=series("off", "explosive", "explosive"),
        turnover=series("off", "turnover", "turnover"),
        form_epa=form,
        sample_plays=sample_plays,
        last_game=usable[-1].played_on if usable else None,
    )


def build_rated_games(
    team_games: Sequence[TeamGame],
    schedule: Sequence[ScheduleGame],
) -> list[RatedGame]:
    """One row per completed game. Ratings use only earlier weeks."""
    by_team: dict[str, list[TeamGame]] = {}
    for game in team_games:
        by_team.setdefault(game.team, []).append(game)
    for games in by_team.values():
        games.sort(key=lambda game: (game.season, game.week, game.played_on, game.game_id))

    weeks: dict[tuple[int, int], list[ScheduleGame]] = {}
    for game in schedule:
        if game.home_score is None or game.away_score is None:
            continue
        weeks.setdefault((game.season, game.week), []).append(game)

    teams = set(by_team)
    for game in schedule:
        teams.add(game.home)
        teams.add(game.away)
    history: dict[str, list[TeamGame]] = {team: [] for team in teams}
    team_game_index = {(game.game_id, game.team): game for game in team_games}
    rated: list[RatedGame] = []
    for season, week in sorted(weeks):
        slate = sorted(
            weeks[(season, week)],
            key=lambda game: (game.played_on, game.game_id),
        )
        as_of = slate[0].played_on
        past = [game for games in history.values() for game in games]
        priors = league_priors(past)
        ratings = {
            team: rate_team(games, as_of, priors) for team, games in history.items()
        }
        scored_ids: list[str] = []
        for game in slate:
            if (game.game_id, game.home) not in team_game_index:
                continue
            if (game.game_id, game.away) not in team_game_index:
                continue
            home = ratings[game.home]
            away = ratings[game.away]
            margin = float(game.home_score - game.away_score)
            total = float(game.home_score + game.away_score)
            rated.append(
                RatedGame(
                    season=season,
                    week=week,
                    played_on=game.played_on,
                    game_id=game.game_id,
                    home=game.home,
                    away=game.away,
                    regular=game.regular,
                    home_off=home.off_epa,
                    away_off=away.off_epa,
                    home_def=home.def_epa,
                    away_def=away.def_epa,
                    home_net=home.net_epa,
                    away_net=away.net_epa,
                    home_form=home.form_epa,
                    away_form=away.form_epa,
                    home_success=home.success,
                    away_success=away.success,
                    home_explosive=home.explosive,
                    away_explosive=away.explosive,
                    home_turnover=home.turnover,
                    away_turnover=away.turnover,
                    home_rest=game.home_rest,
                    away_rest=game.away_rest,
                    home_out=game.home_out,
                    away_out=game.away_out,
                    margin=margin,
                    total=total,
                    spread_line=game.spread_line,
                    total_line=game.total_line,
                )
            )
            scored_ids.append(game.game_id)
        for game in slate:
            if game.game_id not in scored_ids:
                continue
            for team in (game.home, game.away):
                played = team_game_index.get((game.game_id, team))
                if played is not None:
                    history.setdefault(team, []).append(played)
    return rated


def _fit_logistic(rows: Sequence[dict[str, float]], labels: Sequence[int], names: Sequence[str]) -> LogisticFit | None:
    if len(labels) < 80 or len(set(labels)) < 2:
        return None
    matrix = np.asarray([[row[name] for name in names] for row in rows], dtype=float)
    mean = matrix.mean(axis=0)
    scale = matrix.std(axis=0)
    scale[scale < 1e-8] = 1.0
    standardized = (matrix - mean) / scale
    model = LogisticRegression(
        C=LOGISTIC_C,
        solver="lbfgs",
        max_iter=1000,
        random_state=0,
    )
    model.fit(standardized, np.asarray(labels, dtype=int))
    return LogisticFit(
        names=tuple(names),
        mean=tuple(float(value) for value in mean),
        scale=tuple(float(value) for value in scale),
        coefficients=tuple(float(value) for value in model.coef_[0]),
        intercept=float(model.intercept_[0]),
    )


def _scale_pair(rows: Sequence[RatedGame]) -> tuple[float, float, float, float]:
    margins = [row for row in rows if row.margin is not None and row.total is not None]
    margin_scale, home_field = ordinary_least_squares(
        [row.home_net - row.away_net for row in margins],
        [float(row.margin) for row in margins],
    )
    total_scale, total_intercept = ordinary_least_squares(
        [
            combined_scoring_rate(row.home_off, row.home_def, row.away_off, row.away_def)
            for row in margins
        ],
        [float(row.total) for row in margins],
    )
    # OLS returns (slope, intercept). The names above match that order.
    return margin_scale, home_field, total_intercept, total_scale


def _cover_row(game: RatedGame, margin_scale: float, home_field: float) -> dict[str, float] | None:
    if game.spread_line is None or game.margin is None:
        return None
    projected = projected_margin(game.home_net, game.away_net, margin_scale, home_field)
    market_margin = -game.spread_line
    return cover_feature_values(
        projected=projected,
        market_margin=market_margin,
        home_off=game.home_off,
        away_off=game.away_off,
        home_def=game.home_def,
        away_def=game.away_def,
        home_form=game.home_form,
        away_form=game.away_form,
        home_rest=game.home_rest,
        away_rest=game.away_rest,
        home_success=game.home_success,
        away_success=game.away_success,
        home_explosive=game.home_explosive,
        away_explosive=game.away_explosive,
        home_turnover=game.home_turnover,
        away_turnover=game.away_turnover,
        home_out=game.home_out,
        away_out=game.away_out,
    )


def _total_row(game: RatedGame, total_intercept: float, total_scale: float) -> dict[str, float] | None:
    if game.total_line is None or game.total is None:
        return None
    projected = projected_total(
        game.home_off,
        game.home_def,
        game.away_off,
        game.away_def,
        total_intercept,
        total_scale,
    )
    return total_feature_values(
        projected=projected,
        market_total=game.total_line,
        home_off=game.home_off,
        away_off=game.away_off,
        home_def=game.home_def,
        away_def=game.away_def,
        home_rest=game.home_rest,
        away_rest=game.away_rest,
        home_success=game.home_success,
        away_success=game.away_success,
        home_explosive=game.home_explosive,
        away_explosive=game.away_explosive,
        home_out=game.home_out,
        away_out=game.away_out,
    )


@dataclass
class WalkForwardResult:
    primary: ScoreLine
    flagged: ScoreLine
    overs: ScoreLine
    folds: list[Fold]
    seasons: list[int]
    brier_sum: float
    brier_count: int
    log_loss_sum: float
    log_loss_count: int
    calibration: list[dict[str, float]]
    clv_beats: int
    clv_games: int
    model_error_sum: float
    market_error_sum: float
    favorite_wins: int
    favorite_decided: int
    home_wins: int
    home_decided: int
    final_margin_scale: float
    final_home_field: float
    final_total_intercept: float
    final_total_scale: float
    final_cover: LogisticFit | None
    final_total: LogisticFit | None

    @property
    def brier(self) -> float | None:
        if self.brier_count == 0:
            return None
        return self.brier_sum / self.brier_count

    @property
    def log_loss(self) -> float | None:
        if self.log_loss_count == 0:
            return None
        return self.log_loss_sum / self.log_loss_count

    @property
    def clv_beat_rate(self) -> float | None:
        if self.clv_games == 0:
            return None
        return self.clv_beats / self.clv_games

    @property
    def mean_model_error(self) -> float | None:
        if self.clv_games == 0:
            return None
        return self.model_error_sum / self.clv_games

    @property
    def mean_market_error(self) -> float | None:
        if self.clv_games == 0:
            return None
        return self.market_error_sum / self.clv_games


def walk_forward(
    rows: Sequence[RatedGame],
    min_train: int = 400,
    edge_points: float = SPREAD_EDGE_POINTS,
) -> WalkForwardResult:
    """Score each later week with a model fit only on earlier weeks."""
    ordered = sorted(rows, key=lambda row: (row.season, row.week, row.played_on, row.game_id))
    weeks = sorted({(row.season, row.week) for row in ordered if row.regular and row.spread_line is not None})
    primary = ScoreLine()
    flagged = ScoreLine()
    overs = ScoreLine()
    folds: list[Fold] = []
    seasons: set[int] = set()
    brier_sum = 0.0
    brier_count = 0
    log_loss_sum = 0.0
    log_loss_count = 0
    clv_beats = 0
    clv_games = 0
    model_error_sum = 0.0
    market_error_sum = 0.0
    favorite_wins = 0
    favorite_decided = 0
    home_wins = 0
    home_decided = 0
    calibration_rows: list[tuple[float, int]] = []

    for season, week in weeks:
        train = [
            row
            for row in ordered
            if is_before(row.season, row.week, season, week) and row.margin is not None
        ]
        spread_train = [row for row in train if row.spread_line is not None]
        if len(spread_train) < min_train:
            continue
        test = [
            row
            for row in ordered
            if row.season == season
            and row.week == week
            and row.regular
            and row.margin is not None
            and row.spread_line is not None
        ]
        if not test:
            continue
        margin_scale, home_field, total_intercept, total_scale = _scale_pair(train)
        cover_train_rows = []
        cover_labels = []
        for row in spread_train:
            features = _cover_row(row, margin_scale, home_field)
            if features is None or row.margin is None or row.spread_line is None:
                continue
            label = home_covered(row.margin, row.spread_line)
            if label is None:
                continue
            cover_train_rows.append(features)
            cover_labels.append(1 if label else 0)
        cover_model = _fit_logistic(cover_train_rows, cover_labels, COVER_FEATURES)
        total_train_rows = []
        total_labels = []
        for row in train:
            if row.total_line is None:
                continue
            features = _total_row(row, total_intercept, total_scale)
            if features is None or row.total is None:
                continue
            label = over_hit(row.total, row.total_line)
            if label is None:
                continue
            total_train_rows.append(features)
            total_labels.append(1 if label else 0)
        total_model = _fit_logistic(total_train_rows, total_labels, TOTAL_FEATURES)
        last_train = max((row.season, row.week) for row in train)
        if last_train >= (season, week):
            raise RuntimeError("Walk-forward used a game from the test week")
        folds.append(Fold(season, week, last_train, len(train)))
        if cover_model is None:
            continue
        seasons.add(season)
        for row in test:
            assert row.margin is not None and row.spread_line is not None
            features = _cover_row(row, margin_scale, home_field)
            if features is None:
                continue
            probability = cover_model.predict(features)
            covered = home_covered(row.margin, row.spread_line)
            if covered is not None:
                outcome = 1.0 if covered else 0.0
                brier_sum += (probability - outcome) ** 2
                brier_count += 1
                log_loss_sum += bernoulli_log_loss(probability, outcome)
                log_loss_count += 1
                calibration_rows.append((probability, 1 if covered else 0))
                home_decided += 1
                if covered:
                    home_wins += 1
                if row.spread_line < 0:
                    favorite_decided += 1
                    if covered:
                        favorite_wins += 1
                elif row.spread_line > 0:
                    favorite_decided += 1
                    if not covered:
                        favorite_wins += 1
            bet_home = probability >= 0.5
            won = None if covered is None else (covered if bet_home else not covered)
            primary = primary.add(won)
            projected = projected_margin(row.home_net, row.away_net, margin_scale, home_field)
            market_margin = -row.spread_line
            if abs(projected - market_margin) >= edge_points:
                flagged = flagged.add(won)
            model_error = abs(row.margin - projected)
            market_error = abs(row.margin - market_margin)
            model_error_sum += model_error
            market_error_sum += market_error
            clv_games += 1
            if model_error < market_error:
                clv_beats += 1
            if total_model is not None and row.total is not None and row.total_line is not None:
                total_features = _total_row(row, total_intercept, total_scale)
                if total_features is not None:
                    over_probability = total_model.predict(total_features)
                    over = over_hit(row.total, row.total_line)
                    bet_over = over_probability >= 0.5
                    over_won = None if over is None else (over if bet_over else not over)
                    overs = overs.add(over_won)

    final_train = [row for row in ordered if row.margin is not None]
    if len(final_train) >= 2:
        margin_scale, home_field, total_intercept, total_scale = _scale_pair(final_train)
    else:
        margin_scale, home_field, total_intercept, total_scale = 0.0, 0.0, 0.0, 0.0
    final_cover_rows = []
    final_cover_labels = []
    for row in final_train:
        features = _cover_row(row, margin_scale, home_field)
        if features is None or row.margin is None or row.spread_line is None:
            continue
        label = home_covered(row.margin, row.spread_line)
        if label is None:
            continue
        final_cover_rows.append(features)
        final_cover_labels.append(1 if label else 0)
    final_total_rows = []
    final_total_labels = []
    for row in final_train:
        features = _total_row(row, total_intercept, total_scale)
        if features is None or row.total is None or row.total_line is None:
            continue
        label = over_hit(row.total, row.total_line)
        if label is None:
            continue
        final_total_rows.append(features)
        final_total_labels.append(1 if label else 0)
    bins = _calibration(calibration_rows)
    return WalkForwardResult(
        primary=primary,
        flagged=flagged,
        overs=overs,
        folds=folds,
        seasons=sorted(seasons),
        brier_sum=brier_sum,
        brier_count=brier_count,
        log_loss_sum=log_loss_sum,
        log_loss_count=log_loss_count,
        calibration=bins,
        clv_beats=clv_beats,
        clv_games=clv_games,
        model_error_sum=model_error_sum,
        market_error_sum=market_error_sum,
        favorite_wins=favorite_wins,
        favorite_decided=favorite_decided,
        home_wins=home_wins,
        home_decided=home_decided,
        final_margin_scale=margin_scale,
        final_home_field=home_field,
        final_total_intercept=total_intercept,
        final_total_scale=total_scale,
        final_cover=_fit_logistic(final_cover_rows, final_cover_labels, COVER_FEATURES),
        final_total=_fit_logistic(final_total_rows, final_total_labels, TOTAL_FEATURES),
    )


def _calibration(rows: Sequence[tuple[float, int]]) -> list[dict[str, float]]:
    edges = (0.0, 0.4, 0.45, 0.5, 0.55, 0.6, 1.0000001)
    bins: list[dict[str, float]] = []
    for lower, upper in zip(edges, edges[1:]):
        chosen = [(prob, actual) for prob, actual in rows if lower <= prob < upper]
        if not chosen:
            bins.append(
                {
                    "from": lower,
                    "to": min(upper, 1.0),
                    "games": 0,
                    "predicted": 0.0,
                    "actual": 0.0,
                }
            )
            continue
        bins.append(
            {
                "from": lower,
                "to": min(upper, 1.0),
                "games": float(len(chosen)),
                "predicted": float(sum(prob for prob, _ in chosen) / len(chosen)),
                "actual": float(sum(actual for _, actual in chosen) / len(chosen)),
            }
        )
    return bins


def plain_english(result: WalkForwardResult) -> tuple[bool, str]:
    """Say what the past weeks did. Do not dress up a loss as an edge."""
    primary = result.primary
    if primary.hit_rate is None or primary.roi is None or not result.seasons:
        return False, "The backtest did not score any games."
    season_text = f"{result.seasons[0]}–{result.seasons[-1]}"
    hit = f"{primary.hit_rate * 100:.1f}%"
    roi = f"{primary.roi * 100:.1f}%"
    text = (
        f"Tested on {primary.games} regular-season games from {season_text}, "
        f"one week at a time, using only earlier weeks to train. "
        f"Betting the side our number liked, at the closing spread, at the usual -110 price: "
        f"it hit {hit} ({primary.wins} wins, {primary.losses} losses, {primary.pushes} pushes). "
        f"Profit was {roi} of the money staked. "
    )
    decided = primary.decided
    standard_error = (
        (primary.hit_rate * (1.0 - primary.hit_rate) / decided) ** 0.5 if decided else 1.0
    )
    clear = primary.roi > 0 and primary.hit_rate > BREAK_EVEN_RATE + 2.0 * standard_error
    if primary.roi <= 0 or primary.hit_rate <= BREAK_EVEN_RATE:
        text += (
            "That is not an edge. A -110 bet needs about 52.4% just to break even, "
            "and these past weeks did not clear that bar. "
            "The Coach's Line is still shown so you can compare it with the books. It is not a pick."
        )
        has_edge = False
    elif not clear:
        text += (
            "That is above the 52.4% break-even line, but it is close enough that it can be ordinary luck. "
            "Treat it as no proven edge."
        )
        has_edge = False
    else:
        text += (
            "That beat the 52.4% break-even line by more than a small margin on this past sample. "
            "It can still lose next week. It is not a guarantee."
        )
        has_edge = True
    if result.clv_beat_rate is not None and result.mean_model_error is not None:
        text += (
            f" Our number was closer to the final margin than the closing number in "
            f"{result.clv_beat_rate * 100:.1f}% of these games "
            f"(average miss {result.mean_model_error:.1f} points for us, "
            f"{result.mean_market_error:.1f} points for the close). "
            "That is not a bettor's closing-line value, because the historical file only has the closing number, "
            "not the number from earlier in the week."
        )
    flagged = result.flagged
    if flagged.hit_rate is not None and flagged.roi is not None and flagged.decided >= 30:
        text += (
            f" On the smaller slice where our number and the close differed by at least "
            f"{SPREAD_EDGE_POINTS:.1f} points ({flagged.decided} decided games): "
            f"hit {flagged.hit_rate * 100:.1f}%, profit {flagged.roi * 100:.1f}% of the stake. "
            "A smaller slice is easier to overread."
        )
    if result.overs.hit_rate is not None and result.overs.roi is not None:
        text += (
            f" The same style of test on totals, betting over or under at -110, hit "
            f"{result.overs.hit_rate * 100:.1f}% and returned {result.overs.roi * 100:.1f}% of the stake."
        )
    return has_edge, " ".join(text.split())


def current_ratings(
    team_games: Sequence[TeamGame],
    as_of: date,
) -> dict[str, TeamRating]:
    by_team: dict[str, list[TeamGame]] = {}
    for game in team_games:
        if game.played_on <= as_of:
            by_team.setdefault(game.team, []).append(game)
    for games in by_team.values():
        games.sort(key=lambda game: (game.season, game.week, game.played_on, game.game_id))
    priors = league_priors([game for games in by_team.values() for game in games])
    ratings = {}
    for team, games in by_team.items():
        rating = rate_team(games, as_of, priors)
        ratings[team] = TeamRating(
            team=team,
            off_epa=rating.off_epa,
            def_epa=rating.def_epa,
            net_epa=rating.net_epa,
            success=rating.success,
            explosive=rating.explosive,
            turnover=rating.turnover,
            form_epa=rating.form_epa,
            sample_plays=rating.sample_plays,
            last_game=rating.last_game,
        )
    return ratings
