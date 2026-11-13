import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/prop_model.dart';
import '../domain/prop_projection.dart';
import '../theme/edge_theme.dart';

/// The projection, the pieces that moved it, and the pull toward the book.
class PropBreakdown extends StatelessWidget {
  const PropBreakdown({super.key, required this.projection});

  final PropProjection projection;

  @override
  Widget build(BuildContext context) {
    final face = projection;
    final used = propV2Adopted && face.chance != null;
    final maxMove = face.factors
        .where((factor) => factor.label != 'Usage')
        .map((factor) => factor.delta.abs())
        .fold<double>(1, math.max);
    final number = face.mean >= 10
        ? face.mean.toStringAsFixed(0)
        : face.mean.toStringAsFixed(1);
    return Container(
      key: const Key('how-we-got-this'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: EdgeColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EdgeColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'How we got this',
                style: EdgeType.title.copyWith(
                  fontFamily: EdgeFont.display,
                  fontSize: 22,
                ),
              ),
              const Spacer(),
              _Chip(used: used),
            ],
          ),
          const SizedBox(height: 8),
          Text(number, style: EdgeType.number.copyWith(fontSize: 34)),
          Text(
            '${face.unit} projected · ${face.distribution}',
            style: EdgeType.label.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: EdgeColors.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          for (final factor in face.factors) ...[
            _FactorRow(factor: factor, maxMove: maxMove),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 4),
          _MarketPull(projection: face, used: used),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.used});
  final bool used;

  @override
  Widget build(BuildContext context) {
    final color = used ? EdgeColors.accent : EdgeColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        used ? 'In use' : 'Not used',
        style: EdgeType.label.copyWith(
          color: used ? EdgeColors.accent : EdgeColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.factor, required this.maxMove});
  final PropFactor factor;
  final double maxMove;

  @override
  Widget build(BuildContext context) {
    final share = factor.label == 'Usage'
        ? 1.0
        : (factor.delta.abs() / maxMove).clamp(0.0, 1.0);
    final signed = factor.label == 'Usage'
        ? factor.delta.toStringAsFixed(factor.delta >= 10 ? 0 : 1)
        : '${factor.delta >= 0 ? '+' : '−'}${factor.delta.abs().toStringAsFixed(1)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                factor.label,
                maxLines: 1,
                style: EdgeType.label.copyWith(fontSize: 13),
              ),
            ),
            Text(
              signed,
              style: EdgeType.label.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Text(
          factor.detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: EdgeType.label.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: EdgeColors.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 6,
          width: double.infinity,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: share < 0.04 ? 0.04 : share,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: EdgeColors.accent.withValues(alpha: .85),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MarketPull extends StatelessWidget {
  const _MarketPull({required this.projection, required this.used});
  final PropProjection projection;
  final bool used;

  @override
  Widget build(BuildContext context) {
    final raw = (projection.rawChance * 100).round();
    final book = projection.market == null
        ? null
        : (projection.market! * 100).round();
    final pulled = projection.chance == null
        ? null
        : (projection.chance! * 100).round();
    final line = book == null || pulled == null
        ? '$raw% from the projection. No book price to pull toward.'
        : '$raw% from the projection. The book at $book% pulled it to $pulled%.';
    final cap = projection.capped ? ' Gap held.' : '';
    final status = used
        ? ''
        : ' Not the chance above.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 10,
          width: double.infinity,
          child: CustomPaint(
            painter: _PullPainter(
              raw: projection.rawChance,
              book: projection.market,
              pulled: projection.chance,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$line$cap$status',
          style: EdgeType.label.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _PullPainter extends CustomPainter {
  _PullPainter({required this.raw, required this.book, required this.pulled});
  final double raw;
  final double? book, pulled;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - 3, size.width, 6),
        const Radius.circular(99),
      ),
      Paint()..color = EdgeColors.surfaceHigh,
    );
    void dot(double? value, Color color) {
      if (value == null) return;
      final x = value.clamp(0.0, 1.0) * size.width;
      canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = color);
    }

    dot(book, EdgeColors.textTertiary);
    dot(raw, EdgeColors.textSecondary);
    dot(pulled, EdgeColors.accent);
  }

  @override
  bool shouldRepaint(covariant _PullPainter oldDelegate) =>
      oldDelegate.raw != raw ||
      oldDelegate.book != book ||
      oldDelegate.pulled != pulled;
}
