"""Coach's Line version 2.

The line starts at the no-vig market number. A walk-forward fit, using only
earlier weeks, is allowed to add a residual for a quarterback change, outs
weighted by snaps, open-roof weather, and rest or travel. The stated chance
is then recalibrated on earlier weeks only.

These formulas are the ones lib/domain/coach_line_v2.dart applies to a
current game. A change here has to land there too.

The ridge penalty, the point caps, the position weights, and the weather
shape were chosen before the backtest. They are not searched.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Sequence

import numpy as np

from nfl_model import (
    BREAK_EVEN_RATE,
    SPREAD_EDGE_POINTS,
    ScoreLine,
    bernoulli_log_loss,
    is_before,
)

# Points of margin per 1.0 of EPA per dropback when the starter changes.
# 0.20 EPA is about 3.6 points, a backup-sized gap, and then capped.
QB_POINTS_PER_EPA = 18.0
QB_SWAP_CAP = 6.0
# Used only when the starter is out and no replacement has a record.
BACKUP_EPA = -0.10
INJURY_TEAM_CAP = 6.0
# Share of a team's injury points that comes off the total.
INJURY_TOTAL_FACTOR = 0.35
# Share of the two quarterback point-swaps that moves the total.
QB_TOTAL_FACTOR = 0.25
# Residual standard deviation, in points. Pre-set, not fit.
MARGIN_SIGMA = 13.0
TOTAL_SIGMA = 13.0
MARGIN_CAP = 4.0
TOTAL_CAP = 6.0
# Ridge penalty on the residual scales. Larger means stay closer to the market.
RIDGE_LAMBDA = 40.0
# Platt scaling needs this many earlier scored games, then stays inside these bounds.
PLATT_MIN_ROWS = 80
PLATT_INTERCEPT_LIMIT = 1.5
PLATT_SLOPE_MIN = 0.25
PLATT_SLOPE_MAX = 1.5
# Version 2 is adopted only when both scores are strictly better on this many games.
ADOPTION_MIN_GAMES = 1000
# The "differs" slice has to clear this many decided games before it can be shown.
DIFFERS_MIN_DECIDED = 200
PRIOR_DROPBACKS = 200.0

# Points lost if a player who takes every snap at that position is out.
# Quarterback is 0 here. The quarterback swap carries that position.
POSITION_WEIGHTS = {
    "LT": 1.8,
    "RT": 1.5,
    "T": 1.6,
    "OT": 1.6,
    "LG": 0.9,
    "RG": 0.9,
    "G": 0.9,
    "C": 1.2,
    "OL": 1.1,
    "WR": 1.0,
    "TE": 0.8,
    "RB": 0.7,
    "HB": 0.7,
    "FB": 0.3,
    "DE": 1.0,
    "DT": 0.9,
    "DL": 0.9,
    "NT": 0.9,
    "EDGE": 1.2,
    "LB": 0.7,
    "ILB": 0.7,
    "OLB": 0.8,
    "MLB": 0.7,
    "CB": 0.9,
    "S": 0.6,
    "FS": 0.6,
    "SS": 0.6,
    "DB": 0.7,
    "SAF": 0.6,
    "K": 0.15,
    "P": 0.1,
    "LS": 0.05,
}
DEFAULT_POSITION_WEIGHT = 0.4
QB_POSITIONS = {"QB", "QUARTERBACK"}


def normal_cdf(x: float) -> float:
    """Standard-normal CDF. Same Abramowitz-Stegun approximation as the Dart app."""
    if x >= 8:
        return 1.0
    if x <= -8:
        return 0.0
    z = abs(x)
    t = 1.0 / (1.0 + 0.2316419 * z)
    density = 0.3989422804014327 * math.exp(-0.5 * z * z)
    poly = t * (
        0.319381530
        + t
        * (
            -0.356563782
            + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))
        )
    )
    tail = density * poly
    if x >= 0:
        return 1.0 - tail
    return tail


def implied_probability(american: float) -> float | None:
    if american is None or not math.isfinite(american) or abs(american) < 100:
        return None
    if american < 0:
        return abs(american) / (abs(american) + 100.0)
    return 100.0 / (american + 100.0)


def no_vig_probability(american: float, other_american: float) -> float | None:
    """This side's price with the fee taken out. None when a price is missing."""
    side = implied_probability(american)
    other = implied_probability(other_american)
    if side is None or other is None or side + other <= 0:
        return None
    return side / (side + other)


