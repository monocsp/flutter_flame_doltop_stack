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
  final CollisionShapeStrategy strategy;
  final int maxFixturesPerBody;
  bool debugDrawFixtures;
  final VoidCallback? onRemoved;
  final bool enableContinuousCollision;
  final List<Vector2>? imageCollisionHint;
  static const bool _aspectLogEnabled = true;

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
  bool get isSettled {
    if (!isMounted) return false;
    if (!body.isAwake) return true;
    return body.linearVelocity.length2 <= 0.02 && body.angularVelocity.abs() < 0.08;
  }

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
      ..angularDamping = 1.2
      ..linearDamping = 0.55
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

  @override
  void beginContact(Object other, Contact contact) {
    if (other is BoundaryComponent) {
      _boundaryContacts++;
    } else if (other is FallingPolygonComponent) {
      _stoneContacts++;
    }
  }

  @override
  void endContact(Object other, Contact contact) {
    if (other is BoundaryComponent) {
      _boundaryContacts = math.max(0, _boundaryContacts - 1);
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
          ..density = 0.9
          ..friction = 0.88
          ..restitution = 0.01,
      );
    }
  }

  void _attachConvexPolygonFixture(Body targetBody) {
    final safe = _toConvexWithin8(scaledVertices);
    final shape = PolygonShape()..set(safe);
    targetBody.createFixture(
      FixtureDef(shape)
        ..density = 0.9
        ..friction = 0.85
        ..restitution = 0.01,
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
          ..density = 0.9
          ..friction = 0.85
          ..restitution = 0.01,
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
        final path = Path()..moveTo(shape.vertices.first.x, shape.vertices.first.y);
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
}
