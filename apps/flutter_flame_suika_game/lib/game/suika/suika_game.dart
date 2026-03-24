import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flame_forge2d/flame_forge2d.dart' as f2;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_flame_game_2/game/suika/prepared_suika_assets.dart';
import 'package:flutter_flame_game_2/game/suika/stone_spec.dart';
import 'package:flutter_flame_game_2/game/suika/suika_hud_state.dart';
import 'package:flutter_flame_game_2/game/suika/suika_stone_body.dart';

/// 적층 안정성을 위해 고정 스텝으로 Forge2D를 구동합니다.
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
      _accumulator = 0.0;
    }
  }
}

/// Suika 규칙에 맞는 드롭, 합체, 게임오버 루프를 제공합니다.
class SuikaGame extends Forge2DGame with HasCollisionDetection, TapCallbacks {
  static const double boardWidthUnits = 10.2;
  static const double boardHeightUnits = 16.4;
  static const double boardAspectRatio = boardWidthUnits / boardHeightUnits;
  static const double comboStartSeconds = 5;
  static const double comboMaxSeconds = 10;
  static const double comboWarmupWindowSeconds = 1.8;
  static final Vector2 worldGravity = Vector2(0, 36);

  /// HUD 상태와 보드 크기를 받아 게임 세션을 초기화합니다.
  SuikaGame({
    required this.hudState,
    required this.boardWidth,
    required this.boardHeight,
    required this.preparedAssets,
  }) : stoneCatalog = preparedAssets.catalog,
       super(
         world: FixedStepForge2DWorld(
           fixedStep: 1 / 60,
           maxSubSteps: 6,
           velocityIterations: 10,
           positionIterations: 14,
           gravity: worldGravity,
         ),
         gravity: worldGravity,
         zoom: 1,
       );

  /// Flutter HUD와 공유할 상태 객체입니다.
  final SuikaHudState hudState;

  /// 월드 기준 가로 크기입니다.
  final double boardWidth;

  /// 월드 기준 세로 크기입니다.
  final double boardHeight;

  /// 현재 세션의 9단계 스톤 카탈로그입니다.
  final List<StoneSpec> stoneCatalog;

  /// 시작 전에 준비된 스톤 이미지/메타데이터 캐시입니다.
  final PreparedSuikaAssets preparedAssets;

  /// 화면 상단 위험선 높이를 반환합니다.
  double get dangerLineY => 2.25;

  /// 실제 스톤이 스폰되는 높이를 반환합니다.
  double get spawnY => 1.4;

  /// 현재 선택된 드롭 위치입니다.
  double spawnX = 5;

  /// 게임 내 누적 시간을 보관합니다.
  double elapsedTime = 0;

  /// 최근 danger 상태 누적 시간을 보관합니다.
  double dangerAccumulated = 0;

  /// 드롭 후 연속 스폰을 막기 위한 짧은 쿨다운입니다.
  double dropCooldown = 0;

  /// 현재 점수입니다.
  int score = 0;

  /// 아직 정산되지 않은 콤보 보너스입니다.
  int pendingComboBonus = 0;

  /// 세션 동안 콤보로 획득한 총 점수입니다.
  int totalComboEarnedScore = 0;

  /// 세션 동안 콤보가 유지된 누적 시간입니다.
  double totalComboActiveDurationSeconds = 0;

  /// 게임오버 플래그입니다.
  bool isGameOver = false;

  /// 게임오버 후 남은 돌 정산이 진행 중인지 여부입니다.
  bool isClearBonusResolving = false;

  /// 게임오버 후 클리어 보너스로 누적된 점수입니다.
  int clearBonusScore = 0;

  bool skipClearBonusRequested = false;
  int lastGameOverTapAtMs = 0;

  /// 다음 스톤 큐입니다.
  late StoneSpec currentStone;

  /// HUD 미리보기에 보여줄 다음 스톤입니다.
  late StoneSpec nextStone;

