import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flame_game_2/game/suika/stone_spec.dart';
import 'package:flutter_flame_game_2/game/suika/suika_hud_state.dart';
import 'package:flutter_flame_game_2/game/suika/suika_stone_body.dart';

/// Suika 규칙에 맞는 드롭, 합체, 게임오버 루프를 제공합니다.
class SuikaGame extends Forge2DGame with HasCollisionDetection, TapCallbacks {
  /// HUD 상태와 보드 크기를 받아 게임 세션을 초기화합니다.
  SuikaGame({
    required this.hudState,
    required this.boardWidth,
    required this.boardHeight,
  }) : super(
          gravity: Vector2(0, 24),
          zoom: 38,
        );

  /// Flutter HUD와 공유할 상태 객체입니다.
  final SuikaHudState hudState;

  /// 월드 기준 가로 크기입니다.
  final double boardWidth;

  /// 월드 기준 세로 크기입니다.
  final double boardHeight;

  /// 화면 상단 위험선 높이를 반환합니다.
  double get dangerLineY => 2.2;

  /// 실제 스톤이 스폰되는 높이를 반환합니다.
  double get spawnY => 1.5;

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

  /// 게임오버 플래그입니다.
  bool isGameOver = false;

  /// 다음 스톤 큐입니다.
  late StoneSpec currentStone;

  /// HUD 미리보기에 보여줄 다음 스톤입니다.
  late StoneSpec nextStone;

  final Random random = Random();
  final List<StoneSpec> droppableCatalog = StoneCatalog.droppableValues();
  final Map<String, double> contactDurations = <String, double>{};
  final List<MergePair> pendingMerges = <MergePair>[];
  final Set<int> lockedStoneIds = <int>{};

  int stoneSequence = 0;

