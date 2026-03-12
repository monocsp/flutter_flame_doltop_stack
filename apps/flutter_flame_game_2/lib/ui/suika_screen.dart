import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flame_game_2/game/suika/stone_spec.dart';
import 'package:flutter_flame_game_2/game/suika/suika_game.dart';
import 'package:flutter_flame_game_2/game/suika/suika_hud_state.dart';

/// Suika 게임과 Flutter HUD를 한 화면에 조합합니다.
class SuikaScreen extends StatefulWidget {
  /// Suika 메인 화면을 생성합니다.
  const SuikaScreen({super.key});

  @override
  State<SuikaScreen> createState() => SuikaScreenState();
}

/// 게임 인스턴스 재생성과 HUD 연결을 관리합니다.
class SuikaScreenState extends State<SuikaScreen> {
  /// ValueNotifier 기반으로 세션과 게임 참조를 관리합니다.
  SuikaScreenState();

  late final SuikaHudState hudState;
  late final ValueNotifier<int> sessionVersion;
  late final ValueNotifier<SuikaGame?> currentGame;

  @override
  void initState() {
    super.initState();
    hudState = SuikaHudState();
    sessionVersion = ValueNotifier<int>(0);
    currentGame = ValueNotifier<SuikaGame?>(null);
  }

  @override
  void dispose() {
    currentGame.dispose();
    sessionVersion.dispose();
    hudState.dispose();
    super.dispose();
  }

  /// 새 세션 번호를 발급해 게임 위젯을 교체합니다.
  void restartGame() {
    sessionVersion.value = sessionVersion.value + 1;
  }

  /// 입력 위치를 비율로 바꿔 스포너를 이동시킵니다.
  void handlePan(BuildContext context, DragUpdateDetails details) {
    final Size size = MediaQuery.sizeOf(context);
    final double ratio = details.localPosition.dx / size.width;
    currentGame.value?.moveSpawnerByRatio(ratio);
  }

  /// 탭 위치를 기준으로 스포너를 옮기고 즉시 드롭합니다.
  void handleTap(BuildContext context, TapUpDetails details) {
    final Size size = MediaQuery.sizeOf(context);
    final double ratio = details.localPosition.dx / size.width;
    final SuikaGame? game = currentGame.value;
    if (game == null) {
      return;
    }
    game.moveSpawnerByRatio(ratio);
    game.dropCurrentStone();
  }

  /// 드래그 종료 시 현재 위치에서 스톤을 떨어뜨립니다.
  void handlePanEnd() {
    currentGame.value?.dropCurrentStone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF1D1E24),
              Color(0xFF2E1F1A),
              Color(0xFF5C3D2E),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return ValueListenableBuilder<int>(
                valueListenable: sessionVersion,
                builder: (BuildContext context, int version, Widget? child) {
                  final SuikaGame game = createGame(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  );
                  currentGame.value = game;
                  return Stack(
                    children: <Widget>[
                      buildInteractiveGameLayer(context, game),
                      buildHud(),
                      buildGameOverOverlay(),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// 화면 비율에 맞춰 새 게임 인스턴스를 만듭니다.
  SuikaGame createGame({
    required double width,
    required double height,
  }) {
    final double worldWidth = 10.2;
    final double worldHeight = worldWidth * (height / width).clamp(1.4, 2.0);
    return SuikaGame(
      hudState: hudState,
      boardWidth: worldWidth,
      boardHeight: worldHeight,
    );
  }

  /// Flutter 입력을 우선 받아 드롭 조작을 단순화합니다.
  Widget buildInteractiveGameLayer(BuildContext context, SuikaGame game) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (TapUpDetails details) => handleTap(context, details),
      onPanDown: (DragDownDetails details) {
        final double ratio = details.localPosition.dx / MediaQuery.sizeOf(context).width;
        game.moveSpawnerByRatio(ratio);
      },
      onPanUpdate: (DragUpdateDetails details) => handlePan(context, details),
      onPanEnd: (DragEndDetails details) => handlePanEnd(),
      child: GameWidget<SuikaGame>(game: game),
    );
  }

  /// 점수, 미리보기, 제어 버튼을 상단 HUD로 제공합니다.
  Widget buildHud() {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF11151C).withValues(alpha: 0.54),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFF7F3E9).withValues(alpha: 0.14),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: <Widget>[
                Expanded(child: buildScoreColumn()),
                const SizedBox(width: 12),
                buildNextStonePreview(),
                const SizedBox(width: 12),
                buildActionButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 현재 점수와 최고 점수를 세로로 배치합니다.
  Widget buildScoreColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'SUiKA LOOP',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
            color: Color(0xFFF7C59F),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<int>(
          valueListenable: hudState.score,
          builder: (BuildContext context, int value, Widget? child) {
            return Text(
              'Score $value',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        ValueListenableBuilder<int>(
          valueListenable: hudState.bestScore,
          builder: (BuildContext context, int value, Widget? child) {
            return Text(
              'Best $value',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFFD9CAB3),
              ),
            );
          },
        ),
      ],
    );
  }

  /// 다음 단계 미리보기를 작은 원형 카드로 보여줍니다.
  Widget buildNextStonePreview() {
    return ValueListenableBuilder<StoneSpec>(
      valueListenable: hudState.nextStone,
      builder: (BuildContext context, StoneSpec spec, Widget? child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'NEXT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: Color(0xFFD9CAB3),
              ),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: spec.color,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: spec.color.withValues(alpha: 0.34),
                    blurRadius: 18,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                spec.label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFAF5EF),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 재시작과 일시정지 버튼을 제공합니다.
  Widget buildActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextButton(
          onPressed: restartGame,
          child: const Text('Restart'),
        ),
        const SizedBox(height: 4),
        ValueListenableBuilder<bool>(
          valueListenable: hudState.isPaused,
          builder: (BuildContext context, bool isPaused, Widget? child) {
            return TextButton(
              onPressed: () => currentGame.value?.togglePause(),
              child: Text(isPaused ? 'Resume' : 'Pause'),
            );
          },
        ),
      ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
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
                        builder: (BuildContext context, int value, Widget? child) {
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
}