  final Random random = Random();
  late final List<StoneSpec> droppableCatalog = stoneCatalog
      .where((StoneSpec spec) => spec.isDroppable)
      .toList(growable: false);
  final Map<String, double> contactDurations = <String, double>{};
  final Set<String> activeContactKeys = <String>{};
  final List<MergePair> pendingMerges = <MergePair>[];
  final Set<int> lockedStoneIds = <int>{};

  double comboRemainingSeconds = 0;
  double comboWarmupElapsedSeconds = double.infinity;
  int comboWarmupCount = 0;
  int comboHighestMergeValue = 0;
  int comboWarmupHighestMergeValue = 0;
  int stoneSequence = 0;

  /// 월드 경계와 초기 큐를 생성합니다.
  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    camera.viewfinder.position = Vector2.zero();
    await add(ScreenHitbox());
    await addAll(<Component>[
      BoundsBody(boardWidth: boardWidth, boardHeight: boardHeight),
      DangerLineComponent(boardWidth: boardWidth, dangerLineY: dangerLineY),
    ]);
    currentStone = pickRandomDroppableStone();
    nextStone = pickRandomDroppableStone();
    hudState.revealStone(currentStone);
    hudState.revealStone(nextStone);
    hudState.setNextStone(nextStone);
    spawnX = boardWidth / 2;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) {
      return;
    }
    camera.viewfinder.zoom = min(size.x / boardWidth, size.y / boardHeight);
  }

  /// 입력 좌표를 월드 스포너 위치로 변환합니다.
  void moveSpawnerByRatio(double ratio) {
    if (isGameOver || paused) {
      return;
    }
    final double horizontalPadding = currentStone.radius + 0.45;
    final double minX = horizontalPadding;
    final double maxX = boardWidth - horizontalPadding;
    spawnX = minX + (maxX - minX) * ratio.clamp(0, 1);
  }

  /// 현재 선택 스톤을 낙하시켜 다음 큐를 진행합니다.
  void dropCurrentStone() {
    if (isGameOver || paused) {
      return;
    }
    if (dropCooldown > 0) {
      return;
    }
    final SuikaStoneBody stone = createStoneBody(
      spec: currentStone,
      position: Vector2(spawnX, spawnY),
    );
    world.add(stone);
    currentStone = nextStone;
    nextStone = pickRandomDroppableStone();
    hudState.setNextStone(nextStone);
    dropCooldown = 0.22;
  }

  /// 일시정지 상태를 토글해 HUD와 동기화합니다.
  void togglePause() {
    if (isGameOver) {
      return;
    }
    if (paused) {
      resumeEngine();
      hudState.setPaused(false);
      return;
    }
    pauseEngine();
    hudState.setPaused(true);
  }

  /// 두 스톤의 접촉 시작을 안정 합체 후보로 기록합니다.
  void registerContactStart(SuikaStoneBody first, SuikaStoneBody second) {
    if (!canTrackMergeContact(first, second)) {
      return;
    }
    final String key = pairKey(first.id, second.id);
    activeContactKeys.add(key);
    contactDurations.putIfAbsent(key, () => 0);
  }

  /// 두 스톤의 접촉 종료를 추적 상태에서 제거합니다.
  void registerContactEnd(SuikaStoneBody first, SuikaStoneBody second) {
    final String key = pairKey(first.id, second.id);
    activeContactKeys.remove(key);
    contactDurations.remove(key);
  }

  /// 게임 루프에서 합체 큐와 danger 판정을 순차적으로 처리합니다.
  @override
  void update(double dt) {
    if (paused) {
      super.update(dt);
      return;
    }
    if (isGameOver) {
      super.update(dt);
      return;
    }
    elapsedTime += dt;
    dropCooldown = max(0, dropCooldown - dt);
    advanceContactTimers(dt);
    resolvePendingMerges();
    updateComboState(dt);
    updateDangerState(dt);
    super.update(dt);
  }

  /// 보드 상단의 스포너와 프레임을 화면에 그립니다.
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    renderSpawnerGuide(canvas);
  }

  /// 현재 보드의 충돌 중 같은 단계 쌍만 합체 후보로 인정합니다.
  bool isMergeCandidate(SuikaStoneBody first, SuikaStoneBody second) {
    if (first.spec.stage != second.spec.stage) {
      return false;
    }
    if (StoneCatalog.nextOf(first.spec, stoneCatalog) == null) {
      return false;
    }
    if (lockedStoneIds.contains(first.id) ||
        lockedStoneIds.contains(second.id)) {
      return false;
    }
    if (first.isQueuedForMerge || second.isQueuedForMerge) {
      return false;
    }
    if (!first.isMounted || !second.isMounted) {
      return false;
    }
    return true;
  }

  /// 접촉 시간이 기준을 넘긴 쌍을 다음 틱 합체 큐로 옮깁니다.
  void advanceContactTimers(double _) {
    final List<SuikaStoneBody> stones = world.children
        .query<SuikaStoneBody>()
        .where((SuikaStoneBody stone) => stone.isMounted)
        .toList(growable: false);
    final Set<String> touchingKeys = <String>{...activeContactKeys};

    for (final SuikaStoneBody stone in stones) {
      stone.contactIndicator = StoneContactIndicator.none;
    }

    for (int i = 0; i < stones.length; i += 1) {
      final SuikaStoneBody first = stones[i];
      for (int j = i + 1; j < stones.length; j += 1) {
        final SuikaStoneBody second = stones[j];
        if (!areStonesVisuallyTouching(first, second)) {
          continue;
        }

        if (first.contactIndicator == StoneContactIndicator.none) {
          first.contactIndicator = StoneContactIndicator.touching;
        }
        if (second.contactIndicator == StoneContactIndicator.none) {
          second.contactIndicator = StoneContactIndicator.touching;
        }

        if (!canTrackMergeContact(first, second)) {
          continue;
        }

        first.contactIndicator = StoneContactIndicator.mergeReady;
        second.contactIndicator = StoneContactIndicator.mergeReady;
        touchingKeys.add(pairKey(first.id, second.id));
      }
    }

    final List<String> readyKeys = <String>[];
    for (final String key in touchingKeys) {
      final MergePair? pair = resolvePairForKey(key);
      if (pair == null) {
        activeContactKeys.remove(key);
        contactDurations.remove(key);
        continue;
      }
      readyKeys.add(key);
    }
    contactDurations.removeWhere((String key, double value) {
      return !touchingKeys.contains(key);
    });

    for (final String key in readyKeys) {
      final MergePair? pair = resolvePairForKey(key);
      if (pair == null) {
        continue;
      }
      queueMerge(pair);
      activeContactKeys.remove(key);
      contactDurations.remove(key);
    }
  }

  /// 합체용 접촉 추적을 시작해도 되는 기본 조건만 확인합니다.
  bool canTrackMergeContact(SuikaStoneBody first, SuikaStoneBody second) {
    if (first.spec.stage != second.spec.stage) {
      return false;
    }
    if (StoneCatalog.nextOf(first.spec, stoneCatalog) == null) {
      return false;
    }
    if (!first.isMounted || !second.isMounted) {
      return false;
    }
    return true;
  }

  /// 스프라이트 외곽 기준으로도 서로 닿아 보이는지 검사합니다.
  bool areStonesVisuallyTouching(SuikaStoneBody first, SuikaStoneBody second) {
    final double distance = first.body.position.distanceTo(
      second.body.position,
    );
    final double mergeDistance = first.mergeRadius + second.mergeRadius;
    return distance <= mergeDistance;
  }

  /// 실제 월드 상태를 조회해 합체 가능한 바디 쌍을 복원합니다.
  MergePair? resolvePairForKey(String key) {
    final List<String> segments = key.split(':');
    if (segments.length != 2) {
      return null;
    }
    final int? firstId = int.tryParse(segments.first);
    final int? secondId = int.tryParse(segments.last);
    if (firstId == null || secondId == null) {
      return null;
    }
    SuikaStoneBody? firstStone;
    SuikaStoneBody? secondStone;
    for (final SuikaStoneBody stone in world.children.query<SuikaStoneBody>()) {
      if (stone.id == firstId) {
        firstStone = stone;
      }
      if (stone.id == secondId) {
        secondStone = stone;
      }
    }
    if (firstStone == null || secondStone == null) {
      return null;
    }
    if (!isMergeCandidate(firstStone, secondStone)) {
      return null;
    }
    return MergePair(first: firstStone, second: secondStone);
  }

  /// 같은 프레임에 중복 합체가 생기지 않도록 큐로 보냅니다.
  void queueMerge(MergePair pair) {
    pair.first.isQueuedForMerge = true;
    pair.second.isQueuedForMerge = true;
    lockedStoneIds.add(pair.first.id);
    lockedStoneIds.add(pair.second.id);
    pendingMerges.add(pair);
  }

  /// 큐에 담긴 합체를 안전한 시점에 제거와 생성으로 치환합니다.
  void resolvePendingMerges() {
    if (pendingMerges.isEmpty) {
      return;
    }
    final List<MergePair> mergeSnapshot = List<MergePair>.from(pendingMerges);
    mergeSnapshot.sort(
      (MergePair first, MergePair second) =>
          second.first.spec.stage.compareTo(first.first.spec.stage),
    );
    pendingMerges.clear();
    int highestMergeValueThisFrame = 0;
    for (final MergePair pair in mergeSnapshot) {
      if (!pair.first.isMounted || !pair.second.isMounted) {
        releaseMergeLock(pair);
        continue;
      }
      final StoneSpec? mergedSpec = StoneCatalog.nextOf(
        pair.first.spec,
        stoneCatalog,
      );
      if (mergedSpec == null) {
        releaseMergeLock(pair);
        continue;
      }
      final Vector2 mergedPosition = Vector2(
        (pair.first.body.position.x + pair.second.body.position.x) / 2,
        (pair.first.body.position.y + pair.second.body.position.y) / 2,
      );
      final Vector2 mergedVelocity =
          (pair.first.body.linearVelocity + pair.second.body.linearVelocity) *
          0.35;
      pair.first.removeFromParent();
      pair.second.removeFromParent();
      final SuikaStoneBody mergedStone = createStoneBody(
        spec: mergedSpec,
        position: mergedPosition,
        initialLinearVelocity: mergedVelocity,
      );
      world.add(mergedStone);
      highestMergeValueThisFrame = max(
        highestMergeValueThisFrame,
        pair.first.spec.stage + 1,
      );
      setScore(score + mergedSpec.score);
      unawaited(playMergeHaptic(mergedSpec));
      releaseMergeLock(pair);
    }
    if (highestMergeValueThisFrame > 0) {
      registerComboMerge(highestMergeValueThisFrame);
    }
  }

  Future<void> playMergeHaptic(StoneSpec mergedSpec) async {
    switch (mergedSpec.stage) {
      case 1:
        await HapticFeedback.selectionClick();
        return;
      case 2:
        await HapticFeedback.lightImpact();
        return;
      case 3:
        await HapticFeedback.lightImpact();
        await Future<void>.delayed(const Duration(milliseconds: 24));
        await HapticFeedback.selectionClick();
        return;
      case 4:
        await HapticFeedback.mediumImpact();
        return;
      case 5:
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 28));
        await HapticFeedback.lightImpact();
        return;
      case 6:
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 32));
        await HapticFeedback.mediumImpact();
        return;
      case 7:
        await HapticFeedback.heavyImpact();
        return;
      case 8:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 36));
        await HapticFeedback.mediumImpact();
        return;
      default:
        await HapticFeedback.lightImpact();
    }
  }

  /// danger line 위반을 1초 연속 유지한 경우에만 종료합니다.
  void updateDangerState(double dt) {
    final bool hasDangerStone = world.children.query<SuikaStoneBody>().any((
      SuikaStoneBody stone,
    ) {
      final double stoneAge = elapsedTime - stone.createdAt;
      if (stoneAge < 0.8) {
        return false;
      }
      if (stone.body.linearVelocity.length > 1.2) {
        return false;
      }
      final double stoneTop = stone.body.position.y - stone.spec.radius;
      return stoneTop <= dangerLineY;
    });
    if (!hasDangerStone) {
      dangerAccumulated = 0;
      return;
    }
    dangerAccumulated += dt;
    if (dangerAccumulated < 1.0) {
      return;
    }
    finishGame();
  }

  /// 게임오버를 적용하고 더 이상 업데이트되지 않도록 멈춥니다.
  void finishGame() {
    if (isGameOver) {
      return;
    }
    flushPendingComboBonus();
    isGameOver = true;
    isClearBonusResolving = true;
    clearBonusScore = 0;
    skipClearBonusRequested = false;
    lastGameOverTapAtMs = 0;
    hudState.setClearBonusState(score: 0, resolving: true);
    hudState.setGameOver(true);
    hudState.setPaused(false);
    unawaited(runClearBonusSequence());
  }

  /// 점수 갱신 로직을 HUD와 통합합니다.
  void setScore(int nextScore) {
    score = nextScore;
    hudState.setScore(nextScore);
  }

  /// 현재 콤보 상태를 HUD에 동기화합니다.
  void syncComboHud() {
    hudState.setComboState(
      active: comboRemainingSeconds > 0,
      remainingSeconds: comboRemainingSeconds,
      pendingBonus: pendingComboBonus,
    );
    hudState.setComboSessionStats(
      earnedScore: totalComboEarnedScore,
      activeDurationSeconds: totalComboActiveDurationSeconds,
    );
  }

  /// 합체가 한 번 발생했을 때 콤보 예열 또는 활성 콤보를 갱신합니다.
  void registerComboMerge(int mergeValue) {
    if (mergeValue <= 0) {
      return;
    }
    if (comboRemainingSeconds > 0) {
      final bool extendsComboTime = mergeValue >= comboHighestMergeValue;
      if (extendsComboTime) {
        comboHighestMergeValue = max(comboHighestMergeValue, mergeValue);
        comboRemainingSeconds = min(comboMaxSeconds, comboRemainingSeconds + 1);
        hudState.triggerComboTimeAdded();
      }
      pendingComboBonus += calculateComboBonus(mergeValue);
      syncComboHud();
      return;
    }

    if (comboWarmupElapsedSeconds > comboWarmupWindowSeconds) {
      comboWarmupCount = 0;
      comboWarmupHighestMergeValue = 0;
    }

    comboWarmupCount += 1;
    comboWarmupHighestMergeValue = max(
      comboWarmupHighestMergeValue,
      mergeValue,
    );
    comboWarmupElapsedSeconds = 0;

    if (comboWarmupCount < 2) {
      return;
    }

    comboRemainingSeconds = comboStartSeconds;
    comboHighestMergeValue = max(comboWarmupHighestMergeValue, mergeValue);
    pendingComboBonus += calculateComboBonus(mergeValue);
    comboWarmupCount = 0;
    comboWarmupHighestMergeValue = 0;
    comboWarmupElapsedSeconds = double.infinity;
    hudState.triggerComboPulse();
    syncComboHud();
  }

  /// 이번 합체 단계와 남은 콤보 시간으로 추가 점수를 계산합니다.
  int calculateComboBonus(int mergeValue) {
    final int cubeBonus = mergeValue * mergeValue * mergeValue;
    return cubeBonus + comboRemainingSeconds.floor();
  }

  /// 콤보 타이머와 예열 타이머를 매 틱 갱신합니다.
  void updateComboState(double dt) {
    if (comboRemainingSeconds > 0) {
      totalComboActiveDurationSeconds += dt;
      comboRemainingSeconds = max(0, comboRemainingSeconds - dt);
      if (comboRemainingSeconds == 0) {
        flushPendingComboBonus();
        return;
      }
      syncComboHud();
      return;
    }

    if (comboWarmupCount == 0) {
      return;
    }

    comboWarmupElapsedSeconds += dt;
    if (comboWarmupElapsedSeconds <= comboWarmupWindowSeconds) {
      return;
    }
    comboWarmupCount = 0;
    comboWarmupHighestMergeValue = 0;
    comboWarmupElapsedSeconds = double.infinity;
  }

  /// 진행 중인 콤보를 정산하고 HUD를 기본 상태로 되돌립니다.
  void flushPendingComboBonus() {
    final int bonus = pendingComboBonus;
    comboRemainingSeconds = 0;
    comboHighestMergeValue = 0;
    comboWarmupCount = 0;
    comboWarmupHighestMergeValue = 0;
    comboWarmupElapsedSeconds = double.infinity;
    pendingComboBonus = 0;
    if (bonus > 0) {
      totalComboEarnedScore += bonus;
      setScore(score + bonus);
    }
    syncComboHud();
  }

  /// 게임오버 정산 중 두 번 탭하면 남은 보너스를 즉시 정산합니다.
  bool registerGameOverTap() {
    if (!isGameOver || !isClearBonusResolving) {
      return false;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastGameOverTapAtMs <= 260) {
      skipClearBonusRequested = true;
      return true;
    }
    lastGameOverTapAtMs = now;
    return true;
  }

  /// 남은 돌을 단계별로 제거하며 게임오버 클리어 보너스를 계산합니다.
  Future<void> runClearBonusSequence() async {
    for (int stage = 0; stage < stoneCatalog.length; stage += 1) {
      while (true) {
        if (skipClearBonusRequested) {
          applyRemainingClearBonusImmediately();
          await bankClearBonusIntoScore();
          return;
        }
        final SuikaStoneBody? stone = findTopmostStoneForStage(stage);
        if (stone == null) {
          break;
        }
        popStoneForClearBonus(stone);
        await Future<void>.delayed(Duration(milliseconds: 88 + (stage * 10)));
      }
    }
    await bankClearBonusIntoScore();
  }

  /// 현재 보드에서 특정 단계의 가장 위쪽 돌을 찾습니다.
  SuikaStoneBody? findTopmostStoneForStage(int stage) {
    final List<SuikaStoneBody> stones = world.children
        .query<SuikaStoneBody>()
        .where(
          (SuikaStoneBody stone) =>
              stone.isMounted && stone.spec.stage == stage,
        )
        .toList(growable: false);
    if (stones.isEmpty) {
      return null;
    }
    stones.sort(
      (SuikaStoneBody first, SuikaStoneBody second) =>
          first.body.position.y.compareTo(second.body.position.y),
    );
    return stones.first;
  }

  /// 단일 돌을 제거하고 해당 단계의 클리어 보너스를 누적합니다.
  void popStoneForClearBonus(SuikaStoneBody stone) {
    if (!stone.isMounted) {
      return;
    }
    stone.removeFromParent();
    clearBonusScore += clearBonusValueForStage(stone.spec.stage + 1);
    hudState.setClearBonusState(
      score: clearBonusScore,
      resolving: isClearBonusResolving,
    );
    unawaited(playClearBonusHaptic(stone.spec.stage + 1));
  }

  /// 남아 있는 모든 돌을 즉시 제거하고 클리어 보너스를 합산합니다.
  void applyRemainingClearBonusImmediately() {
    final List<SuikaStoneBody> stones = world.children
        .query<SuikaStoneBody>()
        .where((SuikaStoneBody stone) => stone.isMounted)
        .toList(growable: false);
    for (final SuikaStoneBody stone in stones) {
      stone.removeFromParent();
      clearBonusScore += clearBonusValueForStage(stone.spec.stage + 1);
    }
    hudState.setClearBonusState(score: clearBonusScore, resolving: true);
  }

  /// 게임오버 후 누적된 클리어 보너스를 최종 점수에 합산합니다.
  Future<void> bankClearBonusIntoScore() async {
    isClearBonusResolving = false;
    hudState.setClearBonusState(score: clearBonusScore, resolving: false);
    if (clearBonusScore <= 0) {
      hudState.triggerScorePulse();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    setScore(score + clearBonusScore);
    hudState.triggerScorePulse();
  }

  /// 단계별 클리어 보너스 점수 규칙입니다.
  int clearBonusValueForStage(int value) {
    if (value <= 4) {
      return value * value;
    }
    if (value <= 7) {
      return value * value * value;
    }
    return value * value * value * value;
  }

  Future<void> playClearBonusHaptic(int stageValue) async {
    switch (stageValue) {
      case 1:
        await HapticFeedback.selectionClick();
        return;
      case 2:
        await HapticFeedback.lightImpact();
        return;
      case 3:
        await HapticFeedback.mediumImpact();
        return;
      case 4:
        await HapticFeedback.heavyImpact();
        return;
      case 5:
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 18));
        await HapticFeedback.heavyImpact();
        return;
      case 6:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 24));
        await HapticFeedback.lightImpact();
        return;
      case 7:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 28));
        await HapticFeedback.mediumImpact();
        return;
      case 8:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 26));
        await HapticFeedback.heavyImpact();
        return;
      case 9:
        await HapticFeedback.heavyImpact();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await HapticFeedback.mediumImpact();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await HapticFeedback.heavyImpact();
        return;
      default:
        await HapticFeedback.heavyImpact();
    }
  }

  /// 드롭 풀에서 무작위 단계를 선택합니다.
  StoneSpec pickRandomDroppableStone() {
    return droppableCatalog[random.nextInt(droppableCatalog.length)];
  }

  /// 월드 생성 규격을 일관되게 맞춘 새 스톤을 반환합니다.
  SuikaStoneBody createStoneBody({
    required StoneSpec spec,
    required Vector2 position,
    Vector2? initialLinearVelocity,
  }) {
    stoneSequence += 1;
    hudState.revealStone(spec);
    final PreparedStoneAsset prepared = preparedAssets.assetFor(spec);
    return SuikaStoneBody(
      id: stoneSequence,
      spec: spec,
      preparedAsset: prepared,
      spawnPosition: position,
      createdAt: elapsedTime,
      initialLinearVelocity: initialLinearVelocity,
    );
  }

  /// 두 스톤 ID를 정렬한 안정 키를 반환합니다.
  String pairKey(int firstId, int secondId) {
    final int minId = min(firstId, secondId);
    final int maxId = max(firstId, secondId);
    return '$minId:$maxId';
  }

  /// 락과 큐 플래그를 풀어 다음 합체를 허용합니다.
  void releaseMergeLock(MergePair pair) {
    lockedStoneIds.remove(pair.first.id);
    lockedStoneIds.remove(pair.second.id);
    pair.first.isQueuedForMerge = false;
    pair.second.isQueuedForMerge = false;
  }

  /// 현재 스톤의 스포너 가이드를 보드 상단에 그립니다.
  void renderSpawnerGuide(Canvas canvas) {
    final Vector2 topLeft = camera.localToGlobal(Vector2(0.7, dangerLineY));
    final Vector2 topRight = camera.localToGlobal(
      Vector2(boardWidth - 0.7, dangerLineY),
    );
    final Vector2 spawnCenter = camera.localToGlobal(Vector2(spawnX, spawnY));
    final double previewRadius = currentStone.radius * camera.viewfinder.zoom;
    final Paint linePaint = Paint()
      ..color = const Color(0xFFE76F51).withValues(alpha: 0.28)
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(topLeft.x, topLeft.y),
      Offset(topRight.x, topRight.y),
      linePaint,
    );
    final ui.Image image = preparedAssets.assetFor(currentStone).image;
    final double imageAspectRatio = image.width / image.height;
    final double previewHeight = previewRadius * 2.3;
    final double previewWidth = previewHeight * imageAspectRatio;
    final Rect dst = Rect.fromCenter(
      center: Offset(spawnCenter.x, spawnCenter.y),
      width: previewWidth,
      height: previewHeight,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint(),
    );
    canvas.drawLine(
      Offset(spawnCenter.x, 0),
      Offset(spawnCenter.x, spawnCenter.y - previewRadius - 10),
      linePaint,
    );
  }
}

