import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame_forge2d/flame_forge2d.dart' as f2;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'components/boundary_component.dart';
import 'components/falling_polygon_component.dart';
import 'assets/stone_asset_data.dart';
import 'assets/asset_manager.dart';
import 'assets/png_processor.dart';
import 'systems/drag_controller.dart';

/// 돌의 외형 분류를 정의합니다.
enum StoneCategory {
  unstructured, // 비정형 (자연스러운 돌)
  structured,   // 정형 (가공된 모양)
  all,          // 전체
}

/// 고정 스텝 물리 업데이트를 위한 Forge2D 월드 래퍼입니다.
class FixedStepForge2DWorld extends Forge2DWorld {
// ... (중략: FixedStepForge2DWorld 구현은 동일)
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

/// 게임 전체를 조율하는 메인 클래스입니다.
class StackingGame extends Forge2DGame with ScaleDetector {
  StackingGame({
    required List<String> stoneSpriteAssets,
    this.category = StoneCategory.unstructured, // 기본값은 unstructured
    bool debugDrawCollisionShapes = false,
    this.enableImageCollisionHints = false,
  }) : _allAvailableAssets = List<String>.from(stoneSpriteAssets),
       _debugDrawCollisionShapes = debugDrawCollisionShapes,
       super(
         world: FixedStepForge2DWorld(
           fixedStep: 1 / 60,
           maxSubSteps: 6,
           velocityIterations: 8,
           positionIterations: 12,
           gravity: Vector2(0, 50),
         ),
         gravity: Vector2(0, 50),
         zoom: 10,
       );

  final List<String> _allAvailableAssets;
  final StoneCategory category;
  final bool enableImageCollisionHints;
  bool _debugDrawCollisionShapes;
  static const bool _aspectLogEnabled = true;

  /// 현재 카테고리 설정에 따라 필터링된 에셋 목록
  List<String> get stoneSpriteAssets {
    switch (category) {
      case StoneCategory.unstructured:
        return _allAvailableAssets.where((path) => path.contains('/unstructured/')).toList();
      case StoneCategory.structured:
        return _allAvailableAssets.where((path) => path.contains('/structured/')).toList();
      case StoneCategory.all:
        return _allAvailableAssets;
    }
  }

  final math.Random _random = math.Random();
// ... (이하 동일)
  final List<FallingPolygonComponent> _activeStones = [];
  final Map<String, StoneAssetData> _stoneAssetMetadata = {};
  final ValueNotifier<int> activeStoneCount = ValueNotifier(0);

  /// 스폰 중복 방지를 위한 기록 관리
  final Set<String> _spawnHistory = {};
  final PngProcessor _pngProcessor = PngProcessor();

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
  Color backgroundColor() => const Color(0xFFFFFFFF);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // 더 이상 시작 시점에 수백 개를 분석하지 않고, 목록만 인지합니다.
    _assetsPrepared = true;
    _dragController = DragController(
      world: world,
      bodyCandidates: () => world.children
          .whereType<FallingPolygonComponent>()
          .where((stone) => stone.isSelectable)
          .map((stone) => stone.body),
      tuning: const DragTuning(
        pickRadius: 3.2,
        maxForcePerMass: 600,
        frequencyHz: 5.0,
        dampingRatio: 0.9,
        velocityGain: 12.0,
        angularDampingGain: 0.4,
      ),
    );
    await _dragController.initialize();
    _tryInitializeWorld();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (_worldBuilt || size.x <= 0 || size.y <= 0) return;
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