def position_weight(position: str) -> float:
    key = (position or "").strip().upper()
    if key in QB_POSITIONS:
        return 0.0
    return POSITION_WEIGHTS.get(key, DEFAULT_POSITION_WEIGHT)


def injury_points(position: str, snap_share: float) -> float:
    """Points of strength a team loses when this player is out.

    Snap share is 0 to 1 of that team's snaps. A player with no snaps counts
    as nothing. A quarterback counts as nothing here.
    """
    if snap_share <= 0:
        return 0.0
    share = min(float(snap_share), 1.0)
    return position_weight(position) * share


def qb_swap_points(
    starter_id: str,
    usual_id: str,
    starter_epa: float,
    usual_epa: float,
) -> float:
    """Points added to a team's margin when the starter is not the usual one.

    The same quarterback is zero, even if his EPA is unusual. A missing id
    is zero. The result is capped.
    """
    if not starter_id or not usual_id or starter_id == usual_id:
        return 0.0
    raw = (float(starter_epa) - float(usual_epa)) * QB_POINTS_PER_EPA
    return float(max(-QB_SWAP_CAP, min(QB_SWAP_CAP, raw)))


def rest_side_points(days: float) -> float:
    """Points added to one side for short rest or a long week. A normal week is zero."""
    if days <= 5:
        return float(max(-2.0, (days - 7.0) * 0.45))
    if days >= 10:
        return float(min(0.8, (days - 7.0) * 0.15))
    return 0.0


def travel_margin_points(away_home_lon: float | None, game_lon: float | None) -> float:
    """Points added to the home margin when the away team crossed time zones.

    Positive means the away team traveled east. A trip under 1.5 zones is zero.
    """
    if away_home_lon is None or game_lon is None:
        return 0.0
    zones = (float(game_lon) - float(away_home_lon)) / 15.0
    if abs(zones) < 1.5:
        return 0.0
    return float(max(-1.0, min(1.0, 0.35 * zones)))


def weather_total_points(
    wind_mph: float | None,
    temp_f: float | None,
    precip_mm: float | None,
    open_roof: bool,
) -> float:
    """Points added to the total. A closed roof is zero. Wind, cold, and rain lower it."""
    if not open_roof:
        return 0.0
    wind = 0.0 if wind_mph is None else min(8.0, max(0.0, float(wind_mph) - 8.0) * 0.35)
    cold = 0.0 if temp_f is None else min(3.0, max(0.0, 35.0 - float(temp_f)) * 0.05)
    rain = 0.0
    if precip_mm is not None:
        amount = float(precip_mm)
        if amount >= 4:
            rain = 2.5
        elif amount >= 1:
            rain = 1.2
        elif amount >= 0.3:
            rain = 0.5
    return float(max(-10.0, -(wind + cold + rain)))


def qb_total_points(home_qb: float, away_qb: float) -> float:
    return QB_TOTAL_FACTOR * (home_qb + away_qb)


def injury_total_points(home_injury: float, away_injury: float) -> float:
    return -INJURY_TOTAL_FACTOR * (home_injury + away_injury)


def scale_and_cap(parts: Sequence[float], scales: Sequence[float], cap: float) -> list[float]:
    """Multiply each prior by its scale, then shrink the group so the sum stays inside the cap.

    The bars shown in the app are these returned values, so they add up to the
    residual on the line.
    """
    if len(parts) != len(scales):
        raise ValueError("Each nudge needs one scale")
    scaled = [float(part) * float(scale) for part, scale in zip(parts, scales)]
    total = sum(scaled)
    if abs(total) > cap and abs(total) > 1e-12:
        factor = cap / abs(total)
        scaled = [part * factor for part in scaled]
    return scaled


def shifted_probability(market_probability: float | None, delta_points: float, sigma: float) -> float:
    """Market chance, moved by a point residual. A zero residual leaves the market chance."""
    if sigma <= 0:
        raise ValueError("sigma must be positive")
    base = 0.5 if market_probability is None or not math.isfinite(market_probability) else market_probability
    base = min(0.98, max(0.02, base))
    shift = normal_cdf(delta_points / sigma) - 0.5
    return float(min(0.98, max(0.02, base + shift)))


def logit(probability: float) -> float:
    p = min(1.0 - 1e-6, max(1e-6, probability))
    return math.log(p / (1.0 - p))


def apply_platt(probability: float, intercept: float, slope: float) -> float:
    return float(1.0 / (1.0 + math.exp(-max(-20.0, min(20.0, intercept + slope * logit(probability))))))


