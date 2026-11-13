import 'package:flutter/material.dart';

import '../domain/value_check.dart';
import '../theme/edge_theme.dart';
import 'value_check.dart';

/// A Home-style card: a name, a market, the rail, and one reason line.
/// The longer note opens from a tap.
class ScanCard extends StatelessWidget {
  const ScanCard({
    super.key,
    required this.title,
    required this.line,
    required this.detail,
    this.meta = '',
    this.rail,
    this.word = ValueWord.skip,
    this.overpriced = true,
  });

  final String title;
  final String meta;
  final String line;
  final String detail;
  final Widget? rail;
  final ValueWord word;
  final bool overpriced;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EdgeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: EdgeColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: detail.isEmpty
            ? null
            : () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: EdgeColors.surface,
                showDragHandle: true,
                builder: (context) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: EdgeType.title.copyWith(
                          fontFamily: EdgeFont.display,
                          fontSize: 22,
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(meta, style: EdgeType.label),
                      ],
                      const SizedBox(height: 12),
                      Text(detail, style: EdgeType.body),
                    ],
                  ),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EdgeType.title.copyWith(
                        fontFamily: EdgeFont.display,
                        fontSize: 17,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  WordPill(word: word, overpriced: overpriced),
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EdgeType.label.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (rail != null) ...[const SizedBox(height: 10), rail!],
              const SizedBox(height: 8),
              Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: EdgeType.label.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
