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
import 'components/looping_background_component.dart';
import 'assets/stone_asset_data.dart';
import 'assets/png_processor.dart';
import 'systems/drag_controller.dart';

/// 돌의 외형 분류를 정의합니다.
enum StoneCategory {
  unstructured, // 비정형 (자연스러운 돌)
  structured, // 정형 (가공된 모양)
  all, // 전체
}

/// 고정 스텝 물리 업데이트를 위한 Forge2D 월드 래퍼입니다.
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

/// 게임 전체를 조율하는 메인 클래스입니다.
class StackingGame extends Forge2DGame with PanDetector, ScrollDetector {
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

  /// 현재 카테고리 설정에 따라 필터링된 에셋 목록
  List<String> get stoneSpriteAssets {
    switch (category) {
      case StoneCategory.unstructured:
        return _allAvailableAssets
            .where((path) => path.contains('/unstructured/'))
            .toList();
      case StoneCategory.structured:
        return _allAvailableAssets
            .where((path) => path.contains('/structured/'))
            .toList();
      case StoneCategory.all:
        return _allAvailableAssets;
    }
  }

  final math.Random _random = math.Random();
  final List<FallingPolygonComponent> _activeStones = [];
  final Map<String, StoneAssetData> _stoneAssetMetadata = {};
  final ValueNotifier<int> activeStoneCount = ValueNotifier(0);
  final ValueNotifier<int> towerHeightMeters = ValueNotifier(0);

  /// 스폰 중복 방지를 위한 기록 관리
  final Set<String> _spawnHistory = {};
  final PngProcessor _pngProcessor = PngProcessor();

  static const int maxActiveStones = 36;
  static const double despawnMargin = 15.0;
  static const double spawnInterval = 1.05;
  static const int initialSpawnCount = 5;
  static const bool autoSpawnEnabled = false;
  static const double _initialBottomFocusLockDuration = 4.0;

  bool _worldBuilt = false;
  bool _assetsPrepared = false;
  double _spawnAccumulator = 0.0;
  double _initialBottomFocusLockRemaining = 0.0;
  double _timeSinceStart = 0.0;
  double _lastHeightDisturbanceAt = 0.0;
  bool _heightUpdateLocked = true;
  Vector2? _worldSize;
  late final DragController _dragController;

  /// 안착된(Settled) 돌 중 가장 높은 위치(최솟값 Y)를 상시 추적합니다.
  double _globalTopY = 0.0;
  double _historicalHighestTopY = 0.0;

  // 수동 조작 추적을 위한 변수
  double _autoPushCooldown = 0.0;
  static const double _manualControlLockDuration = 3.0; // 수동 조작 후 3초간 자동 추적 정지
  static const double _cameraStillVelocityThreshold = 0.08;
  static const double _cameraStillAngularThreshold = 0.08;

  // 카메라 설정 비율
  static const double _focusLineRatio = 1 / 2; // 최상단 돌을 화면의 상단 1/2 지점에 배치
  static const double _pushThresholdRatio = 1 / 2; // 돌이 화면의 1/2를 차지하면 카메라 이동 준비
  static const double _topScrollHideMargin = 1.0;
  static const bool _cameraDebugLogEnabled = true;
  static const double _settledVelocityThreshold = 0.8;
  static const double _heightSettleDelaySeconds = 1.0;
  static const double _heightCandidateMinAgeSeconds = 0.7;

  bool get debugDrawCollisionShapes => _debugDrawCollisionShapes;