def fit_platt(probabilities: Sequence[float], outcomes: Sequence[int]) -> tuple[float, float] | None:
    """Map an earlier raw chance onto what actually happened. None means leave it alone.

    The fit is Newton on a logistic line through the log-odds. The slope and
    intercept are then kept inside a pre-set range so one week cannot flip the chance.
    """
    if len(outcomes) < PLATT_MIN_ROWS or len(set(outcomes)) < 2:
        return None
    xs = np.asarray([logit(p) for p in probabilities], dtype=float)
    ys = np.asarray(outcomes, dtype=float)
    if float(xs.std()) < 1e-6:
        rate = float(ys.mean())
        return _clamp_platt(logit(min(0.98, max(0.02, rate))), 0.25)
    intercept = 0.0
    slope = 1.0
    for _ in range(30):
        linear = np.clip(intercept + slope * xs, -20, 20)
        predicted = 1.0 / (1.0 + np.exp(-linear))
        weight = np.maximum(predicted * (1.0 - predicted), 1e-6)
        grad_a = float((ys - predicted).sum())
        grad_b = float(((ys - predicted) * xs).sum())
        hess_aa = float(weight.sum())
        hess_ab = float((weight * xs).sum())
        hess_bb = float((weight * xs * xs).sum())
        det = hess_aa * hess_bb - hess_ab * hess_ab
        if abs(det) < 1e-12:
            return None
        step_a = (hess_bb * grad_a - hess_ab * grad_b) / det
        step_b = (hess_aa * grad_b - hess_ab * grad_a) / det
        intercept += step_a
        slope += step_b
        if abs(step_a) < 1e-8 and abs(step_b) < 1e-8:
            break
    if not math.isfinite(intercept) or not math.isfinite(slope):
        return None
    return _clamp_platt(intercept, slope)


def _clamp_platt(intercept: float, slope: float) -> tuple[float, float]:
    return (
        float(max(-PLATT_INTERCEPT_LIMIT, min(PLATT_INTERCEPT_LIMIT, intercept))),
        float(max(PLATT_SLOPE_MIN, min(PLATT_SLOPE_MAX, slope))),
    )


def ridge_scales(features: np.ndarray, target: np.ndarray, lam: float = RIDGE_LAMBDA) -> np.ndarray:
    """Residual scales. A feature the past weeks do not support stays near zero."""
    if features.ndim != 2 or features.shape[0] != target.shape[0] or features.shape[0] < 2:
        return np.zeros(features.shape[1] if features.ndim == 2 else 0, dtype=float)
    gram = features.T @ features
    gram.flat[:: features.shape[1] + 1] += lam
    try:
        scales = np.linalg.solve(gram, features.T @ target)
    except np.linalg.LinAlgError:
        return np.zeros(features.shape[1], dtype=float)
    if not np.isfinite(scales).all():
        return np.zeros(features.shape[1], dtype=float)
    return scales


@dataclass(frozen=True)
class V2Scales:
    qb: float = 0.0
    injury: float = 0.0
    rest: float = 0.0
    travel: float = 0.0
    weather: float = 0.0
    injury_total: float = 0.0
    qb_total: float = 0.0

    def margin_vector(self) -> tuple[float, float, float, float]:
        return (self.qb, self.injury, self.rest, self.travel)

    def total_vector(self) -> tuple[float, float, float]:
        return (self.weather, self.injury_total, self.qb_total)

    @classmethod
    def from_vectors(cls, margin: Sequence[float], total: Sequence[float]) -> "V2Scales":
        pad_m = list(margin) + [0.0, 0.0, 0.0, 0.0]
        pad_t = list(total) + [0.0, 0.0, 0.0]
        return cls(
            qb=float(pad_m[0]),
            injury=float(pad_m[1]),
            rest=float(pad_m[2]),
            travel=float(pad_m[3]),
            weather=float(pad_t[0]),
            injury_total=float(pad_t[1]),
            qb_total=float(pad_t[2]),
        )


@dataclass(frozen=True)
class V2Game:
    season: int
    week: int
    game_id: str
    regular: bool
    margin: float | None
    total_points: float | None
    market_margin: float | None
    market_total: float | None
    market_cover: float
    market_over: float
    qb_margin: float
    injury_margin: float
    rest_margin: float
    travel_margin: float
    weather_total: float
    injury_total: float
    qb_total: float


@dataclass(frozen=True)
class V2Prediction:
    season: int
    week: int
    game_id: str
    margin: float
    probability: float
    total: float | None
    over_probability: float | None


