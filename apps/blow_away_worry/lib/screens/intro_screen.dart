import 'dart:math' as math;

import 'package:blow_away_worry/screens/blow_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _micGranted = false;

  late final AnimationController _starAnim;

  int get _pageCount => _micGranted ? 3 : 4;

  @override
  void initState() {
    super.initState();
    _starAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _checkMicPermission();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _starAnim.dispose();
    super.dispose();
  }

  Future<void> _checkMicPermission() async {
    final PermissionStatus status = await Permission.microphone.status;
    if (mounted) {
      setState(() => _micGranted = status.isGranted);
    }
  }

  Future<void> _requestMic() async {
    final PermissionStatus status = await Permission.microphone.request();
    if (!mounted) return;
    setState(() => _micGranted = status.isGranted);
    if (_micGranted) {
      _goNext();
    }
  }

  void _goNext() {
    if (_currentPage < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _startGame() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const BlowScreen(),
        transitionsBuilder: (_, Animation<double> anim, _, Widget child) {
          return FadeTransition(opacity: anim, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          // Animated background dots
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _starAnim,
              builder: (_, _) => CustomPaint(
                painter: _DotFieldPainter(phase: _starAnim.value),
              ),
            ),
          ),

          // Pages
          SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    onPageChanged: (int page) =>
                        setState(() => _currentPage = page),
                    children: <Widget>[
                      _buildHeroPage(),
                      _buildHowToPage(),
                      if (!_micGranted) _buildPermissionPage(),
                      _buildStartPage(),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Dot indicators
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List<Widget>.generate(_pageCount, (int i) {
                  final bool active = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    width: 6,
                    height: active ? 24 : 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: active
                          ? const Color(0xFFFFE066)
                          : Colors.white.withValues(alpha: 0.25),
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

  // --- Pages ---

  Widget _buildHeroPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '고민을\n날려버려',
            textAlign: TextAlign.center,
            style: GoogleFonts.caveat(
              fontSize: 60,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '포스트잇에 고민을 적고\n후~ 불어서 바람에 날려버리세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 48),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white.withValues(alpha: 0.35),
            size: 32,
          ),
        ],
      ),
    );
  }

  Widget _buildHowToPage() {
    const List<(String, String)> steps = <(String, String)>[
      ('1', '포스트잇에 고민을 적어요'),
      ('2', '마이크 버튼을 눌러요'),
      ('3', '잠시 주변 소리를 측정해요'),
      ('4', '마이크에 후~ 하고 불어요'),
      ('5', '포스트잇이 바람에 날아가요!'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '이렇게 해보세요',
            style: GoogleFonts.caveat(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 28),
          ...steps.map(((String, String) step) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFFE066).withValues(alpha: 0.15),
                      border: Border.all(
                        color: const Color(0xFFFFE066).withValues(alpha: 0.4),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      step.$1,
                      style: const TextStyle(
                        color: Color(0xFFFFE066),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      step.$2,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPermissionPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFE066).withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.mic_rounded,
              color: Color(0xFFFFE066),
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '마이크 권한이 필요해요',
            style: GoogleFonts.caveat(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '바람 소리를 감지하기 위해\n마이크 접근 권한을 허용해 주세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.65),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _requestMic,
            icon: const Icon(Icons.mic_none_rounded),
            label: const Text('마이크 권한 허용'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFE066),
              foregroundColor: const Color(0xFF2A2A2E),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              textStyle: const TextStyle(
                inherit: false,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '준비됐나요?',
            style: GoogleFonts.caveat(
              fontSize: 42,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '지금 떠오르는 고민 하나를 떠올려 보세요.\n적고, 불고, 날려버리면 돼요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.65),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),
          FilledButton(
            onPressed: _startGame,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFE066),
              foregroundColor: const Color(0xFF2A2A2E),
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(
                inherit: false,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('시작하기'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Background dot field — subtle animated star-like dots
// ---------------------------------------------------------------------------
class _DotFieldPainter extends CustomPainter {
  _DotFieldPainter({required this.phase});

  final double phase;
  static final List<_Dot> _dots = _generateDots(30);

  static List<_Dot> _generateDots(int count) {
    final math.Random rng = math.Random(42);
    return List<_Dot>.generate(count, (_) {
      return _Dot(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 1.2 + rng.nextDouble() * 1.8,
        speed: 0.3 + rng.nextDouble() * 0.6,
        phaseOffset: rng.nextDouble() * math.pi * 2,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final _Dot dot in _dots) {
      final double t = math.sin(phase * math.pi * 2 * dot.speed + dot.phaseOffset);
      final double opacity = 0.15 + t * 0.15;
      final Paint paint = Paint()
        ..color = Colors.white.withValues(alpha: opacity.clamp(0.05, 0.4));
      canvas.drawCircle(
        Offset(dot.x * size.width, dot.y * size.height),
        dot.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DotFieldPainter old) => true;
}

class _Dot {
  const _Dot({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.phaseOffset,
  });
  final double x, y, radius, speed, phaseOffset;
}
