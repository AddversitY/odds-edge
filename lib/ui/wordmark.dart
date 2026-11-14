import 'package:flutter/material.dart';

import '../theme/edge_theme.dart';

/// Two uneven ticks: the book's chance and ours, with the gap between
/// them. That gap is the Odds Edge mark.
class OddsMark extends StatelessWidget {
  const OddsMark({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * 0.92, size),
      painter: const _MarkPainter(),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = EdgeColors.accent;
    final radius = size.width * 0.14;
    final gap = size.width * 0.22;
    final bar = (size.width - gap) / 2;
    final short = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height * 0.38, bar, size.height * 0.62),
      Radius.circular(radius),
    );
    final tall = RRect.fromRectAndRadius(
      Rect.fromLTWH(bar + gap, 0, bar, size.height),
      Radius.circular(radius),
    );
    canvas.drawRRect(short, paint);
    canvas.drawRRect(tall, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class OddsWordmark extends StatelessWidget {
  const OddsWordmark({super.key, this.height = 26});

  final double height;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: EdgeFont.brand,
      fontSize: height,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.6,
      height: 1,
      color: EdgeColors.text,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OddsMark(size: height * 0.92),
        SizedBox(width: height * 0.28),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Odds', style: style),
              TextSpan(
                text: ' Edge',
                style: style.copyWith(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ExamplePill extends StatelessWidget {
  const ExamplePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: EdgeColors.warn.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'EXAMPLE',
        style: EdgeType.label.copyWith(
          color: EdgeColors.warn,
          fontSize: 10,
          letterSpacing: 0.7,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
