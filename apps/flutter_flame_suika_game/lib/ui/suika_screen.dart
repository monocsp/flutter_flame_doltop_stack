import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flame_game/ui/widgets/particle_background.dart';
import 'package:flutter_flame_game_2/game/suika/prepared_suika_assets.dart';
import 'package:flutter_flame_game_2/game/suika/stone_spec.dart';
import 'package:flutter_flame_game_2/game/suika/suika_game.dart';
import 'package:flutter_flame_game_2/game/suika/suika_hud_state.dart';

/// Suika 게임과 Flutter HUD를 한 화면에 조합합니다.
class SuikaScreen extends StatefulWidget {
  /// Suika 메인 화면을 생성합니다.
  // ignore: prefer_const_constructors_in_immutables
  SuikaScreen({
    super.key,
    this.stoneAssetPaths = StoneCatalog.defaultAssetPaths,
  }) : assert(
         stoneAssetPaths.length == StoneCatalog.stageCount,
         'Suika stone image paths must contain exactly 9 entries.',
       );

  /// 1~9 단계에 대응하는 스톤 이미지 경로 목록입니다.
  final List<String> stoneAssetPaths;

  @override
  State<SuikaScreen> createState() => SuikaScreenState();
}

/// 게임 인스턴스 재생성과 HUD 연결을 관리합니다.
class SuikaScreenState extends State<SuikaScreen> {
  static const Duration holdToDragDelay = Duration(milliseconds: 140);
  static const double dragActivationDistance = 12;

  /// ValueNotifier 기반으로 세션과 게임 참조를 관리합니다.
  SuikaScreenState();

  late final SuikaHudState hudState;
  PreparedSuikaAssets? preparedAssets;
  SuikaGame? currentGame;
  int sessionVersion = 0;
  bool isPreparing = true;
  Object? loadError;
  Timer? holdTimer;
  int? activePointer;
  Offset? pointerDownPosition;
  bool isDraggingSpawner = false;

  @override
  void initState() {
    super.initState();
    hudState = SuikaHudState(
      initialCatalog: StoneCatalog.droppableValues(widget.stoneAssetPaths),
    );
    prepareAssetsAndGame();
  }