/// 월드 외곽과 바닥을 박스 경계로 구성합니다.
class BoundsBody extends BodyComponent<SuikaGame> {
  static const double wallThickness = 0.44;
  static const double floorThickness = 0.52;
  static const double floorMarginFromBottom = 0.18;

  /// 박스형 Suika 플레이필드를 생성합니다.
  BoundsBody({required this.boardWidth, required this.boardHeight});

  /// 플레이필드 가로 길이입니다.
  final double boardWidth;

  /// 플레이필드 세로 길이입니다.
  final double boardHeight;

  @override
  Body createBody() {
    final BodyDef bodyDef = BodyDef(
      position: Vector2.zero(),
      type: BodyType.static,
    );
    final Body createdBody = world.createBody(bodyDef);
    final double floorCenterY =
        boardHeight - floorMarginFromBottom - (floorThickness / 2);
    final double wallCenterY = floorCenterY / 2;
    createdBody.createFixture(
      FixtureDef(
        PolygonShape()..setAsBox(
          wallThickness / 2,
          floorCenterY / 2,
          Vector2(wallThickness / 2, wallCenterY),
          0,
        ),
        friction: 0.18,
        restitution: 0.0,
      ),
    );
    createdBody.createFixture(
      FixtureDef(
        PolygonShape()..setAsBox(
          wallThickness / 2,
          floorCenterY / 2,
          Vector2(boardWidth - (wallThickness / 2), wallCenterY),
          0,
        ),
        friction: 0.18,
        restitution: 0.0,
      ),
    );
    createdBody.createFixture(
      FixtureDef(
        PolygonShape()..setAsBox(
          (boardWidth - wallThickness) / 2,
          floorThickness / 2,
          Vector2(boardWidth / 2, floorCenterY),
          0,
        ),
        friction: 0.26,
        restitution: 0.0,
      ),
    );
    return createdBody;
  }

