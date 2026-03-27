import 'package:flutter/material.dart';

Path buildStickyNotePath(Size size) {
  final double width = size.width;
  final double height = size.height;
  final double foldStartX = width * 0.74;
  final double foldPeakY = height * 0.78;

  return Path()
    ..moveTo(0, 0)
    ..lineTo(width, 0)
    ..lineTo(width, height)
    ..lineTo(foldStartX, height)
    ..quadraticBezierTo(width * 0.08, height * 0.98, 0, foldPeakY)
    ..lineTo(0, 0)
    ..close();
}

class StickyNotePainter extends CustomPainter {
  const StickyNotePainter({required this.color, required this.hoverProgress});

  final Color color;
  final double hoverProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final Path notePath = buildStickyNotePath(size);
    final Rect rect = Offset.zero & size;

    final Path shadowPath = notePath.shift(
      Offset(0, 18 - hoverProgress.clamp(0.0, 1.0) * 10),
    );
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22 + hoverProgress * 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawPath(shadowPath, shadowPaint);

    final Paint fillPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.95, 0.95),
        radius: 1.28,
        colors: <Color>[
          Color.lerp(color, Colors.white, 0.2)!,
          color,
          Color.lerp(color, Colors.black, 0.18)!,
        ],
        stops: const <double>[0.0, 0.58, 1.0],
      ).createShader(rect);
    canvas.drawPath(notePath, fillPaint);

    final Paint edgePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(notePath, edgePaint);

    final Path foldHighlight = Path()
      ..moveTo(size.width * 0.72, size.height)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.95,
        size.width * 0.08,
        size.height * 0.8,
      )
      ..lineTo(size.width * 0.12, size.height * 0.62)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.86,
        size.width * 0.75,
        size.height * 0.92,
      )
      ..close();

    final Paint foldPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Colors.white.withValues(alpha: 0.42),
          Colors.white.withValues(alpha: 0.1),
        ],
      ).createShader(rect);
    canvas.drawPath(foldHighlight, foldPaint);

    final Paint highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.1, size.height * 0.16)
        ..quadraticBezierTo(
          size.width * 0.42,
          size.height * 0.02,
          size.width * 0.82,
          size.height * 0.08,
        ),
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant StickyNotePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.hoverProgress != hoverProgress;
  }
}
