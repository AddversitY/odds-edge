import 'package:flutter/material.dart';

import '../domain/eastern.dart';
import '../domain/odds.dart';
import '../domain/stale_prices.dart';
import '../domain/value_check.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import '../ui/scan_card.dart';
import '../ui/value_check.dart';
import '../ui/wordmark.dart';
import 'coach_widgets.dart';

class StaleBoardScreen extends StatelessWidget {
  const StaleBoardScreen({
    super.key,
    required this.board,
    required this.now,
    required this.stamp,
    this.books,
  });

  final OddsBoard board;
  final DateTime now;
  final String Function(DateTime time) stamp;
  final Set<String>? books;

  @override
  Widget build(BuildContext context) {
    final rows = stalePrices(board, now, books: books);
    final shown = rows.length > 12 ? rows.sublist(0, 12) : rows;
    final eastern = formatEastern(board.fetchedAt, year: true);
    final saved = stamp(board.fetchedAt);
    final when = saved == eastern ? eastern : '$eastern · $saved';
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          key: const Key('stale-board'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            const SectionLabel('STALE PRICES'),
            const SizedBox(height: 8),
            if (board.demo) ...[const ExamplePill(), const SizedBox(height: 8)],
            Text(
              rows.isEmpty
                  ? 'No book is behind.'
                  : 'Asking more than the other books.',
              style: EdgeType.display.copyWith(fontSize: 28),
            ),
            const SizedBox(height: 8),
            Text(
              '$when. Not a live board.',
              style: EdgeType.label.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            if (shown.isEmpty)
              const EmptyNote('A normal fee is not listed.')
            else
              for (final row in shown) ...[
                ScanCard(
                  title: row.book,
                  meta: row.matchup.isEmpty
                      ? row.label
                      : '${row.label} · ${row.matchup}',
                  line: row.brief,
                  detail: row.reason,
                  rail: ValueCheck(
                    word: ValueWord.skip,
                    ourChance: row.fair,
                    bookChance: row.breakEven,
                    ourLabel: 'Fee-free',
                    bookLabel: 'This book',
                    overpriced: true,
                    compact: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            if (rows.length > shown.length)
              Text(
                '${rows.length - shown.length} more, with a smaller gap.',
                style: EdgeType.label,
              ),
            const SizedBox(height: 16),
            Text(
              'Comparison, not a pick.',
              textAlign: TextAlign.center,
              style: EdgeType.label.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: EdgeColors.textTertiary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              responsibleGamblingNote,
              textAlign: TextAlign.center,
              style: EdgeType.label.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: EdgeColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
