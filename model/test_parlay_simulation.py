import json
import unittest
from pathlib import Path

import numpy as np
from parlay_simulation import fit_matrix, joint_over, training_rows, build_report


class ParlaySimulationTests(unittest.TestCase):
    def test_copula_matches_independent_and_known_quadrant(self):
        self.assertAlmostEqual(joint_over(.6, .4, 0), .24, places=8)
        self.assertAlmostEqual(joint_over(.5, .5, .5), 1/3, places=8)
        self.assertLess(joint_over(.5, .5, -.5), .25)

    def test_sparse_pairs_revert_and_large_pairs_cap(self):
        sparse, counts, _ = fit_matrix([[i, i] for i in range(11)])
        self.assertEqual(sparse[0, 1], 0)
        self.assertEqual(counts[0, 1], 11)
        capped, _, _ = fit_matrix([[i, -i] for i in range(300)])
        self.assertAlmostEqual(capped[0, 1], -.65)
        np.linalg.cholesky(capped)

    def test_missing_pair_covariance_repairs_to_positive_definite(self):
        rows = []
        for i in range(300):
            rows.extend([[i, i, np.nan], [i, np.nan, i], [np.nan, i, -i]])
        matrix, _, scale = fit_matrix(rows)
        self.assertLess(scale, 1)
        np.linalg.cholesky(matrix)

    def test_whole_target_season_is_excluded(self):
        players, games = [], []
        for year in [2025, 2026]:
            for week in range(1, 16):
                date = f'{year}-09-{week:02d}'
                players.append(dict(playerId='p', team='BUF', opponent='KC', season=year,
                                    seasonType='REG', date=date, stats={'passing_yards': week*10}))
                games.append(dict(date=date, season=year, home='BUF', away='KC', homeScore=week, awayScore=7))
        selected = [dict(id='p', team='BUF', metric='passing_yards')]
        actual = training_rows(players, games, selected, 'BUF', 2026)
        self.assertEqual(len(actual), 15)
        np.testing.assert_allclose(actual, training_rows(players[:15], games[:15], selected, 'BUF', 2026), equal_nan=True)

    def test_no_cases_never_adopted_and_saved_report_is_not_profitability(self):
        report = build_report([], [])
        self.assertFalse(report['adopted'])
        self.assertFalse(report['hasEdge'])
        saved = json.loads((Path(__file__).resolve().parents[1]/'assets/parlay-calibration.json').read_text())
        self.assertFalse(saved['hasEdge'])
        self.assertEqual(saved['correlated']['count'], saved['independent']['count'])
        for season in saved['seasons']:
            self.assertLess(season['trainedThrough'], season['season'])


if __name__ == '__main__':
    unittest.main()
