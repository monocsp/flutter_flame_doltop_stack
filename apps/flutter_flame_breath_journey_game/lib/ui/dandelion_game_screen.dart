import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:noise_meter/noise_meter.dart';

import 'result_screen.dart';

enum _GamePhase { prepare, inhale, exhale, roundBreak }

class _FlyingSeed {
  _FlyingSeed({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.lifetime,
    required this.windPhase,
    required this.wobbleAmp,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double size;
  final double lifetime;
  final double windPhase; // random offset for wind wobble
  final double wobbleAmp; // amplitude of lateral wobble
  double age = 0;
  double opacity = 1.0;
  double rotation = 0;

  // Trail: store recent positions for glow trail
  final List<Offset> trail = [];
  static const int maxTrailLength = 8;

  bool get isDead => age >= lifetime;

  void update(double dt) {
    age += dt;
    final progress = age / lifetime;

    // ★ Wind drift: gentle lateral oscillation
    final windForce = sin(age * 2.5 + windPhase) * wobbleAmp;
    vx += windForce * dt;

    // ★ Gravity: very light downward pull after initial burst
    if (progress > 0.3) {
      vy += 12.0 * dt; // gentle gravity
    }

    // ★ Air resistance: gradual slowdown
    final drag = 0.985;
    vx *= drag;
    vy *= drag;

    // Store trail position before updating
    trail.add(Offset(x, y));
    if (trail.length > maxTrailLength) {
      trail.removeAt(0);
    }

    x += vx * dt;
    y += vy * dt;

    // ★ Rotation follows velocity direction with wobble
    rotation += (windForce * 0.08 + 0.5) * dt;

    // Fade out
    opacity = progress < 0.55
        ? 1.0
        : (1.0 - (progress - 0.55) / 0.45).clamp(0.0, 1.0);
  }
}

// ★ Lightweight particle for glow/sparkle effects (no image needed)
class _GlowParticle {
  _GlowParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.radius,
    required this.lifetime,
    required this.color,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double radius;
  final double lifetime;
  final Color color;
  double age = 0;

  bool get isDead => age >= lifetime;
  double get opacity => (1.0 - age / lifetime).clamp(0.0, 1.0);

  void update(double dt) {
    age += dt;
    x += vx * dt;
    y += vy * dt;
    // Slight upward drift for ethereal feel
    vy -= 8.0 * dt;
    vx *= 0.98;
    vy *= 0.98;
  }
}

class DandelionGameScreen extends StatefulWidget {
  const DandelionGameScreen({super.key});

  @override
  State<DandelionGameScreen> createState() => _DandelionGameScreenState();
}

class _DandelionGameScreenState extends State<DandelionGameScreen>
    with TickerProviderStateMixin {
  // ── Constants ──
  static const int _totalRounds = 3;
  static const double _ambientOffsetDb = 10.0; // breath must be this much louder than ambient
  static const double _breathRangeDb = 18.0; // dB range for 0→1 normalized intensity
  static const double _fallbackThresholdDb = 52.0;
  static const double _maxExhaleSecs = 5.0;
  static const int _sustainedTicksRequired = 2; // 2 × 120ms = 240ms

  // ── Game state ──
  _GamePhase _phase = _GamePhase.prepare;
  int _round = 0;
  int _countdown = 3;
  double _exhaleElapsed = 0;
  int _totalSeeds = 0;
  int _lastRoundSeeds = 0;
  bool _endingExhale = false;

  // ── Seed animation ──
  final List<_FlyingSeed> _seeds = [];
  final List<_GlowParticle> _particles = [];
  final Random _random = Random();

  // ── Ticker ──
  late Ticker _ticker;
  Duration _lastTickElapsed = Duration.zero;

  // ── Noise ──
  StreamSubscription<NoiseReading>? _noiseSubscription;
  final NoiseMeter _noiseMeter = NoiseMeter();
  double _currentDb = 0.0;

  // ── Ambient calibration ──
  final List<double> _calibrationReadings = [];
  double _ambientDb = _fallbackThresholdDb;
  double _dynamicThreshold = _fallbackThresholdDb;

  // ── Sustained detection ──
  int _consecutiveAboveTicks = 0;
  bool _breathActive = false;

  // ── Visual feedback (0.0 = silent, 1.0 = max breath) ──
  double _breathLevel = 0.0;

  // ── No-detection hint ──
  bool _showNoDetectionHint = false;
  Timer? _noDetectionTimer;
  bool _everDetectedThisRound = false;

  // ── Dandelion sway ──
  double _dandelionSway = 0; // current sway angle in radians
  double _swayTarget = 0;

  Timer? _countdownTimer;
  Timer? _seedSpawnTimer;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _startPreparePhase();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _countdownTimer?.cancel();
    _seedSpawnTimer?.cancel();
    _noDetectionTimer?.cancel();
    _noiseSubscription?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // Ticker
  // ─────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (_lastTickElapsed == Duration.zero) {
      _lastTickElapsed = elapsed;
      return;
    }
    final dt = (elapsed - _lastTickElapsed).inMicroseconds / 1000000.0;
    _lastTickElapsed = elapsed;

    if (dt <= 0 || dt > 0.1 || !mounted) return;

    setState(() {
      for (final seed in _seeds) {
        seed.update(dt);
        // ★ Spawn glow particles from seed trail
        if (!seed.isDead && seed.age > 0.15 && _random.nextDouble() < 0.4) {
          _particles.add(_GlowParticle(
            x: seed.x,
            y: seed.y,
            vx: (_random.nextDouble() - 0.5) * 12,
            vy: (_random.nextDouble() - 0.5) * 12,
            radius: 1.5 + _random.nextDouble() * 2.5,
            lifetime: 0.5 + _random.nextDouble() * 0.6,
            color: const Color(0xFFE8E0D4),
          ));
        }
      }
      _seeds.removeWhere((s) => s.isDead);

      for (final p in _particles) {
        p.update(dt);
      }
      _particles.removeWhere((p) => p.isDead);

      // ★ Dandelion sway: oscillate left-right during breath
      if (_phase == _GamePhase.exhale && _breathActive) {
        final elapsed = _exhaleElapsed;
        final swingAmp = 0.06 + _breathLevel * 0.10;
        _swayTarget = sin(elapsed * 3.5) * swingAmp;
      } else {
        _swayTarget = 0;
      }
      _dandelionSway += (_swayTarget - _dandelionSway) * 4.0 * dt;

      if (_phase == _GamePhase.exhale && !_endingExhale) {
        _exhaleElapsed += dt;
        if (_exhaleElapsed >= _maxExhaleSecs) {
          _endingExhale = true;
          _endExhale();
        }
      }
    });
  }

