import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame_forge2d/flame_forge2d.dart' as f2;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'components/boundary_component.dart';
import 'components/falling_polygon_component.dart';
import 'systems/drag_controller.dart';

class FixedStepForge2DWorld extends Forge2DWorld {
  FixedStepForge2DWorld({
    required this.fixedStep,
    required this.maxSubSteps,
    required this.velocityIterations,
    required this.positionIterations,
    super.gravity,
  });

  final double fixedStep;
  final int maxSubSteps;
  final int velocityIterations;
  final int positionIterations;

  double _accumulator = 0.0;

  @override
  void update(double dt) {
    f2.velocityIterations = velocityIterations;
    f2.positionIterations = positionIterations;

    _accumulator += dt.clamp(0.0, fixedStep * maxSubSteps);
    var steps = 0;
    while (_accumulator >= fixedStep && steps < maxSubSteps) {
      physicsWorld.stepDt(fixedStep);
      _accumulator -= fixedStep;
      steps++;
    }

    if (steps >= maxSubSteps) {
      _accumulator = 0;
    }
  }
}

class StackingGame extends Forge2DGame with ScaleDetector {
  StackingGame({
    required List<String> stoneSpriteAssets,
    bool debugDrawCollisionShapes = false,
    this.enableImageCollisionHints = false,
  }) : stoneSpriteAssets = List<String>.from(stoneSpriteAssets),
       _debugDrawCollisionShapes = debugDrawCollisionShapes,
       super(
         world: FixedStepForge2DWorld(
           fixedStep: 1 / 60,
           maxSubSteps: 6,
           velocityIterations: 8,
           positionIterations: 3,
           gravity: Vector2(0, 13),
         ),
         gravity: Vector2(0, 13),
         zoom: 10,
       );

  final List<String> stoneSpriteAssets;
  final bool enableImageCollisionHints;
  bool _debugDrawCollisionShapes;
  static const bool _aspectLogEnabled = true;

  final math.Random _random = math.Random();
  final List<FallingPolygonComponent> _activeStones = [];
  final Map<String, List<Vector2>> _imageCollisionHints = {};
  final Map<String, double> _imageAspectRatios = {};
  final ValueNotifier<int> activeStoneCount = ValueNotifier(0);

  static const int maxActiveStones = 36;
  static const double despawnMargin = 7.0;
  static const double spawnInterval = 1.05;
  static const int initialSpawnCount = 5;
  static const bool autoSpawnEnabled = false;

  bool _worldBuilt = false;
  bool _assetsPrepared = false;
  double _spawnAccumulator = 0.0;
  Vector2? _worldSize;
  late final DragController _dragController;

  bool get debugDrawCollisionShapes => _debugDrawCollisionShapes;

  @override
  Color backgroundColor() => const Color(0xFFEAF3FF);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await _prepareImageCollisionHints();
    _assetsPrepared = true;
    _dragController = DragController(
      world: world,
      bodyCandidates: () => world.children
          .whereType<FallingPolygonComponent>()
          .where((stone) => stone.isSelectable)
          .map((stone) => stone.body),
      tuning: const DragTuning(
        pickRadius: 3.2,
        maxForcePerMass: 5200,
        frequencyHz: 14.0,
        dampingRatio: 0.96,
        velocityGain: 18.0,
        angularDampingGain: 0.6,
      ),
    );
    await _dragController.initialize();
    _tryInitializeWorld();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    if (_worldBuilt || size.x <= 0 || size.y <= 0) {
      return;
    }

    camera.viewfinder.anchor = Anchor.topLeft;
    camera.moveTo(Vector2.zero());

