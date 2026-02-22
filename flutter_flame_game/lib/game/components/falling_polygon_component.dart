import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

import 'boundary_component.dart';

enum CollisionShapeStrategy {
  circleCompound,
  convexPolygon,
  autoFromImage,
}

/// 떨어지는 돌 1개를 나타내는 엔티티입니다.
///
/// 주요 역할:
/// - 동적 Forge2D 바디 생성
/// - 충돌 fixture 선택 및 부착
/// - 바디 중심 기준 스프라이트 로드/렌더
/// - 경계/돌 접촉 카운트 추적
class FallingPolygonComponent extends BodyComponent with ContactCallbacks {
  FallingPolygonComponent({
    required this.vertices,
    required this.fallbackColor,
    required this.imageAssetPath,
    required this.imageAspectRatio,
    required this.initialPosition,
    required this.initialAngle,
    this.initialLinearVelocity,
    this.sizeScale = 2.1,
    this.densityMultiplier = 1.0,
    this.strategy = CollisionShapeStrategy.circleCompound,
    this.maxFixturesPerBody = 4,
    this.debugDrawFixtures = false,
    this.onRemoved,
    this.enableContinuousCollision = false,
    this.imageCollisionHint,
  });

  final List<Vector2> vertices;
  final Color fallbackColor;
  final String imageAssetPath;
  final double imageAspectRatio;
  final Vector2 initialPosition;
  final double initialAngle;
  final Vector2? initialLinearVelocity;
  final double sizeScale;
  /// 이미지별 무게 배수(1.0이 기본).
  ///
  /// 최종 밀도는 `기본 밀도 * densityMultiplier`로 계산됩니다.
  final double densityMultiplier;
  final CollisionShapeStrategy strategy;
  final int maxFixturesPerBody;
  bool debugDrawFixtures;
  final VoidCallback? onRemoved;
  final bool enableContinuousCollision;
  final List<Vector2>? imageCollisionHint;
  static const bool _aspectLogEnabled = true;
  // 무게감(질량)에 직접 영향: fixture 밀도(density).
  // 같은 크기라면 density를 올릴수록 질량이 증가합니다.
  static const double _stoneDensity = 3.8;
  // 무게감 보조 파라미터: 마찰/탄성.
  // 탄성을 낮추면 튀는 느낌이 줄어 더 묵직하게 보입니다.
  static const double _stoneFriction = 1.0;
  static const double _stoneRestitution = 0.0;

  bool _spriteReady = false;
  int _boundaryContacts = 0;
  int _stoneContacts = 0;

  late final Vector2 _halfSize = _computeHalfSize(imageAspectRatio, sizeScale);
  late final List<Vector2> scaledVertices = _buildScaledVertices(
    vertices,
    _halfSize,
  );

  bool get isTouchingBoundary => _boundaryContacts > 0;
  bool get isTouchingStone => _stoneContacts > 0;
  bool get isSelectable => isMounted && body.bodyType == BodyType.dynamic;

  /// 상위 게임 로직에서 사용하는 "정지 상태" 추정값입니다.
  bool get isSettled {
    if (!isMounted) return false;
    if (!body.isAwake) return true;
    return body.linearVelocity.length2 <= 0.02 && body.angularVelocity.abs() < 0.08;
  }

  double get _resolvedDensity => (_stoneDensity * densityMultiplier).clamp(2.8, 8.0);

  /// 동적 바디를 만들고 `strategy`에 따라 fixture를 부착합니다.
  @override
  Body createBody() {
    if (_aspectLogEnabled) {
      debugPrint(
        '[ASPECT][BODY] image="$imageAssetPath" '
        'inputAspect=${imageAspectRatio.toStringAsFixed(4)} '
        'sizeScale=${sizeScale.toStringAsFixed(4)} '
        'halfSize=(${_halfSize.x.toStringAsFixed(4)},${_halfSize.y.toStringAsFixed(4)}) '
        'spriteSize=(${(_halfSize.x * 2).toStringAsFixed(4)},${(_halfSize.y * 2).toStringAsFixed(4)}) '
        'strategy=${strategy.name}',
      );
    }

    final bodyDef = BodyDef()
      ..type = BodyType.dynamic
      ..position = initialPosition
      ..angle = initialAngle
      ..linearVelocity = initialLinearVelocity ?? Vector2.zero()
      ..allowSleep = true
      // 무게감은 유지하되 낙하가 답답하지 않도록 선형 감쇠를 더 낮춥니다.
      ..angularDamping = 2.4
      ..linearDamping = 0.2
      ..bullet = enableContinuousCollision;

    final body = world.createBody(bodyDef);
    body.userData = this;

    switch (strategy) {
      case CollisionShapeStrategy.circleCompound:
        _attachCircleCompoundFixtures(body);
        break;
      case CollisionShapeStrategy.convexPolygon:
        _attachConvexPolygonFixture(body);
        break;
      case CollisionShapeStrategy.autoFromImage:
        _attachImageOrFallbackFixtures(body);
        break;
    }

    return body;
  }

