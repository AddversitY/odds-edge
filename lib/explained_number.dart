import 'package:flutter/material.dart';

import 'theme/edge_theme.dart';

const toolMint = EdgeColors.accent;

const responsibleGamblingNote =
    'This is a calculator, not a recommendation and not a promise of profit. '
    'Only risk money you can afford to lose. If betting is causing harm, '
    'call or text 1-800-GAMBLER.';

void explainNumber(BuildContext context, String title, String body) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class ExplainedValue extends StatelessWidget {
  const ExplainedValue({
    super.key,
    required this.value,
    required this.title,
    required this.body,
    this.style,
  });

  final String value, title, body;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(value, style: style),
      IconButton(
        tooltip: title,
        visualDensity: VisualDensity.compact,
        onPressed: () => explainNumber(context, title, body),
        icon: const Icon(Icons.info_outline, size: 18),
      ),
    ],
  );
}

class ToolNote extends StatelessWidget {
  const ToolNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(
        text,
        style: const TextStyle(
          color: EdgeColors.textSecondary,
          fontSize: 15,
          height: 1.45,
        ),
      );
}
