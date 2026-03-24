import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';

import 'dandelion_game_screen.dart';

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
      setState(() {
        _micGranted = status.isGranted;
      });
      if (_micGranted) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        );
      }
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
        backgroundColor: Color(0xFF0D1F2D),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7ADAA5)),
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
                          ? const Color(0xFF7ADAA5)
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
          // 민들레 이미지 (우측 하단에 은은하게)
          Positioned(
            right: -30,
            bottom: 60,
            child: Opacity(
              opacity: 0.18,
              child: SvgPicture.asset(
                'assets/dandelion.svg',
                package: 'flutter_flame_breath_journey_game',
                width: 200,
                height: 300,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DANDELION\nBREATH',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.8,
                    color: Color(0xFFFFD7A1),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '민들레\n여정',
                  style: TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    color: Color(0xFFF7F3E9),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '호흡으로 민들레 씨앗을\n세상 끝까지 날려보세요',
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.7,
                    color: Color(0xFFB0C9B8),
                  ),
                ),
                const SizedBox(height: 56),
                Row(
                  children: const [
                    Text(
                      '아래로 스크롤',
                      style: TextStyle(
                        color: Color(0xFF7ADAA5),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF7ADAA5),
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
          // 씨앗 이미지들 (떠다니는 느낌)
          Positioned(
            right: 30,
            top: 120,
            child: Opacity(
              opacity: 0.15,
              child: Transform.rotate(
                angle: -0.3,
                child: SvgPicture.asset(
                  'assets/dandelion_seed.svg',
                  package: 'flutter_flame_breath_journey_game',
                  width: 60,
                  height: 60,
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 140,
            child: Opacity(
              opacity: 0.12,
              child: Transform.rotate(
                angle: 0.5,
                child: SvgPicture.asset(
                  'assets/dandelion_seed.svg',
                  package: 'flutter_flame_breath_journey_game',
                  width: 45,
                  height: 45,
                ),
              ),
            ),
          ),
          Positioned(
            right: 60,
            bottom: 200,
            child: Opacity(
              opacity: 0.08,
              child: SvgPicture.asset(
                'assets/dandelion_seed.svg',
                package: 'flutter_flame_breath_journey_game',
                width: 35,
                height: 35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '잠깐 멈춰\n호흡해봐요',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    color: Color(0xFFF7F3E9),
                  ),
                ),
                SizedBox(height: 28),
                Text(
                  '바람을 품은 민들레처럼,\n당신의 숨결도 어딘가에\n닿을 수 있어요.',
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.75,
                    color: Color(0xFFB0C9B8),
                  ),
                ),
                SizedBox(height: 28),
                Text(
                  '단 3번의 호흡으로\n민들레의 씨앗이 되어보세요.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.65,
                    color: Color(0xFF7B9A8A),
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
              '화면 가운데 민들레가 기다려요',
            ),
            const SizedBox(height: 22),
            _buildStep(
              '3',
              '천천히, 길게 내쉬세요',
              '오래 내쉴수록 씨앗이 멀리 날아가요',
            ),
            const SizedBox(height: 22),
            _buildStep(
              '4',
              '3번 반복해요',
              '마지막엔 날아간 씨앗들을 확인해요',
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
            color: const Color(0xFF7ADAA5).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF7ADAA5).withValues(alpha: 0.3),
            ),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF7ADAA5),
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
                  color: Color(0xFF7B9A8A),
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
                color: const Color(0xFF7ADAA5).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.mic_rounded,
                size: 34,
                color: Color(0xFF7ADAA5),
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
              '민들레 씨앗을 날리려면\n당신의 숨소리가 필요해요.\n마이크는 게임 중에만 사용되며,\n어디에도 저장되지 않아요.',
              style: TextStyle(
                fontSize: 16,
                height: 1.7,
                color: Color(0xFFB0C9B8),
              ),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _requestMicPermission,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF7ADAA5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '마이크 허용하기',
                  style: TextStyle(
                    color: Color(0xFF0D1F2D),
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
                color: Color(0xFFB0C9B8),
              ),
            ),
            const SizedBox(height: 52),
            GestureDetector(
              onTap: _micGranted
                  ? () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const DandelionGameScreen(),
                        ),
                      );
                    }
                  : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
                decoration: BoxDecoration(
                  color: _micGranted
                      ? const Color(0xFF7ADAA5)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  _micGranted ? '시작하기' : '마이크를 먼저 허용해주세요',
                  style: TextStyle(
                    color: _micGranted
                        ? const Color(0xFF0D1F2D)
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
            Color(0xFF0D1F2D),
            Color(0xFF132A3B),
            Color(0xFF182F40),
          ],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}
