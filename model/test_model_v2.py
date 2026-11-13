"""Version 2 of Coach's Line. No downloads."""

import unittest

from nfl_model_v2 import (
    ADOPTION_MIN_GAMES,
    GameContext,
    LiveQb,
    OutAppearance,
    QbAppearance,
    SnapAppearance,
    V2Game,
    adopt_v2,
    apply_platt,
    assemble_v2,
    choose_quarterback,
    differs_helped,
    fit_platt,
    injury_points,
    names_match,
    no_vig_probability,
    normal_cdf,
    project_margin,
    qb_swap_points,
    rest_side_points,
    scale_and_cap,
    shifted_probability,
    travel_margin_points,
    walk_forward_v2,
    weather_total_points,
)
from nfl_model import ScoreLine


def _game(**overrides) -> V2Game:
    base = dict(
        season=2020,
        week=1,
        game_id="g",
        regular=True,
        margin=3.0,
        total_points=44.0,
        market_margin=3.0,
        market_total=45.0,
        market_cover=0.5,
        market_over=0.5,
        qb_margin=0.0,
        injury_margin=0.0,
        rest_margin=0.0,
        travel_margin=0.0,
        weather_total=0.0,
        injury_total=0.0,
        qb_total=0.0,
    )
    base.update(overrides)
    return V2Game(**base)


def _context(**overrides) -> GameContext:
    base = dict(
        season=2020,
        week=1,
        game_id="g",
        home="H",
        away="A",
        regular=True,
        margin=7.0,
        total_points=40.0,
        market_margin=3.0,
        market_total=44.0,
        market_cover=0.5,
        market_over=0.5,
        home_qb_id="h1",
        away_qb_id="a1",
        home_qb_name="Home Starter",
        away_qb_name="Away Starter",
        home_rest=7,
        away_rest=7,
        open_roof=True,
        wind=5,
        temp_f=60,
        precip=0,
        game_lon=-80.0,
    )
    base.update(overrides)
    return GameContext(**base)


class MarketPriorTest(unittest.TestCase):
    def test_no_vig_removes_an_even_fee(self):
        chance = no_vig_probability(-110, -110)
        self.assertAlmostEqual(chance, 0.5, places=6)
        other = no_vig_probability(-110, -110)
        self.assertAlmostEqual(chance + other, 1.0, places=6)

    def test_no_vig_leans_toward_the_shorter_price(self):
        home = no_vig_probability(-150, 130)
        away = no_vig_probability(130, -150)
        self.assertIsNotNone(home)
        self.assertGreater(home, 0.5)
        self.assertAlmostEqual(home + away, 1.0, places=6)

    def test_a_missing_price_is_blank(self):
        self.assertIsNone(no_vig_probability(-110, 0))

    def test_zero_residual_leaves_the_market_line_and_the_market_chance(self):
        rows = []
        for week in range(1, 30):
            for index in range(16):
                rows.append(
                    _game(
                        week=week,
                        game_id=f"{week}-{index}",
                        margin=3.0 + ((index % 5) - 2),
                        market_margin=3.0,
                        market_cover=0.53,
                    )
                )
        result = walk_forward_v2(rows, min_train=80)
        self.assertGreaterEqual(len(result.predictions), 100)
        for prediction in result.predictions:
            self.assertAlmostEqual(prediction.margin, 3.0, places=4)
        # With no residual, the raw chance is the market's 0.53. Recalibration
        # may move it, but it must not jump to a confident number on its own.
        for prediction in result.predictions:
            self.assertGreater(prediction.probability, 0.35)
            self.assertLess(prediction.probability, 0.7)

    def test_a_point_residual_moves_the_cover_chance_off_the_market(self):
        base = shifted_probability(0.50, 0.0, 13.0)
        moved = shifted_probability(0.50, 3.0, 13.0)
        self.assertAlmostEqual(base, 0.5, places=4)
        self.assertGreater(moved, base)


