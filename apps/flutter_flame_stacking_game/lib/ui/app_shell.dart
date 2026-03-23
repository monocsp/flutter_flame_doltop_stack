import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/stacking_game.dart';
import 'onboarding_screen.dart';
import 'widgets/particle_background.dart';

/// Flutter 앱의 루트 셸입니다.
///
/// `MaterialApp` 설정과 게임 화면 라우팅을 담당합니다.
class StackingApp extends StatelessWidget {
  const StackingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Flame Start',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        fontFamily: 'Pretendard',
      ),
      home: const OnboardingScreen(),
    );
  }
}

/// 에셋을 준비하고 Flame `GameWidget`을 올리는 화면입니다.
///
/// 주요 매개변수:
/// - [stoneAssetPaths]: 게임에 사용할 돌 이미지 에셋 경로 목록.
///   null이면 AssetManifest에서 자동으로 수집합니다.
/// - [initialSpawnCount]: 게임 시작 시 최초로 떨어뜨릴 돌 개수 (기본값: 5)
/// - [enableHaptic]: 돌 충돌 시 햅틱(진동) 피드백 활성화 여부 (기본값: true)
class FlameScreen extends StatefulWidget {
  const FlameScreen({
    super.key,
    this.initialOnboarding = false,
    this.onGameCreated,
    this.stoneAssetPaths,
    this.initialSpawnCount = 5,
    this.enableHaptic = true,
    this.difficulty = DifficultyLevel.easy,
    this.backgroundGradient,
    this.backgroundWidget,
    this.backgroundAssetPaths,
    this.backgroundBaseAssetPath,
  });

  /// 온보딩 모드로 시작할지 여부
  final bool initialOnboarding;

  /// 게임 인스턴스가 생성되었을 때 콜백 (외부에서 제어하기 위함)
  final ValueChanged<StackingGame>? onGameCreated;

  /// 게임에 사용할 돌 이미지 에셋 경로 목록
  /// null이면 AssetManifest에서 모든 'td_?_?_?' 패턴의 돌을 자동 수집합니다.
  final List<String>? stoneAssetPaths;

  /// 게임 시작 시 최초로 생성할 돌 개수 (기본값: 5)
  final int initialSpawnCount;

  /// 돌 충돌 시 햅틱(진동) 피드백 활성화 여부 (기본값: true)
  final bool enableHaptic;

  /// 게임 난이도 (기본값: easy)
  final DifficultyLevel difficulty;

  /// Flutter UI 레이어의 그라데이션 배경 (null이면 기본 그라데이션 사용)
  final Gradient? backgroundGradient;

  /// Flutter UI 레이어의 파티클/배경 위젯 (null이면 기본 ParticleBackground 사용)
  final Widget? backgroundWidget;

  /// Flame 월드 내 루핑 배경 이미지 에셋 경로 (null이면 Flame 배경 없음)
  final List<String>? backgroundAssetPaths;

  /// Flame 월드 내 바닥 오버레이 에셋 경로 (null이면 바닥 오버레이 없음)
  final String? backgroundBaseAssetPath;

  @override
  State<FlameScreen> createState() => _FlameScreenState();
}

class _FlameScreenState extends State<FlameScreen> {
  StackingGame? _game;
  String? _errorMessage;
  final bool _debugEnabled = false;

  @override
  void initState() {
    super.initState();
    _prepareGame();
  }

