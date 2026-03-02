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
  });

  /// 온보딩 모드로 시작할지 여부
  final bool initialOnboarding;

  /// 게임 인스턴스가 생성되었을 때 콜백 (외부에서 제어하기 위함)
  final ValueChanged<StackingGame>? onGameCreated;

  /// 게임에 사용할 돌 이미지 에셋 경로 목록
  /// null이면 AssetManifest에서 모든 'td_?_?_?' 패턴의 돌을 자동 수집합니다.
  /// 예: ['assets/images/unstructured/td_1_1_1.png', ...]
  final List<String>? stoneAssetPaths;

  /// 게임 시작 시 최초로 생성할 돌 개수 (기본값: 5)
  /// 온보딩 모드에서는 자동으로 0으로 설정됩니다.
  final int initialSpawnCount;

  /// 돌 충돌 시 햅틱(진동) 피드백 활성화 여부 (기본값: true)
  final bool enableHaptic;

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
          // 1. 공통 그라데이션 배경
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.3, 1.0],
                colors: [
                  Color(0xFF997FFF), // 상단 보라
                  Color(0xFFF293FF), // 중상단 핑크
                  Color(0xFFFFD582), // 하단 피치
                ],
              ),
            ),
          ),

          // 2. 파티클 이펙트 배경
          const ParticleBackground(),

          SafeArea(
            top: true,
            bottom: false,
            child: Stack(
              children: [
                GameWidget(game: game),

                // 기존 UI (온보딩이 아닐 때만 표시되도록)
                ValueListenableBuilder<OnboardingState>(
                  valueListenable: game.onboardingState,
                  builder: (context, state, _) {
                    if (state != OnboardingState.none) {
                      return const SizedBox.shrink();
                    }
                    return Stack(
                      children: [
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
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '돌 개수 : $count',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      ValueListenableBuilder<int>(
                                        valueListenable: game.towerHeightMeters,
                                        builder: (_, meters, __) {
                                          return _AnimatedMeterText(
                                            meters: meters,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
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
                      ],
                    );
                  },
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
  const _AnimatedMeterText({required this.meters, required this.style});

  final int meters;
  final TextStyle style;

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
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _from.toDouble(), end: _to.toDouble()),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (_, value, __) {
        return Text('높이 : ${value.round()}m', style: widget.style);
      },
    );
  }
}
