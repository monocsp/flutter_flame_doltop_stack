import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    GameWidget(
      game: BasicFlameGame(),
    ),
  );
}

class BasicFlameGame extends FlameGame {
  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;

    await world.addAll([
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