  /// 차집합(Subtraction) 로직을 적용한 새 돌 스폰
  Future<void> _spawnStone({double seedOffset = 0.0}) async {
    if (_worldSize == null || _activeStones.length >= maxActiveStones) return;

    final worldSize = _worldSize!;
    
    // 1. 현재 화면에 있는 에셋 경로 수집
    final currentlyOnScreen = _activeStones.map((s) => s.assetData.assetPath).toSet();

    // 2. 후보군 계산: 전체 풀 - (화면 상의 에셋 + 이번 사이클 사용 기록)
    var candidates = stoneSpriteAssets.where((path) => 
      !currentlyOnScreen.contains(path) && !_spawnHistory.contains(path)
    ).toList();

    // 3. 후보군이 비어있다면 사이클 리셋 (사용 기록 초기화)
    if (candidates.isEmpty) {
      _spawnHistory.clear();
      candidates = stoneSpriteAssets.where((path) => 
        !currentlyOnScreen.contains(path)
      ).toList();
    }

    // 4. 리셋 후에도 비어있다면(모든 에셋이 화면에 있는 경우) 전체에서 무작위 선택
    if (candidates.isEmpty) {
      candidates = List.from(stoneSpriteAssets);
    }

    final selectedPath = candidates[_random.nextInt(candidates.length)];
    _spawnHistory.add(selectedPath);

    // 5. 선택된 에셋의 메타데이터 실시간 로드 및 캐싱 (Lazy Loading)
    if (!_stoneAssetMetadata.containsKey(selectedPath)) {
      final metadata = await _pngProcessor.prepareAssets([selectedPath]);
      if (metadata.containsKey(selectedPath)) {
        _stoneAssetMetadata[selectedPath] = metadata[selectedPath]!;
      }
    }

    final metadata = _stoneAssetMetadata[selectedPath] ?? StoneAssetData(
      assetPath: selectedPath,
      type: StoneAssetType.png,
      aspectRatio: 1.0,
      densityMultiplier: 1.0,
    );

    // 6. 스폰 위치 최적화 (가장 빈 라인 찾기)
    final lanes = <double>[0.20, 0.34, 0.50, 0.66, 0.80]..shuffle(_random);
    final spawnY = 1.0 + seedOffset;
    double bestX = worldSize.x * lanes.first;
    double maxMinDistance = -1.0;

    for (final lane in lanes) {
      final candidateX = worldSize.x * lane + (_random.nextDouble() - 0.5) * 0.9;
      final candidatePos = Vector2(candidateX, spawnY);
      double minDistance = double.infinity;
      for (final stone in _activeStones) {
        if (!stone.isMounted) continue;
        final dist = stone.body.position.distanceTo(candidatePos);
        if (dist < minDistance) minDistance = dist;
      }
      if (minDistance > 8.0) {
        bestX = candidateX;
        break;
      }
      if (minDistance > maxMinDistance) {
        maxMinDistance = minDistance;
        bestX = candidateX;
      }
    }

    final x = bestX;
    final angle = (_random.nextDouble() - 0.5) * (math.pi / 18);
    final baseShape = _basePolygons[_random.nextInt(_basePolygons.length)];
    final fallbackColor = _fallbackColors[_random.nextInt(_fallbackColors.length)];
    final launchVelocity = Vector2((_random.nextDouble() - 0.5) * 0.35, 0.0);
    final sizeScale = (2.05 + _random.nextDouble() * 0.35) * 4.0;

    final stone = FallingPolygonComponent(
      vertices: baseShape,
      fallbackColor: fallbackColor,
      assetData: metadata,
      initialPosition: Vector2(x, spawnY),
      initialAngle: angle,
      initialLinearVelocity: launchVelocity,
      sizeScale: sizeScale,
      strategy: enableImageCollisionHints
          ? CollisionShapeStrategy.autoFromImage
          : CollisionShapeStrategy.circleCompound,
      maxFixturesPerBody: 4,
      debugDrawFixtures: _debugDrawCollisionShapes,
      enableContinuousCollision: true,
      onRemoved: () {
        _activeStones.removeWhere((s) => !s.isMounted);
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
    if (_worldBuilt || !_assetsPrepared || _worldSize == null) return;
    world.add(BoundaryComponent(worldSize: _worldSize!));
    for (var i = 0; i < initialSpawnCount; i++) {
      _spawnStone(seedOffset: i.toDouble());
    }
    _worldBuilt = true;
  }

  // 이제 실시간 분석을 하므로 초기 분석 로직은 사용하지 않거나 최소화할 수 있습니다.
  Future<void> _prepareImageCollisionHints() async {
    // 아무것도 하지 않음 (Lazy Loading으로 대체됨)
  }

  static double _estimateAspectFromBaseShape(List<Vector2> points) {
    var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    for (final point in points) {
      if (point.x < minX) minX = point.x; if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y; if (point.y > maxY) maxY = point.y;
    }
    return (maxX - minX).abs().clamp(0.1, double.infinity) / (maxY - minY).abs().clamp(0.1, double.infinity);
  }

  void _despawnOutOfBoundsStones() {
    if (_worldSize == null) return;
    final maxY = _worldSize!.y + despawnMargin, minX = -despawnMargin, maxX = _worldSize!.x + despawnMargin;
    for (final stone in List<FallingPolygonComponent>.from(_activeStones)) {
      if (!stone.isMounted) { _activeStones.remove(stone); continue; }
      final p = stone.body.position;
      if (p.y > maxY || p.x < minX || p.x > maxX) stone.removeFromParent();
    }
  }

  static const List<Color> _fallbackColors = <Color>[
    Color(0xFF7AA2FF), Color(0xFFFF8A65), Color(0xFF81C784), Color(0xFFFFD54F), Color(0xFFBA68C8),
  ];

  static final List<List<Vector2>> _basePolygons = <List<Vector2>>[
    [Vector2(-0.9, -0.5), Vector2(0.9, -0.5), Vector2(0.9, 0.5), Vector2(-0.9, 0.5)],
    [Vector2(-0.8, -0.6), Vector2(0.8, -0.6), Vector2(1.0, 0.15), Vector2(0.0, 0.85), Vector2(-1.0, 0.15)],
    [Vector2(-0.7, -0.55), Vector2(0.7, -0.55), Vector2(0.95, 0.0), Vector2(0.55, 0.65), Vector2(-0.55, 0.65), Vector2(-0.95, 0.0)],
    [Vector2(-1.0, -0.45), Vector2(0.8, -0.55), Vector2(1.0, 0.45), Vector2(-0.6, 0.65)],
    [Vector2(-0.85, -0.55), Vector2(0.85, -0.55), Vector2(0.75, 0.55), Vector2(-0.75, 0.55)],
  ];
}