  @override
  void didUpdateWidget(covariant SuikaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameAssetPaths(oldWidget.stoneAssetPaths, widget.stoneAssetPaths)) {
      prepareAssetsAndGame();
    }
  }

  @override
  void dispose() {
    holdTimer?.cancel();
    hudState.dispose();
    super.dispose();
  }

  /// 새 세션 번호를 발급해 게임 위젯을 교체합니다.
  void restartGame() {
    final PreparedSuikaAssets? assets = preparedAssets;
    if (assets == null) {
      return;
    }
    hudState.resetForNewGame();
    setState(() {
      sessionVersion += 1;
      currentGame = createGame(assets);
    });
  }

  /// 재시작 전에 한 번 더 확인해 실수로 세션을 잃지 않게 합니다.
  Future<void> openResetConfirmationDialog() async {
    final SuikaGame? game = currentGame;
    final bool shouldResume = game != null && !game.isGameOver && !game.paused;
    if (shouldResume) {
      game.pauseEngine();
      hudState.setPaused(true);
    }

    final bool? shouldReset = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141921),
          title: const Text('Reset Game'),
          content: const Text('현재 점수와 진행 중인 콤보를 버리고 처음부터 다시 시작할까요?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }
    if (shouldReset == true) {
      restartGame();
      return;
    }
    if (!shouldResume) {
      return;
    }
    final SuikaGame? latestGame = currentGame;
    if (latestGame == null || latestGame.isGameOver) {
      return;
    }
    latestGame.resumeEngine();
    hudState.setPaused(false);
  }

  /// 입력 위치를 보드 가로 비율로 바꿔 스포너를 이동시킵니다.
  void moveSpawnerForLocalDx(double localDx, double width) {
    final SuikaGame? game = currentGame;
    if (width <= 0) {
      return;
    }
    if (game == null) {
      return;
    }
    final double ratio = localDx / width;
    game.moveSpawnerByRatio(ratio);
  }

  /// 지정한 위치로 스포너를 옮긴 뒤 현재 스톤을 떨어뜨립니다.
  void dropStoneAtLocalDx(double localDx, double width) {
    moveSpawnerForLocalDx(localDx, width);
    currentGame?.dropCurrentStone();
  }

  /// 포인터를 누른 순간 프리뷰를 해당 위치로 이동시키고 홀드 추적을 시작합니다.
  void beginPointerTracking(PointerDownEvent event, double width) {
    if (activePointer != null) {
      return;
    }
    activePointer = event.pointer;
    pointerDownPosition = event.localPosition;
    isDraggingSpawner = false;
    moveSpawnerForLocalDx(event.localPosition.dx, width);
    holdTimer?.cancel();
    holdTimer = Timer(holdToDragDelay, () {
      if (!mounted) {
        return;
      }
      if (activePointer != event.pointer) {
        return;
      }
      isDraggingSpawner = true;
    });
  }

  /// 누른 채 이동이 확인되면 X축 스포너를 따라오게 만듭니다.
  void updatePointerTracking(PointerMoveEvent event, double width) {
    if (activePointer != event.pointer) {
      return;
    }
    final Offset? downPosition = pointerDownPosition;
    if (downPosition == null) {
      return;
    }
    final double distance = (event.localPosition - downPosition).distance;
    if (!isDraggingSpawner && distance >= dragActivationDistance) {
      holdTimer?.cancel();
      isDraggingSpawner = true;
    }
    if (!isDraggingSpawner) {
      return;
    }
    moveSpawnerForLocalDx(event.localPosition.dx, width);
  }

  /// 포인터를 떼는 순간 마지막 위치에서 스톤을 낙하시킵니다.
  void endPointerTracking(PointerUpEvent event, double width) {
    if (activePointer != event.pointer) {
      return;
    }
    holdTimer?.cancel();
    dropStoneAtLocalDx(event.localPosition.dx, width);
    resetPointerTracking();
  }

  /// 취소된 포인터 세션의 입력 상태를 정리합니다.
  void cancelPointerTracking(PointerCancelEvent event) {
    if (activePointer != event.pointer) {
      return;
    }
    holdTimer?.cancel();
    resetPointerTracking();
  }

  void resetPointerTracking() {
    activePointer = null;
    pointerDownPosition = null;
    isDraggingSpawner = false;
  }

  Future<void> prepareAssetsAndGame() async {
    setState(() {
      isPreparing = true;
      loadError = null;
    });

    try {
      final PreparedSuikaAssets assets = await PreparedSuikaAssets.load(
        stoneAssetPaths: widget.stoneAssetPaths,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        preparedAssets = assets;
        currentGame = createGame(assets);
        isPreparing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        loadError = error;
        isPreparing = false;
      });
    }
  }

  bool _sameAssetPaths(List<String> first, List<String> second) {
    if (identical(first, second)) {
      return true;
    }
    if (first.length != second.length) {
      return false;
    }
    for (int i = 0; i < first.length; i += 1) {
      if (first[i] != second[i]) {
        return false;
      }
    }
    return true;
  }

  /// Suika 전용 고정 월드 크기로 새 게임 인스턴스를 만듭니다.
  SuikaGame createGame(PreparedSuikaAssets assets) {
    return SuikaGame(
      hudState: hudState,
      boardWidth: SuikaGame.boardWidthUnits,
      boardHeight: SuikaGame.boardHeightUnits,
      preparedAssets: assets,
    );
  }

  /// Flutter 입력을 우선 받아 드롭 조작을 단순화합니다.
  Widget buildInteractiveGameLayer(SuikaGame game) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF171A1F),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFFF7F3E9).withValues(alpha: 0.16),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 26,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent event) {
                beginPointerTracking(event, width);
              },
              onPointerMove: (PointerMoveEvent event) {
                updatePointerTracking(event, width);
              },
              onPointerUp: (PointerUpEvent event) {
                endPointerTracking(event, width);
              },
              onPointerCancel: cancelPointerTracking,
              child: GameWidget<SuikaGame>(
                key: ValueKey<int>(sessionVersion),
                game: game,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 점수, 미리보기, 제어 버튼을 상단 HUD로 제공합니다.
  Widget buildHud() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF11151C).withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFF7F3E9).withValues(alpha: 0.14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(child: buildScorePanel()),
            const SizedBox(width: 12),
            buildHudActions(),
          ],
        ),
      ),
    );
  }

  /// 우측 HUD 액션 묶음을 같은 기준선으로 정렬합니다.
  Widget buildHudActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        buildNextStonePreview(),
        const SizedBox(width: 10),
        buildQuickActionColumn(),
      ],
    );
  }

  /// 현재 점수와 최고 점수를 컴팩트한 카드로 배치합니다.
  Widget buildScorePanel() {
    return ValueListenableBuilder<int>(
      valueListenable: hudState.score,
      builder: (BuildContext context, int score, Widget? child) {
        return ValueListenableBuilder<int>(
          valueListenable: hudState.comboPendingBonus,
          builder:
              (BuildContext context, int comboPendingBonus, Widget? child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'SCORE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: Color(0xFFD9CAB3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 254,
                      child: buildMetricCard(
                        child: ScorePanelBody(
                          score: score,
                          pendingBonus: comboPendingBonus,
                        ),
                      ),
                    ),
                  ],
                );
              },
        );
      },
    );
  }

  /// 점수 카드 1개를 구성합니다.
  Widget buildMetricCard({required Widget child, double? minWidth}) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth ?? 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0C1016).withValues(alpha: 0.64),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFF7F3E9).withValues(alpha: 0.08),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: child,
        ),
      ),
    );
  }

  /// 다음 단계 미리보기를 작은 원형 카드로 보여줍니다.
  Widget buildNextStonePreview() {
    return ValueListenableBuilder<StoneSpec>(
      valueListenable: hudState.nextStone,
      builder: (BuildContext context, StoneSpec spec, Widget? child) {
        return SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const Text(
                'NEXT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Color(0xFFD9CAB3),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFF201A17),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: preparedAssets == null
                        ? const SizedBox.shrink()
                        : RawImage(
                            image: preparedAssets!.assetFor(spec).image,
                            fit: BoxFit.contain,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 단계별 스톤 도감을 바텀시트로 엽니다.
  Future<void> openStoneCatalogSheet() async {
    final SuikaGame? game = currentGame;
    final bool shouldResume = game != null && !game.isGameOver && !game.paused;
    if (shouldResume) {
      game.pauseEngine();
      hudState.setPaused(true);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return buildStoneCatalogSheet();
      },
    );

    if (!mounted) {
      return;
    }
    if (!shouldResume) {
      return;
    }
    final SuikaGame? latestGame = currentGame;
    if (latestGame == null || latestGame.isGameOver) {
      return;
    }
    latestGame.resumeEngine();
    hudState.setPaused(false);
  }

  /// 도감 버튼을 HUD 우측 액션으로 제공합니다.
  Widget buildCatalogButton() {
    return SizedBox(
      width: 34,
      height: 34,
      child: FilledButton(
        onPressed: openStoneCatalogSheet,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF28303A),
          foregroundColor: const Color(0xFFFDF7ED),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Icon(Icons.auto_awesome_mosaic_rounded, size: 17),
      ),
    );
  }

  /// 재시작 버튼만 제공합니다.
  Widget buildRestartButton() {
    return SizedBox(
      width: 34,
      height: 34,
      child: FilledButton(
        onPressed: openResetConfirmationDialog,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE76F51),
          foregroundColor: const Color(0xFFFDF7ED),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Icon(Icons.replay_rounded, size: 18),
      ),
    );
  }

  /// 작은 아이콘 액션을 세로로 쌓아 HUD 공간을 절약합니다.
  Widget buildQuickActionColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        buildCatalogButton(),
        const SizedBox(height: 8),
        buildRestartButton(),
      ],
    );
  }

  /// 콤보 유지 시간을 화면 하단의 얇은 진행 바로 렌더링합니다.
  Widget buildBottomComboBar() {
    return ValueListenableBuilder<double>(
      valueListenable: hudState.comboRemainingSeconds,
      builder: (BuildContext context, double remainingSeconds, Widget? child) {
        return ComboProgressBar(
          progress: (remainingSeconds / SuikaGame.comboMaxSeconds).clamp(
            0.0,
            1.0,
          ),
          pulseListenable: hudState.comboTimeAddedToken,
        );
      },
    );
  }

  /// 콤보 시작 순간 중앙 문구를 짧게 표시합니다.
  Widget buildComboPulseOverlay() {
    return ComboPulseOverlay(triggerListenable: hudState.comboPulseToken);
  }

  /// 공개/비공개 단계를 함께 보여주는 도감 바텀시트 본문입니다.
  Widget buildStoneCatalogSheet() {
    final PreparedSuikaAssets assets = preparedAssets!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF11151C),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: const Color(0xFFF7F3E9).withValues(alpha: 0.08),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: ValueListenableBuilder<Set<int>>(
            valueListenable: hudState.revealedStages,
            builder: (BuildContext context, Set<int> revealedStages, Widget? child) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F3E9).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Stone Catalog',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFF7F3E9),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '1~6 단계는 기본 공개됩니다.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: Color(0xFFD9CAB3),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF171C24),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(
                            0xFFF7F3E9,
                          ).withValues(alpha: 0.08),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Combo System',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFF7F3E9),
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              '연속으로 두 번 합체하면 콤보가 시작되고 5초가 주어집니다.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Color(0xFFD9CAB3),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '현재 최고 단계 이상으로 합체하면 콤보 시간이 늘어나고, 더 낮은 합체는 시간 추가 없이 보너스 점수만 줍니다.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Color(0xFFD9CAB3),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '콤보 보너스는 진행 중에는 따로 모였다가 콤보가 끝날 때 점수에 한 번에 합산됩니다.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Color(0xFFD9CAB3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: assets.catalog.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.9,
                          ),
                      itemBuilder: (BuildContext context, int index) {
                        final StoneSpec spec = assets.catalog[index];
                        final bool isRevealed = revealedStages.contains(
                          spec.stage,
                        );
                        return buildStoneCatalogTile(
                          spec: spec,
                          asset: assets.assetFor(spec),
                          isRevealed: isRevealed,
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 단계별 도감 타일 1개를 렌더링합니다.
  Widget buildStoneCatalogTile({
    required StoneSpec spec,
    required PreparedStoneAsset asset,
    required bool isRevealed,
  }) {
    final Color borderColor = isRevealed
        ? const Color(0xFFF7C59F).withValues(alpha: 0.24)
        : const Color(0xFFF7F3E9).withValues(alpha: 0.08);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF171C24),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          children: <Widget>[
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1016).withValues(alpha: 0.74),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Center(
                  child: isRevealed
                      ? Padding(
                          padding: const EdgeInsets.all(8),
                          child: RawImage(
                            image: asset.image,
                            fit: BoxFit.contain,
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Text(
                              '?',
                              style: TextStyle(
                                fontSize: 54,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                color: const Color(
                                  0xFFF7F3E9,
                                ).withValues(alpha: 0.84),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Stone ${spec.label}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF7F3E9),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isRevealed ? 'Revealed' : 'Locked',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isRevealed
                    ? const Color(0xFFF7C59F)
                    : const Color(0xFFD9CAB3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 게임오버일 때만 중앙 오버레이를 노출합니다.
  Widget buildGameOverOverlay() {
    return ValueListenableBuilder<bool>(
      valueListenable: hudState.isGameOver,
      builder: (BuildContext context, bool isGameOver, Widget? child) {
        return IgnorePointer(
          ignoring: !isGameOver,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: isGameOver ? 1 : 0,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      currentGame?.registerGameOverTap();
                    },
                  ),
                ),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF101418).withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: const Color(0xFFF7C59F).withValues(alpha: 0.22),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Text(
                            'Game Over',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF7F3E9),
                            ),
                          ),
                          const SizedBox(height: 8),
                          buildGameOverFinalScore(),
                          const SizedBox(height: 14),
                          buildGameOverStats(),
                          ValueListenableBuilder<bool>(
                            valueListenable: hudState.isClearBonusResolving,
                            builder:
                                (
                                  BuildContext context,
                                  bool resolving,
                                  Widget? child,
                                ) {
                                  return AnimatedOpacity(
                                    duration: const Duration(milliseconds: 180),
                                    opacity: resolving ? 1 : 0,
                                    child: const Padding(
                                      padding: EdgeInsets.only(top: 12),
                                      child: Text(
                                        'Double-tap to skip clear bonus',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFD9CAB3),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: restartGame,
                            child: const Text('Play Again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isPreparing) {
      return buildLoadingScaffold(
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(color: Color(0xFFF7C59F)),
            SizedBox(height: 16),
            Text(
              '수박게임 에셋을 준비하는 중...',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF7F3E9),
              ),
            ),
          ],
        ),
      );
    }

    if (loadError != null || currentGame == null) {
      return buildLoadingScaffold(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              '에셋 준비 중 오류가 발생했습니다.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF7F3E9),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '$loadError',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFD9CAB3)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: prepareAssetsAndGame,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final SuikaGame game = currentGame!;
    return buildGameScaffold(game);
  }

  Widget buildGameScaffold(SuikaGame game) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          buildStackingStyleBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                children: <Widget>[
                  buildHud(),
                  const SizedBox(height: 6),
                  Expanded(
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            final double boardWidth = constraints.maxWidth;
                            final double boardHeight =
                                boardWidth / SuikaGame.boardAspectRatio;

                            return Align(
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: boardWidth,
                                height: boardHeight,
                                child: Stack(
                                  children: <Widget>[
                                    buildInteractiveGameLayer(game),
                                    buildComboPulseOverlay(),
                                    buildGameOverOverlay(),
                                  ],
                                ),
                              ),
                            );
                          },
                    ),
                  ),
                  const SizedBox(height: 6),
                  buildBottomComboBar(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLoadingScaffold({required Widget child}) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: <Widget>[
          buildStackingStyleBackground(),
          Center(
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ],
      ),
    );
  }

  Widget buildStackingStyleBackground() {
    return Stack(
      children: const <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: <double>[0.0, 0.3, 1.0],
              colors: <Color>[
                Color(0xFF997FFF),
                Color(0xFFF293FF),
                Color(0xFFFFD582),
              ],
            ),
          ),
          child: SizedBox.expand(),
        ),
        ParticleBackground(),
      ],
    );
  }

  Widget buildGameOverStats() {
    return ValueListenableBuilder<int>(
      valueListenable: hudState.clearBonusScore,
      builder: (BuildContext context, int clearBonus, Widget? child) {
        return ValueListenableBuilder<int>(
          valueListenable: hudState.comboEarnedScore,
          builder: (BuildContext context, int comboScore, Widget? child) {
            return ValueListenableBuilder<double>(
              valueListenable: hudState.comboActiveDurationSeconds,
              builder:
                  (BuildContext context, double comboDuration, Widget? child) {
                    return Column(
                      children: <Widget>[
                        buildGameOverStatRow(
                          label: 'Clear Bonus',
                          value: AnimatedStatValue(
                            value: clearBonus,
                            color: const Color(0xFFFFD7A1),
                          ),
                        ),
                        const SizedBox(height: 8),
                        buildGameOverStatRow(
                          label: 'Combo Score',
                          value: AnimatedStatValue(value: comboScore),
                        ),
                        const SizedBox(height: 8),
                        buildGameOverStatRow(
                          label: 'Combo Time',
                          value: Text(
                            formatSeconds(comboDuration),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF7F3E9),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
            );
          },
        );
      },
    );
  }

  Widget buildGameOverFinalScore() {
    return ValueListenableBuilder<int>(
      valueListenable: hudState.score,
      builder: (BuildContext context, int value, Widget? child) {
        return Column(
          children: <Widget>[
            const Text(
              'Final Score',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFD9CAB3),
              ),
            ),
            const SizedBox(height: 4),
            PulsingScoreValue(
              score: value,
              pulseTokenListenable: hudState.scorePulseToken,
            ),
          ],
        );
      },
    );
  }

  Widget buildGameOverStatRow({required String label, required Widget value}) {
    return SizedBox(
      width: 220,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB8AB97),
              ),
            ),
          ),
          value,
        ],
      ),
    );
  }

  String formatSeconds(double seconds) {
    return '${seconds.toStringAsFixed(1)}s';
  }
}