    final zoom = camera.viewfinder.zoom;
    _worldSize = Vector2(size.x / zoom, size.y / zoom);
    _tryInitializeWorld();
  }

  @override
  void onScaleStart(ScaleStartInfo info) {
    if (info.pointerCount != 1) return;
    _dragController.startDrag(screenToWorld(info.eventPosition.widget));
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    if (info.pointerCount != 1) return;
    _dragController.updateDrag(screenToWorld(info.eventPosition.widget));
  }

  @override
  void onScaleEnd(ScaleEndInfo info) {
    _dragController.endDrag();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _dragController.tick();
    _syncActiveStoneCountFromWorld();

    if (!_worldBuilt || _worldSize == null) return;

    _spawnAccumulator += dt;
    if (autoSpawnEnabled && _spawnAccumulator >= spawnInterval) {
      _spawnAccumulator = 0.0;
      if (_activeStones.length < maxActiveStones) {
        _spawnStone();
      }
    }

    _despawnOutOfBoundsStones();
  }

  void setDebugCollisionRendering(bool enabled) {
    _debugDrawCollisionShapes = enabled;
    for (final stone in _activeStones) {
      stone.debugDrawFixtures = enabled;
    }
  }

  void spawnNow() {
    _spawnStone();
  }

  void resetGame() {
    _dragController.endDrag();
    for (final stone in List<FallingPolygonComponent>.from(_activeStones)) {
      stone.removeFromParent();
    }
    _activeStones.clear();
    _scheduleActiveStoneCountSync();
    for (var i = 0; i < initialSpawnCount; i++) {
      _spawnStone(seedOffset: i.toDouble());
    }
  }

  void _spawnStone({double seedOffset = 0.0}) {
    if (_worldSize == null) return;
    if (_activeStones.length >= maxActiveStones) return;

    final worldSize = _worldSize!;
    const laneXs = <double>[0.20, 0.34, 0.50, 0.66, 0.80];
    final lane = laneXs[_random.nextInt(laneXs.length)];
    final x = worldSize.x * lane + (_random.nextDouble() - 0.5) * 0.9;
    final y = 1.0 + seedOffset;
    final angle = (_random.nextDouble() - 0.5) * (math.pi / 18);

    final baseShape = _basePolygons[_random.nextInt(_basePolygons.length)];
    final spritePath = stoneSpriteAssets.isEmpty
        ? ''
        : stoneSpriteAssets[_random.nextInt(stoneSpriteAssets.length)];
    final imageHint = _imageCollisionHints[spritePath];
    final hasImageAspect = _imageAspectRatios.containsKey(spritePath);
    final imageAspectRatio = hasImageAspect
        ? _imageAspectRatios[spritePath]!
        : _estimateAspectFromBaseShape(baseShape);
    final fallbackColor = _fallbackColors[_random.nextInt(_fallbackColors.length)];
    final launchVelocity = Vector2((_random.nextDouble() - 0.5) * 0.8, 0.0);
    final sizeScale = (2.05 + _random.nextDouble() * 0.35) * 4.0;
    if (_aspectLogEnabled) {
      debugPrint(
        '[ASPECT][SPAWN] sprite="$spritePath" hasImageAspect=$hasImageAspect '
        'aspectUsed=${imageAspectRatio.toStringAsFixed(4)} '
        'sizeScale=${sizeScale.toStringAsFixed(4)} '
        'hintPoints=${imageHint?.length ?? 0}',
      );
    }

    late final FallingPolygonComponent stone;
    stone = FallingPolygonComponent(
      vertices: baseShape,
      fallbackColor: fallbackColor,
      imageAssetPath: spritePath,
      imageAspectRatio: imageAspectRatio,
      initialPosition: Vector2(x, y),
      initialAngle: angle,
      initialLinearVelocity: launchVelocity,
      sizeScale: sizeScale,
      strategy: enableImageCollisionHints
          ? CollisionShapeStrategy.autoFromImage
          : CollisionShapeStrategy.circleCompound,
      imageCollisionHint: imageHint,
      maxFixturesPerBody: 4,
      debugDrawFixtures: debugDrawCollisionShapes,
      enableContinuousCollision: true,
      onRemoved: () {
        _activeStones.remove(stone);
        _scheduleActiveStoneCountSync();
      },
    );

    _activeStones.add(stone);
    world.add(stone);
  }

  void _scheduleActiveStoneCountSync() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final refreshed = _activeStones.length;
      if (activeStoneCount.value != refreshed) {
        activeStoneCount.value = refreshed;
      }
    });
  }

  void _syncActiveStoneCountFromWorld() {
    final count = world.children
        .whereType<FallingPolygonComponent>()
        .where((stone) => stone.isMounted)
        .length;
    if (activeStoneCount.value == count) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final refreshed = world.children
          .whereType<FallingPolygonComponent>()
          .where((stone) => stone.isMounted)
          .length;
      if (activeStoneCount.value != refreshed) {
        activeStoneCount.value = refreshed;
      }
    });
  }

  void _tryInitializeWorld() {
    if (_worldBuilt) return;
    if (!_assetsPrepared) return;
    if (_worldSize == null) return;

    world.add(BoundaryComponent(worldSize: _worldSize!));
    for (var i = 0; i < initialSpawnCount; i++) {
      _spawnStone(seedOffset: i.toDouble());
    }
    _worldBuilt = true;
  }

  Future<void> _prepareImageCollisionHints() async {
    _imageCollisionHints.clear();
    _imageAspectRatios.clear();
    for (final assetPath in stoneSpriteAssets) {
      try {
        final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        final aspect = decoded.width / decoded.height;
        _imageAspectRatios[assetPath] = aspect;
        if (_aspectLogEnabled) {
          debugPrint(
            '[ASPECT][IMAGE] asset="$assetPath" width=${decoded.width} '
            'height=${decoded.height} aspect=${aspect.toStringAsFixed(4)}',
          );
        }
        final hint = _buildCollisionHintFromDecoded(decoded);
        if (hint != null && hint.length >= 3) {
          _imageCollisionHints[assetPath] = hint;
          if (_aspectLogEnabled) {
            debugPrint(
              '[ASPECT][HINT] asset="$assetPath" hintVertices=${hint.length}',
            );
          }
        }
      } catch (_) {}
    }
  }

  List<Vector2>? _buildCollisionHintFromDecoded(img.Image decoded) {
    final opaque = <Vector2>[];
    for (var y = 0; y < decoded.height; y += 2) {
      for (var x = 0; x < decoded.width; x += 2) {
        final p = decoded.getPixel(x, y);
        if (p.a.toInt() > 20) {
          opaque.add(Vector2(x.toDouble(), y.toDouble()));
        }
      }
    }
    if (opaque.length < 12) return null;

    final center = _centroid(opaque);
    final support = <Vector2>[];
    const supportCount = 8;
    for (var i = 0; i < supportCount; i++) {
      final angle = i * (2 * math.pi / supportCount);
      final dir = Vector2(math.cos(angle), math.sin(angle));
      var best = opaque.first;
      var bestDot = (best - center).dot(dir);
      for (var j = 1; j < opaque.length; j++) {
        final candidate = opaque[j];
        final dot = (candidate - center).dot(dir);
        if (dot > bestDot) {
          bestDot = dot;
          best = candidate;
        }
      }
      support.add(best);
    }

    final hull = _convexHull(_dedup(support));
    if (hull.length < 3) return null;

    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final point in hull) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }
    final halfW = ((maxX - minX) * 0.5).clamp(1.0, double.infinity);
    final halfH = ((maxY - minY) * 0.5).clamp(1.0, double.infinity);
    final centerX = (minX + maxX) * 0.5;
    final centerY = (minY + maxY) * 0.5;
    if (_aspectLogEnabled) {
      final hullW = (maxX - minX).abs();
      final hullH = (maxY - minY).abs();
      final hullAspect = hullH <= 1e-6 ? 1.0 : (hullW / hullH);
      debugPrint(
        '[ASPECT][HINT_BOUNDS] hullW=${hullW.toStringAsFixed(2)} '
        'hullH=${hullH.toStringAsFixed(2)} hullAspect=${hullAspect.toStringAsFixed(4)}',
      );
    }

    return hull
        .map(
          (p) => Vector2(
            (p.x - centerX) / halfW,
            (p.y - centerY) / halfH,
          ),
        )
        .toList(growable: false);
  }

  double _estimateAspectFromBaseShape(List<Vector2> points) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final point in points) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }
    final w = (maxX - minX).abs().clamp(0.1, double.infinity);
    final h = (maxY - minY).abs().clamp(0.1, double.infinity);
    final aspect = w / h;
    if (_aspectLogEnabled) {
      debugPrint(
        '[ASPECT][BASE_FALLBACK] width=${w.toStringAsFixed(4)} '
        'height=${h.toStringAsFixed(4)} aspect=${aspect.toStringAsFixed(4)}',
      );
    }
    return aspect;
  }

  Vector2 _centroid(List<Vector2> points) {
    var x = 0.0;
    var y = 0.0;
    for (final p in points) {
      x += p.x;
      y += p.y;
    }
    return Vector2(x / points.length, y / points.length);
  }

  List<Vector2> _dedup(List<Vector2> points) {
    final out = <Vector2>[];
    for (final p in points) {
      if (out.any((q) => q.distanceToSquared(p) < 0.01)) continue;
      out.add(Vector2.copy(p));
    }
    return out;
  }

  List<Vector2> _convexHull(List<Vector2> points) {
    if (points.length <= 2) return points;
    final sorted = points.map(Vector2.copy).toList(growable: true)
      ..sort((a, b) {
        final cx = a.x.compareTo(b.x);
        if (cx != 0) return cx;
        return a.y.compareTo(b.y);
      });

    double cross(Vector2 o, Vector2 a, Vector2 b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    final lower = <Vector2>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <Vector2>[];
    for (var i = sorted.length - 1; i >= 0; i--) {
      final p = sorted[i];
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  void _despawnOutOfBoundsStones() {
    if (_worldSize == null) return;
    final maxY = _worldSize!.y + despawnMargin;
    final minX = -despawnMargin;
    final maxX = _worldSize!.x + despawnMargin;

    for (final stone in List<FallingPolygonComponent>.from(_activeStones)) {
      if (!stone.isMounted) {
        _activeStones.remove(stone);
        continue;
      }
      final p = stone.body.position;
      final out = p.y > maxY || p.x < minX || p.x > maxX;
      if (out) {
        stone.removeFromParent();
      }
    }
  }

  static const List<Color> _fallbackColors = <Color>[
    Color(0xFF7AA2FF),
    Color(0xFFFF8A65),
    Color(0xFF81C784),
    Color(0xFFFFD54F),
    Color(0xFFBA68C8),
  ];

  static final List<List<Vector2>> _basePolygons = <List<Vector2>>[
    [
      Vector2(-0.9, -0.5),
      Vector2(0.9, -0.5),
      Vector2(0.9, 0.5),
      Vector2(-0.9, 0.5),
    ],
    [
      Vector2(-0.8, -0.6),
      Vector2(0.8, -0.6),
      Vector2(1.0, 0.15),
      Vector2(0.0, 0.85),
      Vector2(-1.0, 0.15),
    ],
    [
      Vector2(-0.7, -0.55),
      Vector2(0.7, -0.55),
      Vector2(0.95, 0.0),
      Vector2(0.55, 0.65),
      Vector2(-0.55, 0.65),
      Vector2(-0.95, 0.0),
    ],
    [
      Vector2(-1.0, -0.45),
      Vector2(0.8, -0.55),
      Vector2(1.0, 0.45),
      Vector2(-0.6, 0.65),
    ],
    [
      Vector2(-0.85, -0.55),
      Vector2(0.85, -0.55),
      Vector2(0.75, 0.55),
      Vector2(-0.75, 0.55),
    ],
  ];
}
