import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/edge_theme.dart';

class ParlayValidation extends StatefulWidget {
  const ParlayValidation({super.key});
  @override
  State<ParlayValidation> createState() => _ParlayValidationState();
}

class _ParlayValidationState extends State<ParlayValidation> {
  late final Future<Map<String, dynamic>> report = rootBundle
      .loadString('assets/parlay-calibration.json')
      .then((raw) => jsonDecode(raw) as Map<String, dynamic>);
  String score(dynamic value) => value is num ? value.toStringAsFixed(5) : '—';
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: report,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text(
          'Parlay validation report unavailable. No validation claim is made.',
          style: EdgeType.label,
        );
      }
      final r = snapshot.data;
      if (r == null) {
        return const Text('Loading parlay validation…', style: EdgeType.label);
      }
      final a = r['correlated'], b = r['independent'];
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text(
          'Parlay validation · experimental',
          style: EdgeType.title,
        ),
        subtitle: Text(
          '${a['count']} cases · ${r['uniqueGames']} games · no demonstrated betting edge',
          style: EdgeType.label,
        ),
        children: [
          Text(
            'Joint Brier ${score(a['brier'])} vs product ${score(b['brier'])}. Joint log loss ${score(a['logLoss'])} vs product ${score(b['logLoss'])}. Lower is better.',
            style: EdgeType.body,
          ),
          const SizedBox(height: 8),
          Text(
            r['adopted'] == true
                ? 'The dependence test passed the comparison gate. It does not establish profitability.'
                : 'Not adopted as a proven improvement: the gate needs at least 1,000 unique games and both scores to improve.',
            style: EdgeType.body,
          ),
          Text(
            '${r['scope']} Data cutoff ${r['dataCutoff']}.',
            style: EdgeType.label,
          ),
          Text('${r['exercise']} ${r['method']}', style: EdgeType.label),
          const SizedBox(height: 8),
          for (final s in r['seasons'])
            Text(
              '${s['season']}: trained through ${s['trainedThrough']}; ${s['correlated']['count']} cases. Brier ${score(s['correlated']['brier'])} / ${score(s['independent']['brier'])}; log loss ${score(s['correlated']['logLoss'])} / ${score(s['independent']['logLoss'])}.',
              style: EdgeType.label,
            ),
          const SizedBox(height: 8),
          const Text(
            'Calibration: predicted joint chance → observed joint frequency',
            style: EdgeType.label,
          ),
          for (final bin in r['calibration'])
            if (bin['count'] > 0)
              Text(
                '${((bin['meanChance'] as num) * 100).toStringAsFixed(1)}% → ${((bin['observed'] as num) * 100).toStringAsFixed(1)}% (${bin['count']} cases)',
                style: EdgeType.label,
              ),
        ],
      );
    },
  );
}
