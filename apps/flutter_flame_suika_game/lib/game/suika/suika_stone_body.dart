import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flame_game_2/game/suika/prepared_suika_assets.dart';
import 'package:flutter_flame_game_2/game/suika/stone_spec.dart';
import 'package:flutter_flame_game_2/game/suika/suika_game.dart';

enum StoneContactIndicator { none, touching, mergeReady }

/// 원형 물리 바디와 단계 메타데이터를 함께 관리합니다.
class SuikaStoneBody extends BodyComponent<SuikaGame> with ContactCallbacks {
  /// 스톤 생성 시 필요한 규격과 위치를 주입합니다.
  SuikaStoneBody({
    required this.id,
    required this.spec,
    required this.preparedAsset,
    required this.spawnPosition,
    required this.createdAt,
    this.initialLinearVelocity,
  });

  /// 중복 합체를 막기 위한 고유 식별자입니다.
  final int id;

  /// 단계별 반지름과 점수 규격입니다.
  final StoneSpec spec;

  /// 이미지 기반 충돌/비율 메타데이터입니다.
  final PreparedStoneAsset preparedAsset;

  /// 월드 내 생성 위치입니다.
  final Vector2 spawnPosition;

  /// 합체 쿨다운 계산에 사용할 생성 시각입니다.
  final double createdAt;

  /// 생성 시점에 적용할 초기 속도입니다.
  final Vector2? initialLinearVelocity;

  /// 합체 큐 등록 여부를 표시합니다.
  bool isQueuedForMerge = false;

  StoneContactIndicator contactIndicator = StoneContactIndicator.none;

  late final Vector2 halfSize = _computeHalfSize(
    preparedAsset.assetData.aspectRatio,
    spec.radius * 2,
  );

  /// 화면상 스프라이트 외곽 기준의 느슨한 합체 반경입니다.
  late final double mergeRadius = math.max(halfSize.x, halfSize.y) * 0.92;
  late final List<Vector2>? overlayPolygon = preparedAsset.overlayPolygon;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(
      SpriteComponent(
        sprite: Sprite(preparedAsset.image),
        size: _spriteWorldSize(),
        anchor: Anchor.center,
      ),
    );
    add(
      TextComponent(
        text: spec.label,
        anchor: Anchor.center,
        textRenderer: TextPaint(
          style: TextStyle(
            color: const Color(0xFFFDF7ED),
            fontSize: spec.radius * 0.82,
            fontWeight: FontWeight.w900,
            shadows: const <Shadow>[
              Shadow(color: Color(0xCC000000), blurRadius: 6),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Body createBody() {
    final double stageProgress = spec.stage / (StoneCatalog.stageCount - 1);
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
    createdBody.userData = this;
    _attachImageOrFallbackFixtures(createdBody, stageProgress);
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
    if (contactIndicator != StoneContactIndicator.mergeReady) {
      return;
    }

    final Color strokeColor = const Color(0xFFFFE082);
    final Paint outlinePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.10;
    final Paint glowPaint = Paint()
      ..color = strokeColor.withValues(alpha: 0.26)
      ..style = PaintingStyle.stroke
      ..strokeWidth = outlinePaint.strokeWidth * 1.9
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.8);

    final List<Vector2>? polygon = overlayPolygon;
    if (polygon == null || polygon.length < 3) {
      // TODO: polygon hint가 없는 경우 생기는 흰색 원형 fallback 표시는 없애야 함.
      final double radius = math.max(mergeRadius, spec.radius);
      canvas.drawCircle(Offset.zero, radius, glowPaint);
      canvas.drawCircle(Offset.zero, radius, outlinePaint);
      return;
    }

    final Path path = Path()
      ..moveTo(polygon.first.x, polygon.first.y);
    for (int i = 1; i < polygon.length; i += 1) {
      path.lineTo(polygon[i].x, polygon[i].y);
    }
    path.close();

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, outlinePaint);
  }

  void _attachImageOrFallbackFixtures(Body targetBody, double stageProgress) {
    final List<Vector2>? safe = overlayPolygon;
    if (safe == null || safe.length < 3) {
      _attachCircleFallback(targetBody, stageProgress);
      return;
    }

    try {
      final PolygonShape shape = PolygonShape()..set(safe);
      targetBody.createFixture(
        FixtureDef(shape)
          ..density = _resolvedDensity(stageProgress)
          ..friction = _resolvedFriction(stageProgress)
          ..restitution = 0.0,
      );
    } catch (_) {
      _attachCircleFallback(targetBody, stageProgress);
    }
  }

  void _attachCircleFallback(Body targetBody, double stageProgress) {
    final CircleShape shape = CircleShape()..radius = spec.radius;
    targetBody.createFixture(
      FixtureDef(shape)
        ..density = _resolvedDensity(stageProgress)
        ..friction = _resolvedFriction(stageProgress)
        ..restitution = 0.0,
    );
  }

  double _resolvedDensity(double stageProgress) {
    return (2.8 + (stageProgress * 0.9)) *
        preparedAsset.assetData.densityMultiplier;
  }

  double _resolvedFriction(double stageProgress) {
    return 0.16 + (stageProgress * 0.06);
  }

  Vector2 _spriteWorldSize() {
    return Vector2(halfSize.x * 2, halfSize.y * 2);
  }

  Vector2 _computeHalfSize(double aspect, double diameter) {
    final double safeAspect = aspect <= 0 ? 1.0 : aspect;
    if (safeAspect >= 1.0) {
      final double halfHeight = diameter * 0.5;
      return Vector2(halfHeight * safeAspect, halfHeight);
    }

    final double halfWidth = diameter * 0.5;
    return Vector2(halfWidth, halfWidth / safeAspect);
  }
}
