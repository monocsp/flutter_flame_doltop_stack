import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'intro_screen.dart';

// ★ A falling seed with physics-based landing
class _FallingSeed {
  _FallingSeed({
    required this.x,
    required this.y,
    required this.size,
    required this.fallSpeed,
    required this.drift,
    required this.rotationSpeed,
  });

  double x;
  double y;
  final double size;
  final double fallSpeed;
  final double drift;
  final double rotationSpeed;
  double rotation = 0;
  bool landed = false;
  double landedY = double.infinity;
  double opacity = 0.0;
  // ★ Surfaces this seed has already decided to pass through
  final Set<int> passedSurfaces = {};
}

class _TextMeasurement {
  _TextMeasurement({required this.texts, this.extraPadding = 0});
  final List<(String, TextStyle)> texts;
  final double extraPadding;
}

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.totalSeeds});

  final int totalSeeds;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  final Random _random = Random();

  // ── Falling seeds ──
  final List<_FallingSeed> _seeds = [];
  int _seedsSpawned = 0;
  double _spawnAccumulator = 0;

  // ── Collision surfaces (text bounding boxes + floor) ──
  final List<Rect> _surfaces = [];
  // Track stacked height on each surface for pile-up effect
  final Map<int, double> _surfaceStackHeight = {};

  // ── Keys for measuring text positions ──
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _text1Key = GlobalKey();
  final GlobalKey _text2Key = GlobalKey();
  final GlobalKey _text3Key = GlobalKey();
  final GlobalKey _buttonKey = GlobalKey();

  // ── Ticker ──
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  bool _surfacesMeasured = false;

  // ── Bloom phase: seeds fade out → flowers bloom ──
  bool _allSeedsLanded = false;
  double _seedFadeOut = 1.0; // 1.0 = visible, 0.0 = gone
  bool _bloomStarted = false;

  late AnimationController _bloomController;
  late Animation<double> _bloomScale;
  late Animation<double> _bloomFade;

  // ── Text animations (keep existing) ──
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
    _setupHeaderAnimation();
    _setupCountAnimation();
    _setupTextAnimations();
    _setupBloomAnimation();

    _ticker = createTicker(_onTick)..start();

    _headerController.forward();

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _countController.forward();
    });

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) _textController.forward();
    });

    // Measure text positions after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureSurfaces();
    });
  }

  void _setupBloomAnimation() {
    _bloomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _bloomScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _bloomController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );
    _bloomFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _bloomController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );
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
    ).animate(
        CurvedAnimation(parent: _headerController, curve: Curves.easeOut));
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

  // ★ Measure actual text width using TextPainter, not widget constraints
  double _measureTextWidth(String text, TextStyle style) {
    final maxW = MediaQuery.of(context).size.width - 72; // padding 36*2
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW);
    final w = tp.width;
    tp.dispose();
    return w;
  }

  void _measureSurfaces() {
    _surfaces.clear();
    _surfaceStackHeight.clear();

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // ★ Text content + styles to measure actual rendered widths
    final textMeasurements = <GlobalKey, _TextMeasurement>{
      _headerKey: _TextMeasurement(
        // Header's widest line: the count number row is dynamic,
        // but "날아갔어요!" at 26px bold is a good approximation
        texts: [
          ('호흡하며 민들레 씨앗이', const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
          ('${widget.totalSeeds}개', const TextStyle(fontSize: 80, fontWeight: FontWeight.w900)),
          ('날아갔어요!', const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        ],
      ),
      _text1Key: _TextMeasurement(
        texts: [
          ('당신의 호흡으로\n민들레의 희망이 되었어요',
            const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        ],
      ),
      _text2Key: _TextMeasurement(
        texts: [
          ('작은 숨 하나가\n어딘가에서 꽃을 피울 거예요.\n\n오늘 당신이 내쉰 바람은\n씨앗이 되어 세상 어딘가에\n조용히 뿌리를 내릴 거예요.',
            const TextStyle(fontSize: 15)),
        ],
      ),
      _text3Key: _TextMeasurement(
        texts: [
          ('잘했어요.\n오늘 하루도 수고했어요. 🌱',
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ],
        extraPadding: 36, // container padding 18*2
      ),
      _buttonKey: _TextMeasurement(
        texts: [
          ('다시 호흡하기', const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ],
        extraPadding: 56, // horizontal padding 28*2
      ),
    };

    for (final entry in textMeasurements.entries) {
      final renderBox =
          entry.key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) continue;

      final pos = renderBox.localToGlobal(Offset.zero);
      final widgetHeight = renderBox.size.height;

      // ★ Calculate actual text width (widest line)
      final measurement = entry.value;
      double maxTextWidth = 0;
      for (final (text, style) in measurement.texts) {
        final w = _measureTextWidth(text, style);
        if (w > maxTextWidth) maxTextWidth = w;
      }
      maxTextWidth += measurement.extraPadding;

      _surfaces.add(Rect.fromLTWH(pos.dx, pos.dy, maxTextWidth, widgetHeight));
    }

    // Floor surface (full width)
    _surfaces.add(Rect.fromLTWH(0, screenHeight - 20, screenWidth, 20));

    for (int i = 0; i < _surfaces.length; i++) {
      _surfaceStackHeight[i] = 0;
    }

    _surfacesMeasured = true;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _countController.dispose();
    _textController.dispose();
    _headerController.dispose();
    _bloomController.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1 || !mounted) return;

    setState(() {
      // ★ Spawn seeds gradually over time
      if (_seedsSpawned < widget.totalSeeds) {
        final seedsPerSecond = max(1.0, widget.totalSeeds / 8.0);
        _spawnAccumulator += seedsPerSecond * dt;
        while (_spawnAccumulator >= 1.0 && _seedsSpawned < widget.totalSeeds) {
          _spawnAccumulator -= 1.0;
          _spawnSeed();
        }
      }

      // ★ Update all seeds
      for (final seed in _seeds) {
        if (seed.landed) continue;

        seed.opacity = (seed.opacity + dt * 3.0).clamp(0.0, 0.7);

        seed.y += seed.fallSpeed * dt;
        seed.x += seed.drift * dt;
        seed.rotation += seed.rotationSpeed * dt;

        if (_surfacesMeasured) {
          _checkLanding(seed);
        }
      }

      // ★ Detect all seeds landed → start bloom sequence
      if (!_allSeedsLanded &&
          _seedsSpawned >= widget.totalSeeds &&
          _seeds.every((s) => s.landed)) {
        _allSeedsLanded = true;
        // Wait a moment, then fade out seeds and bloom flowers
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _bloomStarted = true);
        });
      }

      // ★ Fade out seeds when bloom starts
      if (_bloomStarted && _seedFadeOut > 0) {
        _seedFadeOut = (_seedFadeOut - dt * 0.8).clamp(0.0, 1.0);
        // Start bloom animation when seeds are half faded
        if (_seedFadeOut < 0.5 && !_bloomController.isAnimating && !_bloomController.isCompleted) {
          _bloomController.forward();
        }
      }
    });
  }

  void _spawnSeed() {
    final screenWidth = MediaQuery.of(context).size.width;
    _seeds.add(_FallingSeed(
      x: _random.nextDouble() * screenWidth,
      y: -30 - _random.nextDouble() * 60,
      size: 0.3 + _random.nextDouble() * 0.5,
      fallSpeed: 35.0 + _random.nextDouble() * 45.0,
      drift: (_random.nextDouble() - 0.5) * 15.0,
      rotationSpeed: (_random.nextDouble() - 0.5) * 1.5,
    ));
    _seedsSpawned++;
  }

  void _checkLanding(_FallingSeed seed) {
    final seedBottom = seed.y + 25 * seed.size;
    final seedCenterX = seed.x;
    final isFloor = _surfaces.length - 1; // last surface = floor

    for (int i = 0; i < _surfaces.length; i++) {
      // ★ Skip surfaces this seed already decided to pass through
      if (seed.passedSurfaces.contains(i)) continue;

      final surface = _surfaces[i];
      final stackH = _surfaceStackHeight[i] ?? 0;

      if (seedCenterX >= surface.left - 3 &&
          seedCenterX <= surface.right + 3) {
        final landingY = surface.top - stackH;
        if (seedBottom >= landingY) {
          // ★ Floor always catches. Text surfaces: ~30% chance to land.
          if (i != isFloor && _random.nextDouble() > 0.30) {
            seed.passedSurfaces.add(i); // remember to skip next time
            continue;
          }
          seed.landed = true;
          final jitterX = (_random.nextDouble() - 0.5) * 6;
          seed.x += jitterX;
          seed.y = landingY - 25 * seed.size;
          seed.opacity = 0.65;
          _surfaceStackHeight[i] = stackH + 3 * seed.size;
          return;
        }
      }
    }
  }

  List<Widget> _buildBloomingFlowers() {
    final screenWidth = MediaQuery.of(context).size.width;
    const flowerSize = 160.0;

    return [
      // Flower 1 — bottom left area
      Positioned(
        left: screenWidth * 0.08,
        bottom: 20,
        child: AnimatedBuilder(
          animation: _bloomController,
          builder: (context, child) {
            return Opacity(
              opacity: _bloomFade.value,
              child: Transform.scale(
                scale: _bloomScale.value,
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            );
          },
          child: Image.asset(
            'assets/Gemini_Generated_Image_9934bl9934bl9934.png',
            package: 'flutter_flame_breath_journey_game',
            width: flowerSize,
            height: flowerSize,
            fit: BoxFit.contain,
          ),
        ),
      ),
      // Flower 2 — bottom right area (slightly delayed)
      Positioned(
        right: screenWidth * 0.05,
        bottom: 10,
        child: AnimatedBuilder(
          animation: _bloomController,
          builder: (context, child) {
            final delayed = (_bloomController.value - 0.2).clamp(0.0, 1.0) / 0.8;
            final scale = Curves.easeOutBack.transform(delayed);
            final fade = Curves.easeIn.transform(delayed.clamp(0.0, 1.0));
            return Opacity(
              opacity: fade,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            );
          },
          child: Image.asset(
            'assets/Gemini_Generated_Image_3p3ukx3p3ukx3p3u.png',
            package: 'flutter_flame_breath_journey_game',
            width: flowerSize * 0.85,
            height: flowerSize * 0.85,
            fit: BoxFit.contain,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
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

          // 민들레 본체 (하단 우측)
          Positioned(
            right: -20,
            bottom: -60,
            child: Opacity(
              opacity: 0.12,
              child: SvgPicture.asset(
                'assets/dandelion.svg',
                package: 'flutter_flame_breath_journey_game',
                width: 180,
                height: 270,
              ),
            ),
          ),

          // ★ Falling seeds layer (behind content)
          ..._seeds.map((seed) {
            return Positioned(
              left: seed.x - 20,
              top: seed.y,
              child: Opacity(
                opacity: seed.opacity * _seedFadeOut,
                child: Transform.rotate(
                  angle: seed.rotation,
                  child: Transform.scale(
                    scale: seed.size,
                    child: SvgPicture.asset(
                      'assets/dandelion_seed.svg',
                      package: 'flutter_flame_breath_journey_game',
                      width: 40,
                      height: 50,
                    ),
                  ),
                ),
              ),
            );
          }),

          // ★ Blooming dandelion flowers
          if (_bloomStarted)
            ..._buildBloomingFlowers(),

          // Back button
          Positioned(
            left: 12,
            top: MediaQuery.of(context).padding.top + 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).popUntil(
                (route) => route.isFirst,
              ),
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
                        key: _headerKey,
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
                                crossAxisAlignment:
                                    CrossAxisAlignment.baseline,
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
                    child: Text(
                      key: _text1Key,
                      '당신의 호흡으로\n민들레의 희망이 되었어요',
                      style: const TextStyle(
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
                    child: Text(
                      key: _text2Key,
                      '작은 숨 하나가\n어딘가에서 꽃을 피울 거예요.\n\n'
                      '오늘 당신이 내쉬 바람은\n씨앗이 되어 세상 어딘가에\n조용히 뿌리를 내릴 거예요.',
                      style: const TextStyle(
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
                      key: _text3Key,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF7ADAA5).withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF7ADAA5)
                              .withValues(alpha: 0.18),
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
                        key: _buttonKey,
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
