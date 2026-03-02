import 'dart:async';
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
import 'components/terrain_floor_component.dart';
import 'assets/stone_asset_data.dart';
import 'assets/png_processor.dart';
import 'terrain/terrain_profile_extractor.dart';
import 'systems/drag_controller.dart';
import 'systems/impact_haptic_controller.dart';

enum StoneCategory {
  unstructured, // 비정형 (자연스러운 돌)
  structured, // 정형 (가공된 모양)
  all, // 전체
}

/// 온보딩 진행 상태를 정의합니다.
enum OnboardingState {
  none, // 일반 게임 모드
  intro, // 1단계: 천천히 느껴지는 감각에 집중해 보세요
  selectStone, // 2단계: 첫 번째 돌을 골라볼까요? (여러 돌 스폰 후 대기)
  dragStone, // 3단계: 돌을 쌓을 때 손 끝에 느껴지는 감각... (돌 선택 및 낙하, 드래그 유도)
  stackFinish, // 4단계: 이제부터 돌탑을 차분히 쌓아볼까요? (돌탑 연출 후 완료 대기)
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

class StackingGame extends Forge2DGame with PanDetector, ScrollDetector {
  StackingGame({
    required List<String> stoneSpriteAssets,
    this.category = StoneCategory.unstructured, // 기본값은 unstructured
    bool debugDrawCollisionShapes = false,
    this.enableImageCollisionHints = false,
    this.initialOnboarding = false,
    this.initialSpawnCount = 5,
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
  final bool initialOnboarding;
  final int initialSpawnCount;
  bool _debugDrawCollisionShapes;

  late final ValueNotifier<OnboardingState> onboardingState = ValueNotifier(
    initialOnboarding ? OnboardingState.intro : OnboardingState.none,
  );

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
  final List<String> _onboardingInitialAssets = []; // 온보딩용 랜덤 에셋 저장
  final ValueNotifier<int> activeStoneCount = ValueNotifier(0);
  final ValueNotifier<int> towerHeightMeters = ValueNotifier(0);

  /// 스폰 중복 방지를 위한 기록 관리
  final Set<String> _spawnHistory = {};
  final PngProcessor _pngProcessor = PngProcessor();
  final TerrainProfileExtractor _terrainProfileExtractor =
      const TerrainProfileExtractor();

  static const int maxActiveStones = 36;
  static const double despawnMargin = 15.0;
  static const double spawnInterval = 1.05;
  static const double _initialSpawnInterval = 0.15;
  static const bool autoSpawnEnabled = false;
  static const double _initialBottomFocusLockDuration = 4.0;

  bool _worldBuilt = false;
  bool _worldInitializing = false;
  bool _assetsPrepared = false;
  double _spawnAccumulator = 0.0;
  double _initialSpawnDelayRemaining = 0.0;
  int _pendingInitialSpawnCount = 0;
  double _initialBottomFocusLockRemaining = 0.0;
  double _timeSinceStart = 0.0;
  double _lastHeightDisturbanceAt = 0.0;
  bool _heightUpdateLocked = true;
  Vector2? _worldSize;
  late final DragController _dragController;
  late final ImpactHapticController _impactHaptic = ImpactHapticController();

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
  static const bool _cameraDebugLogEnabled = false;
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
    await _tryInitializeWorld();
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

    unawaited(_tryInitializeWorld());
  }

  void transitionToStep2SelectStone() {
    onboardingState.value = OnboardingState.selectStone;
    _spawnOnboardingSelectionStones();
  }

  Future<void> _spawnOnboardingSelectionStones() async {
    if (_worldSize == null) return;

    final placementData = [
      {
        'path': 'assets/images/unstructured/td_1_11_3.png',
        'uiX': 221.0,
        'uiY': 264.0, // 294 - 30
        'uiW': 168.0,
        'uiH': 129.0,
        'angle': 0.0,
      },
      {
        'path': 'assets/images/unstructured/td_1_33_5.png',
        'uiX': 62.0,
        'uiY': 322.0, // 352 - 30
        'uiW': 140.0,
        'uiH': 80.0,
        'angle': -22.0,
      },
      {
        'path': 'assets/images/unstructured/td_1_30_6.png',
        'uiX': 213.0,
        'uiY': 407.0, // 437 - 30
        'uiW': 163.0,
        'uiH': 156.0,
        'angle': 0.0,
      },
      {
        'path': 'assets/images/unstructured/td_1_9_2.png',
        'uiX': 117.0,
        'uiY': 457.0, // 487 - 30
        'uiW': 101.0,
        'uiH': 126.0,
        'angle': 0.0,
      },
      {
        'path': 'assets/images/unstructured/td_1_15_4.png',
        'uiX': -10.0,
        'uiY': 436.0, // 원래 466이었으므로 이번엔 제외 없이 - 30 적용
        'uiW': 111.0,
        'uiH': 111.0,
        'angle': 0.0,
      },
      {
        'path': 'assets/images/unstructured/td_1_24_7.png',
        'uiX': 0.0,
        'uiY': 581.0, // 예외 유지
        'uiW': 181.0,
        'uiH': 103.0,
        'angle': 28.0,
      },
      {
        'path': 'assets/images/unstructured/td_1_1_1.png',
        'uiX': 209.0,
        'uiY': 561.0, // 예외 유지, 아까 실수로 수정했던 531에서 원복
        'uiW': 210.0,
        'uiH': 120.0,
        'angle': -25.0,
      },
    ];

    _onboardingInitialAssets.clear();
    for (final data in placementData) {
      _onboardingInitialAssets.add(data['path'] as String);
    }

    // UI(OnboardingScreen) 측에 실제로 뽑힌 7개의 돌 에셋 목록을 전달
    onStonesSpawned?.call(List.unmodifiable(_onboardingInitialAssets));

    final worldSize = _worldSize!;
    final ratioX = worldSize.x / 375.0;
    final ratioY = worldSize.y / 812.0;
    final baseY = _cameraBottomLimitY();

    for (int i = 0; i < placementData.length; i++) {
      final data = placementData[i];
      final path = data['path'] as String;
      final uiX = data['uiX'] as double;
      final uiY = data['uiY'] as double;
      final uiW = data['uiW'] as double;
      final uiH = data['uiH'] as double;
      final degrees = data['angle'] as double;

      if (!_stoneAssetMetadata.containsKey(path)) {
        final metadata = await _pngProcessor.prepareAssets([path]);
        if (metadata.containsKey(path)) {
          _stoneAssetMetadata[path] = metadata[path]!;
        }
      }

      final aspect = uiW / uiH;
      final metadata =
          _stoneAssetMetadata[path] ??
          StoneAssetData(
            assetPath: path,
            type: StoneAssetType.png,
            aspectRatio: aspect,
            densityMultiplier: 1.0,
          );

      // 화면상에 유저가 지정한 좌상단 좌표(uiX, uiY)를 Center 좌표로 보정
      final centerXUi = uiX + uiW / 2;
      final centerYUi = uiY + uiH / 2;

      final cx = centerXUi * ratioX;
      final cy = baseY + (centerYUi * ratioY);

      // Flame 내에서의 물리적 크기 보정 (비율 왜곡 방지를 위해 ratioX로 통일)
      final worldW = uiW * ratioX;
      final worldH = uiH * ratioX;
      final sizeScale = (aspect >= 1.0) ? worldH : worldW;

      final angle = degrees * (math.pi / 180.0); // degree(각도) -> radian(라디안) 변환

      final fallbackColor =
          _fallbackColors[_random.nextInt(_fallbackColors.length)];
      final baseShape = _basePolygons[_random.nextInt(_basePolygons.length)];

      final stone = FallingPolygonComponent(
        vertices: baseShape,
        fallbackColor: fallbackColor,
        assetData: metadata,
        initialPosition: Vector2(cx, cy),
        initialAngle: angle,
        initialLinearVelocity: Vector2.zero(),
        sizeScale: sizeScale,
        strategy: enableImageCollisionHints
            ? CollisionShapeStrategy.autoFromImage
            : CollisionShapeStrategy.circleCompound,
        maxFixturesPerBody: 4,
        debugDrawFixtures: _debugDrawCollisionShapes,
        enableContinuousCollision: true,
        spawnedAtSeconds: _timeSinceStart,
        isKinematic: true, // 중력 무시
        onRemoved: () {
          _activeStones.removeWhere((s) => !s.isMounted);
          _scheduleActiveStoneCountSync();
        },
      );

      _activeStones.add(stone);
      world.add(stone);
    }
  }

  void _onOnboardingStoneSelected(Body body) {
    HapticFeedback.lightImpact();
    // 선택된 돌 찾기
    final selectedStone = _activeStones.firstWhere((s) => s.body == body);

    // 나머지 삭제
    for (final stone in List.from(_activeStones)) {
      if (stone != selectedStone) {
        stone.removeFromParent();
        _activeStones.remove(stone);
      }
    }
    _scheduleActiveStoneCountSync();

    // 선택된 돌을 dynamic으로 변경하여 중력 반영
    selectedStone.makeDynamic();

    // 상태를 dragStone(3단계)으로 전환
    onboardingState.value = OnboardingState.dragStone;

    // 콜백이 있다면 실행 (Flutter UI 전환용)
    onStoneSelected?.call(selectedStone.assetData.assetPath);
  }

  /// 온보딩 중 처음 7개의 돌이 스폰되었을 때 UI에 목록을 알려주기 위한 콜백
  Function(List<String>)? onStonesSpawned;

  /// 온보딩 중 돌을 선택했을 때 Flutter UI로 신호를 보내기 위한 콜백
  Function(String)? onStoneSelected;

  void transitionToStep4StackFinish() async {
    onboardingState.value = OnboardingState.stackFinish;
    HapticFeedback.lightImpact();

    if (_worldSize == null) return;

    // 기존 돌 모두 제거 후 중앙 정렬로 다시 스폰 (4단계 연출)
    for (final stone in List.from(_activeStones)) {
      stone.removeFromParent();
    }
    _activeStones.clear();

    final zoom = camera.viewfinder.zoom;
    // safeArea를 대략 무시한 디바이스 상단에서 273 픽셀 위치를 월드 좌표로 변환
    final startYWidget = 273.0;
    final startYWorld = camera.viewfinder.position.y + (startYWidget / zoom);

    final centerX = _worldSize!.x / 2;

    // 3개 정도 돌출
    final stackAssets = _onboardingInitialAssets.take(3).toList();

    double currentY = startYWorld;
    for (int i = 0; i < stackAssets.length; i++) {
      final path = stackAssets[i];
      final metadata =
          _stoneAssetMetadata[path] ??
          StoneAssetData(
            assetPath: path,
            type: StoneAssetType.png,
            aspectRatio: 1.0,
            densityMultiplier: 1.0,
          );

      final angle = (_random.nextDouble() * 10 - 5) * (math.pi / 180);
      final fallbackColor =
          _fallbackColors[_random.nextInt(_fallbackColors.length)];
      final baseShape = _basePolygons[_random.nextInt(_basePolygons.length)];

      final sizeScale = 8.0 + (i * 1.5); // 아래로 갈수록 조금 더 크게

      final stone = FallingPolygonComponent(
        vertices: baseShape,
        fallbackColor: fallbackColor,
        assetData: metadata,
        initialPosition: Vector2(centerX, currentY),
        initialAngle: angle,
        initialLinearVelocity: Vector2.zero(),
        sizeScale: sizeScale,
        strategy: enableImageCollisionHints
            ? CollisionShapeStrategy.autoFromImage
            : CollisionShapeStrategy.circleCompound,
        maxFixturesPerBody: 4,
        debugDrawFixtures: _debugDrawCollisionShapes,
        enableContinuousCollision: true,
        spawnedAtSeconds: _timeSinceStart,
        isKinematic: true, // 공중에 고정
        onRemoved: () {},
      );

      _activeStones.add(stone);
      world.add(stone);

      currentY += 12.0; // 돌 간의 대략적인 간격
    }
  }

  void completeOnboarding() {
    onboardingState.value = OnboardingState.none;
    HapticFeedback.heavyImpact();
    // 온보딩 자산 정리 후 게임 시작
    for (final stone in List.from(_activeStones)) {
      stone.makeDynamic(); // 떨어지도록 설정
    }
    // 온보딩 중 잠겼던 생성/조작 로직 재개 (원점)
  }

  @override
  void onPanStart(DragStartInfo info) {
    if (onboardingState.value == OnboardingState.selectStone) {
      final point = screenToWorld(info.eventPosition.widget);
      Body? selectedBody;
      var bestDistance = double.infinity;
      for (final stone in _activeStones) {
        if (!stone.isMounted || stone.body.bodyType != BodyType.kinematic) {
          continue;
        }
        final distance = stone.body.position.distanceToSquared(point);
        final touched = stone.body.fixtures.any(
          (fixture) => fixture.testPoint(point),
        );
        if (touched && distance < bestDistance) {
          bestDistance = distance;
          selectedBody = stone.body;
        }
      }

      if (selectedBody != null) {
        _onOnboardingStoneSelected(selectedBody);
      }
      return;
    }

    if (onboardingState.value == OnboardingState.stackFinish ||
        onboardingState.value == OnboardingState.intro) {
      return; // 조작 무시
    }

    _initialBottomFocusLockRemaining = 0.0;
    _autoPushCooldown = _manualControlLockDuration;
    _logCameraDebug(
      'pan-start pos=${info.eventPosition.widget}, cooldown=${_autoPushCooldown.toStringAsFixed(2)}',
    );
    _dragController.startDrag(screenToWorld(info.eventPosition.widget));
    if (_dragController.isDragging) {
      _impactHaptic.onDragStart();
    }
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
    debugPrint('[Haptic] onPanEnd isDragging=${_dragController.isDragging}');
    _dragController.endDrag();
    _markLastDraggedForImpact();
  }

  @override
  void onPanCancel() {
    _autoPushCooldown = _manualControlLockDuration;
    _logCameraDebug(
      'pan-cancel cooldown=${_autoPushCooldown.toStringAsFixed(2)}',
    );
    _dragController.endDrag();
    _markLastDraggedForImpact();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (onboardingState.value == OnboardingState.stackFinish ||
        onboardingState.value == OnboardingState.selectStone ||
        onboardingState.value == OnboardingState.intro) {
      // 카메라 업데이트, 스폰 정지
      _dragController.tick();
      return;
    }

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
              stone.body.angularVelocity.abs() >= _cameraStillAngularThreshold),
    );
    if (_dragController.isDragging || hasMovingStoneForCamera) {
      // 움직임/터치가 감지되면 정지 카운트다운을 즉시 리셋합니다.
      _autoPushCooldown = _manualControlLockDuration;
    } else if (_autoPushCooldown > 0) {
      _autoPushCooldown = math.max(0.0, _autoPushCooldown - dt);
    }

