"""Pure-function tests. They do not download nflverse files."""

import random
import unittest
from datetime import date

from nfl_model import (
    COVER_FEATURES,
    OffenseLine,
    RatedGame,
    ScheduleGame,
    TeamGame,
    american_to_decimal,
    build_rated_games,
    decay_weight,
    expected_value,
    home_covered,
    is_before,
    ordinary_least_squares,
    over_hit,
    roi_at_minus_110,
    shrunk_average,
    walk_forward,
)


class RatingMathTest(unittest.TestCase):
    def test_decay_half_life(self):
        self.assertEqual(decay_weight(0), 1.0)
        self.assertAlmostEqual(decay_weight(42), 0.5)
        self.assertAlmostEqual(decay_weight(84), 0.25)

    def test_decay_rejects_a_future_game(self):
        with self.assertRaises(ValueError):
            decay_weight(-1)

    def test_shrunk_average_pulls_a_short_sample_toward_the_prior(self):
        # One game of 200 plays at 1.0, no decay, prior 0 with 200 plays → 0.5.
        self.assertAlmostEqual(
            shrunk_average([(1.0, 200.0, 0.0)], prior_value=0.0, prior_plays=200.0),
            0.5,
        )

    def test_older_game_counts_less(self):
        recent = shrunk_average([(1.0, 100.0, 0.0)], prior_value=0.0, prior_plays=0.0000001)
        older = shrunk_average([(1.0, 100.0, 42.0), (0.0, 100.0, 0.0)], prior_value=0.0, prior_plays=0.0000001)
        self.assertAlmostEqual(recent, 1.0, places=4)
        self.assertLess(older, 0.4)

    def test_points_conversion_recovers_a_known_line(self):
        slope, intercept = ordinary_least_squares([0.0, 1.0, 2.0], [1.5, 3.5, 5.5])
        self.assertAlmostEqual(slope, 2.0)
        self.assertAlmostEqual(intercept, 1.5)


class MarketMathTest(unittest.TestCase):
    def test_nflverse_spread_is_the_expected_home_margin(self):
        from nfl_model import nflverse_home_spread

        # File value +3.5 means the home team is favored by 3.5, so the
        # betting number on the home team is -3.5.
        self.assertAlmostEqual(nflverse_home_spread(3.5), -3.5)
        self.assertIs(home_covered(7, nflverse_home_spread(3.0)), True)
        self.assertIs(home_covered(1, nflverse_home_spread(3.0)), False)

    def test_home_cover_uses_the_home_number(self):
        # Home won by 4, laying 3.5, so the home team covered.
        self.assertIs(home_covered(4, -3.5), True)
        # Home won by 3, laying 3.5, so the home team did not cover.
        self.assertIs(home_covered(3, -3.5), False)
        self.assertIsNone(home_covered(3, -3))

    def test_over(self):
        self.assertIs(over_hit(48, 47.5), True)
        self.assertIsNone(over_hit(47, 47))

    def test_expected_value_at_minus_110(self):
        decimal = american_to_decimal(-110)
        self.assertAlmostEqual(decimal, 1 + 100 / 110)
        # 55% at -110 is five cents of profit per dollar staked.
        self.assertAlmostEqual(expected_value(decimal, 0.55), 0.05)

    def test_roi_stakes_110_to_win_100(self):
        self.assertAlmostEqual(roi_at_minus_110(1, 0, 0), 1 / 1.1)
        self.assertAlmostEqual(roi_at_minus_110(0, 1, 0), -1.0)
        self.assertIsNone(roi_at_minus_110(0, 0, 0))
        # A push returns the stake, so it adds stake and no profit.
        self.assertAlmostEqual(roi_at_minus_110(1, 0, 1), 1 / 2.2)


class WalkForwardSplitTest(unittest.TestCase):
    def test_same_week_is_not_training(self):
        self.assertTrue(is_before(2020, 5, 2020, 6))
        self.assertFalse(is_before(2020, 5, 2020, 5))
        self.assertFalse(is_before(2021, 1, 2020, 18))
        self.assertTrue(is_before(2019, 17, 2020, 1))

    def test_rated_games_do_not_use_the_current_week(self):
        def line(epa: float) -> OffenseLine:
            return OffenseLine(plays=60, epa=epa, success=0.5, explosive=0.1, turnover=0.02)

        team_games = []
        schedule = []
        for week, epa in ((1, 0.2), (2, -0.2)):
            played = date(2020, 9, week)
            schedule.append(
                ScheduleGame(
                    season=2020,
                    week=week,
                    played_on=played,
                    game_id=f"g{week}",
                    home="A",
                    away="B",
                    home_score=20,
                    away_score=10,
                    spread_line=-3.0,
                    total_line=40.0,
                    home_rest=7,
                    away_rest=7,
                    regular=True,
                    home_out=0,
                    away_out=0,
                )
            )
            team_games.append(
                TeamGame(2020, week, played, f"g{week}", "A", line(epa), line(0.0))
            )
            team_games.append(
                TeamGame(2020, week, played, f"g{week}", "B", line(0.0), line(epa))
            )
        rated = build_rated_games(team_games, schedule)
        self.assertEqual(len(rated), 2)
        # Week 1 has no past games, so both teams sit on the prior (EPA 0).
        self.assertAlmostEqual(rated[0].home_off, 0.0)
        # Week 2 can see week 1, and team A was the better offense that week.
        self.assertGreater(rated[1].home_off, rated[1].away_off)

    def test_walk_forward_leaves_the_test_week_out_and_finds_a_clear_signal(self):
        rng = random.Random(0)
        rows = []
        for season in range(2018, 2024):
            for week in range(1, 19):
                for index in range(8):
                    home_net = rng.choice((-0.2, 0.2))
                    away_net = -home_net
                    margin = 2.0 + 50.0 * (home_net - away_net)
                    rows.append(
                        RatedGame(
                            season=season,
                            week=week,
                            played_on=date(season, 9, 1),
                            game_id=f"{season}-{week}-{index}",
                            home="H",
                            away="A",
                            regular=True,
                            home_off=home_net,
                            away_off=away_net,
                            home_def=0.0,
                            away_def=0.0,
                            home_net=home_net,
                            away_net=away_net,
                            home_form=0.0,
                            away_form=0.0,
                            home_success=0.45,
                            away_success=0.45,
                            home_explosive=0.1,
                            away_explosive=0.1,
                            home_turnover=0.02,
                            away_turnover=0.02,
                            home_rest=7,
                            away_rest=7,
                            home_out=0,
                            away_out=0,
                            margin=margin,
                            total=45.0,
                            spread_line=0.0,
                            total_line=44.0,
                        )
                    )
        result = walk_forward(rows, min_train=200, edge_points=2.5)
        self.assertGreater(result.primary.decided, 100)
        self.assertGreater(result.primary.hit_rate, 0.9)
        self.assertTrue(result.folds)
        for fold in result.folds:
            self.assertIsNotNone(fold.train_last)
            self.assertLess(fold.train_last, (fold.season, fold.week))
        self.assertEqual(result.final_cover.names, COVER_FEATURES)


if __name__ == "__main__":
    unittest.main()