  @override
  void render(Canvas canvas) {
    final double floorTopY =
        boardHeight - floorMarginFromBottom - floorThickness;
    final Paint framePaint = Paint()
      ..color = const Color(0xFFDDB892)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.12;
    final Paint floorPaint = Paint()
      ..color = const Color(0xFF7F5539).withValues(alpha: 0.44)
      ..style = PaintingStyle.fill;
    final Paint belowFloorPaint = Paint()
      ..color = const Color(0xFF281E1A).withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, boardWidth, boardHeight), framePaint);
    canvas.drawRect(
      Rect.fromLTWH(0, floorTopY, boardWidth, floorThickness),
      floorPaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        floorTopY + floorThickness,
        boardWidth,
        floorMarginFromBottom,
      ),
      belowFloorPaint,
    );
  }
}

/// danger line 위치를 화면에 표시해 종료 조건을 안내합니다.
class DangerLineComponent extends PositionComponent {
  /// 상단 위험선을 얇은 선으로 표현합니다.
  DangerLineComponent({required this.boardWidth, required this.dangerLineY}) {
    position = Vector2(0, dangerLineY);
    size = Vector2(boardWidth, 0.02);
    anchor = Anchor.topLeft;
  }

  /// 위험선 가로 길이입니다.
  final double boardWidth;

  /// 위험선 높이입니다.
  final double dangerLineY;

  @override
  void render(Canvas canvas) {
    final Paint paint = Paint()
      ..color = const Color(0xFFFF7F51).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, boardWidth, 0.03), paint);
  }
}

/// 안정 접촉이 끝난 두 스톤을 합체 큐에 담습니다.
class MergePair {
  /// 합체 대상 두 바디를 함께 보관합니다.
  const MergePair({required this.first, required this.second});

  /// 첫 번째 스톤입니다.
  final SuikaStoneBody first;

  /// 두 번째 스톤입니다.
  final SuikaStoneBody second;
}
