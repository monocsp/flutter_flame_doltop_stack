import 'dart:async';

import 'package:flame/game.dart';
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
        buildCatalogButton(),
        const SizedBox(width: 10),
        buildRestartButton(),
      ],
    );
  }

  /// 현재 점수와 최고 점수를 컴팩트한 카드로 배치합니다.
  Widget buildScorePanel() {
    return ValueListenableBuilder<int>(
      valueListenable: hudState.score,
      builder: (BuildContext context, int score, Widget? child) {
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
            buildMetricCard(
              minWidth: 148,
              child: AnimatedScoreValue(score: score),
            ),
          ],
        );
      },
    );
  }

  /// 점수 카드 1개를 구성합니다.
  Widget buildMetricCard({
    required Widget child,
    double? minWidth,
  }) {
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
    final bool shouldResume =
        game != null && !game.isGameOver && !game.paused;
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
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Text(
            'CATALOG',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Color(0xFFD9CAB3),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 54,
            height: 54,
            child: FilledButton(
              onPressed: openStoneCatalogSheet,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF28303A),
                foregroundColor: const Color(0xFFFDF7ED),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Icon(Icons.auto_awesome_mosaic_rounded, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  /// 재시작 버튼만 제공합니다.
  Widget buildRestartButton() {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: restartGame,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFE76F51),
          foregroundColor: const Color(0xFFFDF7ED),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'Restart',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
    );
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
            builder: (
              BuildContext context,
              Set<int> revealedStages,
              Widget? child,
            ) {
              return Column(
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
                    '1~6 단계는 기본 공개됩니다. 7~9 단계는 게임에서 처음 등장하면 해금됩니다.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFFD9CAB3),
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
                          child: RawImage(image: asset.image, fit: BoxFit.contain),
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
    return Center(
      child: ValueListenableBuilder<bool>(
        valueListenable: hudState.isGameOver,
        builder: (BuildContext context, bool isGameOver, Widget? child) {
          return IgnorePointer(
            ignoring: !isGameOver,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: isGameOver ? 1 : 0,
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
                        ),
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<int>(
                        valueListenable: hudState.score,
                        builder:
                            (BuildContext context, int value, Widget? child) {
                              return Text(
                                'Final Score $value',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFFD9CAB3),
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
          );
        },
      ),
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
                      builder: (
                        BuildContext context,
                        BoxConstraints constraints,
                      ) {
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
                                buildGameOverOverlay(),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
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
}

class AnimatedScoreValue extends StatefulWidget {
  const AnimatedScoreValue({super.key, required this.score});

  final int score;

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
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: from.toDouble(), end: to.toDouble()),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, Widget? child) {
        return Text(
          value.round().toString(),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        );
      },
    );
  }
}