class AnimatedScoreValue extends StatefulWidget {
  const AnimatedScoreValue({
    super.key,
    required this.score,
    this.textColor = const Color(0xFFF7F3E9),
  });

  final int score;
  final Color textColor;

  @override
  State<AnimatedScoreValue> createState() => _AnimatedScoreValueState();
}

class _AnimatedScoreValueState extends State<AnimatedScoreValue> {
  late int from;
  late int to;

  @override
  void initState() {
    super.initState();
    from = widget.score;
    to = widget.score;
  }

  @override
  void didUpdateWidget(covariant AnimatedScoreValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.score == to) {
      return;
    }
    from = to;
    to = widget.score;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: widget.textColor,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: from.toDouble(), end: to.toDouble()),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double value, Widget? child) {
          return Text(
            value.round().toString(),
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            textAlign: TextAlign.left,
          );
        },
      ),
    );
  }
}

class AnimatedPendingComboBonusValue extends StatefulWidget {
  const AnimatedPendingComboBonusValue({
    super.key,
    required this.amount,
    this.leftPadding = 10,
  });

  final int amount;
  final double leftPadding;

  @override
  State<AnimatedPendingComboBonusValue> createState() =>
      _AnimatedPendingComboBonusValueState();
}

class _AnimatedPendingComboBonusValueState
    extends State<AnimatedPendingComboBonusValue>
    with SingleTickerProviderStateMixin {
  late int from;
  late int to;
  bool wasVisible = false;
  late final AnimationController pulseController;
  late final Animation<double> scaleAnimation;
  late final Animation<Color?> colorAnimation;

  @override
  void initState() {
    super.initState();
    from = widget.amount;
    to = widget.amount;
    wasVisible = widget.amount > 0;
    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
    );
    scaleAnimation = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.08,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 42,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.08,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 58,
      ),
    ]).animate(pulseController);
    colorAnimation =
        ColorTween(
          begin: const Color(0xFFFF6B57),
          end: const Color(0xFFFFC2A8),
        ).animate(
          CurvedAnimation(parent: pulseController, curve: Curves.easeOutCubic),
        );
  }

  @override
  void didUpdateWidget(covariant AnimatedPendingComboBonusValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.amount == to) {
      return;
    }
    from = to;
    to = widget.amount;
    wasVisible = oldWidget.amount > 0;
    if (widget.amount > oldWidget.amount && widget.amount > 0) {
      pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isVisible = widget.amount > 0;
    final double width = isVisible || wasVisible ? 112 : 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: width,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        opacity: isVisible ? 1 : 0,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(left: widget.leftPadding),
            child: AnimatedBuilder(
              animation: pulseController,
              builder: (BuildContext context, Widget? child) {
                return Transform.scale(
                  scale: scaleAnimation.value,
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: from.toDouble(),
                      end: to.toDouble(),
                    ),
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    builder:
                        (BuildContext context, double value, Widget? child) {
                          return Text(
                            '+${value.round()}',
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color:
                                  colorAnimation.value ??
                                  const Color(0xFFFF6B57),
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          );
                        },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class ScorePanelBody extends StatefulWidget {
  const ScorePanelBody({
    super.key,
    required this.score,
    required this.pendingBonus,
  });

  final int score;
  final int pendingBonus;

  @override
  State<ScorePanelBody> createState() => _ScorePanelBodyState();
}

class _ScorePanelBodyState extends State<ScorePanelBody> {
  Timer? settlementTimer;
  Timer? settleHighlightTimer;
  late int displayedScore;
  late int displayedPendingBonus;
  bool isBankingScore = false;

  @override
  void initState() {
    super.initState();
    displayedScore = widget.score;
    displayedPendingBonus = widget.pendingBonus;
  }

  @override
  void didUpdateWidget(covariant ScorePanelBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool hadPendingBonus = oldWidget.pendingBonus > 0;
    final bool hasPendingBonus = widget.pendingBonus > 0;

    if (hasPendingBonus) {
      settlementTimer?.cancel();
      if (displayedScore != widget.score ||
          displayedPendingBonus != widget.pendingBonus) {
        setState(() {
          displayedScore = widget.score;
          displayedPendingBonus = widget.pendingBonus;
        });
      }
      return;
    }

    if (hadPendingBonus && widget.score > oldWidget.score) {
      settlementTimer?.cancel();
      settleHighlightTimer?.cancel();
      setState(() {
        displayedScore = oldWidget.score;
        displayedPendingBonus = 0;
        isBankingScore = true;
      });
      settlementTimer = Timer(const Duration(milliseconds: 150), () {
        if (!mounted) {
          return;
        }
        setState(() {
          displayedScore = widget.score;
        });
      });
      settleHighlightTimer = Timer(const Duration(milliseconds: 610), () {
        if (!mounted) {
          return;
        }
        setState(() {
          isBankingScore = false;
        });
      });
      return;
    }

    settlementTimer?.cancel();
    settleHighlightTimer?.cancel();
    if (displayedScore != widget.score || displayedPendingBonus != 0) {
      setState(() {
        displayedScore = widget.score;
        displayedPendingBonus = 0;
        isBankingScore = false;
      });
    }
  }

  @override
  void dispose() {
    settlementTimer?.cancel();
    settleHighlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (displayedPendingBonus > 0) {
      return ComboScorePanel(
        score: displayedScore,
        pendingBonus: displayedPendingBonus,
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedScoreValue(
        score: displayedScore,
        textColor: isBankingScore
            ? const Color(0xFFFF6B57)
            : const Color(0xFFF7F3E9),
      ),
    );
  }
}

class ComboScorePanel extends StatelessWidget {
  const ComboScorePanel({
    super.key,
    required this.score,
    required this.pendingBonus,
  });

  final int score;
  final int pendingBonus;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          score.toString(),
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFFB3A38F),
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        AnimatedPendingComboBonusValue(amount: pendingBonus, leftPadding: 0),
      ],
    );
  }
}

