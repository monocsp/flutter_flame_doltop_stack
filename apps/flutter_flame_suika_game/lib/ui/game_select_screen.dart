import 'dart:math' show sin;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_flame_game_2/main.dart';

enum GameCardTitleStyle { normal, rising, growing, breathing, twinkling }

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
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
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
                        color: Color(0xFFF7F3E9),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '스택 게임, 수박게임, 호흡 여정, 별자리 호흡을 선택해 실행할 수 있습니다.',
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
                      title: '어디까지 올라가는거에요?',
                      description: '평온한 마음으로 돌탑을 조심히 쌓아올려보아요',
                      titleStyle: GameCardTitleStyle.rising,
                      accentColor: const Color(0xFF1F6FEB),
                      onTap: () => openGame(context, const StackGameRoute()),
                    ),
                    const SizedBox(height: 16),
                    buildGameCard(
                      context: context,
                      title: '어디까지 커지는거에요?',
                      description: '같은 돌을 합쳐서 제한된 높이까지 가장 많은 점수를 모아보세요',
                      titleStyle: GameCardTitleStyle.growing,
                      accentColor: const Color(0xFFF28C28),
                      onTap: () => openGame(context, const SuikaGameRoute()),
                    ),
                    const SizedBox(height: 16),
                    buildGameCard(
                      context: context,
                      title: '어디까지 날아가는거에요?',
                      description: '호흡으로 민들레 씨앗을 날려보세요. 오래 내쉴수록 멀리 날아가요',
                      titleStyle: GameCardTitleStyle.breathing,
                      accentColor: const Color(0xFF7ADAA5),
                      onTap: () =>
                          openGame(context, const BreathJourneyRoute()),
                    ),
                    const SizedBox(height: 16),
                    buildGameCard(
                      context: context,
                      title: '어디까지 이어지는거에요?',
                      description: '호흡으로 밤하늘에 별자리를 그려보세요. 숨결이 별을 잇습니다',
                      titleStyle: GameCardTitleStyle.twinkling,
                      accentColor: const Color(0xFF9EDCFF),
                      onTap: () =>
                          openGame(context, const BreathStarRoute()),
                    ),
                  ],
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
    GameCardTitleStyle titleStyle = GameCardTitleStyle.normal,
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
                    buildTitleWidget(title: title, titleStyle: titleStyle),
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

  Widget buildTitleWidget({
    required String title,
    required GameCardTitleStyle titleStyle,
  }) {
    switch (titleStyle) {
      case GameCardTitleStyle.rising:
        return RisingTitleText(text: title);
      case GameCardTitleStyle.growing:
        return GrowingTitleText(text: title);
      case GameCardTitleStyle.breathing:
        return BreathingTitleText(text: title);
      case GameCardTitleStyle.twinkling:
        return TwinklingTitleText(text: title);
      case GameCardTitleStyle.normal:
        return Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFFF7F3E9),
          ),
        );
    }
  }

  /// 선택한 게임 화면으로 라우팅합니다.
  void openGame(BuildContext context, Widget screen) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (BuildContext context) => screen));
  }
}

class RisingTitleText extends StatelessWidget {
  const RisingTitleText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final List<String> glyphs = text.split('');
    const TextStyle style = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: Color(0xFFF7F3E9),
      letterSpacing: -0.6,
      height: 1,
    );
    return SizedBox(
      height: 36,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List<Widget>.generate(glyphs.length, (int index) {
              final double lift = index * 1.15;
              return Transform.translate(
                offset: Offset(0, -lift),
                child: Text(glyphs[index], style: style),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class GrowingTitleText extends StatelessWidget {
  const GrowingTitleText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final List<String> glyphs = text.split('');
    const double minFontSize = 17;
    const double maxFontSize = 28;
    return SizedBox(
      height: 38,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List<Widget>.generate(glyphs.length, (int index) {
              final double t = glyphs.length <= 1
                  ? 1
                  : index / (glyphs.length - 1);
              final double fontSize = lerpDouble(minFontSize, maxFontSize, t)!;
              return Padding(
                padding: const EdgeInsets.only(right: 0.4),
                child: Text(
                  glyphs[index],
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFF7F3E9),
                    letterSpacing: -0.7,
                    height: 1,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class BreathingTitleText extends StatefulWidget {
  const BreathingTitleText({super.key, required this.text});

  final String text;

  @override
  State<BreathingTitleText> createState() => _BreathingTitleTextState();
}

class _BreathingTitleTextState extends State<BreathingTitleText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> glyphs = widget.text.split('');
    return SizedBox(
      height: 36,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomLeft,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children:
                    List<Widget>.generate(glyphs.length, (int index) {
                      final double phase = index / glyphs.length;
                      final double wave =
                          sin((_controller.value + phase) * 3.14159 * 2) *
                              0.5 +
                          0.5;
                      final double opacity = lerpDouble(0.5, 1.0, wave)!;
                      final double scale = lerpDouble(0.95, 1.05, wave)!;
                      return Opacity(
                        opacity: opacity,
                        child: Transform.scale(
                          scale: scale,
                          child: Text(
                            glyphs[index],
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF7F3E9),
                              letterSpacing: -0.6,
                              height: 1,
                            ),
                          ),
                        ),
                      );
                    }),
              );
            },
          ),
        ),
      ),
    );
  }
}

class TwinklingTitleText extends StatefulWidget {
  const TwinklingTitleText({super.key, required this.text});

  final String text;

  @override
  State<TwinklingTitleText> createState() => _TwinklingTitleTextState();
}

class _TwinklingTitleTextState extends State<TwinklingTitleText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<String> glyphs = widget.text.split('');
    return SizedBox(
      height: 36,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.bottomLeft,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children:
                    List<Widget>.generate(glyphs.length, (int index) {
                      final double phase = index / glyphs.length;
                      final double wave =
                          sin((_controller.value + phase) * 3.14159 * 3) *
                              0.5 +
                          0.5;
                      final double opacity = lerpDouble(0.4, 1.0, wave)!;
                      return Opacity(
                        opacity: opacity,
                        child: Text(
                          glyphs[index],
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFF7F3E9),
                            letterSpacing: -0.6,
                            height: 1,
                          ),
                        ),
                      );
                    }),
              );
            },
          ),
        ),
      ),
    );
  }
}