  @override
  Color backgroundColor() => const Color(0xFFFFFFFF);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _assetsPrepared = true;
    _dragController = DragController(
      world: world,
      bodyCandidates: () => world.children
          .whereType<FallingPolygonComponent>()
          .where((stone) => stone.isSelectable)
          .map((stone) => stone.body),
      tuning: const DragTuning(
        pickRadius: 3.2,
        maxForcePerMass: 1500,
        frequencyHz: 5.0,
        dampingRatio: 0.9,
        velocityGain: 12.0,
        angularDampingGain: 0.4,
        compressionSuppressionPerStone: 0.45,
        maxCompressionSuppression: 0.10,
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
    final zoom = camera.viewfinder.zoom;
    _worldSize = Vector2(size.x / zoom, size.y / zoom);
    camera.moveTo(Vector2(0.0, _cameraBottomLimitY()));
    _globalTopY = _worldSize!.y - BoundaryComponent.floorMarginFromBottom;
    _historicalHighestTopY = _globalTopY;
    _updateTowerHeightMeters();
    _tryInitializeWorld();
  }

  @override
  void onPanStart(DragStartInfo info) {
    _initialBottomFocusLockRemaining = 0.0;
    _autoPushCooldown = _manualControlLockDuration;
    _logCameraDebug(
      'pan-start pos=${info.eventPosition.widget}, cooldown=${_autoPushCooldown.toStringAsFixed(2)}',
    );
    _dragController.startDrag(screenToWorld(info.eventPosition.widget));
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    _autoPushCooldown = _manualControlLockDuration;

    if (_dragController.isDragging) {
      _logCameraDebug(
        'pan-update dragging=true (camera pan skipped), pos=${info.eventPosition.widget}',
      );
      _dragController.updateDrag(screenToWorld(info.eventPosition.widget));
    } else {
      _applyManualCameraPan(delta: info.delta.global, source: 'pan-update');
    }
  }

  @override
  void onScroll(PointerScrollInfo info) {
    _initialBottomFocusLockRemaining = 0.0;
    _autoPushCooldown = _manualControlLockDuration;
    _logCameraDebug(
      'scroll-detected delta=${info.scrollDelta.global}, pos=${info.eventPosition.widget}, dragging=${_dragController.isDragging}',
    );
    if (_dragController.isDragging) {
      _logCameraDebug('scroll-blocked reason=dragging');
      return;
    }
    _applyManualCameraPan(delta: info.scrollDelta.global, source: 'scroll');
  }

  @override
  void onPanEnd(DragEndInfo info) {
    _autoPushCooldown = _manualControlLockDuration;
    _logCameraDebug(
      'pan-end velocity=${info.velocity}, cooldown=${_autoPushCooldown.toStringAsFixed(2)}',
    );
    _dragController.endDrag();
  }

  @override
  void onPanCancel() {
    _autoPushCooldown = _manualControlLockDuration;
    _logCameraDebug(
      'pan-cancel cooldown=${_autoPushCooldown.toStringAsFixed(2)}',
    );
    _dragController.endDrag();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timeSinceStart += dt;
    _dragController.tick();
    _syncActiveStoneCountFromWorld();
    if (!_worldBuilt || _worldSize == null) return;
    if (camera.viewfinder.position.x != 0.0) {
      camera.viewfinder.position = Vector2(0.0, camera.viewfinder.position.y);
    }
    if (_initialBottomFocusLockRemaining > 0) {
      _initialBottomFocusLockRemaining -= dt;
      camera.viewfinder.position = Vector2(0.0, _cameraBottomLimitY());
    }

    _updateGlobalTopY();
    _updateTowerHeightMeters();

    final hasMovingStoneForCamera = _mountedWorldStones().any(
      (stone) =>
          !_dragController.isBodyBeingDragged(stone.body) &&
          (stone.body.linearVelocity.length >= _cameraStillVelocityThreshold ||
              stone.body.angularVelocity.abs() >=
                  _cameraStillAngularThreshold),
    );
    if (_dragController.isDragging || hasMovingStoneForCamera) {
      // 움직임/터치가 감지되면 정지 카운트다운을 즉시 리셋합니다.
      _autoPushCooldown = _manualControlLockDuration;
    } else if (_autoPushCooldown > 0) {
      _autoPushCooldown = math.max(0.0, _autoPushCooldown - dt);
    }

    _handleAutoCameraPush(dt);

    _spawnAccumulator += dt;
    if (autoSpawnEnabled && _spawnAccumulator >= spawnInterval) {
      _spawnAccumulator = 0.0;
      if (_activeStones.length < maxActiveStones) {
        _spawnStone();
      }
    }
    _despawnOutOfBoundsStones();
  }

  /// 최상단 돌 위치에 따라 카메라를 자동으로 밀어올립니다
  void _handleAutoCameraPush(double dt) {
    if (_worldSize == null ||
        _autoPushCooldown > 0 ||
        _dragController.isDragging) {
      _logCameraDebug(
        'auto-push-skipped cooldown=${_autoPushCooldown.toStringAsFixed(2)}, dragging=${_dragController.isDragging}',
      );
      return;
    }

    final currentCamY = camera.viewfinder.position.y;
    final floorY = _worldSize!.y - BoundaryComponent.floorMarginFromBottom;
    final stackHeight = floorY - _globalTopY;

    // 돌이 화면 높이의 2/3 이상 쌓였는지 체크
    if (stackHeight > _worldSize!.y * _pushThresholdRatio) {
      // 최상단이 화면의 1/3 지점에 오도록 목표 설정
      final targetY = _globalTopY - (_worldSize!.y * _focusLineRatio);
      final safeTargetY = math.min(targetY, _cameraBottomLimitY());

      final deltaToTarget = safeTargetY - currentCamY;
      if (deltaToTarget.abs() > 0.01) {
        final nextY = currentCamY + deltaToTarget * 2.0 * dt;
        camera.viewfinder.position = Vector2(
          camera.viewfinder.position.x,
          nextY,
        );
      }
    }
  }

  void _updateGlobalTopY() {
    final stones = _mountedWorldStones().toList(growable: false);
    if (stones.isEmpty) {
      if (_worldSize != null) {
        _globalTopY = _worldSize!.y - BoundaryComponent.floorMarginFromBottom;
        _historicalHighestTopY = _globalTopY;
      }
      return;
    }

    double minY = double.infinity;
    for (final stone in stones) {
      if (_dragController.isBodyBeingDragged(stone.body)) continue;
      final age = _timeSinceStart - stone.spawnedAtSeconds;
      final hasSupportContact =
          stone.isTouchingBoundary || stone.isTouchingStone;
      final isStable =
          stone.body.linearVelocity.length < _settledVelocityThreshold;

      final isCandidate = age >= _heightCandidateMinAgeSeconds &&
          hasSupportContact &&
          isStable;
      // 스폰 직후 공중 물체를 제외하고, 접촉 중이며 안정된 돌만 높이 후보로 사용합니다.
      if (!isCandidate) {
        continue;
      }

      final y = stone.body.position.y;
      if (y < minY) minY = y;
    }

    if (minY == double.infinity) {
      if (_globalTopY == 0.0 && _worldSize != null) {
        _globalTopY = _worldSize!.y - BoundaryComponent.floorMarginFromBottom;
      }
    } else {
      _globalTopY = minY;
      if (_globalTopY < _historicalHighestTopY) {
        _historicalHighestTopY = _globalTopY;
      }
    }

  }

  void _updateTowerHeightMeters() {
    if (_worldSize == null) {
      if (towerHeightMeters.value != 0) {
        towerHeightMeters.value = 0;
      }
      return;
    }
    final stones = _mountedWorldStones().toList(growable: false);
    final hasMovingStone = stones.any(
      (stone) =>
          !_dragController.isBodyBeingDragged(stone.body) &&
          stone.body.linearVelocity.length >= _settledVelocityThreshold,
    );
    if (hasMovingStone) {
      _markHeightDisturbance();
      return;
    }
    if (_heightUpdateLocked) {
      final stableFor = _timeSinceStart - _lastHeightDisturbanceAt;
      if (stableFor < _heightSettleDelaySeconds) {
        return;
      }
      _heightUpdateLocked = false;
    }

    final floorY = _worldSize!.y - BoundaryComponent.floorMarginFromBottom;
    final height = math.max(0.0, floorY - _globalTopY).floor();
    if (towerHeightMeters.value != height) {
      towerHeightMeters.value = height;
    }
  }

  void _markHeightDisturbance() {
    _lastHeightDisturbanceAt = _timeSinceStart;
    _heightUpdateLocked = true;
  }

  void setDebugCollisionRendering(bool enabled) {
    _debugDrawCollisionShapes = enabled;
    for (final stone in _activeStones) {
      stone.debugDrawFixtures = enabled;
    }
  }

  void spawnNow() {
    _autoPushCooldown = _manualControlLockDuration;
    _markHeightDisturbance();
    _spawnStone();
  }

  Future<void> _spawnStone({double seedOffset = 0.0}) async {
    if (_worldSize == null || _activeStones.length >= maxActiveStones) return;

    final worldSize = _worldSize!;
    final currentlyOnScreen = _activeStones
        .map((s) => s.assetData.assetPath)
        .toSet();
    var candidates = stoneSpriteAssets
        .where(
          (path) =>
              !currentlyOnScreen.contains(path) &&
              !_spawnHistory.contains(path),
        )
        .toList();

    if (candidates.isEmpty) {
      _spawnHistory.clear();
      candidates = stoneSpriteAssets
          .where((path) => !currentlyOnScreen.contains(path))
          .toList();
    }

    if (candidates.isEmpty) {
      candidates = List.from(stoneSpriteAssets);
    }

    final selectedPath = candidates[_random.nextInt(candidates.length)];
    _spawnHistory.add(selectedPath);

    if (!_stoneAssetMetadata.containsKey(selectedPath)) {
      final metadata = await _pngProcessor.prepareAssets([selectedPath]);
      if (metadata.containsKey(selectedPath)) {
        _stoneAssetMetadata[selectedPath] = metadata[selectedPath]!;
      }
    }

    final metadata =
        _stoneAssetMetadata[selectedPath] ??
        StoneAssetData(
          assetPath: selectedPath,
          type: StoneAssetType.png,
          aspectRatio: 1.0,
          densityMultiplier: 1.0,
        );

    final lanes = <double>[0.20, 0.34, 0.50, 0.66, 0.80]..shuffle(_random);

    // 스폰 높이: 화면 상단 경계보다 위에서 생성되도록 보장
    final camTopY = camera.viewfinder.position.y;
    final spawnY = camTopY - 10.0 + seedOffset;

    double bestX = worldSize.x * lanes.first;
    double maxMinDistance = -1.0;

    for (final lane in lanes) {
      final candidateX =
          worldSize.x * lane + (_random.nextDouble() - 0.5) * 0.9;
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
    final fallbackColor =
        _fallbackColors[_random.nextInt(_fallbackColors.length)];
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
      spawnedAtSeconds: _timeSinceStart,
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
    final backgroundBottomY =
        _worldSize!.y - BoundaryComponent.floorBaseMarginFromBottom;
    world.add(
      LoopingBackgroundComponent(
        assetPathsInOrder: const <String>[
          'assets/background/1.png',
          'assets/background/2.png',
          'assets/background/3.png',
          'assets/background/4.png',
          'assets/background/5.png',
          'assets/background/6.png',
        ],
        baseBottomY: backgroundBottomY,
        worldWidth: _worldSize!.x,
        bottomOverlayAssetPath: 'assets/background/base.png',
        priority: -1000,
      ),
    );
    world.add(BoundaryComponent(worldSize: _worldSize!));
    _markHeightDisturbance();
    _initialBottomFocusLockRemaining = _initialBottomFocusLockDuration;
    for (var i = 0; i < initialSpawnCount; i++) {
      _spawnStone(seedOffset: i.toDouble());
    }
    _worldBuilt = true;
  }

  static double _estimateAspectFromBaseShape(List<Vector2> points) {
    var minX = double.infinity,
        maxX = -double.infinity,
        minY = double.infinity,
        maxY = -double.infinity;
    for (final point in points) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }
    return (maxX - minX).abs().clamp(0.1, double.infinity) /
        (maxY - minY).abs().clamp(0.1, double.infinity);
  }

  void _despawnOutOfBoundsStones() {
    if (_worldSize == null) return;
    final maxY = _worldSize!.y + despawnMargin,
        minX = -despawnMargin,
        maxX = _worldSize!.x + despawnMargin;
    for (final stone in List<FallingPolygonComponent>.from(_activeStones)) {
      if (!stone.isMounted) {
        _activeStones.remove(stone);
        continue;
      }
      final p = stone.body.position;
      if (p.y > maxY || p.x < minX || p.x > maxX) stone.removeFromParent();
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

  void _applyManualCameraPan({required Vector2 delta, required String source}) {
    if (_worldSize == null) return;
    final beforeX = camera.viewfinder.position.x;
    final beforeY = camera.viewfinder.position.y;
    final zoom = camera.viewfinder.zoom;

    const newX = 0.0;
    var newY = beforeY - delta.y / zoom;

    // 최대 상단 스크롤: 최고 정착 돌이 화면에서 막 사라지는 지점까지만 허용합니다.
    final upperPanLimit =
        _historicalHighestTopY - _worldSize!.y - _topScrollHideMargin;
    final lowerPanLimit = _cameraBottomLimitY();
    newY = newY.clamp(upperPanLimit, lowerPanLimit);

    camera.viewfinder.position = Vector2(newX, newY);

    final afterX = camera.viewfinder.position.x;
    final afterY = camera.viewfinder.position.y;
    final moved =
        (afterX - beforeX).abs() > 1e-6 || (afterY - beforeY).abs() > 1e-6;

    _logCameraDebug(
      '$source manual-pan moved=$moved delta=$delta camBefore=(${beforeX.toStringAsFixed(2)}, ${beforeY.toStringAsFixed(2)}) camAfter=(${afterX.toStringAsFixed(2)}, ${afterY.toStringAsFixed(2)}) yClamp=[${upperPanLimit.toStringAsFixed(2)}, ${lowerPanLimit.toStringAsFixed(2)}] topY=${_globalTopY.toStringAsFixed(2)} peakTopY=${_historicalHighestTopY.toStringAsFixed(2)}',
    );
  }

  double _cameraBottomLimitY() {
    if (_worldSize == null) return 0.0;
    // 카메라 하한은 "기본 마진" 기준으로 유지해,
    // floorSafetyMarginFromBottom 값이 화면상 하단 안전 여백으로 보이게 합니다.
    final floorY = _worldSize!.y - BoundaryComponent.floorBaseMarginFromBottom;
    return floorY - _worldSize!.y;
  }

  void _logCameraDebug(String message) {
    if (!kDebugMode || !_cameraDebugLogEnabled) return;
    debugPrint('[StackCam] $message');
  }

  Iterable<FallingPolygonComponent> _mountedWorldStones() {
    return world.children
        .whereType<FallingPolygonComponent>()
        .where((stone) => stone.isMounted);
  }
}
