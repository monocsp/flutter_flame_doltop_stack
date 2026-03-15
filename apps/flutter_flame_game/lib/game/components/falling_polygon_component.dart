import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame_svg/flame_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../assets/stone_asset_data.dart';
import 'boundary_component.dart';
import 'terrain_floor_component.dart';
import '../../utils/asset_path_resolver.dart';

enum CollisionShapeStrategy { circleCompound, convexPolygon, autoFromImage }

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
    required this.assetData,
    required this.initialPosition,
    required this.initialAngle,
    this.initialLinearVelocity,
    this.sizeScale = 2.1,
    this.strategy = CollisionShapeStrategy.circleCompound,
    this.maxFixturesPerBody = 4,
    this.debugDrawFixtures = false,
    this.onRemoved,
    this.enableContinuousCollision = false,
    required this.spawnedAtSeconds,
    this.isKinematic = false,
  });

  final List<Vector2> vertices;
  final Color fallbackColor;
  final StoneAssetData assetData;
  final Vector2 initialPosition;
  final double initialAngle;
  final Vector2? initialLinearVelocity;
  final double sizeScale;

  final CollisionShapeStrategy strategy;
  final int maxFixturesPerBody;
  bool debugDrawFixtures;
  final VoidCallback? onRemoved;
  final bool enableContinuousCollision;
  final double spawnedAtSeconds;
  final bool isKinematic;

  /// 드래그 후 충돌 추적 모드 여부 (매 beginContact마다 진동 발동)
  bool _trackingImpacts = false;

  /// 충돌 추적 남은 시간 (초)
  double _impactTrackingRemaining = 0.0;

  /// 추적 윈도우 (초)
  static const double _impactTrackingDuration = 2.0;

  /// 충돌 시 호출되는 콜백. 인자는 충돌 순간 속도(impactSpeed).
  void Function(double impactSpeed)? onImpactContact;

  /// 드래그 종료 시 게임에서 호출하여 충돌 추적을 시작합니다.
  void startTrackingImpacts(double currentGameTime) {
    _trackingImpacts = true;
    _impactTrackingRemaining = _impactTrackingDuration;
    _logHaptic('startTrackingImpacts stone="$imageAssetPath"');

    // 이미 접촉 중이면 즉시 진동 발동
    if (isTouchingFloor || isTouchingStone || isTouchingWall) {
      final speed = body.linearVelocity.length;
      _logHaptic('immediate-contact speed=${speed.toStringAsFixed(2)}');
      onImpactContact?.call(speed);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    // 추적 윈도우 만료 체크
    if (_trackingImpacts) {
      _impactTrackingRemaining -= dt;
      if (_impactTrackingRemaining <= 0) {
        _trackingImpacts = false;
        _logHaptic('tracking EXPIRED for "$imageAssetPath"');
      }
    }
  }

  String get imageAssetPath => assetData.assetPath;
  double get imageAspectRatio => assetData.aspectRatio;
  double get densityMultiplier => assetData.densityMultiplier;
  List<Vector2>? get imageCollisionHint => assetData.collisionHint;

  static const bool _aspectLogEnabled = false;
  // 무게감(질량)에 직접 영향: fixture 밀도(density).
  static const double _stoneDensity = 6.0;
  // 현실의 돌처럼 거친 느낌을 주기 위해 마찰력을 대폭 높입니다.
  static const double _stoneFriction = 3.5;
  static const double _stoneRestitution = 0.0;

  bool _visualReady = false;
  int _floorContacts = 0;
  int _wallContacts = 0;
  int _stoneContacts = 0;

  late final Vector2 _halfSize = _computeHalfSize(imageAspectRatio, sizeScale);
  late final List<Vector2> scaledVertices = _buildScaledVertices(
    vertices,
    _halfSize,
  );

  bool get isTouchingFloor => _floorContacts > 0;
  bool get isTouchingWall => _wallContacts > 0;
  bool get isTouchingBoundary => _floorContacts > 0;
  bool get isTouchingStone => _stoneContacts > 0;
  bool get isSelectable => isMounted && body.bodyType == BodyType.dynamic;

  /// 상위 게임 로직에서 사용하는 "정지 상태" 추정값입니다.
  bool get isSettled {
    if (!isMounted) return false;
    if (!body.isAwake) return true;
    return body.linearVelocity.length2 <= 0.02 &&
        body.angularVelocity.abs() < 0.08;
  }

  double get _resolvedDensity =>
      (_stoneDensity * densityMultiplier).clamp(2.8, 12.0);

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
      ..type = isKinematic ? BodyType.kinematic : BodyType.dynamic
      ..position = initialPosition
      ..angle = initialAngle
      ..linearVelocity = initialLinearVelocity ?? Vector2.zero()
      ..allowSleep = true
      // 회전 감쇠는 유지하여 충돌 후 팽이처럼 도는 것을 방지하되,
      // 선형 감쇠는 낮추어(0.1) 공기 저항 없이 빠르게 낙하하게 합니다.
      ..angularDamping = 8.0
      ..linearDamping = 0.1
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

  /// 물리 엔진의 영향을 받도록 동적 바디로 전환합니다.
  void makeDynamic() {
    if (body.bodyType != BodyType.dynamic) {
      body.setType(BodyType.dynamic);
      body.setAwake(true);
    }
  }

  /// 스프라이트(PNG) 혹은 SVG를 로드해 시각 자식 컴포넌트로 붙입니다.
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (imageAssetPath.isEmpty) return;

    try {
      if (assetData.isSvg) {
        Svg? svg;
        Object? lastError;
        for (final candidate in assetPathCandidates(imageAssetPath)) {
          try {
            svg = await Svg.load(candidate);
            break;
          } catch (error) {
            lastError = error;
          }
        }
        if (svg == null) {
          throw lastError ??
              FlutterError('Failed to load svg asset "$imageAssetPath".');
        }
        add(
          SvgComponent(
            svg: svg,
            size: _spriteWorldSize(),
            anchor: Anchor.center,
          ),
        );
        _visualReady = true;
      } else {
        final image = await _loadUiImage(imageAssetPath);
        add(
          SpriteComponent(
            sprite: Sprite(image),
            size: _spriteWorldSize(),
            anchor: Anchor.center,
          ),
        );
        _visualReady = true;
      }
    } catch (e) {
      debugPrint('[FallingPolygonComponent] Failed to load visual asset: $e');
      _visualReady = false;
    }
  }

  Future<ui.Image> _loadUiImage(String assetPath) async {
    return loadUiImageFromAsset(assetPath);
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (other is BoundaryComponent) {
      // 접촉한 fixture가 벽인지 바닥인지 구분합니다.
      final boundaryFixture = contact.fixtureA.body.userData == other
          ? contact.fixtureA
          : contact.fixtureB;
      if (other.wallFixtures.contains(boundaryFixture)) {
        _wallContacts++;
      } else {
        _floorContacts++;
      }
    } else if (other is TerrainFloorComponent) {
      _floorContacts++;
    } else if (other is FallingPolygonComponent) {
      _stoneContacts++;
    }

    // 충돌 추적 중이면 매 충돌마다 진동 콜백 호출
    if (_trackingImpacts && onImpactContact != null) {
      final speed = body.linearVelocity.length;
      _logHaptic('beginContact FIRE speed=${speed.toStringAsFixed(2)}');
      onImpactContact!(speed);
    }
  }

  @override
  void endContact(Object other, Contact contact) {
    if (other is BoundaryComponent) {
      final boundaryFixture = contact.fixtureA.body.userData == other
          ? contact.fixtureA
          : contact.fixtureB;
      if (other.wallFixtures.contains(boundaryFixture)) {
        _wallContacts = math.max(0, _wallContacts - 1);
      } else {
        _floorContacts = math.max(0, _floorContacts - 1);
      }
    } else if (other is TerrainFloorComponent) {
      _floorContacts = math.max(0, _floorContacts - 1);
    } else if (other is FallingPolygonComponent) {
      _stoneContacts = math.max(0, _stoneContacts - 1);
    }
  }

  @override
  void onRemove() {
    onRemoved?.call();
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    if (!_visualReady && scaledVertices.isNotEmpty) {
      final fillPaint = Paint()
        ..color = fallbackColor
        ..style = PaintingStyle.fill;
      final strokePaint = Paint()
        ..color = const Color(0xFF202020)
        ..strokeWidth = 0.06
        ..style = PaintingStyle.stroke;

      final path = Path()
        ..moveTo(scaledVertices.first.x, scaledVertices.first.y);
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
        final loss =
            ((prev.x * (curr.y - next.y)) +
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

  Vector2 _spriteWorldSize() {
    return Vector2(_halfSize.x * 2, _halfSize.y * 2);
  }

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
        final path = Path()
          ..moveTo(shape.vertices.first.x, shape.vertices.first.y);
        for (var i = 1; i < shape.vertices.length; i++) {
          path.lineTo(shape.vertices[i].x, shape.vertices[i].y);
        }
        path.close();
        canvas.drawPath(path, debugPaint);
      }
    }
  }

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

  void _logHaptic(String message) {
    if (!kDebugMode) return;
    debugPrint('[Haptic][Stone] $message');
  }
}