class AnimatedStatValue extends StatefulWidget {
  const AnimatedStatValue({
    super.key,
    required this.value,
    this.color = const Color(0xFFF7F3E9),
  });

  final int value;
  final Color color;

  @override
  State<AnimatedStatValue> createState() => _AnimatedStatValueState();
}

class _AnimatedStatValueState extends State<AnimatedStatValue> {
  late int from;
  late int to;

  @override
  void initState() {
    super.initState();
    from = widget.value;
    to = widget.value;
  }

  @override
  void didUpdateWidget(covariant AnimatedStatValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == to) {
      return;
    }
    from = to;
    to = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: from.toDouble(), end: to.toDouble()),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, Widget? child) {
        return Text(
          value.round().toString(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: widget.color,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        );
      },
    );
  }
}

class PulsingScoreValue extends StatefulWidget {
  const PulsingScoreValue({
    super.key,
    required this.score,
    required this.pulseTokenListenable,
  });

  final int score;
  final ValueListenable<int> pulseTokenListenable;

  @override
  State<PulsingScoreValue> createState() => _PulsingScoreValueState();
}

class _PulsingScoreValueState extends State<PulsingScoreValue>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> scaleAnimation;
  late final Animation<Color?> colorAnimation;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    scaleAnimation = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.1,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 32,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.1,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 68,
      ),
    ]).animate(controller);
    colorAnimation = ColorTween(
      begin: const Color(0xFFF7F3E9),
      end: const Color(0xFFFF6B57),
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
    widget.pulseTokenListenable.addListener(handlePulse);
  }

  @override
  void didUpdateWidget(covariant PulsingScoreValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(
      oldWidget.pulseTokenListenable,
      widget.pulseTokenListenable,
    )) {
      return;
    }
    oldWidget.pulseTokenListenable.removeListener(handlePulse);
    widget.pulseTokenListenable.addListener(handlePulse);
  }

  @override
  void dispose() {
    widget.pulseTokenListenable.removeListener(handlePulse);
    controller.dispose();
    super.dispose();
  }

  void handlePulse() {
    controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Transform.scale(
          scale: scaleAnimation.value,
          child: AnimatedScoreValue(
            score: widget.score,
            textColor: colorAnimation.value ?? const Color(0xFFF7F3E9),
          ),
        );
      },
    );
  }
}

