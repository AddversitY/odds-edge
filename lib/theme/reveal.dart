import 'package:flutter/material.dart';

import 'edge_theme.dart';

/// Three layers: a verdict, then plain-language reasons, then the math.
/// The next layer appears only after a tap.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.verdict,
    this.reasons,
    this.math,
    this.reasonsLabel = 'Why',
    this.mathLabel = 'The math',
  });

  final Widget verdict;
  final Widget? reasons;
  final Widget? math;
  final String reasonsLabel;
  final String mathLabel;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  bool reasonsOpen = false;
  bool mathOpen = false;

  @override
  Widget build(BuildContext context) {
    final reasons = widget.reasons;
    final math = widget.math;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.verdict,
        if (reasons != null)
          _layer(
            open: reasonsOpen,
            showLabel: widget.reasonsLabel,
            hideLabel: 'Hide the reason',
            onTap: () => setState(() {
              reasonsOpen = !reasonsOpen;
              if (!reasonsOpen) mathOpen = false;
            }),
            child: reasons,
            trailing: math == null
                ? null
                : _layer(
                    open: mathOpen,
                    showLabel: widget.mathLabel,
                    hideLabel: 'Hide the math',
                    onTap: () => setState(() => mathOpen = !mathOpen),
                    child: math,
                  ),
          )
        else if (math != null)
          _layer(
            open: mathOpen,
            showLabel: widget.mathLabel,
            hideLabel: 'Hide the math',
            onTap: () => setState(() => mathOpen = !mathOpen),
            child: math,
          ),
      ],
    );
  }

  Widget _layer({
    required bool open,
    required String showLabel,
    required String hideLabel,
    required VoidCallback onTap,
    required Widget child,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, EdgeSpace.tap),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.centerLeft,
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            onPressed: onTap,
            child: Text(open ? hideLabel : showLabel),
          ),
        ),
          if (open) ...[
          const SizedBox(height: EdgeSpace.sm),
          child,
          ?trailing,
        ],
      ],
    );
  }
}