  /// 스프라이트 이미지를 로드해 시각 자식 `SpriteComponent`로 붙입니다.
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (imageAssetPath.isEmpty) return;

    try {
      // Flame's images loader uses `assets/images/` as prefix in this project.
      // Strip it when the path is already absolute in Flutter asset space.
      final flamePath = imageAssetPath.startsWith('assets/images/')
          ? imageAssetPath.substring('assets/images/'.length)
          : imageAssetPath;
      final image = await game.images.load(flamePath);
      if (_aspectLogEnabled) {
        final loadedAspect =
            image.height == 0 ? 1.0 : image.width / image.height;
        debugPrint(
          '[ASPECT][SPRITE_LOAD] path="$flamePath" '
          'loadedSize=${image.width}x${image.height} '
          'loadedAspect=${loadedAspect.toStringAsFixed(4)} '
          'renderSize=${_spriteWorldSize().x.toStringAsFixed(4)}x${_spriteWorldSize().y.toStringAsFixed(4)}',
        );
      }
      add(
        SpriteComponent(
          sprite: Sprite(image),
          size: _spriteWorldSize(),
          anchor: Anchor.center,
        ),
      );
      _spriteReady = true;
    } catch (_) {
      _spriteReady = false;
    }
  }

  /// 접촉 시작 시 카운트를 올려 빠른 상태 체크에 사용합니다.
  @override
  void beginContact(Object other, Contact contact) {
    if (other is BoundaryComponent) {
      _boundaryContacts++;
    } else if (other is FallingPolygonComponent) {
      _stoneContacts++;
    }
  }

  /// 접촉 종료 시 카운트를 내려 빠른 상태 체크에 사용합니다.
  @override
  void endContact(Object other, Contact contact) {
    if (other is BoundaryComponent) {
      _boundaryContacts = math.max(0, _boundaryContacts - 1);
    } else if (other is FallingPolygonComponent) {
      _stoneContacts = math.max(0, _stoneContacts - 1);
    }
  }

  /// 제거 시 콜백을 게임 상위 소유자에게 전달합니다.
  @override
  void onRemove() {
    onRemoved?.call();
    super.onRemove();
  }

  /// 스프라이트 로드 실패 시 대체 폴리곤을 그립니다.
  @override
  void render(Canvas canvas) {
    if (!_spriteReady && scaledVertices.isNotEmpty) {
      final fillPaint = Paint()
        ..color = fallbackColor
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = const Color(0xFF202020)
        ..strokeWidth = 0.06
        ..style = PaintingStyle.stroke;

      final path = Path()..moveTo(scaledVertices.first.x, scaledVertices.first.y);
      for (var i = 1; i < scaledVertices.length; i++) {
        path.lineTo(scaledVertices[i].x, scaledVertices[i].y);
      }
      path.close();
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }

    if (debugDrawFixtures) {
      _renderFixtureDebug(canvas);
    }
  }

  /// 여러 원 fixture로 돌 형태를 근사합니다.
  void _attachCircleCompoundFixtures(Body targetBody) {
    final size = _spriteWorldSize();
    final width = size.x;
    final height = size.y;

    final longAxisHorizontal = width > height * 1.2;
    final longSize = longAxisHorizontal ? width : height;
    final shortSize = longAxisHorizontal ? height : width;

    var circleCount = longSize / shortSize > 1.8 ? 4 : 3;
    circleCount = circleCount.clamp(2, maxFixturesPerBody);

    final radius = math.max(0.18, shortSize * 0.27);
    final spacing = radius * 1.35;
    final start = -((circleCount - 1) * spacing) / 2;
    if (_aspectLogEnabled) {
      debugPrint(
        '[ASPECT][CIRCLE_FIXTURE] image="$imageAssetPath" '
        'width=${width.toStringAsFixed(4)} height=${height.toStringAsFixed(4)} '
        'longHorizontal=$longAxisHorizontal circles=$circleCount '
        'radius=${radius.toStringAsFixed(4)} spacing=${spacing.toStringAsFixed(4)}',
      );
    }

    for (var i = 0; i < circleCount; i++) {
      final shape = CircleShape()..radius = radius;
      if (longAxisHorizontal) {
        shape.position.setValues(start + i * spacing, 0);
      } else {
        shape.position.setValues(0, start + i * spacing);
      }

      targetBody.createFixture(
        FixtureDef(shape)
          ..density = _resolvedDensity
          ..friction = _stoneFriction
          ..restitution = _stoneRestitution,
      );
    }
  }

  /// 정규화된 꼭짓점으로 볼록 다각형 fixture 1개를 부착합니다.
  void _attachConvexPolygonFixture(Body targetBody) {
    final safe = _toConvexWithin8(scaledVertices);
    final shape = PolygonShape()..set(safe);
    targetBody.createFixture(
      FixtureDef(shape)
        ..density = _resolvedDensity
        ..friction = _stoneFriction
        ..restitution = _stoneRestitution,
    );
  }

  /// 이미지 기반 힌트 다각형을 우선 사용하고 불가하면 fallback합니다.
  void _attachImageOrFallbackFixtures(Body targetBody) {
    final hint = imageCollisionHint;
    if (hint == null || hint.length < 3) {
      if (_aspectLogEnabled) {
        debugPrint(
          '[ASPECT][AUTO_HINT] image="$imageAssetPath" fallback=circle '
          'reason=hint_null_or_small hintLen=${hint?.length ?? 0}',
        );
      }
      _attachCircleCompoundFixtures(targetBody);
      return;
    }
    final scaled = hint
        .map((p) => Vector2(p.x * _halfSize.x, p.y * _halfSize.y))
        .toList(growable: false);
    final safe = _toConvexWithin8(scaled);
    if (safe.length < 3 || safe.length > 8) {
      if (_aspectLogEnabled) {
        debugPrint(
          '[ASPECT][AUTO_HINT] image="$imageAssetPath" fallback=circle '
          'reason=safe_vertices_out_of_range safeLen=${safe.length}',
        );
      }
      _attachCircleCompoundFixtures(targetBody);
      return;
    }
    try {
      final shape = PolygonShape()..set(safe);
      targetBody.createFixture(
        FixtureDef(shape)
          ..density = _resolvedDensity
          ..friction = _stoneFriction
          ..restitution = _stoneRestitution,
      );
      if (_aspectLogEnabled) {
        debugPrint(
          '[ASPECT][AUTO_HINT] image="$imageAssetPath" fixture=polygon '
          'safeLen=${safe.length} halfSize=(${_halfSize.x.toStringAsFixed(4)},${_halfSize.y.toStringAsFixed(4)})',
        );
      }
    } catch (_) {
      if (_aspectLogEnabled) {
        debugPrint(
          '[ASPECT][AUTO_HINT] image="$imageAssetPath" fallback=circle reason=shape_set_exception',
        );
      }
      _attachCircleCompoundFixtures(targetBody);
    }
  }

  /// 다각형 꼭짓점 수를 최대 8개로 줄입니다(Forge2D 제한 대응).
  List<Vector2> _toConvexWithin8(List<Vector2> points) {
    final out = points.map((p) => Vector2.copy(p)).toList(growable: true);
    if (out.length <= 8) return out;

    while (out.length > 8) {
      var minIndex = 0;
      var minLoss = double.infinity;
      for (var i = 0; i < out.length; i++) {
        final prev = out[(i - 1 + out.length) % out.length];
        final curr = out[i];
        final next = out[(i + 1) % out.length];
        final loss = ((prev.x * (curr.y - next.y)) +
                (curr.x * (next.y - prev.y)) +
                (next.x * (prev.y - curr.y)))
            .abs();
        if (loss < minLoss) {
          minLoss = loss;
          minIndex = i;
        }
      }
      out.removeAt(minIndex);
    }
    return out;
  }

  /// 월드 단위 기준 최종 렌더 가로/세로 크기입니다.
  Vector2 _spriteWorldSize() {
    return Vector2(_halfSize.x * 2, _halfSize.y * 2);
  }

  /// 디버그용 fixture 외곽선 렌더입니다.
  void _renderFixtureDebug(Canvas canvas) {
    final debugPaint = Paint()
      ..color = const Color(0xAAFF2E2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.05;

    for (final fixture in body.fixtures) {
      final shape = fixture.shape;
      if (shape is CircleShape) {
        final c = shape.position;
        canvas.drawCircle(Offset(c.x, c.y), shape.radius, debugPaint);
      } else if (shape is PolygonShape) {
        if (shape.vertices.isEmpty) continue;
        final path = Path()..moveTo(shape.vertices.first.x, shape.vertices.first.y);
        for (var i = 1; i < shape.vertices.length; i++) {
          path.lineTo(shape.vertices[i].x, shape.vertices[i].y);
        }
        path.close();
        canvas.drawPath(path, debugPaint);
      }
    }
  }

  /// 종횡비와 스케일 입력으로 반쪽 크기(extents)를 계산합니다.
  static Vector2 _computeHalfSize(double aspect, double scale) {
    final safeAspect = aspect <= 0 ? 1.0 : aspect;
    if (safeAspect >= 1.0) {
      final halfH = scale * 0.5;
      return Vector2(halfH * safeAspect, halfH);
    } else {
      final halfW = scale * 0.5;
      return Vector2(halfW, halfW / safeAspect);
    }
  }

  /// 원본 도형을 정규화한 뒤 목표 반쪽 크기로 스케일합니다.
  static List<Vector2> _buildScaledVertices(
    List<Vector2> source,
    Vector2 halfSize,
  ) {
    if (source.isEmpty) return const <Vector2>[];

    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final point in source) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }

    final centerX = (minX + maxX) * 0.5;
    final centerY = (minY + maxY) * 0.5;
    final invHalfW = 1.0 / math.max(1e-6, (maxX - minX) * 0.5);
    final invHalfH = 1.0 / math.max(1e-6, (maxY - minY) * 0.5);

    return source
        .map(
          (point) => Vector2(
            (point.x - centerX) * invHalfW * halfSize.x,
            (point.y - centerY) * invHalfH * halfSize.y,
          ),
        )
        .toList(growable: false);
  }
}