class ComboProgressBar extends StatefulWidget {
  const ComboProgressBar({
    super.key,
    required this.progress,
    required this.pulseListenable,
  });

  final double progress;
  final ValueListenable<int> pulseListenable;

  @override
  State<ComboProgressBar> createState() => _ComboProgressBarState();
}

class _ComboProgressBarState extends State<ComboProgressBar>
    with SingleTickerProviderStateMixin {
  late double previousProgress;
  late final AnimationController pulseController;
  late final Animation<double> capScaleAnimation;
  late final Animation<double> capSlideAnimation;
  late final Animation<double> flashAnimation;
  late final Animation<double> labelLiftAnimation;
  late final Animation<double> labelOpacityAnimation;

  @override
  void initState() {
    super.initState();
    previousProgress = widget.progress;
    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 430),
    );
    capScaleAnimation = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.22,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 30,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1.22,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 70,
      ),
    ]).animate(pulseController);
    capSlideAnimation = Tween<double>(begin: 0, end: 7).animate(
      CurvedAnimation(parent: pulseController, curve: Curves.easeOutCubic),
    );
    flashAnimation = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 0,
          end: 0.18,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 0.18,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 82,
      ),
    ]).animate(pulseController);
    labelLiftAnimation = Tween<double>(begin: 0, end: -10).animate(
      CurvedAnimation(parent: pulseController, curve: Curves.easeOutCubic),
    );
    labelOpacityAnimation = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 0,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 24,
      ),
      TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 24),
      TweenSequenceItem<double>(
        tween: Tween<double>(
          begin: 1,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 52,
      ),
    ]).animate(pulseController);
    widget.pulseListenable.addListener(handlePulse);
  }

  @override
  void didUpdateWidget(covariant ComboProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.progress - widget.progress).abs() < 0.0001) {
      return;
    }
    previousProgress = oldWidget.progress;
    if (!identical(oldWidget.pulseListenable, widget.pulseListenable)) {
      oldWidget.pulseListenable.removeListener(handlePulse);
      widget.pulseListenable.addListener(handlePulse);
    }
  }

  @override
  void dispose() {
    widget.pulseListenable.removeListener(handlePulse);
    pulseController.dispose();
    super.dispose();
  }

  void handlePulse() {
    pulseController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final Duration duration = widget.progress > previousProgress
        ? const Duration(milliseconds: 150)
        : const Duration(milliseconds: 84);

    return IgnorePointer(
      child: SizedBox(
        height: 24,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: previousProgress,
                end: widget.progress,
              ),
              duration: duration,
              curve: Curves.linear,
              builder: (BuildContext context, double value, Widget? child) {
                final double clamped = value.clamp(0.0, 1.0);
                final double filledWidth = constraints.maxWidth * clamped;

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: <Widget>[
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: SizedBox(
                        height: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF5A5C62,
                            ).withValues(alpha: 0.34),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      bottom: 0,
                      width: filledWidth,
                      child: SizedBox(
                        height: 8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Stack(
                            children: <Widget>[
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    stops: <double>[0.0, 0.48, 1.0],
                                    colors: <Color>[
                                      Color(0xFF8A1720),
                                      Color(0xFFD83A44),
                                      Color(0xFFFF8D62),
                                    ],
                                  ),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: const Color(
                                        0xFFFF6C58,
                                      ).withValues(alpha: 0.18),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: const SizedBox.expand(),
                              ),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(
                                      alpha: flashAnimation.value,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (filledWidth > 0)
                      Positioned(
                        left: (filledWidth - 8).clamp(
                          0.0,
                          constraints.maxWidth,
                        ),
                        bottom: -1,
                        child: Transform.translate(
                          offset: Offset(capSlideAnimation.value, 0),
                          child: Transform.scale(
                            scale: capScaleAnimation.value,
                            alignment: Alignment.center,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(
                                  0xFFFFA173,
                                ).withValues(alpha: 0.92),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFF8D62,
                                    ).withValues(alpha: 0.26),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (filledWidth > 0)
                      Positioned(
                        left: (filledWidth - 12).clamp(
                          0.0,
                          constraints.maxWidth,
                        ),
                        bottom: 12,
                        child: Transform.translate(
                          offset: Offset(0, labelLiftAnimation.value),
                          child: Opacity(
                            opacity: labelOpacityAnimation.value,
                            child: const Text(
                              '+1s',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFFD7A1),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class ComboPulseOverlay extends StatefulWidget {
  const ComboPulseOverlay({super.key, required this.triggerListenable});

  final ValueListenable<int> triggerListenable;

  @override
  State<ComboPulseOverlay> createState() => _ComboPulseOverlayState();
}

class _ComboPulseOverlayState extends State<ComboPulseOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> opacity;
  late final Animation<double> scale;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    opacity = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOutCubic),
      reverseCurve: Curves.easeInCubic,
    );
    scale = Tween<double>(
      begin: 0.92,
      end: 1.02,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
    widget.triggerListenable.addListener(handleTrigger);
  }

  @override
  void didUpdateWidget(covariant ComboPulseOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.triggerListenable, widget.triggerListenable)) {
      return;
    }
    oldWidget.triggerListenable.removeListener(handleTrigger);
    widget.triggerListenable.addListener(handleTrigger);
  }

  @override
  void dispose() {
    widget.triggerListenable.removeListener(handleTrigger);
    controller.dispose();
    super.dispose();
  }

  void handleTrigger() {
    controller
      ..stop()
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: controller,
          builder: (BuildContext context, Widget? child) {
            if (controller.isDismissed) {
              return const SizedBox.shrink();
            }
            final double fadeOut =
                1 - Curves.easeIn.transform(controller.value);
            final double visibleOpacity = opacity.value * fadeOut;
            return Opacity(
              opacity: visibleOpacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale.value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF101418).withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Text(
                      'Combo',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        color: Color(0xFFFFE3D1),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
