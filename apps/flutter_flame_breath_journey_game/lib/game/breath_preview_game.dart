import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

class BreathPreviewGame extends FlameGame {
  static const double boardWidth = 10;
  static const double boardHeight = 15.5;
  static const double boardAspectRatio = boardWidth / boardHeight;

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    camera.viewfinder.position = Vector2.zero();
    add(_BreathBackdrop());
    add(_BreathOrb());
    addAll(<Component>[
      _FloatSeed(position: Vector2(2.0, 11.4), radius: 0.32, speed: 0.42),
      _FloatSeed(position: Vector2(7.6, 9.3), radius: 0.22, speed: 0.56),
      _FloatSeed(position: Vector2(6.8, 4.0), radius: 0.18, speed: 0.34),
    ]);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) {
      return;
    }
    camera.viewfinder.zoom = math.min(
      size.x / boardWidth,
      size.y / boardHeight,
    );
  }
}

class _BreathBackdrop extends PositionComponent {
  _BreathBackdrop() {
    position = Vector2.zero();
    size = Vector2(BreathPreviewGame.boardWidth, BreathPreviewGame.boardHeight);
    anchor = Anchor.topLeft;
  }

  @override
  void render(Canvas canvas) {
    final Rect rect = Rect.fromLTWH(0, 0, size.x, size.y);
    final Paint gradientPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFF132033),
          Color(0xFF17293A),
          Color(0xFF22354A),
        ],
      ).createShader(rect);
    final Paint gridPaint = Paint()
      ..color = const Color(0xFFF7F3E9).withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.04;
    final Paint bandPaint = Paint()
      ..color = const Color(0xFF78C0E0).withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    final RRect panel = RRect.fromRectAndRadius(
      rect.deflate(0.16),
      const Radius.circular(0.5),
    );
    canvas.drawRRect(panel, gradientPaint);

    for (int i = 0; i < 4; i += 1) {
      final double top = 2.1 + (i * 2.8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1.0, top, 8.0, 1.2),
          const Radius.circular(0.24),
        ),
        bandPaint,
      );
    }

    for (int line = 0; line < 5; line += 1) {
      final double y = 2.2 + (line * 2.4);
      canvas.drawLine(Offset(1.1, y), Offset(8.9, y), gridPaint);
    }
  }
}

class _BreathOrb extends PositionComponent {
  double elapsed = 0;

  _BreathOrb() {
    position = Vector2(5, 7.8);
    anchor = Anchor.center;
    size = Vector2.all(2.2);
  }

  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    final double inhaleWave = (math.sin(elapsed * 1.4) + 1) / 2;
    final double radius = 0.62 + (inhaleWave * 0.34);
    final double ringRadius = radius + 0.68;

    final Paint ringPaint = Paint()
      ..color = const Color(
        0xFFF7F3E9,
      ).withValues(alpha: 0.12 + (inhaleWave * 0.10))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.07;
    final Paint orbPaint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          const Color(0xFFFFF3C8).withValues(alpha: 0.92),
          const Color(0xFF78C0E0).withValues(alpha: 0.88),
          const Color(0xFF2A9D8F).withValues(alpha: 0.74),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));

    canvas.drawCircle(Offset.zero, ringRadius, ringPaint);
    canvas.drawCircle(Offset.zero, radius, orbPaint);
  }
}

class _FloatSeed extends PositionComponent {
  _FloatSeed({
    required Vector2 position,
    required this.radius,
    required this.speed,
  }) {
    this.position = position;
    anchor = Anchor.center;
    size = Vector2.all(radius * 2);
  }

  final double radius;
  final double speed;
  double elapsed = 0;
  late final Vector2 basePosition = position.clone();

  @override
  void update(double dt) {
    super.update(dt);
    elapsed += dt;
    position
      ..x = basePosition.x + math.sin(elapsed * speed) * 0.28
      ..y = basePosition.y - (math.sin(elapsed * speed * 0.7) * 0.18);
  }

  @override
  void render(Canvas canvas) {
    final Paint stemPaint = Paint()
      ..color = const Color(0xFFF7F3E9).withValues(alpha: 0.22)
      ..strokeWidth = 0.03;
    final Paint seedPaint = Paint()
      ..color = const Color(0xFFF7F3E9).withValues(alpha: 0.20);
    canvas.drawLine(
      Offset(0, radius * 0.9),
      Offset(0, -radius * 0.7),
      stemPaint,
    );
    canvas.drawCircle(Offset.zero, radius, seedPaint);
  }
}
