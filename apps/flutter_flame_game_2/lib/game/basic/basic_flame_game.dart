import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

/// 기본 샘플 Flame 게임 장면을 유지합니다.
class BasicFlameGame extends FlameGame {
  /// 단순 도형과 텍스트로 샘플 게임 화면을 구성합니다.
  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;

    await world.addAll(<Component>[
      RectangleComponent(
        position: Vector2(48, 72),
        size: Vector2(220, 220),
        paint: Paint()..color = const Color(0xFF1F6FEB),
      ),
      TextComponent(
        text: 'Flutter Flame Game 2',
        position: Vector2(48, 320),
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Color(0xFFF5F7FA),
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      TextComponent(
        text: 'Monorepo-ready second game',
        position: Vector2(48, 360),
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Color(0xFFB8C0CC),
            fontSize: 16,
          ),
        ),
      ),
    ]);
  }

  @override
  Color backgroundColor() => const Color(0xFF0F1720);
}
