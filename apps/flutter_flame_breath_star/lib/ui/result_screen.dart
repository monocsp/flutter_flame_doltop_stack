import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/constellation.dart';
import 'intro_screen.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.constellation});

  final ConstellationState constellation;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  final Random _random = Random();

  // ── Background star dust (fixed positions) ──
  late final List<_DustStar> _dustStars;

  // ── Camera ──
  double _cameraZoom = 1.0;
  Offset _cameraCenter = Offset.zero;
  late double _targetZoom;
  late Offset _targetCenter;

  // ── Zoom-out animation ──
  late AnimationController _zoomController;
  late CurvedAnimation _zoomCurve;

  // ── Light-up animation ──
  late AnimationController _lightUpController;

  // ── Text fade-in animations ──
  late AnimationController _textController;
  late Animation<double> _nameFade;
  late Animation<double> _countFade;
  late Animation<double> _poeticFade;
  late Animation<double> _boxFade;
  late Animation<double> _buttonFade;

  // ── Twinkle ticker ──
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _elapsedSeconds = 0.0;

  // ── Constellation name ──
  late final String _constellationName;

  @override
  void initState() {
    super.initState();

    _constellationName = generateConstellationName(_random);

    // Generate fixed background dust stars
    _dustStars = List.generate(60, (_) {
      return _DustStar(
        x: _random.nextDouble(),
        y: _random.nextDouble(),
        radius: 0.5 + _random.nextDouble() * 1.5,
        opacity: 0.1 + _random.nextDouble() * 0.35,
        flickerSpeed: 0.3 + _random.nextDouble() * 1.5,
        flickerPhase: _random.nextDouble() * pi * 2,
      );
    });

    // Calculate target camera from constellation bounds
    _computeTargetCamera();

    // Zoom-out animation
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _zoomCurve = CurvedAnimation(
      parent: _zoomController,
      curve: Curves.easeInOutCubic,
    );

    // Light-up animation (starts after zoom-out)
    _lightUpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Text animations (total ~5s of sequenced fade-ins)
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );

    // Name fades in at 2.5s → Interval starts at 0.0 of _textController
    // _textController starts at 2.5s after initState
    _nameFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.0, 0.18, curve: Curves.easeIn),
      ),
    );
    // Star count at 3.2s → 0.7s into _textController → 0.14
    _countFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.14, 0.34, curve: Curves.easeIn),
      ),
    );
    // Poetic message at 4.0s → 1.5s into _textController → 0.30
    _poeticFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.30, 0.55, curve: Curves.easeIn),
      ),
    );
    // Encouragement box at 5.0s → 2.5s into _textController → 0.50
    _boxFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.50, 0.75, curve: Curves.easeIn),
      ),
    );
    // Replay button at 5.0s → same interval as box
    _buttonFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _textController,
        curve: const Interval(0.50, 0.80, curve: Curves.easeIn),
      ),
    );

    // Start ticker for twinkle
    _ticker = createTicker(_onTick)..start();

    // Start zoom-out immediately
    _zoomController.forward();

    // After zoom-out, start light-up
    _zoomController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _lightUpController.forward();
      }
    });

    // After zoom-out + light-up (~2.5s total), start text fade-ins
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) _textController.forward();
    });
  }

  void _computeTargetCamera() {
    if (widget.constellation.stars.isEmpty) {
      _targetZoom = 1.0;
      _targetCenter = Offset.zero;
      return;
    }

    final bounds = widget.constellation.boundingBox;
    final padding = max(bounds.shortestSide * 0.3, 80.0);
    final paddedBounds = bounds.inflate(padding);

    // We'll compute screen-dependent zoom in build via LayoutBuilder,
    // store padded bounds for now.
    _targetCenter = paddedBounds.center;

    // Start camera at the last star's position
    if (widget.constellation.stars.isNotEmpty) {
      _cameraCenter = widget.constellation.stars.last.position;
    }
  }

  double _computeTargetZoom(Size screenSize, EdgeInsets safeArea) {
    if (widget.constellation.stars.isEmpty) return 1.0;

    final bounds = widget.constellation.boundingBox;
    final padding = max(bounds.shortestSide * 0.3, 80.0);
    final paddedBounds = bounds.inflate(padding);

    // Account for safeArea so stars don't get clipped by notch/dynamic island
    final safeWidth = screenSize.width - safeArea.left - safeArea.right;
    final safeHeight =
        (screenSize.height - safeArea.top - safeArea.bottom) * 0.50;

    final zoomX = safeWidth / paddedBounds.width;
    final zoomY = safeHeight / paddedBounds.height;
    return min(zoomX, zoomY).clamp(0.3, 3.0);
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
      _elapsedSeconds += dt;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _zoomController.dispose();
    _lightUpController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeArea = MediaQuery.of(context).padding;
    _targetZoom = _computeTargetZoom(screenSize, safeArea);

    // Interpolate camera
    final t = _zoomCurve.value;
    _cameraZoom = ui.lerpDouble(1.0, _targetZoom, t)!;
    _cameraCenter = Offset.lerp(
      widget.constellation.stars.isNotEmpty
          ? widget.constellation.stars.last.position
          : Offset.zero,
      _targetCenter,
      t,
    )!;

    return Scaffold(
      backgroundColor: const Color(0xFF09111F),
      body: Stack(
        children: [
          // Background gradient
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF09111F),
                  Color(0xFF0E1A30),
                  Color(0xFF09111F),
                ],
              ),
            ),
            child: SizedBox.expand(),
          ),

          // Constellation canvas (top 55%)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenSize.height * 0.55,
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _zoomCurve,
                _lightUpController,
              ]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _ResultConstellationPainter(
                    constellation: widget.constellation,
                    cameraCenter: _cameraCenter,
                    cameraZoom: _cameraZoom,
                    elapsedSeconds: _elapsedSeconds,
                    lightUpProgress: _lightUpController.value,
                    dustStars: _dustStars,
                  ),
                  size: Size(screenSize.width, screenSize.height * 0.55),
                );
              },
            ),
          ),

          // Text content (bottom half, scrollable)
          Positioned(
            top: screenSize.height * 0.50,
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: _textController,
              builder: (context, _) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(36, 16, 36, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Constellation name
                      FadeTransition(
                        opacity: _nameFade,
                        child: Text(
                          _constellationName,
                          style: const TextStyle(
                            color: Color(0xFFFFDCA8),
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Star count
                      FadeTransition(
                        opacity: _countFade,
                        child: Text(
                          '${widget.constellation.stars.length}개의 별이 밤하늘에 빛나고 있어요',
                          style: const TextStyle(
                            color: Color(0xFFF7F3E9),
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Poetic message
                      FadeTransition(
                        opacity: _poeticFade,
                        child: const Text(
                          '당신의 숨결이 만든 별자리예요.\n'
                          '작은 숨 하나가 밤하늘에 흔적을 남겼어요.',
                          style: TextStyle(
                            color: Color(0xFFAFC3D9),
                            fontSize: 15,
                            height: 1.75,
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // Encouragement box
                      FadeTransition(
                        opacity: _boxFade,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFF9EDCFF)
                                .withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF9EDCFF)
                                  .withValues(alpha: 0.18),
                            ),
                          ),
                          child: const Text(
                            '잘했어요.\n오늘의 밤하늘은 당신 덕분에 빛나요.',
                            style: TextStyle(
                              color: Color(0xFFB5D1E8),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              height: 1.65,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 44),

                      // Replay button
                      FadeTransition(
                        opacity: _buttonFade,
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
                              horizontal: 28,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Text(
                              '다시 호흡하기',
                              style: TextStyle(
                                color: Color(0xFFD9E8F7),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Back button (top left)
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
        ],
      ),
    );
  }
}

// ── Background dust star data ──

class _DustStar {
  _DustStar({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
    required this.flickerSpeed,
    required this.flickerPhase,
  });

  final double x; // 0..1 normalized
  final double y;
  final double radius;
  final double opacity;
  final double flickerSpeed;
  final double flickerPhase;
}

// ── Constellation painter ──

class _ResultConstellationPainter extends CustomPainter {
  _ResultConstellationPainter({
    required this.constellation,
    required this.cameraCenter,
    required this.cameraZoom,
    required this.elapsedSeconds,
    required this.lightUpProgress,
    required this.dustStars,
  });

  final ConstellationState constellation;
  final Offset cameraCenter;
  final double cameraZoom;
  final double elapsedSeconds;
  final double lightUpProgress; // 0..1 sequential light-up
  final List<_DustStar> dustStars;

  Offset _worldToScreen(Offset world, Size size) {
    final screenCenter = Offset(size.width / 2, size.height / 2);
    return screenCenter + (world - cameraCenter) * cameraZoom;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawDustStars(canvas, size);
    _drawEdges(canvas, size);
    _drawStars(canvas, size);
  }

  void _drawDustStars(Canvas canvas, Size size) {
    final paint = Paint();
    for (final dust in dustStars) {
      final flicker =
          0.6 + 0.4 * sin(elapsedSeconds * dust.flickerSpeed + dust.flickerPhase);
      paint.color = Colors.white.withValues(alpha: dust.opacity * flicker);
      canvas.drawCircle(
        Offset(dust.x * size.width, dust.y * size.height),
        dust.radius,
        paint,
      );
    }
  }

  void _drawEdges(Canvas canvas, Size size) {
    if (constellation.edges.isEmpty) return;

    final totalEdges = constellation.edges.length;
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < totalEdges; i++) {
      final edge = constellation.edges[i];

      // Calculate this edge's visibility based on lightUpProgress
      // Each edge lights up over ~80ms window, distributed across total progress
      final edgeStart = i / totalEdges;
      final edgeEnd = (i + 1) / totalEdges;
      final edgeProgress =
          ((lightUpProgress - edgeStart) / (edgeEnd - edgeStart)).clamp(0.0, 1.0);

      // Before light-up begins, edges are still visible but dim
      final baseOpacity = 0.25;
      final litOpacity = 0.7;
      final opacity = baseOpacity + (litOpacity - baseOpacity) * edgeProgress;

      edgePaint.color = const Color(0xFF9EDCFF).withValues(alpha: opacity);

      final from = _worldToScreen(
        constellation.starById(edge.fromStarId).position,
        size,
      );
      final to = _worldToScreen(
        constellation.starById(edge.toStarId).position,
        size,
      );

      canvas.drawLine(from, to, edgePaint);
    }
  }

  void _drawStars(Canvas canvas, Size size) {
    for (final star in constellation.stars) {
      final screenPos = _worldToScreen(star.position, size);

      // Twinkle animation
      final twinkle =
          0.7 + 0.3 * sin(elapsedSeconds * 2.0 + star.flickerPhase);

      final baseRadius = star.radius * cameraZoom.clamp(0.5, 2.0);

      // Outer glow (lavender)
      final glowRadius = baseRadius * 3.5 * twinkle;
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFC7B6FF).withValues(alpha: 0.35 * twinkle),
            const Color(0xFFC7B6FF).withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCircle(center: screenPos, radius: glowRadius),
        );
      canvas.drawCircle(screenPos, glowRadius, glowPaint);

      // Inner bloom (warm white to lavender)
      final bloomRadius = baseRadius * 2.0;
      final bloomPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFF7F3E9).withValues(alpha: 0.9 * twinkle),
            const Color(0xFFC7B6FF).withValues(alpha: 0.3 * twinkle),
            const Color(0xFFC7B6FF).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(
          Rect.fromCircle(center: screenPos, radius: bloomRadius),
        );
      canvas.drawCircle(screenPos, bloomRadius, bloomPaint);

      // Core (bright white)
      final corePaint = Paint()
        ..color = const Color(0xFFF7F3E9).withValues(alpha: twinkle);
      canvas.drawCircle(screenPos, baseRadius * 0.6, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ResultConstellationPainter oldDelegate) => true;
}
