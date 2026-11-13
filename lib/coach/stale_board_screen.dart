import 'package:flutter/material.dart';

import '../domain/eastern.dart';
import '../domain/odds.dart';
import '../domain/stale_prices.dart';
import '../domain/value_check.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
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
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          key: const Key('stale-board'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SectionLabel('STALE PRICES'),
            const SizedBox(height: 8),
            if (board.demo) ...[const ExamplePill(), const SizedBox(height: 8)],
            Text(
              rows.isEmpty
                  ? 'No book in this snapshot is short of the fee-free consensus.'
                  : 'These books are asking more than the other books, after the fee.',
              style: EdgeType.display.copyWith(fontSize: 28),
            ),
            const SizedBox(height: 8),
            Text(
              'Snapshot as of ${formatEastern(board.fetchedAt, year: true)}. ${stamp(board.fetchedAt)}. This is the snapshot already saved. It is not a live board, and it is not a pick.',
              style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (shown.isEmpty)
              const EmptyNote(
                'Nothing here is far enough from the fee-free consensus to call a book behind. A normal fee is not listed.',
              )
            else
              for (final row in shown) ...[
                CoachCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.book,
                        style: EdgeType.label.copyWith(color: EdgeColors.bad),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        row.label,
                        style: EdgeType.title.copyWith(
                          fontFamily: EdgeFont.display,
                          fontSize: 20,
                        ),
                      ),
                      if (row.matchup.isNotEmpty)
                        Text(row.matchup, style: EdgeType.label),
                      const SizedBox(height: 10),
                      ValueCheck(
                        word: ValueWord.skip,
                        ourChance: row.fair,
                        bookChance: row.breakEven,
                        ourLabel: 'Fee-free',
                        bookLabel: 'This book',
                        overpriced: true,
                        compact: true,
                        note: row.reason,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            if (rows.length > shown.length)
              Text(
                '${rows.length - shown.length} more ${rows.length - shown.length == 1 ? 'price is' : 'prices are'} behind by a smaller gap. The longest gaps are shown.',
                style: EdgeType.label,
              ),
            const SizedBox(height: 8),
            const ToolNote(responsibleGamblingNote),
          ],
        ),
      ),
    );
  }
}
