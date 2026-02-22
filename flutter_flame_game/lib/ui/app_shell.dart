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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
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
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const FlameScreen()),
            );
          },
          child: const Text('시작'),
        ),
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

  /// 돌 에셋 일부를 무작위로 로드한 뒤 게임 인스턴스를 생성합니다.
  ///
  /// 비동기 준비/오류 처리는 Flutter에서 담당하고,
  /// Flame 쪽은 게임 플레이에 집중하도록 분리합니다.
  Future<void> _prepareGame() async {
    try {
      final selectedAssets = await _pickRandomUnstructuredStoneAssets(count: 5);
      for (final asset in selectedAssets) {
        await rootBundle.load(asset);
      }

      if (!mounted) return;
      setState(() {
        _game = StackingGame(
          stoneSpriteAssets: selectedAssets,
          enableImageCollisionHints: true,
          debugDrawCollisionShapes: _debugEnabled,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '이미지 로딩 실패: $e';
      });
    }
  }

  /// `AssetManifest`에서 비정형 돌 PNG를 무작위로 선택합니다.
  Future<List<String>> _pickRandomUnstructuredStoneAssets({
    required int count,
  }) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final candidates = manifest
        .listAssets()
        .where(
          (path) =>
              path.startsWith('assets/images/unstructured/') &&
              path.endsWith('.png') &&
              path.contains('td_1_'),
        )
        .toList(growable: true);
    candidates.sort();
    candidates.shuffle(math.Random());

    if (candidates.length <= count) {
      return candidates;
    }
    return candidates.take(count).toList(growable: false);
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: ValueListenableBuilder<int>(
                    valueListenable: game.activeStoneCount,
                    builder: (_, count, __) {
                      return Text(
                        'Active: $count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FilledButton.tonal(
                    onPressed: game.spawnNow,
                    child: const Text('Spawn'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: game.resetGame,
                    child: const Text('Reset'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () {
                      final next = !_debugEnabled;
                      setState(() {
                        _debugEnabled = next;
                      });
                      game.setDebugCollisionRendering(next);
                    },
                    child: Text(_debugEnabled ? 'Debug: ON' : 'Debug: OFF'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
