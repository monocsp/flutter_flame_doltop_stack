import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/stacking_game.dart';

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