  /// 돌 에셋 전체 목록을 준비합니다.
  /// [stoneAssetPaths]가 지정되어 있으면 해당 목록을 사용하고,
  /// null이면 AssetManifest에서 자동으로 수집합니다.
  Future<void> _prepareGame() async {
    try {
      final allAssets =
          widget.stoneAssetPaths ?? await _collectAllStoneAssets();

      if (!mounted) return;
      final game = StackingGame(
        stoneSpriteAssets: allAssets,
        enableImageCollisionHints: true,
        debugDrawCollisionShapes: _debugEnabled,
        initialOnboarding: widget.initialOnboarding,
        initialSpawnCount: widget.initialOnboarding
            ? 0
            : widget.initialSpawnCount,
        enableHaptic: widget.enableHaptic,
        difficulty: widget.difficulty,
        backgroundAssetPaths: widget.backgroundAssetPaths,
        backgroundBaseAssetPath: widget.backgroundBaseAssetPath,
      );

      setState(() {
        _game = game;
      });

      widget.onGameCreated?.call(game);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '이미지 목록 로딩 실패: $e';
      });
    }
  }

  /// `AssetManifest`에서 모든 'td_?_?_?' 패턴의 돌 에셋을 수집합니다.
  Future<List<String>> _collectAllStoneAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final candidates = manifest
        .listAssets()
        .where(
          (path) =>
              (path.contains('assets/images/unstructured/') ||
                  path.contains('assets/images/structured/')) &&
              path.endsWith('.png') &&
              RegExp(r'td_\d+_\d+_\d+').hasMatch(path),
        )
        .toList(growable: true);

    // 무작위성을 위해 섞어서 반환합니다.
    candidates.shuffle(math.Random());
    return candidates;
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.transparent, // 투명 처리
        body: SafeArea(
          child: Center(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_game == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent, // 투명 처리
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 12),
                Text('돌 이미지 로딩 중...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      );
    }

    final game = _game!;
    return Scaffold(
      backgroundColor: Colors.transparent, // 배경 투명
      body: Stack(
        children: [
          // 1. 배경 (그라데이션 또는 커스텀)
          if (widget.backgroundGradient != null)
            Container(
              decoration: BoxDecoration(gradient: widget.backgroundGradient),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.3, 1.0],
                  colors: [
                    Color(0xFF997FFF),
                    Color(0xFFF293FF),
                    Color(0xFFFFD582),
                  ],
                ),
              ),
            ),

          // 2. 파티클 이펙트 배경 (커스텀 또는 기본)
          widget.backgroundWidget ?? const ParticleBackground(),

          SafeArea(
            top: true,
            bottom: false,
            child: Stack(
              children: [
                GameWidget(game: game),

                // 기존 UI (온보딩이 아닐 때만 표시되도록)
                Positioned.fill(
                  child: ValueListenableBuilder<OnboardingState>(
                    valueListenable: game.onboardingState,
                    builder: (context, state, _) {
                      if (state != OnboardingState.none) {
                        return const SizedBox.shrink();
                      }
                      return Stack(
                        children: [
                          // ── HUD 좌측 상단 ──────────────────
                          Positioned(
                            top: 12,
                            left: 12,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(140),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: ValueListenableBuilder<int>(
                                  valueListenable: game.activeStoneCount,
                                  builder: (_, count, __) {
                                    return ValueListenableBuilder<bool>(
                                      valueListenable: game.difficultyCleared,
                                      builder: (_, cleared, __) {
                                        return ValueListenableBuilder<bool>(
                                          valueListenable: game.goalReached,
                                          builder: (_, goalHit, __) {
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // 난이도 라벨 (클리어 시 초록색 + 탭 가능)
                                                GestureDetector(
                                                  onTap: cleared
                                                      ? () => game
                                                            .advanceToNextLevel()
                                                      : null,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        '난이도 : ${game.difficulty.label}',
                                                        style: TextStyle(
                                                          color: cleared
                                                              ? const Color(
                                                                  0xFF4CAF50,
                                                                )
                                                              : Colors.white70,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      if (cleared) ...[
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        const Text(
                                                          '✓',
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFF4CAF50,
                                                            ),
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 2),

                                                // 돌 개수
                                                Text(
                                                  '돌 개수 : $count / ${StackingGame.maxActiveStones}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),

                                                // 높이 + 목표
                                                ValueListenableBuilder<int>(
                                                  valueListenable:
                                                      game.towerHeightMeters,
                                                  builder: (_, meters, __) {
                                                    final target = game
                                                        .difficulty
                                                        .targetHeight;
                                                    return _AnimatedMeterText(
                                                      meters: meters,
                                                      targetMeters: target,
                                                      style: TextStyle(
                                                        color: goalHit
                                                            ? const Color(
                                                                0xFF4CAF50,
                                                              )
                                                            : Colors.white,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),

                          // ── 우측 상단 추가 버튼 ──────────────
                          Positioned(
                            top: 12,
                            right: 12,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(140),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: TextButton(
                                onPressed: game.spawnNow,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: const Text('추가'),
                              ),
                            ),
                          ),

                          // ── 카운트다운 오버레이 (3→2→1) ──────
                          ValueListenableBuilder<int>(
                            valueListenable: game.stableCountdown,
                            builder: (_, countdown, __) {
                              if (countdown < 1 || countdown > 3) {
                                return const SizedBox.shrink();
                              }
                              return Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: Text(
                                    '$countdown',
                                    key: ValueKey(countdown),
                                    style: TextStyle(
                                      fontSize: 120,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white.withAlpha(200),
                                      shadows: [
                                        Shadow(
                                          blurRadius: 30,
                                          color: Colors.black.withAlpha(100),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          // ── 성공 다이얼로그 오버레이 ──────────
                          ValueListenableBuilder<bool>(
                            valueListenable: game.levelCleared,
                            builder: (_, cleared, __) {
                              if (!cleared) return const SizedBox.shrink();
                              final hasNext = game.difficulty.nextLevel != null;
                              return Container(
                                color: Colors.black.withAlpha(140),
                                child: Center(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 40,
                                    ),
                                    padding: const EdgeInsets.all(32),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          blurRadius: 20,
                                          color: Colors.black.withAlpha(60),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          '🎉',
                                          style: TextStyle(fontSize: 48),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          '${game.difficulty.label} 난이도 성공!',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${game.difficulty.targetHeight}m 달성',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // 머무르기 버튼
                                            OutlinedButton(
                                              onPressed: () =>
                                                  game.stayAtCurrentLevel(),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.black87,
                                                side: const BorderSide(
                                                  color: Colors.black26,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              child: const Text('머무르기'),
                                            ),
                                            if (hasNext) ...[
                                              const SizedBox(width: 12),
                                              // 다음 단계 버튼
                                              ElevatedButton(
                                                onPressed: () =>
                                                    game.advanceToNextLevel(),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFF4CAF50,
                                                  ),
                                                  foregroundColor: Colors.white,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 20,
                                                        vertical: 12,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text('다음 단계'),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedMeterText extends StatefulWidget {
  const _AnimatedMeterText({
    required this.meters,
    required this.style,
    this.targetMeters,
  });

  final int meters;
  final TextStyle style;

  /// 목표 높이 (null이면 표시하지 않음)
  final int? targetMeters;

  @override
  State<_AnimatedMeterText> createState() => _AnimatedMeterTextState();
}

class _AnimatedMeterTextState extends State<_AnimatedMeterText> {
  late int _from;
  late int _to;

  @override
  void initState() {
    super.initState();
    _from = widget.meters;
    _to = widget.meters;
  }

  @override
  void didUpdateWidget(covariant _AnimatedMeterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.meters != _to) {
      _from = _to;
      _to = widget.meters;
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.targetMeters;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _from.toDouble(), end: _to.toDouble()),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) {
        final heightStr = '높이 : ${value.round()}m';
        final display = target != null ? '$heightStr / ${target}m' : heightStr;
        return Text(display, style: widget.style);
      },
    );
  }
}
