import 'package:flutter/material.dart';

import '../domain/assistant.dart';
import '../domain/odds.dart';
import '../domain/research.dart';
import '../explained_number.dart';
import 'coach_widgets.dart';

/// Numbers the coach is allowed to see. A missing price means the coach
/// stays quiet instead of inventing one.
class CoachBrief {
  const CoachBrief({
    required this.label,
    required this.matchup,
    required this.price,
    required this.demo,
    required this.identity,
    required this.note,
    this.quote,
    this.event,
    this.teamEvidence = const [],
  });

  final String label, matchup, identity, note;
  final double price;
  final bool demo;
  final OddsQuote? quote;
  final SportEvent? event;
  final List<Map<String, dynamic>> teamEvidence;

  AssistantRequest request(String question) => AssistantRequest(
    mode: 'explain',
    question: question.trim(),
    selection: {
      'label': label,
      'matchup': matchup,
      'identity': identity,
      'price': price,
      'demo': demo,
    },
    assumptions: const ResearchAssumptions(
      performance: 0,
      availability: 0,
      environment: 0,
    ).toJson(),
    quote: quote?.toJson(),
    event: event?.toJson(),
    teamEvidence: [
      for (final item in teamEvidence) Map<String, dynamic>.from(item),
    ],
    playerEvidence: [
      {'note': note.length > 500 ? note.substring(0, 500) : note},
    ],
  );
}

Future<void> showAskCoach(
  BuildContext context, {
  required CoachBrief? brief,
  required Future<AssistantReply> Function(AssistantRequest request)? ask,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AskCoachSheet(brief: brief, ask: ask),
  );
}

class _AskCoachSheet extends StatefulWidget {
  const _AskCoachSheet({required this.brief, required this.ask});
  final CoachBrief? brief;
  final Future<AssistantReply> Function(AssistantRequest request)? ask;

  @override
  State<_AskCoachSheet> createState() => _AskCoachSheetState();
}

class _AskCoachSheetState extends State<_AskCoachSheet> {
  final question = TextEditingController();
  String? answer;
  bool busy = false;

  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brief = widget.brief;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('ASK COACH'),
          const SizedBox(height: 8),
          const Text(
            'Coach explains the numbers on this screen. It is not a pick, and it cannot see anything that is not written here.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 8),
          if (brief == null || widget.ask == null)
            const ToolNote(
              'Ask Coach needs the local backend, with the model key set only on that server. '
              'It also needs a real price on screen. This button does not call the model by itself and will not guess a number.',
            )
          else ...[
            Text(
              brief.note,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: question,
              maxLength: 400,
              decoration: const InputDecoration(
                labelText: 'What do you want explained?',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final text = question.text.trim();
                      if (text.isEmpty) return;
                      setState(() {
                        busy = true;
                        answer = null;
                      });
                      try {
                        final reply = await widget.ask!(brief.request(text));
                        if (!mounted) return;
                        setState(() {
                          answer = reply.available
                              ? reply.answer
                              : 'Coach is unavailable. Your notes were not changed.';
                        });
                      } catch (_) {
                        if (!mounted) return;
                        setState(
                          () => answer =
                              'Coach is unavailable. Your notes were not changed.',
                        );
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(busy ? 'Thinking…' : 'Ask Coach'),
            ),
            if (answer != null) ...[
              const SizedBox(height: 8),
              const Text('AI-generated', style: TextStyle(color: coachMint)),
              const SizedBox(height: 4),
              Text(answer!, style: const TextStyle(height: 1.4)),
            ],
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
