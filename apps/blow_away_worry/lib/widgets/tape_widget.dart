import 'package:flutter/material.dart';

class TapeWidget extends StatelessWidget {
  const TapeWidget({required this.width, required this.opacity, super.key});

  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.06,
      child: CustomPaint(
        size: Size(width, 28),
        painter: _TapePainter(opacity: opacity),
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  const _TapePainter({required this.opacity});

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );

    final Paint fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.42);
    canvas.drawRRect(rrect, fillPaint);

    final Paint dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.55)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    const double dash = 5;
    const double gap = 4;
    final Path dashedBorder = Path();

    void addDashedLine(Offset start, Offset end) {
      final Offset delta = end - start;
      final double length = delta.distance;
      final Offset direction = Offset(delta.dx / length, delta.dy / length);
      double current = 0;
      while (current < length) {
        final double next = (current + dash).clamp(0, length).toDouble();
        dashedBorder.moveTo(
          start.dx + direction.dx * current,
          start.dy + direction.dy * current,
        );
        dashedBorder.lineTo(
          start.dx + direction.dx * next,
          start.dy + direction.dy * next,
        );
        current += dash + gap;
      }
    }

    addDashedLine(const Offset(6, 2), Offset(size.width - 6, 2));
    addDashedLine(
      Offset(size.width - 2, 6),
      Offset(size.width - 2, size.height - 6),
    );
    addDashedLine(
      Offset(size.width - 6, size.height - 2),
      Offset(6, size.height - 2),
    );
    addDashedLine(Offset(2, size.height - 6), const Offset(2, 6));
    canvas.drawPath(dashedBorder, dashPaint);
  }

  @override
  bool shouldRepaint(covariant _TapePainter oldDelegate) {
    return oldDelegate.opacity != opacity;
  }
}