class QuarterbackSwapTest(unittest.TestCase):
    def test_the_usual_starter_does_not_move_the_line(self):
        self.assertEqual(qb_swap_points("qb", "qb", 0.3, -0.2), 0.0)
        self.assertEqual(qb_swap_points("", "qb", 0.3, 0.0), 0.0)

    def test_a_better_starter_adds_points_and_a_backup_subtracts_them(self):
        upgrade = qb_swap_points("new", "old", 0.2, 0.0)
        downgrade = qb_swap_points("new", "old", -0.1, 0.15)
        self.assertGreater(upgrade, 0)
        self.assertLess(downgrade, 0)

    def test_the_swap_is_capped(self):
        huge = qb_swap_points("new", "old", 5.0, -5.0)
        self.assertLessEqual(abs(huge), 6.0)

    def test_an_out_starter_uses_the_backup_record(self):
        usual = LiveQb("usual", "Usual Starter", 0.15, 400)
        backup = LiveQb("backup", "Backup Arm", -0.05, 80)
        points = choose_quarterback(usual, usual, [backup], ["Usual Starter"])
        self.assertLess(points, 0)
        staying = choose_quarterback(usual, usual, [backup], [])
        self.assertEqual(staying, 0.0)


class InjuryWeightTest(unittest.TestCase):
    def test_a_starting_tackle_counts_more_than_a_part_time_receiver(self):
        tackle = injury_points("LT", 0.98)
        receiver = injury_points("WR", 0.15)
        self.assertGreater(tackle, receiver)
        self.assertGreater(tackle, 1.0)

    def test_a_quarterback_is_not_counted_twice(self):
        self.assertEqual(injury_points("QB", 1.0), 0.0)

    def test_no_snaps_is_nothing(self):
        self.assertEqual(injury_points("CB", 0.0), 0.0)
        self.assertEqual(injury_points("WR", -1), 0.0)

    def test_this_weeks_snaps_do_not_change_this_weeks_outs(self):
        games = [
            _context(week=1, game_id="w1"),
            _context(week=2, game_id="w2"),
        ]
        snaps = [
            SnapAppearance(2020, 1, "H", "Big Tackle", "LT", 0.2),
            SnapAppearance(2020, 2, "H", "Big Tackle", "LT", 1.0),
        ]
        outs = [OutAppearance(2020, 2, "H", "Big Tackle", "LT")]
        built, _ = assemble_v2(games, [], snaps, outs)
        week2 = next(row for row in built if row.game_id == "w2")
        # Home tackle out at a 0.2 snap share. Away has nobody out.
        # injury_margin = away - home, so the home side being worse is negative.
        expected = -injury_points("LT", 0.2)
        self.assertAlmostEqual(week2.injury_margin, expected, places=4)
        self.assertNotAlmostEqual(week2.injury_margin, -injury_points("LT", 1.0), places=2)


class WeatherTest(unittest.TestCase):
    def test_a_closed_roof_ignores_the_weather(self):
        self.assertEqual(weather_total_points(25, 10, 8, False), 0.0)

    def test_wind_cold_and_rain_lower_an_open_roof_total(self):
        calm = weather_total_points(5, 70, 0, True)
        wind = weather_total_points(20, 70, 0, True)
        nasty = weather_total_points(20, 20, 6, True)
        self.assertEqual(calm, 0.0)
        self.assertLess(wind, 0)
        self.assertLess(nasty, wind)

    def test_rest_and_travel_are_signed(self):
        self.assertLess(rest_side_points(4), 0)
        self.assertEqual(rest_side_points(7), 0)
        self.assertGreater(rest_side_points(12), 0)
        # Away team traveled east across the country: home margin goes up.
        east = travel_margin_points(-122.0, -74.0)
        self.assertGreater(east, 0)
        self.assertEqual(travel_margin_points(-84.0, -88.0), 0.0)


class RecalibrationTest(unittest.TestCase):
    def test_an_overconfident_chance_is_pulled_toward_what_happened(self):
        probabilities = []
        outcomes = []
        for index in range(240):
            if index % 2 == 0:
                probabilities.append(0.75)
                outcomes.append(1 if index % 20 < 11 else 0)
            else:
                probabilities.append(0.30)
                outcomes.append(1 if index % 10 < 3 else 0)
        # About 55% of the 0.75 rows hit, so 0.75 is too sure.
        high = [outcomes[i] for i, p in enumerate(probabilities) if p == 0.75]
        self.assertLess(sum(high) / len(high), 0.65)
        fit = fit_platt(probabilities, outcomes)
        self.assertIsNotNone(fit)
        calibrated = apply_platt(0.75, fit[0], fit[1])
        self.assertLess(abs(calibrated - (sum(high) / len(high))), abs(0.75 - (sum(high) / len(high))))

    def test_the_cap_keeps_the_nudges_inside_the_line(self):
        capped = scale_and_cap([3.0, 3.0], [1.0, 1.0], 4.0)
        self.assertAlmostEqual(sum(capped), 4.0, places=6)
        self.assertAlmostEqual(capped[0], capped[1], places=6)

    def test_normal_cdf_is_centered(self):
        self.assertAlmostEqual(normal_cdf(0), 0.5, places=4)
        self.assertAlmostEqual(normal_cdf(1), 0.8413, places=3)
        self.assertAlmostEqual(normal_cdf(-1), 1 - normal_cdf(1), places=4)


