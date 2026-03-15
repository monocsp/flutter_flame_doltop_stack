import 'package:flutter/material.dart';
import 'package:flutter_flame_game_2/main.dart';

/// 앱 시작 시 플레이할 게임을 선택할 수 있게 합니다.
class GameSelectScreen extends StatelessWidget {
  /// 게임 선택 화면을 생성합니다.
  const GameSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF17181D),
              Color(0xFF23262F),
              Color(0xFF4A2F24),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'FLAME GAME HUB',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.8,
                        color: Color(0xFFF7C59F),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '플레이할 게임을 선택하세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '현재 플레이 가능한 스택 게임과 수박게임 모드를 선택해 실행할 수 있습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFFD9CAB3),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    buildGameCard(
                      context: context,
                      title: '스택게임',
                      description: '현재 구현된 적층 플레이를 바로 실행합니다.',
                      accentColor: const Color(0xFF1F6FEB),
                      onTap: () => openGame(context, const StackGameRoute()),
                    ),
                    const SizedBox(height: 16),
                    buildGameCard(
                      context: context,
                      title: '수박게임',
                      description: '같은 숫자를 합치며 점수를 올리는 수박게임 모드입니다.',
                      accentColor: const Color(0xFFF28C28),
                      onTap: () => openGame(context, const SuikaGameRoute()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 선택 카드 공통 UI를 재사용 가능한 메서드로 구성합니다.
  Widget buildGameCard({
    required BuildContext context,
    required String title,
    required String description,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: <Color>[
              accentColor.withValues(alpha: 0.22),
              const Color(0xFF11151C).withValues(alpha: 0.94),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: accentColor.withValues(alpha: 0.42)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accentColor.withValues(alpha: 0.14),
              blurRadius: 26,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Color(0xFFD9CAB3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward_rounded, color: Color(0xFFF7F3E9)),
            ],
          ),
        ),
      ),
    );
  }

  /// 선택한 게임 화면으로 라우팅합니다.
  void openGame(BuildContext context, Widget screen) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (BuildContext context) => screen));
  }
}
