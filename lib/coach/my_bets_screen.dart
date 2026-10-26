import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/research_store.dart';
import '../domain/bets.dart';
import '../domain/coach_board.dart';
import '../domain/odds.dart';
import '../domain/saved_play.dart';
import '../explained_number.dart';
import 'coach_widgets.dart';

class MyBetsScreen extends StatefulWidget {
  const MyBetsScreen({super.key, required this.store});
  final ResearchStore store;

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
          if (tab == 0) _saved(log.plays) else _logged(log.bets),
        ],
      );
    },
  );

  Widget _saved(List<SavedPlay> plays) {
    if (plays.isEmpty) {
      return const CoachCard(
        child: Text(
          'No saved plays yet. On a prop card, tap the bookmark or double-tap the card. This is a shortlist, not a bet you have placed.',
          style: TextStyle(height: 1.4),
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
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(play.detail, style: const TextStyle(color: Colors.white60)),
                  Text(
                    [
                      if (play.book.isNotEmpty) play.book,
                      if (play.decimal != null) americanLabel(play.decimal!),
                      play.demo ? 'Sample price' : 'Saved price',
                      play.priceNote,
                    ].join(' · '),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () async {
                        await widget.store.saveSavedPlay(play.copyWith(removed: true));
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

  Widget _logged(List<TrackedBet> bets) {
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
              ),
            ),
            const SizedBox(width: 8),
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
        const SizedBox(height: 8),
        Text(
          'Record ${ledger.wins}-${ledger.losses}-${ledger.pushes}. Days below are local dates. A day with no bet is left blank.',
          style: const TextStyle(color: Colors.white60, height: 1.35),
        ),
        const SizedBox(height: 10),
        _MonthGrid(month: DateTime(month.year, month.month), days: monthDays),
        const SizedBox(height: 16),
        _AddBet(
          onAdd: (bet) async {
            await widget.store.saveBet(bet);
            setState(() => future = _load());
          },
        ),
        const SizedBox(height: 12),
        if (bets.isEmpty)
          const Text('No bets in the log yet. Adding one here does not place it.')
        else
          for (final bet in bets)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CoachCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bet.description, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${bet.book} · ${americanLabel(bet.decimal)} · stake ${money(bet.stake)} · ${bet.result.name}',
                    ),
                    Text(
                      bet.profit == null
                          ? 'Not in the settled total.'
                          : 'Result ${money(bet.profit!)}',
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

class _Log {
  const _Log({required this.plays, required this.bets});
  final List<SavedPlay> plays;
  final List<TrackedBet> bets;
}

class _Report extends StatelessWidget {
  const _Report({required this.title, required this.value});
  final String title, value;
  @override
  Widget build(BuildContext context) => CoachCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ],
    ),
  );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.days});
  final DateTime month;
  final List<DayReport> days;

  @override
  Widget build(BuildContext context) {
    final byDay = {for (final day in days) day.day.day: day};
    final first = DateTime(month.year, month.month);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final blanks = first.weekday % 7;
    return CoachCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_months[month.month - 1]} ${month.year}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final label in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
            ],
          ),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.8,
            children: [
              for (var i = 0; i < blanks; i++) const SizedBox(),
              for (var day = 1; day <= count; day++)
                _cell(day, byDay[day]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(int day, DayReport? report) {
    final profit = report == null || report.settledCount == 0
        ? ''
        : money(report.settledProfit);
    return Column(
      children: [
        Text('$day', style: const TextStyle(fontSize: 12)),
        if (profit.isNotEmpty)
          Text(
            profit,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              color: (report?.settledProfit ?? 0) < 0
                  ? const Color(0xFFFF7B7B)
                  : coachMint,
            ),
          ),
      ],
    );
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
  const _AddBet({required this.onAdd});
  final Future<void> Function(TrackedBet bet) onAdd;
  @override
  State<_AddBet> createState() => _AddBetState();
}

class _AddBetState extends State<_AddBet> {
  final description = TextEditingController();
  final book = TextEditingController();
  final odds = TextEditingController();
  final stake = TextEditingController();
  String? message;

  @override
  void dispose() {
    description.dispose();
    book.dispose();
    odds.dispose();
    stake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CoachCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Log a bet you placed', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          controller: description,
          decoration: const InputDecoration(labelText: 'What you bet'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: book,
          decoration: const InputDecoration(labelText: 'Sportsbook'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: odds,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+-]'))],
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
                () => message =
                    'Enter a description, a sportsbook, American odds, and a stake greater than zero.',
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
              ),
            );
            description.clear();
            setState(() => message = null);
          },
          child: const Text('Add to log'),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(message!, style: const TextStyle(color: Colors.orangeAccent)),
          ),
      ],
    ),
  );
}
