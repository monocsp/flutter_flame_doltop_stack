import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:permission_handler/permission_handler.dart';

import 'constellation_game_screen.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _pageController = PageController();
  bool _micGranted = false;
  bool _checked = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _checkMicPermission();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkMicPermission() async {
    // Only check status — don't request yet
    final status = await Permission.microphone.status;
    if (mounted) {
      setState(() {
        _micGranted = status.isGranted;
        _checked = true;
      });
    }
  }

  Future<void> _requestMicPermission() async {
    final status = await Permission.microphone.request();
    if (mounted) {
      setState(() => _micGranted = status.isGranted);
      // Move to next page regardless of result
      _pageController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    }
  }

  List<Widget> get _pages {
    final pages = <Widget>[
      _buildHeroPage(),
      _buildStoryPage(),
      _buildHowToPlayPage(),
    ];
    if (!_micGranted) {
      pages.add(_buildMicPermissionPage());
    }
    pages.add(_buildStartPage());
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        backgroundColor: Color(0xFF09111F),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF9EDCFF)),
        ),
      );
    }

    final pages = _pages;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _buildBackground(),
          PageView(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: (page) => setState(() => _currentPage = page),
            children: pages,
          ),
          // Back button
          Positioned(
            left: 12,
            top: MediaQuery.of(context).padding.top + 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.07),
              ),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFFF7F3E9),
                size: 22,
              ),
            ),
          ),
          // Dot indicators
          Positioned(
            right: 18,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(pages.length, (i) {
                  final isActive = _currentPage == i;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    width: 6,
                    height: isActive ? 22 : 6,
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF9EDCFF)
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroPage() {
    return SafeArea(
      child: Stack(
        children: [
          // Star decorations — small painted circles
          const _StarField(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CONSTELLATION\nBREATH',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.8,
                    color: Color(0xFFFFDCA8),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '별자리\n호흡',
                  style: TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    color: Color(0xFFF7F3E9),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '당신의 숨결로 밤하늘에\n별자리를 그려보세요',
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.7,
                    color: Color(0xFFAFC3D9),
                  ),
                ),
                const SizedBox(height: 56),
                Row(
                  children: const [
                    Text(
                      '아래로 스크롤',
                      style: TextStyle(
                        color: Color(0xFF9EDCFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF9EDCFF),
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryPage() {
    return SafeArea(
      child: Stack(
        children: [
          // Subtle star decorations
          const _StarField(seed: 42),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '밤하늘을\n올려다보세요',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    color: Color(0xFFF7F3E9),
                  ),
                ),
                SizedBox(height: 28),
                Text(
                  '당신의 숨결이 별이 되어\n하늘을 수놓을 거예요.\n\n단 세 번의 호흡으로\n당신만의 별자리를 만들어보세요.',
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.75,
                    color: Color(0xFFAFC3D9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowToPlayPage() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '이렇게 해요',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: Color(0xFFF7F3E9),
              ),
            ),
            const SizedBox(height: 36),
            _buildStep(
              '1',
              '입을 마이크에 가까이 대세요',
              '휴대폰 하단 마이크에 입을 가까이',
            ),
            const SizedBox(height: 22),
            _buildStep(
              '2',
              '3초간 숨을 크게 들이쉬세요',
              '화면 가운데 별이 기다려요',
            ),
            const SizedBox(height: 22),
            _buildStep(
              '3',
              '천천히 내쉬면 별이 이어져요',
              '오래 내쉴수록 별이 밝게 빛나요',
            ),
            const SizedBox(height: 22),
            _buildStep(
              '4',
              '3번 반복하면 별자리가 완성돼요',
              '마지막엔 완성된 별자리를 확인해요',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFF9EDCFF).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF9EDCFF).withValues(alpha: 0.3),
            ),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF9EDCFF),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFF7F3E9),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF6B8BA4),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMicPermissionPage() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF9EDCFF).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.mic_rounded,
                size: 34,
                color: Color(0xFF9EDCFF),
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              '마이크 허용이\n필요해요',
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w900,
                height: 1.1,
                color: Color(0xFFF7F3E9),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '별자리를 그리려면\n당신의 숨소리가 필요해요.\n마이크는 게임 중에만 사용되며,\n어디에도 저장되지 않아요.',
              style: TextStyle(
                fontSize: 16,
                height: 1.7,
                color: Color(0xFFAFC3D9),
              ),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _requestMicPermission,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF9EDCFF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '마이크 허용하기',
                  style: TextStyle(
                    color: Color(0xFF09111F),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartPage() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '준비됐나요?',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w900,
                color: Color(0xFFF7F3E9),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '편안한 자세로\n천천히 시작해요.',
              style: TextStyle(
                fontSize: 18,
                height: 1.65,
                color: Color(0xFFAFC3D9),
              ),
            ),
            const SizedBox(height: 52),
            GestureDetector(
              onTap: _micGranted
                  ? () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const ConstellationGameScreen(),
                        ),
                      );
                    }
                  : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
                decoration: BoxDecoration(
                  color: _micGranted
                      ? const Color(0xFF9EDCFF)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  _micGranted ? '시작하기' : '마이크를 먼저 허용해주세요',
                  style: TextStyle(
                    color: _micGranted
                        ? const Color(0xFF09111F)
                        : Colors.white30,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF09111F),
            Color(0xFF10203A),
            Color(0xFF162A48),
          ],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

/// Animated star field with slow random twinkling.
class _StarField extends StatefulWidget {
  final int seed;

  const _StarField({this.seed = 0});

  @override
  State<_StarField> createState() => _StarFieldState();
}

class _StarFieldState extends State<_StarField>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((duration) {
      setState(() {
        _elapsed = duration.inMicroseconds / 1000000.0;
      });
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _StarFieldPainter(
          seed: widget.seed,
          elapsed: _elapsed,
        ),
      ),
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  final int seed;
  final double elapsed;
  static const int _count = 25;

  _StarFieldPainter({required this.seed, required this.elapsed});

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final paint = Paint();

    for (int i = 0; i < _count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final baseRadius = 0.8 + rng.nextDouble() * 1.8;
      final baseOpacity = 0.1 + rng.nextDouble() * 0.4;
      // Each star has its own slow twinkle speed and phase
      final speed = 0.3 + rng.nextDouble() * 0.6; // 0.3~0.9 Hz
      final phase = rng.nextDouble() * pi * 2;

      // Slow sinusoidal twinkle
      final twinkle = (sin(elapsed * speed * pi * 2 + phase) + 1.0) / 2.0;
      final opacity = (baseOpacity * (0.2 + twinkle * 0.8)).clamp(0.0, 1.0);
      final radius = baseRadius * (0.7 + twinkle * 0.3);

      paint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) => true;
}