@dataclass
class V2Result:
    primary: ScoreLine
    flagged: ScoreLine
    overs: ScoreLine
    brier_sum: float
    brier_count: int
    log_loss_sum: float
    log_loss_count: int
    calibration: list[dict[str, float]]
    clv_beats: int
    clv_games: int
    model_error_sum: float
    market_error_sum: float
    seasons: list[int]
    scales: V2Scales
    cover_platt: tuple[float, float]
    total_platt: tuple[float, float]
    predictions: list[V2Prediction] = field(default_factory=list)
    folds: list[tuple[int, int, tuple[int, int]]] = field(default_factory=list)

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


def margin_parts(game: V2Game) -> list[float]:
    return [game.qb_margin, game.injury_margin, game.rest_margin, game.travel_margin]


def total_parts(game: V2Game) -> list[float]:
    return [game.weather_total, game.injury_total, game.qb_total]


def project_margin(game: V2Game, scales: V2Scales) -> float | None:
    if game.market_margin is None:
        return None
    nudges = scale_and_cap(margin_parts(game), scales.margin_vector(), MARGIN_CAP)
    return float(game.market_margin + sum(nudges))


def project_total(game: V2Game, scales: V2Scales) -> float | None:
    if game.market_total is None:
        return None
    nudges = scale_and_cap(total_parts(game), scales.total_vector(), TOTAL_CAP)
    return float(game.market_total + sum(nudges))


def _fit_scales(rows: Sequence[V2Game]) -> V2Scales:
    margin_rows = [row for row in rows if row.margin is not None and row.market_margin is not None]
    total_rows = [row for row in rows if row.total_points is not None and row.market_total is not None]
    margin = np.zeros(4, dtype=float)
    total = np.zeros(3, dtype=float)
    if len(margin_rows) >= 2:
        features = np.asarray([margin_parts(row) for row in margin_rows], dtype=float)
        target = np.asarray(
            [float(row.margin) - float(row.market_margin) for row in margin_rows],
            dtype=float,
        )
        margin = ridge_scales(features, target)
    if len(total_rows) >= 2:
        features = np.asarray([total_parts(row) for row in total_rows], dtype=float)
        target = np.asarray(
            [float(row.total_points) - float(row.market_total) for row in total_rows],
            dtype=float,
        )
        total = ridge_scales(features, target)
    return V2Scales.from_vectors(margin, total)


