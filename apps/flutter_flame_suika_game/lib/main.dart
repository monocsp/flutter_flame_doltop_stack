import 'package:flutter/material.dart';
import 'package:flutter_flame_breath_journey_game/ui/intro_screen.dart';
import 'package:flutter_flame_breath_star/ui/intro_screen.dart' as star;
import 'package:flutter_flame_game/ui/app_shell.dart';
import 'package:flutter_flame_game/ui/widgets/particle_background.dart';
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

/// 현재 스택 게임 화면을 라우트 단위로 제공합니다.
class StackGameRoute extends StatelessWidget {
  /// 스택 게임 라우트를 생성합니다.
  const StackGameRoute({super.key});

  static const LinearGradient _backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: <double>[0.0, 0.3, 1.0],
    colors: <Color>[Color(0xFF997FFF), Color(0xFFF293FF), Color(0xFFFFD582)],
  );

  static const List<String> _backgroundAssetPaths = <String>[
    'assets/background/1.png',
    'assets/background/2.png',
    'assets/background/3.png',
    'assets/background/4.png',
    'assets/background/5.png',
    'assets/background/6.png',
  ];

  static const String _backgroundBaseAssetPath = 'assets/background/base.png';

  @override
  Widget build(BuildContext context) {
    return const FlameScreen(
      backgroundGradient: _backgroundGradient,
      backgroundWidget: ParticleBackground(),
      backgroundAssetPaths: _backgroundAssetPaths,
      backgroundBaseAssetPath: _backgroundBaseAssetPath,
    );
  }
}

/// Suika 게임 화면을 라우트 단위로 제공합니다.
class SuikaGameRoute extends StatelessWidget {
  /// Suika 게임 라우트를 생성합니다.
  const SuikaGameRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return SuikaScreen();
  }
}

/// 호흡 여정 게임을 라우트 단위로 제공합니다.
class BreathJourneyRoute extends StatelessWidget {
  /// 호흡 여정 라우트를 생성합니다.
  const BreathJourneyRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const IntroScreen();
  }
}

/// 별자리 호흡 게임을 라우트 단위로 제공합니다.
class BreathStarRoute extends StatelessWidget {
  /// 별자리 호흡 라우트를 생성합니다.
  const BreathStarRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const star.IntroScreen();
  }
}
