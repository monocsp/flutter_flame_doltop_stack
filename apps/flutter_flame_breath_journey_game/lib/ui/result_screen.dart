import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'intro_screen.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.totalSeeds});

  final int totalSeeds;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  static const int _visualSeedCount = 18;
  final Random _random = Random();

  late List<AnimationController> _seedControllers;
  late List<double> _seedX;
  late List<double> _seedDrift;
  late List<double> _seedSizes;

  late AnimationController _countController;
  late Animation<int> _countAnimation;

  late AnimationController _textController;
  late Animation<double> _text1Fade;
  late Animation<double> _text2Fade;
  late Animation<double> _text3Fade;

  late AnimationController _headerController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();
    _setupSeedAnimations();
    _setupHeaderAnimation();
    _setupCountAnimation();
    _setupTextAnimations();

    _headerController.forward();

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _countController.forward();
    });

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) _textController.forward();
    });
  }

  void _setupSeedAnimations() {
    _seedX = List.generate(_visualSeedCount, (_) => _random.nextDouble());
    _seedDrift =
        List.generate(_visualSeedCount, (_) => (_random.nextDouble() - 0.5) * 0.08);
    _seedSizes =
        List.generate(_visualSeedCount, (_) => 0.35 + _random.nextDouble() * 0.55);

    _seedControllers = List.generate(_visualSeedCount, (i) {
      final duration =
          Duration(milliseconds: 3500 + _random.nextInt(3500));
      final ctrl = AnimationController(
        vsync: this,
        duration: duration,
        value: _random.nextDouble(),
      );
      ctrl.repeat();
      return ctrl;
    });
  }

  void _setupHeaderAnimation() {
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerFade = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOut,
    );
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerController, curve: Curves.easeOut));
  }

  void _setupCountAnimation() {
    _countController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _countAnimation = IntTween(begin: 0, end: widget.totalSeeds).animate(
      CurvedAnimation(parent: _countController, curve: Curves.easeOut),
    );
  }

  void _setupTextAnimations() {
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    _text1Fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
      ),
    );
    _text2Fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.3, 0.65, curve: Curves.easeIn),
      ),
    );
    _text3Fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.62, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    for (final ctrl in _seedControllers) {
      ctrl.dispose();
    }
    _countController.dispose();
    _textController.dispose();
    _headerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1F2D),
      body: Stack(
        children: [
          // Background
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0D1F2D),
                  Color(0xFF132A3B),
                  Color(0xFF1A3548),
                ],
              ),
            ),
            child: SizedBox.expand(),
          ),

          // 민들레 본체 (하단 우측, 씨앗이 다 날아간 모습)
          Positioned(
            right: -20,
            bottom: -60,
            child: Opacity(
              opacity: 0.12,
              child: SvgPicture.asset(
                'assets/dandelion.svg',
                width: 180,
                height: 270,
              ),
            ),
          ),

          // Falling seeds (background layer)
          ...List.generate(_visualSeedCount, (i) {
            return AnimatedBuilder(
              animation: _seedControllers[i],
              builder: (context, _) {
                final progress = _seedControllers[i].value;
                final xPos =
                    (_seedX[i] + _seedDrift[i] * progress).clamp(0.0, 1.0);
                final fadeOpacity = progress > 0.85
                    ? (1.0 - (progress - 0.85) / 0.15).clamp(0.0, 1.0)
                    : 1.0;

                return Positioned(
                  left: (xPos * size.width - 20).clamp(0.0, size.width - 40),
                  top: progress * (size.height + 50) - 50,
                  child: Opacity(
                    opacity: fadeOpacity * 0.6,
                    child: Transform.scale(
                      scale: _seedSizes[i],
                      child: SvgPicture.asset(
                        'assets/dandelion_seed.svg',
                        width: 40,
                        height: 50,
                      ),
                    ),
                  ),
                );
              },
            );
          }),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(36, 48, 36, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header count section
                  FadeTransition(
                    opacity: _headerFade,
                    child: SlideTransition(
                      position: _headerSlide,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '호흡하며 민들레 씨앗이',
                            style: TextStyle(
                              color: Color(0xFFB0C9B8),
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          AnimatedBuilder(
                            animation: _countAnimation,
                            builder: (context, _) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '${_countAnimation.value}',
                                    style: const TextStyle(
                                      color: Color(0xFF7ADAA5),
                                      fontSize: 80,
                                      fontWeight: FontWeight.w900,
                                      height: 1.0,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '개',
                                    style: TextStyle(
                                      color: Color(0xFFF7F3E9),
                                      fontSize: 30,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const Text(
                            '날아갔어요!',
                            style: TextStyle(
                              color: Color(0xFFF7F3E9),
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 52),

                  // Emotional messages
                  FadeTransition(
                    opacity: _text1Fade,
                    child: const Text(
                      '당신의 호흡으로\n민들레의 희망이 되었어요',
                      style: TextStyle(
                        color: Color(0xFFF7F3E9),
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        height: 1.55,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  FadeTransition(
                    opacity: _text2Fade,
                    child: const Text(
                      '작은 숨 하나가\n어딘가에서 꽃을 피울 거예요.\n\n'
                      '오늘 당신이 내쉰 바람은\n씨앗이 되어 세상 어딘가에\n조용히 뿌리를 내릴 거예요.',
                      style: TextStyle(
                        color: Color(0xFF8BA89A),
                        fontSize: 15,
                        height: 1.75,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  FadeTransition(
                    opacity: _text3Fade,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7ADAA5).withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF7ADAA5).withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Text(
                        '잘했어요.\n오늘 하루도 수고했어요. 🌱',
                        style: TextStyle(
                          color: Color(0xFFB5D9C4),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          height: 1.65,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 52),

                  // Replay button
                  FadeTransition(
                    opacity: _text3Fade,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const IntroScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Text(
                          '다시 호흡하기',
                          style: TextStyle(
                            color: Color(0xFFD9EAE0),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