def _calibration(rows: Sequence[tuple[float, int]]) -> list[dict[str, float]]:
    edges = (0.0, 0.4, 0.45, 0.5, 0.55, 0.6, 1.0000001)
    bins: list[dict[str, float]] = []
    for lower, upper in zip(edges, edges[1:]):
        chosen = [(prob, actual) for prob, actual in rows if lower <= prob < upper]
        if not chosen:
            bins.append(
                {"from": lower, "to": min(upper, 1.0), "games": 0, "predicted": 0.0, "actual": 0.0}
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


def walk_forward_v2(rows: Sequence[V2Game], min_train: int = 400) -> V2Result:
    """Score each later week with scales and a recalibration fit only on earlier weeks."""
    ordered = sorted(rows, key=lambda row: (row.season, row.week, row.game_id))
    weeks = sorted(
        {
            (row.season, row.week)
            for row in ordered
            if row.regular and row.market_margin is not None and row.margin is not None
        }
    )
    primary = ScoreLine()
    flagged = ScoreLine()
    overs = ScoreLine()
    brier_sum = 0.0
    brier_count = 0
    log_loss_sum = 0.0
    log_loss_count = 0
    clv_beats = 0
    clv_games = 0
    model_error_sum = 0.0
    market_error_sum = 0.0
    seasons: set[int] = set()
    calibration_rows: list[tuple[float, int]] = []
    predictions: list[V2Prediction] = []
    folds: list[tuple[int, int, tuple[int, int]]] = []
    cover_raw: list[float] = []
    cover_y: list[int] = []
    total_raw: list[float] = []
    total_y: list[int] = []

    for season, week in weeks:
        train = [
            row
            for row in ordered
            if is_before(row.season, row.week, season, week)
            and row.margin is not None
            and row.market_margin is not None
        ]
        if len(train) < min_train:
            continue
        test = [
            row
            for row in ordered
            if row.season == season
            and row.week == week
            and row.regular
            and row.margin is not None
            and row.market_margin is not None
        ]
        if not test:
            continue
        last_train = max((row.season, row.week) for row in train)
        if last_train >= (season, week):
            raise RuntimeError("Walk-forward used a game from the test week")
        folds.append((season, week, last_train))
        scales = _fit_scales(train)
        cover_fit = fit_platt(cover_raw, cover_y) or (0.0, 1.0)
        total_fit = fit_platt(total_raw, total_y) or (0.0, 1.0)
        seasons.add(season)
        for row in test:
            assert row.margin is not None and row.market_margin is not None
            projected = project_margin(row, scales)
            assert projected is not None
            raw = shifted_probability(
                row.market_cover,
                projected - row.market_margin,
                MARGIN_SIGMA,
            )
            probability = apply_platt(raw, cover_fit[0], cover_fit[1])
            covered = None
            result = row.margin - row.market_margin
            # Home covers when the margin beats the market margin. A tie is a push.
            # market_margin is the expected home margin, so home covers when
            # margin > market_margin. The betting number is the negative of that.
            if abs(result) >= 1e-6:
                covered = result > 0
            if covered is not None:
                outcome = 1.0 if covered else 0.0
                brier_sum += (probability - outcome) ** 2
                brier_count += 1
                log_loss_sum += bernoulli_log_loss(probability, outcome)
                log_loss_count += 1
                calibration_rows.append((probability, 1 if covered else 0))
                cover_raw.append(raw)
                cover_y.append(1 if covered else 0)
            bet_home = probability >= 0.5
            won = None if covered is None else (covered if bet_home else not covered)
            primary = primary.add(won)
            if abs(projected - row.market_margin) >= SPREAD_EDGE_POINTS:
                flagged = flagged.add(won)
            model_error = abs(row.margin - projected)
            market_error = abs(row.margin - row.market_margin)
            model_error_sum += model_error
            market_error_sum += market_error
            clv_games += 1
            if model_error < market_error:
                clv_beats += 1
            over_probability = None
            projected_total = project_total(row, scales)
            if (
                projected_total is not None
                and row.total_points is not None
                and row.market_total is not None
            ):
                raw_over = shifted_probability(
                    row.market_over,
                    projected_total - row.market_total,
                    TOTAL_SIGMA,
                )
                over_probability = apply_platt(raw_over, total_fit[0], total_fit[1])
                over_result = row.total_points - row.market_total
                over = None if abs(over_result) < 1e-6 else over_result > 0
                if over is not None:
                    total_raw.append(raw_over)
                    total_y.append(1 if over else 0)
                bet_over = over_probability >= 0.5
                overs = overs.add(None if over is None else (over if bet_over else not over))
            predictions.append(
                V2Prediction(
                    season=season,
                    week=week,
                    game_id=row.game_id,
                    margin=projected,
                    probability=probability,
                    total=projected_total,
                    over_probability=over_probability,
                )
            )

    final_rows = [row for row in ordered if row.margin is not None and row.market_margin is not None]
    return V2Result(
        primary=primary,
        flagged=flagged,
        overs=overs,
        brier_sum=brier_sum,
        brier_count=brier_count,
        log_loss_sum=log_loss_sum,
        log_loss_count=log_loss_count,
        calibration=_calibration(calibration_rows),
        clv_beats=clv_beats,
        clv_games=clv_games,
        model_error_sum=model_error_sum,
        market_error_sum=market_error_sum,
        seasons=sorted(seasons),
        scales=_fit_scales(final_rows),
        cover_platt=fit_platt(cover_raw, cover_y) or (0.0, 1.0),
        total_platt=fit_platt(total_raw, total_y) or (0.0, 1.0),
        predictions=predictions,
        folds=folds,
    )


def differs_helped(flagged: ScoreLine, min_decided: int = DIFFERS_MIN_DECIDED) -> bool:
    """True only when moving off the market beat a -110 price on a large slice."""
    if flagged.decided < min_decided or flagged.hit_rate is None or flagged.roi is None:
        return False
    return flagged.roi > 0 and flagged.hit_rate > BREAK_EVEN_RATE


def has_betting_edge(primary: ScoreLine) -> bool:
    """Same bar as version 1: profit, and a hit rate that clears luck on this sample."""
    if primary.hit_rate is None or primary.roi is None or primary.decided == 0:
        return False
    standard_error = (primary.hit_rate * (1.0 - primary.hit_rate) / primary.decided) ** 0.5
    clear = primary.roi > 0 and primary.hit_rate > BREAK_EVEN_RATE + 2.0 * standard_error
    return bool(clear)


def adopt_v2(
    *,
    v1_brier: float | None,
    v1_log_loss: float | None,
    v2_brier: float | None,
    v2_log_loss: float | None,
    games: int,
    min_games: int = ADOPTION_MIN_GAMES,
) -> bool:
    """Version 2 goes on the game cards only when both scores are strictly lower."""
    if games < min_games:
        return False
    if None in (v1_brier, v1_log_loss, v2_brier, v2_log_loss):
        return False
    return float(v2_brier) < float(v1_brier) and float(v2_log_loss) < float(v1_log_loss)


def norm_name(name: str) -> str:
    text = (name or "").lower().replace("'", "").replace("’", "").replace(".", " ")
    text = text.replace("-", " ")
    return " ".join(text.split())


def names_match(left: str, right: str) -> bool:
    """Full names must agree. An initial ("J. Love") may match the full name."""
    a = norm_name(left)
    b = norm_name(right)
    if not a or not b:
        return False
    if a == b:
        return True
    a_parts = a.split()
    b_parts = b.split()
    if len(a_parts) < 2 or len(b_parts) < 2 or a_parts[-1] != b_parts[-1]:
        return False
    first_a, first_b = a_parts[0], b_parts[0]
    if len(first_a) <= 2 and first_b.startswith(first_a[0]):
        return True
    if len(first_b) <= 2 and first_a.startswith(first_b[0]):
        return True
    return False


@dataclass(frozen=True)
class GameContext:
    season: int
    week: int
    game_id: str
    home: str
    away: str
    regular: bool
    margin: float | None
    total_points: float | None
    market_margin: float | None
    market_total: float | None
    market_cover: float
    market_over: float
    home_qb_id: str
    away_qb_id: str
    home_qb_name: str
    away_qb_name: str
    home_rest: float
    away_rest: float
    open_roof: bool
    wind: float | None
    temp_f: float | None
    precip: float | None
    game_lon: float | None


@dataclass(frozen=True)
class QbAppearance:
    season: int
    week: int
    team: str
    player_id: str
    name: str
    dropbacks: float
    epa_sum: float


@dataclass(frozen=True)
class SnapAppearance:
    season: int
    week: int
    team: str
    name: str
    position: str
    snap_share: float


@dataclass(frozen=True)
class OutAppearance:
    season: int
    week: int
    team: str
    name: str
    position: str


@dataclass
class LiveQb:
    player_id: str
    name: str
    epa: float
    dropbacks: float


@dataclass
class LiveTeam:
    home_lon: float | None
    usual: LiveQb | None
    replacements: list[LiveQb]


@dataclass
class LivePlayer:
    team: str
    name: str
    position: str
    points: float


@dataclass
class LiveState:
    teams: dict[str, LiveTeam]
    players: list[LivePlayer]
    known_qbs: dict[str, LiveQb]


def _shrunk_epa(dropbacks: float, epa_sum: float, league_drop: float, league_epa: float) -> float:
    prior = (league_epa / league_drop) if league_drop >= 100 else 0.0
    return (epa_sum + prior * PRIOR_DROPBACKS) / (dropbacks + PRIOR_DROPBACKS)


def assemble_v2(
    games: Sequence[GameContext],
    quarterbacks: Sequence[QbAppearance],
    snaps: Sequence[SnapAppearance],
    outs: Sequence[OutAppearance],
) -> tuple[list[V2Game], LiveState]:
    """Build one row per game. Ratings, snaps, and quarterback EPA use only earlier weeks."""
    qb_by_week: dict[tuple[int, int], list[QbAppearance]] = {}
    for row in quarterbacks:
        qb_by_week.setdefault((row.season, row.week), []).append(row)
    snap_by_week: dict[tuple[int, int], list[SnapAppearance]] = {}
    for row in snaps:
        snap_by_week.setdefault((row.season, row.week), []).append(row)
    out_by_week: dict[tuple[int, int], list[OutAppearance]] = {}
    for row in outs:
        out_by_week.setdefault((row.season, row.week), []).append(row)

    weeks: dict[tuple[int, int], list[GameContext]] = {}
    for game in games:
        weeks.setdefault((game.season, game.week), []).append(game)

    last_starter: dict[str, str] = {}
    starter_name: dict[tuple[str, str], str] = {}
    player_drop: dict[str, float] = {}
    player_epa: dict[str, float] = {}
    player_name: dict[str, str] = {}
    player_team: dict[str, str] = {}
    league_drop = 0.0
    league_epa = 0.0
    snap_hist: dict[tuple[str, str], list[float]] = {}
    snap_pos: dict[tuple[str, str], str] = {}
    snap_display: dict[tuple[str, str], str] = {}
    team_lon: dict[str, float] = {}
    built: list[V2Game] = []

    def epa_of(player_id: str) -> float:
        return _shrunk_epa(
            player_drop.get(player_id, 0.0),
            player_epa.get(player_id, 0.0),
            league_drop,
            league_epa,
        )

    def side_qb(team: str, starter_id: str) -> float:
        usual = last_starter.get(team, "")
        return qb_swap_points(starter_id, usual, epa_of(starter_id), epa_of(usual) if usual else 0.0)

    def side_injury(team: str, week_outs: list[OutAppearance]) -> float:
        total = 0.0
        seen: set[str] = set()
        for out in week_outs:
            if out.team != team:
                continue
            key_name = norm_name(out.name)
            if not key_name or key_name in seen:
                continue
            seen.add(key_name)
            key = (key_name, team)
            shares = snap_hist.get(key, [])
            share = sum(shares[-8:]) / len(shares[-8:]) if shares else 0.0
            position = out.position or snap_pos.get(key, "")
            total += injury_points(position, share)
        return min(INJURY_TEAM_CAP, total)

    for season, week in sorted(weeks):
        slate = weeks[(season, week)]
        week_outs = out_by_week.get((season, week), [])
        for game in slate:
            home_qb = side_qb(game.home, game.home_qb_id)
            away_qb = side_qb(game.away, game.away_qb_id)
            home_inj = side_injury(game.home, week_outs)
            away_inj = side_injury(game.away, week_outs)
            if game.home_qb_id and game.home_qb_name:
                starter_name[(game.home, game.home_qb_id)] = game.home_qb_name
            if game.away_qb_id and game.away_qb_name:
                starter_name[(game.away, game.away_qb_id)] = game.away_qb_name
            built.append(
                V2Game(
                    season=season,
                    week=week,
                    game_id=game.game_id,
                    regular=game.regular,
                    margin=game.margin,
                    total_points=game.total_points,
                    market_margin=game.market_margin,
                    market_total=game.market_total,
                    market_cover=game.market_cover,
                    market_over=game.market_over,
                    qb_margin=home_qb - away_qb,
                    injury_margin=away_inj - home_inj,
                    rest_margin=rest_side_points(game.home_rest) - rest_side_points(game.away_rest),
                    travel_margin=travel_margin_points(team_lon.get(game.away), game.game_lon),
                    weather_total=weather_total_points(
                        game.wind, game.temp_f, game.precip, game.open_roof
                    ),
                    injury_total=injury_total_points(home_inj, away_inj),
                    qb_total=qb_total_points(home_qb, away_qb),
                )
            )
        for row in qb_by_week.get((season, week), []):
            if not row.player_id:
                continue
            player_drop[row.player_id] = player_drop.get(row.player_id, 0.0) + row.dropbacks
            player_epa[row.player_id] = player_epa.get(row.player_id, 0.0) + row.epa_sum
            league_drop += row.dropbacks
            league_epa += row.epa_sum
            if row.name:
                player_name[row.player_id] = row.name
            player_team[row.player_id] = row.team
        for game in slate:
            if game.home_qb_id:
                last_starter[game.home] = game.home_qb_id
            if game.away_qb_id:
                last_starter[game.away] = game.away_qb_id
            if game.game_lon is not None:
                team_lon[game.home] = game.game_lon
        for row in snap_by_week.get((season, week), []):
            key_name = norm_name(row.name)
            if not key_name or row.snap_share <= 0:
                continue
            key = (key_name, row.team)
            snap_hist.setdefault(key, []).append(min(row.snap_share, 1.0))
            if row.position:
                snap_pos[key] = row.position
            snap_display[key] = row.name

    teams: dict[str, LiveTeam] = {}
    seen_teams = set(last_starter) | set(team_lon)
    by_team_qbs: dict[str, list[LiveQb]] = {}
    for player_id, team in player_team.items():
        dropbacks = player_drop.get(player_id, 0.0)
        if dropbacks < 10:
            continue
        name = starter_name.get((team, player_id)) or player_name.get(player_id) or player_id
        by_team_qbs.setdefault(team, []).append(
            LiveQb(
                player_id=player_id,
                name=name,
                epa=_shrunk_epa(dropbacks, player_epa.get(player_id, 0.0), league_drop, league_epa),
                dropbacks=dropbacks,
            )
        )
        seen_teams.add(team)
    for team in seen_teams:
        usual_id = last_starter.get(team, "")
        pool = sorted(by_team_qbs.get(team, []), key=lambda qb: qb.dropbacks, reverse=True)
        usual = next((qb for qb in pool if qb.player_id == usual_id), None)
        if usual is None and usual_id:
            usual = LiveQb(
                player_id=usual_id,
                name=starter_name.get((team, usual_id), usual_id),
                epa=epa_of(usual_id),
                dropbacks=player_drop.get(usual_id, 0.0),
            )
        replacements = [qb for qb in pool if qb.player_id != usual_id][:3]
        teams[team] = LiveTeam(
            home_lon=team_lon.get(team),
            usual=usual,
            replacements=replacements,
        )
    players: list[LivePlayer] = []
    for (key_name, team), shares in snap_hist.items():
        recent = shares[-8:]
        share = sum(recent) / len(recent)
        position = snap_pos.get((key_name, team), "")
        points = injury_points(position, share)
        if points < 0.2:
            continue
        players.append(
            LivePlayer(
                team=team,
                name=snap_display.get((key_name, team), key_name),
                position=position,
                points=points,
            )
        )
    players.sort(key=lambda player: (player.team, -player.points, player.name))
    known = {
        player_id: LiveQb(
            player_id=player_id,
            name=player_name.get(player_id, player_id),
            epa=_shrunk_epa(
                dropbacks,
                player_epa.get(player_id, 0.0),
                league_drop,
                league_epa,
            ),
            dropbacks=dropbacks,
        )
        for player_id, dropbacks in player_drop.items()
        if dropbacks >= 10
    }
    return built, LiveState(teams=teams, players=players, known_qbs=known)


def choose_quarterback(
    usual: LiveQb | None,
    planned: LiveQb | None,
    replacements: Sequence[LiveQb],
    out_names: Sequence[str],
) -> float:
    """Points added to this team when the quarterback who will start is not the usual one."""
    if usual is None:
        return 0.0

    def is_out(name: str) -> bool:
        return any(names_match(name, out) for out in out_names)

    starter = planned or usual
    if is_out(starter.name):
        starter = next((qb for qb in replacements if not is_out(qb.name)), None)
        if starter is None:
            return qb_swap_points("backup", usual.player_id, BACKUP_EPA, usual.epa)
    return qb_swap_points(starter.player_id, usual.player_id, starter.epa, usual.epa)


def v2_plain(result: V2Result, adopted: bool, helped: bool) -> str:
    primary = result.primary
    if primary.hit_rate is None or primary.roi is None or not result.seasons:
        return "Version 2 did not score any games."
    season_text = f"{result.seasons[0]}–{result.seasons[-1]}"
    text = (
        f"Version 2 was tested on {primary.games} regular-season games from {season_text}, "
        f"one week at a time. The number starts at the closing line. "
        f"Only earlier weeks can move it, and only for a quarterback change, "
        f"outs weighted by snaps, weather on an open roof, and rest or travel. "
        f"Betting the side it liked, at the closing spread, at the usual -110 price: "
        f"it hit {primary.hit_rate * 100:.1f}% "
        f"({primary.wins} wins, {primary.losses} losses, {primary.pushes} pushes). "
        f"Profit was {primary.roi * 100:.1f}% of the money staked. "
    )
    if result.brier is not None and result.log_loss is not None:
        text += f"Brier {result.brier:.3f}. Log loss {result.log_loss:.3f}. "
    if not has_betting_edge(result.primary):
        text += (
            "That is not an edge against the market. "
            "A -110 bet needs about 52.4% to break even. "
        )
    else:
        text += "That beat the break-even line on this past sample. It can still lose next week. "
    if result.clv_beat_rate is not None and result.mean_model_error is not None:
        text += (
            f"It was closer to the final margin than the close in "
            f"{result.clv_beat_rate * 100:.1f}% of these games "
            f"(average miss {result.mean_model_error:.1f} points, "
            f"the close {result.mean_market_error:.1f}). "
        )
    if helped:
        text += "Moving off the market helped on the past slice where the number differed, so that mark can be shown. "
    else:
        text += (
            "Moving off the market did not help on the past slice where the number differed, "
            "so the games do not say it differs from the books. "
        )
    if adopted:
        text += "Version 2 is the number on the game cards because its chances were closer to what happened than version 1. "
    else:
        text += "Version 2 was not adopted. The game cards still use version 1. "
    if result.overs.hit_rate is not None and result.overs.roi is not None:
        text += (
            f"The same test on totals hit {result.overs.hit_rate * 100:.1f}% "
            f"and returned {result.overs.roi * 100:.1f}% of the stake. "
        )
        if not has_betting_edge(result.overs):
            text += "That is not an edge on totals either."
    return " ".join(text.split())