    _handleAutoCameraPush(dt);

    _spawnAccumulator += dt;
    if (_pendingInitialSpawnCount > 0) {
      _initialSpawnDelayRemaining -= dt;
      while (_pendingInitialSpawnCount > 0 &&
          _initialSpawnDelayRemaining <= 0) {
        _spawnStone(
          seedOffset: (initialSpawnCount - _pendingInitialSpawnCount)
              .toDouble(),
        );
        _pendingInitialSpawnCount--;
        _initialSpawnDelayRemaining += _initialSpawnInterval;
      }
    }
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

      final isCandidate =
          age >= _heightCandidateMinAgeSeconds && hasSupportContact && isStable;
      // 스폰 직후 공중 물체를 제외하고, 접촉 중이며 안정된 돌만 높이 후보로 사용합니다.
      if (!isCandidate) {
        continue;
      }

      // 바디 중심이 아닌 AABB 상단(가장 높은 지점)을 사용하여
      // 돌 크기에 관계없이 실제 최상단 위치를 정확히 측정합니다.
      double stoneTopY = stone.body.position.y;
      final aabb = AABB();
      for (final fixture in stone.body.fixtures) {
        fixture.shape.computeAABB(aabb, stone.body.transform, 0);
        if (aabb.lowerBound.y < stoneTopY) {
          stoneTopY = aabb.lowerBound.y;
        }
      }
      if (stoneTopY < minY) minY = stoneTopY;
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

