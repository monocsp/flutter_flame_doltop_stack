import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/stacking_game.dart';

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
      home: const HomeScreen(),
    );
  }
}

/// Flame 장면으로 진입하는 간단한 시작 화면입니다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 그라데이션 배경
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.3, 1.0],
                colors: [
                  Color(0xFF997FFF), // 상단 (우측 끝에 있던 100% 보라색)
                  Color(0xFFF293FF), // 중상단 (30% 핑크색)
                  Color(0xFFFFD582), // 하단 (0% 노란/피치색)
                ],
              ),
            ),
          ),

          // 2. 파티클 효과 (임시: TODO 애니메이션)
          // 구현하려면 CustomPainter나 AnimatedBuilder를 사용해 별빛들을 그려줘야 합니다.

          // 3. 중앙 텍스트
          const Center(
            child: Text(
              '천천히 느껴지는\n감각에 집중해 보세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),

          // 4. 닫기/취소 버튼 (시작 버튼으로 일단 기능 연결)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const FlameScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 에셋을 준비하고 Flame `GameWidget`을 올리는 화면입니다.
class FlameScreen extends StatefulWidget {
  const FlameScreen({super.key});

  @override
  State<FlameScreen> createState() => _FlameScreenState();
}

class _FlameScreenState extends State<FlameScreen> {
  StackingGame? _game;
  String? _errorMessage;
  bool _debugEnabled = false;

  @override
  void initState() {
    super.initState();
    _prepareGame();
  }

  /// 돌 에셋 전체 목록을 준비합니다.
  /// 이제 제한된 개수가 아닌 사용 가능한 모든 돌 에셋을 수집합니다.
  Future<void> _prepareGame() async {
    try {
      final allAssets = await _collectAllStoneAssets();

      if (!mounted) return;
      setState(() {
        _game = StackingGame(
          stoneSpriteAssets: allAssets,
          enableImageCollisionHints: true,
          debugDrawCollisionShapes: _debugEnabled,
        );
      });
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
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('돌 이미지 로딩 중...'),
              ],
            ),
          ),
        ),
      );
    }

    final game = _game!;
    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: Stack(
          children: [
            GameWidget(game: game),
            Positioned(
              top: 12,
              left: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                  color: Colors.black.withValues(alpha: 0.55),
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
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  child: const Text('추가'),
                ),
              ),
            ),
          ],
        ),
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
