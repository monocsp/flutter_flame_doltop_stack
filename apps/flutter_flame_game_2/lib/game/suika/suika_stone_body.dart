import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flame_game_2/game/suika/stone_spec.dart';
import 'package:flutter_flame_game_2/game/suika/suika_game.dart';

/// 원형 물리 바디와 단계 메타데이터를 함께 관리합니다.
class SuikaStoneBody extends BodyComponent<SuikaGame> with ContactCallbacks {
  /// 스톤 생성 시 필요한 규격과 위치를 주입합니다.
  SuikaStoneBody({
    required this.id,
    required this.spec,
    required this.spawnPosition,
    required this.createdAt,
    this.initialLinearVelocity,
  });

  /// 중복 합체를 막기 위한 고유 식별자입니다.
  final int id;

  /// 단계별 반지름과 점수 규격입니다.
  final StoneSpec spec;

  /// 월드 내 생성 위치입니다.
  final Vector2 spawnPosition;

  /// 합체 쿨다운 계산에 사용할 생성 시각입니다.
  final double createdAt;

  /// 생성 시점에 적용할 초기 속도입니다.
  final Vector2? initialLinearVelocity;

  /// 합체 큐 등록 여부를 표시합니다.
  bool isQueuedForMerge = false;

  @override
  Body createBody() {
    final double stageProgress = spec.stage / (StoneCatalog.values.length - 1);
    final BodyDef bodyDef = BodyDef(
      position: spawnPosition,
      type: BodyType.dynamic,
      allowSleep: true,
      fixedRotation: false,
      linearVelocity: initialLinearVelocity ?? Vector2.zero(),
      linearDamping: 0.08 + (stageProgress * 0.04),
      angularDamping: 1.6 + (stageProgress * 0.6),
    );
    final Body createdBody = world.createBody(bodyDef);
    final CircleShape shape = CircleShape()..radius = spec.radius;
    final FixtureDef fixtureDef = FixtureDef(
      shape,
      density: 2.8 + (stageProgress * 0.9),
      friction: 0.16 + (stageProgress * 0.06),
      restitution: 0.0,
    );
    createdBody.createFixture(fixtureDef);
    createdBody.isBullet = true;
    return createdBody;
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (other is! SuikaStoneBody) {
      return;
    }
    game.registerContactStart(this, other);
  }

  @override
  void endContact(Object other, Contact contact) {
    if (other is! SuikaStoneBody) {
      return;
    }
    game.registerContactEnd(this, other);
  }

  @override
  void render(Canvas canvas) {
    final double diameter = spec.radius * 2;
    final Offset center = Offset.zero;
    final Rect bodyRect = Rect.fromCircle(center: center, radius: spec.radius);
    final Paint fillPaint = Paint()..color = spec.color;
    final Paint borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.06;

    canvas.drawCircle(center, spec.radius, fillPaint);
    canvas.drawArc(bodyRect, 4.2, 1.2, false, borderPaint);

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: spec.label,
        style: const TextStyle(
          color: Color(0xFFFDF7ED),
          fontSize: 0.54,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: diameter);

    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }
}
