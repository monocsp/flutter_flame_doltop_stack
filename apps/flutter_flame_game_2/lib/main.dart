import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flame_game_2/game/basic/basic_flame_game.dart';
import 'package:flutter_flame_game_2/ui/game_select_screen.dart';
import 'package:flutter_flame_game_2/ui/suika_screen.dart';

/// 앱의 게임 선택 진입점을 초기화합니다.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GameHubApp());
}

/// 두 게임으로 이동할 수 있는 앱 루트를 제공합니다.
class GameHubApp extends StatelessWidget {
  /// 앱 루트를 구성합니다.
  const GameHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF15161B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF28C28),
          brightness: Brightness.dark,
        ),
        textTheme: Theme.of(context).textTheme.apply(
              bodyColor: const Color(0xFFF7F3E9),
              displayColor: const Color(0xFFF7F3E9),
            ),
      ),
      home: const GameSelectScreen(),
    );
  }
}

/// 기존 샘플 Flame 게임 화면을 제공합니다.
class BasicGameScreen extends StatelessWidget {
  /// 샘플 게임 진입 화면을 생성합니다.
  const BasicGameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Basic Flame Game'),
      ),
      body: GameWidget<BasicFlameGame>(
        game: BasicFlameGame(),
      ),
    );
  }
}

/// Suika 게임 화면을 라우트 단위로 제공합니다.
class SuikaGameRoute extends StatelessWidget {
  /// Suika 게임 라우트를 생성합니다.
  const SuikaGameRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const SuikaScreen();
  }
}