  // ─────────────────────────────────────────────
  // Phase transitions
  // ─────────────────────────────────────────────

  void _startPreparePhase() {
    if (!mounted) return;
    setState(() {
      _phase = _GamePhase.prepare;
      _countdown = 3;
      _endingExhale = false;
      _breathLevel = 0;
    });

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
          _startInhalePhase();
        }
      });
    });
  }

  void _startInhalePhase() {
    if (!mounted) return;
    setState(() {
      _phase = _GamePhase.inhale;
      _countdown = 3;
    });

    // ★ Start ambient calibration — measure background noise during inhale
    _calibrationReadings.clear();
    _startCalibrationListening();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
          _finishCalibrationAndStartExhale();
        }
      });
    });
  }

  void _finishCalibrationAndStartExhale() {
    // ★ Calculate ambient baseline from calibration readings
    _noiseSubscription?.cancel();
    _noiseSubscription = null;

    if (_calibrationReadings.length >= 3) {
      // Use median to avoid outlier spikes
      final sorted = List<double>.from(_calibrationReadings)..sort();
      _ambientDb = sorted[sorted.length ~/ 2];
    } else if (_calibrationReadings.isNotEmpty) {
      _ambientDb =
          _calibrationReadings.reduce((a, b) => a + b) / _calibrationReadings.length;
    } else {
      _ambientDb = _fallbackThresholdDb;
    }

    // ★ Dynamic threshold = ambient + offset
    _dynamicThreshold = _ambientDb + _ambientOffsetDb;

    _startExhalePhase();
  }

  void _startCalibrationListening() {
    _noiseSubscription?.cancel();
    _noiseSubscription = _noiseMeter.noise.listen(
      (reading) {
        if (reading.maxDecibel.isFinite) {
          _calibrationReadings.add(reading.maxDecibel);
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _startExhalePhase() {
    if (!mounted) return;
    setState(() {
      _phase = _GamePhase.exhale;
      _exhaleElapsed = 0;
      _lastRoundSeeds = 0;
      _endingExhale = false;
      _consecutiveAboveTicks = 0;
      _breathActive = false;
      _breathLevel = 0;
      _showNoDetectionHint = false;
      _everDetectedThisRound = false;
    });
    _startNoiseListening();
    _startSeedSpawning();
    _startNoDetectionTimer();
  }

  void _startNoDetectionTimer() {
    _noDetectionTimer?.cancel();
    _noDetectionTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _phase == _GamePhase.exhale && !_everDetectedThisRound) {
        setState(() => _showNoDetectionHint = true);
      }
    });
  }

  // ─────────────────────────────────────────────
  // Noise listening (exhale phase)
  // ─────────────────────────────────────────────

  void _startNoiseListening() {
    _noiseSubscription?.cancel();
    _noiseSubscription = _noiseMeter.noise.listen(
      (reading) {
        if (mounted) {
          setState(() {
            _currentDb =
                reading.maxDecibel.isFinite ? reading.maxDecibel : 0.0;

            // ★ Update visual feedback level (0.0 – 1.0)
            _breathLevel =
                ((_currentDb - _dynamicThreshold) / _breathRangeDb)
                    .clamp(0.0, 1.0);
          });
        }
      },
      onError: (_) {
        _currentDb = 0.0;
        _breathLevel = 0;
      },
      cancelOnError: false,
    );
  }

  // ─────────────────────────────────────────────
  // Seed spawning with sustained detection
  // ─────────────────────────────────────────────

  void _startSeedSpawning() {
    _seedSpawnTimer?.cancel();
    _seedSpawnTimer =
        Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _phase != _GamePhase.exhale) return;

      final normalized =
          ((_currentDb - _dynamicThreshold) / _breathRangeDb).clamp(0.0, 1.0);

      if (normalized <= 0) {
        // ★ Below threshold → reset sustained counter
        _consecutiveAboveTicks = 0;
        _breathActive = false;
        return;
      }

      // ★ Sustained detection: must stay above threshold for 240ms+
      _consecutiveAboveTicks++;
      if (_consecutiveAboveTicks < _sustainedTicksRequired) return;
      _breathActive = true;

      // ★ First detection → hide hint, cancel timer
      if (!_everDetectedThisRound) {
        _everDetectedThisRound = true;
        _noDetectionTimer?.cancel();
        if (_showNoDetectionHint) {
          setState(() => _showNoDetectionHint = false);
        }
      }

      // ★ Always spawn 1 seed per tick (intensity affects speed/size, not count)
      if (mounted) _spawnSeed(normalized);
    });
  }

  void _spawnSeed(double intensity) {
    final spread = pi * 0.7;
    final angle = -pi / 2 + (_random.nextDouble() - 0.5) * spread;
    final speed = 60.0 + intensity * 130.0 + _random.nextDouble() * 35.0;

    // ★ Burst particles at spawn point
    for (int j = 0; j < 3; j++) {
      _particles.add(_GlowParticle(
        x: (_random.nextDouble() - 0.5) * 10,
        y: (_random.nextDouble() - 0.5) * 10,
        vx: cos(angle) * speed * 0.3 + (_random.nextDouble() - 0.5) * 20,
        vy: sin(angle) * speed * 0.3 + (_random.nextDouble() - 0.5) * 20,
        radius: 2.0 + _random.nextDouble() * 3.0,
        lifetime: 0.3 + _random.nextDouble() * 0.4,
        color: _random.nextBool()
            ? const Color(0xFFF7F3E9)
            : const Color(0xFFE8E0D4),
      ));
    }

    setState(() {
      _seeds.add(_FlyingSeed(
        x: (_random.nextDouble() - 0.5) * 18,
        y: (_random.nextDouble() - 0.5) * 10,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed,
        size: 0.3 + intensity * 0.5 + _random.nextDouble() * 0.2,
        lifetime: 2.2 + intensity * 1.5 + _random.nextDouble() * 1.0,
        windPhase: _random.nextDouble() * pi * 2,
        wobbleAmp: 15.0 + _random.nextDouble() * 25.0,
      ));
      _lastRoundSeeds++;
      _totalSeeds++;
    });
  }

  void _endExhale() {
    _noiseSubscription?.cancel();
    _noiseSubscription = null;
    _seedSpawnTimer?.cancel();
    _seedSpawnTimer = null;
    _noDetectionTimer?.cancel();

    setState(() {
      _phase = _GamePhase.roundBreak;
      _breathLevel = 0;
      _showNoDetectionHint = false;
      _dandelionSway = 0;
      _swayTarget = 0;
    });

    _round++;

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      if (_round >= _totalRounds) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ResultScreen(totalSeeds: _totalSeeds),
          ),
        );
      } else {
        _startPreparePhase();
      }
    });
  }

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1F2D),
      body: Stack(
        children: [
          _buildBackground(),
          switch (_phase) {
            _GamePhase.prepare => _buildPreparePhase(),
            _GamePhase.inhale => _buildInhalePhase(),
            _GamePhase.exhale => _buildExhalePhase(),
            _GamePhase.roundBreak => _buildRoundBreak(),
          },
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1F2D), Color(0xFF132A3B), Color(0xFF1A3548)],
        ),
      ),
      child: SizedBox.expand(),
    );
  }

  Widget _buildRoundBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        '${_round + 1} / $_totalRounds',
        style: const TextStyle(
          color: Color(0xFFFFD7A1),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  // ★ Breath detection visual feedback indicator
  Widget _buildBreathIndicator() {
    final level = _breathLevel.clamp(0.0, 1.0);
    final isActive = _breathActive;
    final baseSize = 52.0;
    final pulseSize = baseSize + level * 24.0;
    final glowOpacity = isActive ? 0.15 + level * 0.25 : 0.06;
    final iconColor = isActive
        ? Color.lerp(const Color(0xFF7ADAA5), const Color(0xFFB8F0D0), level)!
        : const Color(0xFF4A7A62);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: pulseSize,
          height: pulseSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF7ADAA5).withValues(alpha: glowOpacity),
            border: Border.all(
              color: iconColor.withValues(alpha: 0.5),
              width: isActive ? 2.5 : 1.5,
            ),
          ),
          child: Icon(Icons.mic_rounded, color: iconColor, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          isActive ? '감지 중' : '숨을 내쉬세요',
          style: TextStyle(
            color: isActive
                ? const Color(0xFF7ADAA5)
                : Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPreparePhase() {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildRoundBadge(),
            const SizedBox(height: 52),
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF7ADAA5).withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  '$_countdown',
                  style: const TextStyle(
                    color: Color(0xFFF7F3E9),
                    fontSize: 70,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 36),
            const Text(
              '입을 마이크에\n가까이 대세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFE3D7C8),
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF7ADAA5).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Color(0xFF7ADAA5),
                size: 36,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInhalePhase() {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildRoundBadge(),
            const SizedBox(height: 32),
            const Text(
              '숨을 크게 들이쉬세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFF7F3E9),
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$_countdown',
              style: const TextStyle(
                color: Color(0xFFFFD7A1),
                fontSize: 56,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            // ★ Calibration status
            Text(
              '주변 소음을 측정하고 있어요…',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 36),
            SvgPicture.asset(
              'assets/dandelion.svg',
              package: 'flutter_flame_breath_journey_game',
              width: 200,
              height: 300,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExhalePhase() {
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height * 0.58;

    // ★ Breath-reactive background tint
    final breathTint = _breathActive ? _breathLevel * 0.08 : 0.0;

    return Stack(
      children: [
        // ★ Dynamic background glow when breathing
        if (breathTint > 0)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, 0.15),
                  radius: 0.9,
                  colors: [
                    const Color(0xFF7ADAA5).withValues(alpha: breathTint),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        // ★ Glow particle layer (painted with Canvas)
        Positioned.fill(
          child: CustomPaint(
            painter: _GlowParticlePainter(
              particles: _particles,
              center: Offset(cx, cy),
            ),
          ),
        ),
        // ★ Seed trail layer
        Positioned.fill(
          child: CustomPaint(
            painter: _SeedTrailPainter(
              seeds: _seeds,
              center: Offset(cx, cy),
            ),
          ),
        ),
        // Flying seeds with rotation
        ..._seeds.map((seed) {
          return Positioned(
            left: cx + seed.x - 20,
            top: cy + seed.y - 25,
            child: Opacity(
              opacity: seed.opacity,
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
        // ★ Dandelion with breath sway
        Positioned(
          left: cx - 100,
          top: cy - 150,
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()..rotateZ(_dandelionSway),
            child: SvgPicture.asset(
              'assets/dandelion.svg',
              package: 'flutter_flame_breath_journey_game',
              width: 200,
              height: 300,
            ),
          ),
        ),
        // UI overlay
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 28),
              _buildRoundBadge(),
              const SizedBox(height: 18),
              const Text(
                '내쉬세요',
                style: TextStyle(
                  color: Color(0xFFF7F3E9),
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 52),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (_exhaleElapsed / _maxExhaleSecs).clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: Colors.white12,
                    valueColor:
                        const AlwaysStoppedAnimation(Color(0xFF7ADAA5)),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // ★ Breath detection feedback
              _buildBreathIndicator(),
              const SizedBox(height: 16),
              // ★ No-detection hint (fade in after 2s of silence)
              AnimatedOpacity(
                opacity: _showNoDetectionHint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD7A1).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFFD7A1).withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFFFD7A1),
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          '혹시 마이크에서 떨어져있거나,\n막혀있지 않나요?',
                          style: TextStyle(
                            color: Color(0xFFFFD7A1),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 0, 36, 36),
                child: Text(
                  '오래 내쉬면 내 쉴수록\n민들레 씨앗이 멀리, 많이 날아가요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 13,
                    height: 1.65,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoundBreak() {
    final isLast = _round >= _totalRounds;
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF7ADAA5).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLast ? Icons.check_rounded : Icons.air_rounded,
                color: const Color(0xFF7ADAA5),
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isLast ? '완료!' : '잘했어요!',
              style: const TextStyle(
                color: Color(0xFFF7F3E9),
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '씨앗 $_lastRoundSeeds개가 날아갔어요',
              style: const TextStyle(
                color: Color(0xFFB0C9B8),
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ★ Custom painters for particle effects
// ─────────────────────────────────────────────

class _GlowParticlePainter extends CustomPainter {
  _GlowParticlePainter({required this.particles, required this.center});

  final List<_GlowParticle> particles;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withValues(alpha: p.opacity * 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        Offset(center.dx + p.x, center.dy + p.y),
        p.radius * p.opacity,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlowParticlePainter oldDelegate) => true;
}

class _SeedTrailPainter extends CustomPainter {
  _SeedTrailPainter({required this.seeds, required this.center});

  final List<_FlyingSeed> seeds;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    for (final seed in seeds) {
      if (seed.trail.length < 2) continue;
      final trailPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (int i = 1; i < seed.trail.length; i++) {
        final t = i / seed.trail.length;
        trailPaint
          ..color = const Color(0xFFF7F3E9)
              .withValues(alpha: t * seed.opacity * 0.25)
          ..strokeWidth = t * 2.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawLine(
          Offset(center.dx + seed.trail[i - 1].dx,
              center.dy + seed.trail[i - 1].dy),
          Offset(center.dx + seed.trail[i].dx, center.dy + seed.trail[i].dy),
          trailPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SeedTrailPainter oldDelegate) => true;
}