  /// 마지막으로 드래그했던 돌의 충돌 추적을 시작합니다.
  /// endDrag() 호출 후에 호출해야 합니다 (lastDraggedBody가 설정된 후).
  void _markLastDraggedForImpact() {
    final lastBody = _dragController.lastDraggedBody;
    if (lastBody == null) {
      debugPrint(
        '[Haptic] _markLastDraggedForImpact SKIP: lastDraggedBody is null',
      );
      return;
    }
    // DragController와 동일하게 world.children에서 직접 검색합니다.
    for (final stone in world.children.whereType<FallingPolygonComponent>()) {
      if (!stone.isMounted) continue;
      if (identical(stone.body, lastBody)) {
        // onImpactContact가 설정되지 않은 경우 안전하게 설정
        stone.onImpactContact ??= (speed) => _impactHaptic.onImpact(speed);
        stone.startTrackingImpacts(_timeSinceStart);
        return;
      }
    }
    debugPrint(
      '[Haptic] _markLastDraggedForImpact FAIL: stone not found in world',
    );
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
    stone.onImpactContact = (speed) => _impactHaptic.onImpact(speed);

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

  Future<void> _tryInitializeWorld() async {
    if (_worldBuilt ||
        _worldInitializing ||
        !_assetsPrepared ||
        _worldSize == null) {
      return;
    }
    _worldInitializing = true;
    final backgroundBottomY =
        _worldSize!.y - BoundaryComponent.floorBaseMarginFromBottom;
    try {
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

      var curvedFloorAdded = false;
      try {
        final profile = await _terrainProfileExtractor
            .extractTopSilhouetteFromAsset(
              assetPath: 'assets/background/base.png',
              worldWidth: _worldSize!.x,
              baseBottomY: backgroundBottomY,
            );
        if (profile != null && profile.worldPoints.length >= 2) {
          world.add(TerrainFloorComponent(profile: profile));
          curvedFloorAdded = true;
        }
      } catch (e) {
        debugPrint('[TerrainFloor] failed to extract terrain from image: $e');
      }
      world.add(
        BoundaryComponent(
          worldSize: _worldSize!,
          includeFloor: !curvedFloorAdded,
        ),
      );
      _markHeightDisturbance();
      _initialBottomFocusLockRemaining = _initialBottomFocusLockDuration;
      _pendingInitialSpawnCount = initialSpawnCount;
      _initialSpawnDelayRemaining = 0.0;
      _worldBuilt = true;
    } finally {
      _worldInitializing = false;
    }
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
    return world.children.whereType<FallingPolygonComponent>().where(
      (stone) => stone.isMounted,
    );
  }
}
