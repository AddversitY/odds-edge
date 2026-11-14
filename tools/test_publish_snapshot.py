import unittest
from datetime import datetime, timezone
from publish_snapshot import build_snapshot

class SnapshotExportTests(unittest.TestCase):
    def row(self, **extra):
        return dict(game_id='2026_11_BUF_KC', gameday='2026-11-15', gametime='20:20',
                    home_team='KC', away_team='BUF', home_score='', away_score='', **extra)

    def test_eastern_sunday_night_is_monday_utc_without_invented_odds(self):
        result = build_snapshot([self.row()], datetime(2026,11,14,tzinfo=timezone.utc))
        event = result['board']['events'][0]
        self.assertEqual(event['startsAt'], '2026-11-16T01:20:00Z')
        self.assertEqual(event['home'], 'Kansas City Chiefs')
        self.assertFalse(result['board']['demo'])
        self.assertEqual(result['board']['quotes'], [])
        self.assertEqual(result['odds']['status'], 'not_configured')
        self.assertEqual(result['board'], result['props'])

    def test_completed_past_unscheduled_unknown_teams_and_outside_window_omitted(self):
        rows = []
        for changes in [dict(home_score='20'), dict(gameday='2026-11-01'), dict(gametime=''),
                        dict(home_team='UNKNOWN'), dict(gameday='2026-12-15')]:
            row = self.row()
            row.update(changes)
            rows.append(row)
        result = build_snapshot(rows, datetime(2026,11,14,tzinfo=timezone.utc))
        self.assertEqual(result['board']['events'], [])

    def test_duplicate_ids_stop_publication_and_naive_clock_rejected(self):
        with self.assertRaises(ValueError):
            build_snapshot([self.row(), self.row()], datetime(2026,11,14,tzinfo=timezone.utc))
        with self.assertRaises(ValueError):
            build_snapshot([], datetime(2026,11,14))

    def test_daylight_saving_and_aliases(self):
        row = self.row()
        row.update(gameday='2026-10-25', away_team='LA', gametime='13:00')
        event = build_snapshot([row], datetime(2026,10,24,tzinfo=timezone.utc))['board']['events'][0]
        self.assertEqual(event['startsAt'], '2026-10-25T17:00:00Z')
        self.assertEqual(event['away'], 'Los Angeles Rams')

if __name__ == '__main__':
    unittest.main()