class NoLookaheadTest(unittest.TestCase):
    def test_a_later_week_does_not_change_an_earlier_prediction(self):
        rows = []
        for week in range(1, 21):
            for index in range(12):
                rows.append(
                    _game(
                        week=week,
                        game_id=f"{week}-{index}",
                        margin=1.0,
                        market_margin=1.0,
                    )
                )
        first = walk_forward_v2(rows, min_train=40)
        week15 = [row for row in first.predictions if row.week == 15]
        self.assertTrue(week15)
        rows.append(
            _game(
                week=30,
                game_id="future",
                margin=40.0,
                market_margin=1.0,
                qb_margin=12.0,
                weather_total=-8.0,
            )
        )
        second = walk_forward_v2(rows, min_train=40)
        again = [row for row in second.predictions if row.week == 15]
        self.assertEqual(len(again), len(week15))
        for left, right in zip(week15, again):
            self.assertAlmostEqual(left.margin, right.margin, places=6)
            self.assertAlmostEqual(left.probability, right.probability, places=6)
        for season, week, last in second.folds:
            self.assertLess(last, (season, week))

    def test_this_weeks_quarterback_epa_is_not_used_yet(self):
        games = [
            _context(week=1, game_id="w1", home_qb_id="old", away_qb_id="a"),
            _context(week=2, game_id="w2", home_qb_id="old", away_qb_id="a"),
            _context(week=3, game_id="w3", home_qb_id="new", away_qb_id="a"),
        ]
        quarterbacks = [
            QbAppearance(2020, 1, "H", "old", "Old Arm", 40, 8),  # 0.20 EPA
            QbAppearance(2020, 3, "H", "new", "New Arm", 40, 80),  # huge, but this week
        ]
        built, _ = assemble_v2(games, quarterbacks, [], [])
        week3 = next(row for row in built if row.game_id == "w3")
        # The new starter has no earlier dropbacks, so he sits near average,
        # below the usual starter. This week's 80 EPA must not flip the sign.
        self.assertLess(week3.qb_margin, 0)

    def test_names_match_an_initial_and_not_a_different_first_name(self):
        self.assertTrue(names_match("J. Love", "Jordan Love"))
        self.assertTrue(names_match("Jordan Love", "Jordan Love"))
        self.assertFalse(names_match("Josh Allen", "Jason Allen"))


class AdoptionTest(unittest.TestCase):
    def test_both_scores_must_be_strictly_lower_on_enough_games(self):
        self.assertTrue(
            adopt_v2(v1_brier=0.251, v1_log_loss=0.700, v2_brier=0.249, v2_log_loss=0.693, games=1200)
        )
        self.assertFalse(
            adopt_v2(v1_brier=0.251, v1_log_loss=0.690, v2_brier=0.249, v2_log_loss=0.693, games=1200)
        )
        self.assertFalse(
            adopt_v2(v1_brier=0.251, v1_log_loss=0.700, v2_brier=0.249, v2_log_loss=0.693, games=ADOPTION_MIN_GAMES - 1)
        )
        self.assertFalse(
            adopt_v2(v1_brier=0.251, v1_log_loss=0.700, v2_brier=0.251, v2_log_loss=0.690, games=1200)
        )

    def test_a_small_or_losing_slice_does_not_get_the_differs_mark(self):
        thin = ScoreLine(wins=20, losses=10, pushes=0)
        self.assertFalse(differs_helped(thin))
        losing = ScoreLine(wins=100, losses=120, pushes=0)
        self.assertFalse(differs_helped(losing))
        # 120 wins and 80 losses is 60%, which clears 52.4%, and the profit is positive.
        helped = ScoreLine(wins=120, losses=80, pushes=0)
        self.assertTrue(differs_helped(helped))

    def test_projection_uses_only_the_scales_it_is_given(self):
        from nfl_model_v2 import V2Scales

        game = _game(market_margin=3.0, qb_margin=2.0, injury_margin=-1.0)
        projected = project_margin(game, V2Scales(qb=0.5, injury=1.0))
        self.assertAlmostEqual(projected, 3.0 + 1.0 - 1.0, places=6)


if __name__ == "__main__":
    unittest.main()
