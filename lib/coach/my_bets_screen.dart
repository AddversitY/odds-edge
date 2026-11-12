import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/research_store.dart';
import '../domain/bets.dart';
import '../domain/coach_board.dart';
import '../domain/coach_model.dart';
import '../domain/odds.dart';
import '../domain/saved_play.dart';
import '../explained_number.dart';
import '../theme/edge_theme.dart';
import '../theme/reveal.dart';
import 'coach_widgets.dart';

class MyBetsScreen extends StatefulWidget {
  const MyBetsScreen({
    super.key,
    required this.store,
    this.board,
    this.now,
    this.books,
  });
  final ResearchStore store;
  final OddsBoard? board;
  final DateTime? now;
  final Set<String>? books;

  @override
  State<MyBetsScreen> createState() => _MyBetsScreenState();
}

class _MyBetsScreenState extends State<MyBetsScreen> {
  late Future<_Log> future = _load();
  int tab = 0;

  Future<_Log> _load() async => _Log(
    plays: await widget.store.loadSavedPlays(),
    bets: await widget.store.loadBets(),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<_Log>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text('Saved plays could not be read on this device.'),
        );
      }
      final log = snapshot.data;
      if (log == null) return const Center(child: CircularProgressIndicator());
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SectionLabel('MY BETS'),
          const SizedBox(height: 4),
          const Text(
            'A shortlist and a log. Nothing here is sent to a book.',
            style: EdgeType.label,
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              FilterPill(
                label: 'Saved',
                selected: tab == 0,
                onTap: () => setState(() => tab = 0),
              ),
              FilterPill(
                label: 'Bet log',
                selected: tab == 1,
                onTap: () => setState(() => tab = 1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (tab == 0) _saved(log.plays) else _logged(log.bets, widget.board),
        ],
      );
    },
  );

  Widget _saved(List<SavedPlay> plays) {
    if (plays.isEmpty) {
      return const CoachCard(
        child: Text(
          'No saved plays yet. Save one from a prop card.',
          style: EdgeType.label,
        ),
      );
    }
    return Column(
      children: [
        for (final play in plays)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CoachCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    play.title,
                    style: EdgeType.title.copyWith(
                      fontFamily: EdgeFont.display,
                      fontSize: 20,
                    ),
                  ),
                  Text(play.detail, style: EdgeType.label),
                  Text(
                    [
                      if (play.book.isNotEmpty) play.book,
                      if (play.decimal != null) americanLabel(play.decimal!),
                      play.demo ? 'Sample price' : 'Saved price',
                      play.priceNote,
                    ].join(' · '),
                    style: EdgeType.body,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () async {
                        await widget.store.saveSavedPlay(
                          play.copyWith(removed: true),
                        );
                        setState(() => future = _load());
                      },
                      child: const Text('Remove'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _logged(List<TrackedBet> bets, OddsBoard? board) {
    final ledger = BetLedger(bets);
    final days = betCalendar(bets);
    final month = calendarDay(DateTime.now());
    final monthDays = [
      for (final day in days)
        if (day.day.year == month.year && day.day.month == month.month) day,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Report(
                title: 'Settled',
                value: bets.isEmpty ? 'Nothing settled' : money(ledger.profit),
                color: bets.isEmpty ? null : valueColor(ledger.profit),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Report(
                title: 'At risk',
                value: pendingStake(bets) == 0
                    ? 'Nothing pending'
                    : money(pendingStake(bets)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Record ${ledger.wins}-${ledger.losses}-${ledger.pushes}. A day with no bet is left plain.',
          style: EdgeType.body.copyWith(color: EdgeColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(_closingSummary(ledger), style: EdgeType.body),
        const SizedBox(height: 12),
        _MonthGrid(month: DateTime(month.year, month.month), days: monthDays),
        const SizedBox(height: 16),
        _AddBet(
          board: board,
          books: widget.books,
          onAdd: (bet) async {
            await widget.store.saveBet(bet);
            setState(() => future = _load());
          },
        ),
        const SizedBox(height: 12),
        if (bets.isEmpty)
          const Text(
            'No bets in the log yet. Adding one here does not place it.',
            style: EdgeType.body,
          )
        else
          for (final bet in bets)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CoachCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bet.result.name,
                      style: EdgeType.label.copyWith(
                        color: switch (bet.result.name) {
                          'won' => EdgeColors.good,
                          'lost' => EdgeColors.bad,
                          'push' => EdgeColors.warn,
                          _ => EdgeColors.textSecondary,
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(bet.description, style: EdgeType.title),
                    const SizedBox(height: 4),
                    Text(
                      bet.profit == null ? 'Not settled' : money(bet.profit!),
                      style: EdgeType.title.copyWith(
                        color: bet.profit == null
                            ? EdgeColors.text
                            : valueColor(bet.profit),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${bet.book} · ${americanLabel(bet.decimal)} · stake ${money(bet.stake)}',
                      style: EdgeType.label,
                    ),
                    const SizedBox(height: 8),
                    Reveal(
                      verdict: Text(_clvSentence(bet), style: EdgeType.body),
                      math: bet.closingLineValue == null
                          ? null
                          : Text(
                              'Closing price versus the price you took: ${signedPercent(bet.closingLineValue!)}. Positive means the close was a shorter price.',
                              style: EdgeType.body,
                            ),
                    ),
                    _ClosingNumber(
                      key: ValueKey(bet.id),
                      bet: bet,
                      onSave: (closing) async {
                        await widget.store.saveBet(
                          bet.copyWith(
                            closingLine: closing,
                            replaceClosingLine: true,
                          ),
                        );
                        setState(() => future = _load());
                      },
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 8),
        const ToolNote(responsibleGamblingNote),
      ],
    );
  }
}

String _closingSummary(BetLedger ledger) {
  final values = ledger.lineClvPoints;
  if (values.isEmpty) {
    return 'Closing number: none yet. Log the number on your ticket, then add the number the game closed at. Beating the close means you got the better number, not that the bet won.';
  }
  final average = ledger.averageLineClv!;
  final direction = average > 0.05
      ? 'ahead of the close'
      : average < -0.05
      ? 'behind the close'
      : 'about even with the close';
  return 'Closing number: you beat the close on ${ledger.beatClosingNumber} of ${values.length} bets with a closing number. Average ${signedNumber(average)} points, $direction.';
}

String _clvSentence(TrackedBet bet) {
  final points = bet.lineClvPoints;
  if (bet.line == null) {
    return 'No number was saved with this bet, so it cannot be compared with the close.';
  }
  final logged = 'Number when you logged it: ${signedNumber(bet.line!)}.';
  if (points == null) {
    return '$logged Add the closing number when the game closes.';
  }
  if (points.abs() < 0.05) {
    return '$logged Same number as the close.';
  }
  if (points > 0) {
    return '$logged You beat the closing number by ${points.toStringAsFixed(1)} points.';
  }
  return '$logged The closing number beat you by ${(-points).toStringAsFixed(1)} points.';
}

class _ClosingNumber extends StatefulWidget {
  const _ClosingNumber({super.key, required this.bet, required this.onSave});
  final TrackedBet bet;
  final Future<void> Function(double? closing) onSave;

  @override
  State<_ClosingNumber> createState() => _ClosingNumberState();
}

class _ClosingNumberState extends State<_ClosingNumber> {
  late final closing = TextEditingController(
    text: widget.bet.closingLine?.toString() ?? '',
  );
  String? message;

  @override
  void dispose() {
    closing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.bet.line != null) ...[
          const SizedBox(height: 6),
          TextField(
            controller: closing,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(labelText: 'Closing number'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                final text = closing.text.trim();
                if (text.isEmpty) {
                  await widget.onSave(null);
                  return;
                }
                final value = double.tryParse(text);
                if (value == null) {
                  setState(
                    () => message =
                        'Enter the closing number, such as -3.5 or 47.5.',
                  );
                  return;
                }
                await widget.onSave(value);
                if (mounted) setState(() => message = null);
              },
              child: const Text('Save closing number'),
            ),
          ),
        ],
        if (message != null)
          Text(message!, style: EdgeType.body.copyWith(color: EdgeColors.warn)),
      ],
    );
  }
}

class _Log {
  const _Log({required this.plays, required this.bets});
  final List<SavedPlay> plays;
  final List<TrackedBet> bets;
}

class _Report extends StatelessWidget {
  const _Report({required this.title, required this.value, this.color});
  final String title, value;
  final Color? color;
  @override
  Widget build(BuildContext context) => CoachCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: EdgeType.label),
        const SizedBox(height: 8),
        Text(
          value,
          style: EdgeType.title.copyWith(color: color ?? EdgeColors.text),
        ),
      ],
    ),
  );
}

class _MonthGrid extends StatefulWidget {
  const _MonthGrid({required this.month, required this.days});
  final DateTime month;
  final List<DayReport> days;

  @override
  State<_MonthGrid> createState() => _MonthGridState();
}

class _MonthGridState extends State<_MonthGrid> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    final byDay = {for (final day in widget.days) day.day.day: day};
    final first = DateTime(widget.month.year, widget.month.month);
    final count = DateTime(widget.month.year, widget.month.month + 1, 0).day;
    final blanks = first.weekday % 7;
    final picked = selected == null ? null : byDay[selected];
    return CoachCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_months[widget.month.month - 1]} ${widget.month.year}',
            style: EdgeType.title,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final label in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: EdgeType.label,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (var i = 0; i < blanks; i++) const SizedBox(),
              for (var day = 1; day <= count; day++) _cell(day, byDay[day]),
            ],
          ),
          if (picked != null) ...[
            const SizedBox(height: 12),
            Text(_daySentence(picked), style: EdgeType.body),
          ],
        ],
      ),
    );
  }

  Widget _cell(int day, DayReport? report) {
    final settled = report != null && report.settledCount > 0;
    final color = !settled ? EdgeColors.text : valueColor(report.settledProfit);
    final chosen = selected == day;
    return InkWell(
      onTap: report == null
          ? null
          : () => setState(() => selected = chosen ? null : day),
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: chosen ? EdgeColors.surfaceHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            '$day',
            style: EdgeType.body.copyWith(
              color: color,
              fontWeight: settled ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  String _daySentence(DayReport report) {
    final label = '${_months[widget.month.month - 1]} ${report.day.day}';
    if (report.settledCount == 0) {
      return '$label: ${report.pendingCount} still open. Nothing settled that day.';
    }
    return '$label: ${money(report.settledProfit)} settled across ${report.settledCount} ${report.settledCount == 1 ? 'bet' : 'bets'}.';
  }
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class _AddBet extends StatefulWidget {
  const _AddBet({required this.onAdd, this.board, this.books});
  final Future<void> Function(TrackedBet bet) onAdd;
  final OddsBoard? board;
  final Set<String>? books;
  @override
  State<_AddBet> createState() => _AddBetState();
}

class _AddBetState extends State<_AddBet> {
  final description = TextEditingController();
  final book = TextEditingController();
  final odds = TextEditingController();
  final stake = TextEditingController();
  final line = TextEditingController();
  String kind = 'spreads';
  String side = '';
  String? eventId;
  String? message;
  bool open = false;

  @override
  void dispose() {
    description.dispose();
    book.dispose();
    odds.dispose();
    stake.dispose();
    line.dispose();
    super.dispose();
  }

  void _fillFromBoard() {
    final board = widget.board;
    final id = eventId;
    if (board == null || id == null) return;
    SportEvent? event;
    for (final candidate in board.events) {
      if (candidate.id == id) event = candidate;
    }
    if (event == null) return;
    final market = readMarketLine(event, board.quotes, books: widget.books);
    String? chosen = side;
    if (chosen.isEmpty) {
      chosen = kind == 'totals' ? 'over' : 'away';
    }
    OddsQuote? quote;
    double? number;
    var label = '';
    if (kind == 'spreads' && market.homeSpread != null) {
      if (chosen == 'home') {
        number = market.homeSpread;
        quote = market.homeSpreadPrice;
        label = '${event.home} ${signedNumber(number!)}';
      } else {
        chosen = 'away';
        number = -market.homeSpread!;
        quote = market.awaySpreadPrice;
        label = '${event.away} ${signedNumber(number)}';
      }
    } else if (kind == 'totals' && market.total != null) {
      final total = market.total!;
      number = total;
      if (chosen == 'under') {
        quote = market.underPrice;
        label = 'Under ${total.toStringAsFixed(1)}';
      } else {
        chosen = 'over';
        quote = market.overPrice;
        label = 'Over ${total.toStringAsFixed(1)}';
      }
    } else if (kind == 'h2h') {
      number = null;
      label = chosen == 'home' ? event.home : event.away;
    }
    side = chosen;
    if (label.isNotEmpty) description.text = label;
    if (number == null) {
      line.clear();
    } else {
      line.text = number.toStringAsFixed(1);
    }
    if (quote != null) {
      book.text = quote.book;
      odds.text = americanLabel(quote.decimal);
    }
  }

  @override
  Widget build(BuildContext context) => CoachCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 48),
            alignment: Alignment.centerLeft,
          ),
          onPressed: () => setState(() => open = !open),
          child: Text(open ? 'Hide the bet form' : 'Log a bet you placed'),
        ),
        if (open) ...[
          const SizedBox(height: 4),
          const Text(
            'The number on the ticket is saved now. After the game closes, add the closing number on the bet to see if you beat the close. This does not place the bet.',
            style: EdgeType.body,
          ),
          const SizedBox(height: 8),
          if (widget.board != null && widget.board!.events.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: eventId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Game on this screen',
              ),
              items: [
                for (final event in widget.board!.events)
                  DropdownMenuItem(
                    value: event.id,
                    child: Text(
                      '${event.away} at ${event.home}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() {
                eventId = value;
                _fillFromBoard();
              }),
            ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              FilterPill(
                label: 'Spread',
                selected: kind == 'spreads',
                onTap: () => setState(() {
                  kind = 'spreads';
                  side = '';
                  _fillFromBoard();
                }),
              ),
              FilterPill(
                label: 'Total',
                selected: kind == 'totals',
                onTap: () => setState(() {
                  kind = 'totals';
                  side = 'over';
                  _fillFromBoard();
                }),
              ),
              FilterPill(
                label: 'Moneyline',
                selected: kind == 'h2h',
                onTap: () => setState(() {
                  kind = 'h2h';
                  side = '';
                  _fillFromBoard();
                }),
              ),
            ],
          ),
          if (kind == 'totals')
            Wrap(
              children: [
                FilterPill(
                  label: 'Over',
                  selected: side != 'under',
                  onTap: () => setState(() {
                    side = 'over';
                    _fillFromBoard();
                  }),
                ),
                FilterPill(
                  label: 'Under',
                  selected: side == 'under',
                  onTap: () => setState(() {
                    side = 'under';
                    _fillFromBoard();
                  }),
                ),
              ],
            ),
          const SizedBox(height: 8),
          TextField(
            controller: description,
            decoration: const InputDecoration(labelText: 'What you bet'),
          ),
          if (kind != 'h2h') ...[
            const SizedBox(height: 8),
            TextField(
              controller: line,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Number on your ticket',
                helperText: 'Spread: -3.5 if you lay points, +3.5 if you get points. Total: 47.5.',
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: book,
            decoration: const InputDecoration(labelText: 'Sportsbook'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: odds,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+-]')),
            ],
            decoration: const InputDecoration(labelText: 'American odds'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: stake,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Stake'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              final american = int.tryParse(odds.text.trim());
              final amount = double.tryParse(stake.text.trim());
              if (american == null ||
                  american.abs() < 100 ||
                  amount == null ||
                  amount <= 0 ||
                  description.text.trim().isEmpty ||
                  book.text.trim().isEmpty) {
                setState(
                  () => message = 'Enter a description, a sportsbook, American odds, and a stake greater than zero.',
                );
                return;
              }
              final number = kind == 'h2h'
                  ? null
                  : double.tryParse(line.text.trim());
              if (kind != 'h2h' && number == null) {
                setState(
                  () => message =
                      'Enter the number on your ticket, such as -3.5 or 47.5.',
                );
                return;
              }
              await widget.onAdd(
                TrackedBet(
                  id: DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
                  placedAt: DateTime.now().toUtc(),
                  description: description.text.trim(),
                  book: book.text.trim(),
                  decimal: americanToDecimal(american),
                  stake: amount,
                  result: BetResult.pending,
                  market: kind,
                  side: side,
                  line: number,
                ),
              );
              description.clear();
              line.clear();
              setState(() => message = null);
            },
            child: const Text('Add to log'),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                message!,
                style: EdgeType.body.copyWith(color: EdgeColors.warn),
              ),
            ),
        ],
      ],
    ),
  );
}