  /// 월드 경계와 초기 큐를 생성합니다.
  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    camera.viewfinder.position = Vector2.zero();
    hudState.resetForNewGame();
    await add(ScreenHitbox());
    await addAll(<Component>[
      BoundsBody(boardWidth: boardWidth, boardHeight: boardHeight),
      DangerLineComponent(
        boardWidth: boardWidth,
        dangerLineY: dangerLineY,
      ),
    ]);
    currentStone = pickRandomDroppableStone();
    nextStone = pickRandomDroppableStone();
    hudState.setNextStone(nextStone);
    spawnX = boardWidth / 2;
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
    if (!isMergeCandidate(first, second)) {
      return;
    }
    contactDurations.putIfAbsent(pairKey(first.id, second.id), () => 0);
  }

  /// 두 스톤의 접촉 종료를 추적 상태에서 제거합니다.
  void registerContactEnd(SuikaStoneBody first, SuikaStoneBody second) {
    contactDurations.remove(pairKey(first.id, second.id));
  }

  /// 게임 루프에서 합체 큐와 danger 판정을 순차적으로 처리합니다.
  @override
  void update(double dt) {
    if (paused) {
      super.update(dt);
      return;
    }
    elapsedTime += dt;
    dropCooldown = max(0, dropCooldown - dt);
    advanceContactTimers(dt);
    resolvePendingMerges();
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
    if (StoneCatalog.nextOf(first.spec) == null) {
      return false;
    }
    if (lockedStoneIds.contains(first.id) || lockedStoneIds.contains(second.id)) {
      return false;
    }
    if (first.isQueuedForMerge || second.isQueuedForMerge) {
      return false;
    }
    if (!first.isMounted || !second.isMounted) {
      return false;
    }
    if (elapsedTime - first.createdAt < 0.15 || elapsedTime - second.createdAt < 0.15) {
      return false;
    }
    return true;
  }

  /// 접촉 시간이 기준을 넘긴 쌍을 다음 틱 합체 큐로 옮깁니다.
  void advanceContactTimers(double dt) {
    final List<String> readyKeys = <String>[];
    contactDurations.forEach((String key, double value) {
      final double nextValue = value + dt;
      contactDurations[key] = nextValue;
      if (nextValue >= 0.1) {
        readyKeys.add(key);
      }
    });
    for (final String key in readyKeys) {
      final MergePair? pair = resolvePairForKey(key);
      if (pair == null) {
        contactDurations.remove(key);
        continue;
      }
      queueMerge(pair);
      contactDurations.remove(key);
    }
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
    pendingMerges.clear();
    for (final MergePair pair in mergeSnapshot) {
      if (!pair.first.isMounted || !pair.second.isMounted) {
        releaseMergeLock(pair);
        continue;
      }
      final StoneSpec? mergedSpec = StoneCatalog.nextOf(pair.first.spec);
      if (mergedSpec == null) {
        releaseMergeLock(pair);
        continue;
      }
      final Vector2 mergedPosition = Vector2(
        (pair.first.body.position.x + pair.second.body.position.x) / 2,
        (pair.first.body.position.y + pair.second.body.position.y) / 2,
      );
      pair.first.removeFromParent();
      pair.second.removeFromParent();
      final SuikaStoneBody mergedStone = createStoneBody(
        spec: mergedSpec,
        position: mergedPosition,
      );
      world.add(mergedStone);
      setScore(score + mergedSpec.score);
      releaseMergeLock(pair);
    }
  }

  /// danger line 위반을 1초 연속 유지한 경우에만 종료합니다.
  void updateDangerState(double dt) {
    final bool hasDangerStone = world.children.query<SuikaStoneBody>().any((SuikaStoneBody stone) {
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
    isGameOver = true;
    hudState.setGameOver(true);
    hudState.setPaused(false);
    pauseEngine();
  }

  /// 점수 갱신 로직을 HUD와 통합합니다.
  void setScore(int nextScore) {
    score = nextScore;
    hudState.setScore(nextScore);
  }

  /// 드롭 풀에서 무작위 단계를 선택합니다.
  StoneSpec pickRandomDroppableStone() {
    return droppableCatalog[random.nextInt(droppableCatalog.length)];
  }

  /// 월드 생성 규격을 일관되게 맞춘 새 스톤을 반환합니다.
  SuikaStoneBody createStoneBody({
    required StoneSpec spec,
    required Vector2 position,
  }) {
    stoneSequence += 1;
    return SuikaStoneBody(
      id: stoneSequence,
      spec: spec,
      spawnPosition: position,
      createdAt: elapsedTime,
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
    final Vector2 topRight = camera.localToGlobal(Vector2(boardWidth - 0.7, dangerLineY));
    final Vector2 spawnCenter = camera.localToGlobal(Vector2(spawnX, spawnY));
    final double previewRadius = currentStone.radius * camera.viewfinder.zoom;
    final Paint linePaint = Paint()
      ..color = const Color(0xFFE76F51).withValues(alpha: 0.45)
      ..strokeWidth = 2;
    final Paint previewPaint = Paint()
      ..color = currentStone.color.withValues(alpha: 0.68);

    canvas.drawLine(
      Offset(topLeft.x, topLeft.y),
      Offset(topRight.x, topRight.y),
      linePaint,
    );
    canvas.drawCircle(
      Offset(spawnCenter.x, spawnCenter.y),
      previewRadius,
      previewPaint,
    );
  }
}

/// 월드 외곽과 바닥을 박스 경계로 구성합니다.
class BoundsBody extends BodyComponent<SuikaGame> {
  /// 박스형 Suika 플레이필드를 생성합니다.
  BoundsBody({
    required this.boardWidth,
    required this.boardHeight,
  });

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
    createdBody.createFixture(
      FixtureDef(
        PolygonShape()..setAsBox(0.35, boardHeight / 2, Vector2(0, boardHeight / 2), 0),
      ),
    );
    createdBody.createFixture(
      FixtureDef(
        PolygonShape()..setAsBox(0.35, boardHeight / 2, Vector2(boardWidth, boardHeight / 2), 0),
      ),
    );
    createdBody.createFixture(
      FixtureDef(
        PolygonShape()..setAsBox(boardWidth / 2, 0.4, Vector2(boardWidth / 2, boardHeight), 0),
      ),
    );
    return createdBody;
  }

  @override
  void render(Canvas canvas) {
    final Paint framePaint = Paint()
      ..color = const Color(0xFFDDB892)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.12;
    final Paint floorPaint = Paint()
      ..color = const Color(0xFF7F5539).withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, boardWidth, boardHeight),
      framePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, boardHeight - 0.7, boardWidth, 0.7),
      floorPaint,
    );
  }
}

/// danger line 위치를 화면에 표시해 종료 조건을 안내합니다.
class DangerLineComponent extends PositionComponent {
  /// 상단 위험선을 얇은 선으로 표현합니다.
  DangerLineComponent({
    required this.boardWidth,
    required this.dangerLineY,
  }) {
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
  const MergePair({
    required this.first,
    required this.second,
  });

  /// 첫 번째 스톤입니다.
  final SuikaStoneBody first;

  /// 두 번째 스톤입니다.
  final SuikaStoneBody second;
}
