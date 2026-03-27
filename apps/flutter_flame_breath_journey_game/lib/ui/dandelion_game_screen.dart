import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:noise_meter/noise_meter.dart';

import 'result_screen.dart';

enum _GamePhase { prepare, inhale, hold, exhale, roundBreak }

class _AttachedSeed {
  _AttachedSeed({
    required this.angle,
    required this.distance,
    required this.size,
    required this.rotation,
    required this.maxOpacity,
  });

  final double angle;
  final double distance;
  final double size;
  final double rotation;
  final double maxOpacity; // each seed has different max opacity
  double opacity = 0.0;
}

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
  final double windPhase;
  final double wobbleAmp;
  double age = 0;
  double opacity = 1.0;
  double rotation = 0;

  // Trail: circular buffer for O(1) add/remove
  final Queue<Offset> trail = Queue<Offset>();
  static const int maxTrailLength = 8;

  bool get isDead => age >= lifetime;

  void update(double dt) {
    age += dt;
    final progress = age / lifetime;

    final windForce = sin(age * 2.5 + windPhase) * wobbleAmp;
    vx += windForce * dt;

    if (progress > 0.3) {
      vy += 12.0 * dt;
    }

    const drag = 0.985;
    vx *= drag;
    vy *= drag;

    trail.addLast(Offset(x, y));
    if (trail.length > maxTrailLength) {
      trail.removeFirst(); // O(1) with Queue
    }

    x += vx * dt;
    y += vy * dt;

    rotation += (windForce * 0.08 + 0.5) * dt;

    opacity = progress < 0.55
        ? 1.0
        : (1.0 - (progress - 0.55) / 0.45).clamp(0.0, 1.0);
  }
}

// Poolable particle — reset() instead of creating new objects
class _GlowParticle {
  double x = 0;
  double y = 0;
  double vx = 0;
  double vy = 0;
  double radius = 0;
  double lifetime = 0;
  Color color = const Color(0xFFE8E0D4);
  double age = 0;
  bool alive = false;

  double get opacity => (1.0 - age / lifetime).clamp(0.0, 1.0);

  void reset({
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double radius,
    required double lifetime,
    required Color color,
  }) {
    this.x = x;
    this.y = y;
    this.vx = vx;
    this.vy = vy;
    this.radius = radius;
    this.lifetime = lifetime;
    this.color = color;
    age = 0;
    alive = true;
  }

  void update(double dt) {
    age += dt;
    x += vx * dt;
    y += vy * dt;
    vy -= 8.0 * dt;
    vx *= 0.98;
    vy *= 0.98;
    if (age >= lifetime) alive = false;
  }
}

// Object pool for particles to avoid GC pressure
class _ParticlePool {
  static const int maxParticles = 120;
  final List<_GlowParticle> _pool =
      List.generate(maxParticles, (_) => _GlowParticle());
  int _activeCount = 0;

  List<_GlowParticle> get pool => _pool;
  int get activeCount => _activeCount;

  _GlowParticle? acquire() {
    for (int i = 0; i < maxParticles; i++) {
      if (!_pool[i].alive) {
        _activeCount++;
        return _pool[i];
      }
    }
    return null; // pool exhausted — skip particle
  }

  void updateAll(double dt) {
    _activeCount = 0;
    for (int i = 0; i < maxParticles; i++) {
      if (_pool[i].alive) {
        _pool[i].update(dt);
        if (_pool[i].alive) _activeCount++;
      }
    }
  }
}

// ─────────────────────────────────────────────
// Mutable render state read by painters (no rebuild needed)
// ─────────────────────────────────────────────

class _DandelionRenderState {
  double dandelionSway = 0;
  double breathLevel = 0;
  bool breathActive = false;
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
  static const double _ambientOffsetDb = 10.0;
  static const double _breathRangeDb = 18.0;
  static const double _fallbackThresholdDb = 52.0;
  static const double _maxExhaleSecs = 8.0;
  static const int _sustainedTicksRequired = 2;
  static const int _holdSeconds = 7;

  // ── ValueNotifiers (drive UI via ValueListenableBuilder) ──
  final ValueNotifier<_GamePhase> _phase =
      ValueNotifier<_GamePhase>(_GamePhase.prepare);
  final ValueNotifier<int> _round = ValueNotifier<int>(0);
  final ValueNotifier<int> _countdown = ValueNotifier<int>(3);
  final ValueNotifier<double> _exhaleElapsed = ValueNotifier<double>(0);
  final ValueNotifier<double> _breathLevel = ValueNotifier<double>(0);
  final ValueNotifier<bool> _breathActive = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _showNoDetectionHint = ValueNotifier<bool>(false);
  final ValueNotifier<double> _dandelionSway = ValueNotifier<double>(0);

  // ── Plain fields (internal logic only) ──
  bool _endingExhale = false;
  int _totalSeeds = 0;
  int _lastRoundSeeds = 0;
  double _elapsedTime = 0;

  // ── Seed animation ──
  final List<_FlyingSeed> _seeds = [];
  final _ParticlePool _particlePool = _ParticlePool();
  final Random _random = Random();

  // ── Attached seeds (hold phase) ──
  final List<_AttachedSeed> _attachedSeeds = [];
  Timer? _holdSeedTimer;

  // ── Ticker ──
  late Ticker _ticker;
  Duration _lastTickElapsed = Duration.zero;

  // ── Repaint notifier — drives CustomPainter without rebuild ──
  final _GameRepaintNotifier _repaintNotifier = _GameRepaintNotifier();

  // ── Render state read by painters ──
  final _DandelionRenderState _renderState = _DandelionRenderState();

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

  // ── No-detection hint ──
  Timer? _noDetectionTimer;
  bool _everDetectedThisRound = false;

  // ── Dandelion sway (internal) ──
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
    _holdSeedTimer?.cancel();
    _noDetectionTimer?.cancel();
    _noiseSubscription?.cancel();
    _repaintNotifier.dispose();
    // Dispose all ValueNotifiers
    _phase.dispose();
    _round.dispose();
    _countdown.dispose();
    _exhaleElapsed.dispose();
    _breathLevel.dispose();
    _breathActive.dispose();
    _showNoDetectionHint.dispose();
    _dandelionSway.dispose();
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

    _elapsedTime += dt;

    // Update seeds (no rebuild — painter reads these directly)
    for (final seed in _seeds) {
      seed.update(dt);
      // Spawn glow particles from seed trail (with pool)
      if (!seed.isDead && seed.age > 0.15 && _random.nextDouble() < 0.3) {
        final p = _particlePool.acquire();
        if (p != null) {
          p.reset(
            x: seed.x,
            y: seed.y,
            vx: (_random.nextDouble() - 0.5) * 12,
            vy: (_random.nextDouble() - 0.5) * 12,
            radius: 1.5 + _random.nextDouble() * 2.5,
            lifetime: 0.5 + _random.nextDouble() * 0.6,
            color: const Color(0xFFE8E0D4),
          );
        }
      }
    }
    _seeds.removeWhere((s) => s.isDead);

    // Update particles via pool (no allocation)
    _particlePool.updateAll(dt);

    // Fade in attached seeds
    for (final seed in _attachedSeeds) {
      if (seed.opacity < seed.maxOpacity) {
        seed.opacity = (seed.opacity + dt * 2.0).clamp(0.0, seed.maxOpacity);
      }
    }

    // Dandelion sway
    if (_phase.value == _GamePhase.exhale && _breathActive.value) {
      final swingAmp = 0.06 + _breathLevel.value * 0.10;
      _swayTarget = sin(_exhaleElapsed.value * 3.5) * swingAmp;
    } else if (_phase.value == _GamePhase.hold && _countdown.value <= 2) {
      // Hold phase gentle sway in last 2 seconds
      _swayTarget = sin(_elapsedTime * 2.0) * 0.04;
    } else {
      _swayTarget = 0;
    }
    final newSway =
        _dandelionSway.value + (_swayTarget - _dandelionSway.value) * 4.0 * dt;
    _dandelionSway.value = newSway;

    if (_phase.value == _GamePhase.exhale && !_endingExhale) {
      _exhaleElapsed.value += dt;
      if (_exhaleElapsed.value >= _maxExhaleSecs) {
        _endingExhale = true;
        _endExhale();
      }
    }

    // Sync render state for painters
    _renderState.dandelionSway = _dandelionSway.value;
    _renderState.breathLevel = _breathLevel.value;
    _renderState.breathActive = _breathActive.value;

    // Notify the game painter to repaint (no widget rebuild)
    _repaintNotifier.notify();
  }

  // ─────────────────────────────────────────────
  // Phase transitions
  // ─────────────────────────────────────────────

  void _startPreparePhase() {
    if (!mounted) return;
    _phase.value = _GamePhase.prepare;
    _countdown.value = 3;
    _endingExhale = false;
    _breathLevel.value = 0;

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _countdown.value--;
      if (_countdown.value <= 0) {
        timer.cancel();
        _startInhalePhase();
      }
    });
  }

  void _startInhalePhase() {
    if (!mounted) return;
    _phase.value = _GamePhase.inhale;
    _countdown.value = 4;

    // Start ambient calibration — measure background noise during inhale
    _calibrationReadings.clear();
    _startCalibrationListening();

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _countdown.value--;
      if (_countdown.value <= 0) {
        timer.cancel();
        _startHoldPhase();
      }
    });
  }

  void _startHoldPhase() {
    if (!mounted) return;

    // Finish calibration (moved from _finishCalibrationAndStartExhale)
    _noiseSubscription?.cancel();
    _noiseSubscription = null;

    if (_calibrationReadings.length >= 3) {
      final sorted = List<double>.from(_calibrationReadings)..sort();
      _ambientDb = sorted[sorted.length ~/ 2];
    } else if (_calibrationReadings.isNotEmpty) {
      _ambientDb = _calibrationReadings.reduce((a, b) => a + b) /
          _calibrationReadings.length;
    } else {
      _ambientDb = _fallbackThresholdDb;
    }
    _dynamicThreshold = _ambientDb + _ambientOffsetDb;

    _attachedSeeds.clear();
    _countdown.value = _holdSeconds;
    _phase.value = _GamePhase.hold;

    // Seed attachment timer: add 2-3 seeds every second for first 5 seconds
    _holdSeedTimer?.cancel();
    _holdSeedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown.value <= 2) {
        timer.cancel();
        return;
      }
      final count = 10 + _random.nextInt(5); // 10~14 per second → 50~70 total
      for (int i = 0; i < count; i++) {
        // Fan shape: mostly upper hemisphere (-π to 0) with some below
        final double angle;
        if (_random.nextDouble() < 0.8) {
          // 80%: upper fan (-π to 0, i.e. upward)
          angle = -pi + _random.nextDouble() * pi;
        } else {
          // 20%: slightly below (0 to π*0.3)
          angle = _random.nextDouble() * pi * 0.3;
        }
        _attachedSeeds.add(_AttachedSeed(
          angle: angle,
          distance: 10.0 + _random.nextDouble() * 40.0,
          size: 0.6 + _random.nextDouble() * 0.5,
          rotation: angle + pi / 2,
          maxOpacity: 0.5 + _random.nextDouble() * 0.5,
        ));
      }
      _repaintNotifier.notify();
    });

    // Hold countdown timer
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _countdown.value--;
      if (_countdown.value <= 0) {
        timer.cancel();
        _holdSeedTimer?.cancel();
        _startExhalePhase();
      }
    });
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
    _phase.value = _GamePhase.exhale;
    _exhaleElapsed.value = 0;
    _lastRoundSeeds = 0;
    _endingExhale = false;
    _consecutiveAboveTicks = 0;
    _breathActive.value = false;
    _breathLevel.value = 0;
    _showNoDetectionHint.value = false;
    _everDetectedThisRound = false;
    _startNoiseListening();
    _startSeedSpawning();
    _startNoDetectionTimer();
  }

  void _startNoDetectionTimer() {
    _noDetectionTimer?.cancel();
    _noDetectionTimer = Timer(const Duration(seconds: 2), () {
      if (mounted &&
          _phase.value == _GamePhase.exhale &&
          !_everDetectedThisRound) {
        _showNoDetectionHint.value = true;
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
          // Update values — ticker drives repaints via _repaintNotifier
          _currentDb =
              reading.maxDecibel.isFinite ? reading.maxDecibel : 0.0;
          _breathLevel.value =
              ((_currentDb - _dynamicThreshold) / _breathRangeDb)
                  .clamp(0.0, 1.0);
        }
      },
      onError: (_) {
        _currentDb = 0.0;
        _breathLevel.value = 0;
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
      if (!mounted || _phase.value != _GamePhase.exhale) return;

      final normalized =
          ((_currentDb - _dynamicThreshold) / _breathRangeDb).clamp(0.0, 1.0);

      if (normalized <= 0) {
        // Below threshold -> reset sustained counter
        _consecutiveAboveTicks = 0;
        _breathActive.value = false;
        return;
      }

      // Sustained detection: must stay above threshold for 240ms+
      _consecutiveAboveTicks++;
      if (_consecutiveAboveTicks < _sustainedTicksRequired) return;
      _breathActive.value = true;

      // First detection -> hide hint, cancel timer
      if (!_everDetectedThisRound) {
        _everDetectedThisRound = true;
        _noDetectionTimer?.cancel();
        if (_showNoDetectionHint.value) {
          _showNoDetectionHint.value = false;
        }
      }

      // Always spawn 1 seed per tick (intensity affects speed/size, not count)
      if (mounted) _spawnSeed(normalized);
    });
  }

  void _spawnSeed(double intensity) {
    // Only detach from dandelion — no spawning from thin air
    if (_attachedSeeds.isEmpty) return;

    final attached = _attachedSeeds.removeLast();
    final seedX = cos(attached.angle) * attached.distance;
    final seedY = sin(attached.angle) * attached.distance;

    final spread = pi * 0.7;
    final angle = -pi / 2 + (_random.nextDouble() - 0.5) * spread;
    final speed = 40.0 + intensity * 100.0 + _random.nextDouble() * 25.0;

    _seeds.add(_FlyingSeed(
      x: seedX,
      y: seedY,
      vx: cos(angle) * speed,
      vy: sin(angle) * speed,
      size: attached.size, // same size as when attached
      lifetime: 2.2 + intensity * 1.5 + _random.nextDouble() * 1.0,
      windPhase: _random.nextDouble() * pi * 2,
      wobbleAmp: 15.0 + _random.nextDouble() * 25.0,
    ));
    _lastRoundSeeds++;
    _totalSeeds++;
    _repaintNotifier.notify();
  }

  void _endExhale() {
    _noiseSubscription?.cancel();
    _noiseSubscription = null;
    _seedSpawnTimer?.cancel();
    _seedSpawnTimer = null;
    _noDetectionTimer?.cancel();
    _attachedSeeds.clear();

    _phase.value = _GamePhase.roundBreak;
    _breathLevel.value = 0;
    _showNoDetectionHint.value = false;
    _dandelionSway.value = 0;
    _swayTarget = 0;

    _round.value++;

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      if (_round.value >= _totalRounds) {
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
  // Dandelion + attached seeds widget
  // ─────────────────────────────────────────────

  Widget _buildDandelionWithSeeds({required double cx, required double cy}) {
    return Positioned(
      left: cx - 100,
      top: cy - 150,
      child: ValueListenableBuilder<double>(
        valueListenable: _dandelionSway,
        builder: (context, sway, child) {
          return Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()..rotateZ(sway),
            child: child,
          );
        },
        child: SizedBox(
          width: 200,
          height: 300,
          child: ListenableBuilder(
            listenable: _repaintNotifier,
            builder: (context, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Dandelion bold SVG (clean stem + head for seed attachment)
                  SvgPicture.asset(
                    'assets/dandelion_bold.svg',
                    package: 'flutter_flame_breath_journey_game',
                    width: 200,
                    height: 300,
                  ),
                  // Attached seeds around dandelion head (SVG circle: cx=100, cy=148)
                  ..._attachedSeeds.map((seed) {
                    const seedW = 55.0;
                    const seedH = 104.0; // tall seeds
                    final seedLeft =
                        100 + cos(seed.angle) * seed.distance - seedW / 2;
                    final seedTop =
                        148 + sin(seed.angle) * seed.distance - seedH / 2;
                    return Positioned(
                      left: seedLeft,
                      top: seedTop,
                      child: Opacity(
                        opacity: seed.opacity,
                        child: Transform.rotate(
                          angle: seed.rotation,
                          child: Transform.scale(
                            scale: seed.size,
                            child: SvgPicture.asset(
                              'assets/dandelion_seed.svg',
                              package: 'flutter_flame_breath_journey_game',
                              width: seedW,
                              height: seedH,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ),
    );
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
          ValueListenableBuilder<_GamePhase>(
            valueListenable: _phase,
            builder: (context, phase, _) {
              return switch (phase) {
                _GamePhase.prepare => _buildPreparePhase(),
                _GamePhase.inhale => _buildInhalePhase(),
                _GamePhase.hold => _buildHoldPhase(),
                _GamePhase.exhale => _buildExhalePhase(),
                _GamePhase.roundBreak => _buildRoundBreak(),
              };
            },
          ),
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
    return ValueListenableBuilder<int>(
      valueListenable: _round,
      builder: (context, round, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            '${round + 1} / $_totalRounds',
            style: const TextStyle(
              color: Color(0xFFFFD7A1),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
        );
      },
    );
  }

  // Breath detection visual feedback indicator
  Widget _buildBreathIndicator() {
    return ListenableBuilder(
      listenable: Listenable.merge([_breathLevel, _breathActive]),
      builder: (context, _) {
        final level = _breathLevel.value.clamp(0.0, 1.0);
        final isActive = _breathActive.value;
        final baseSize = 52.0;
        final pulseSize = baseSize + level * 24.0;
        final glowOpacity = isActive ? 0.15 + level * 0.25 : 0.06;
        final iconColor = isActive
            ? Color.lerp(
                const Color(0xFF7ADAA5), const Color(0xFFB8F0D0), level)!
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
      },
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
                child: ValueListenableBuilder<int>(
                  valueListenable: _countdown,
                  builder: (context, countdown, _) {
                    return Text(
                      '$countdown',
                      style: const TextStyle(
                        color: Color(0xFFF7F3E9),
                        fontSize: 70,
                        fontWeight: FontWeight.w900,
                      ),
                    );
                  },
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
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height * 0.58;

    return Stack(
      children: [
        // Dandelion at same position as hold/exhale
        Positioned(
          left: cx - 100,
          top: cy - 150,
          child: SvgPicture.asset(
            'assets/dandelion.svg',
            package: 'flutter_flame_breath_journey_game',
            width: 200,
            height: 300,
          ),
        ),
        // UI overlay
        SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 28),
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
                ValueListenableBuilder<int>(
                  valueListenable: _countdown,
                  builder: (context, countdown, _) {
                    return Text(
                      '$countdown',
                      style: const TextStyle(
                        color: Color(0xFFFFD7A1),
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '주변 소음을 측정하고 있어요…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHoldPhase() {
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height * 0.58;

    return Stack(
      children: [
        // Dandelion with attached seeds
        _buildDandelionWithSeeds(cx: cx, cy: cy),
        // UI overlay
        SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 28),
                _buildRoundBadge(),
                const SizedBox(height: 32),
                const Text(
                  '숨을 참으세요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFF7F3E9),
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                ValueListenableBuilder<int>(
                  valueListenable: _countdown,
                  builder: (context, countdown, _) {
                    return Text(
                      '$countdown',
                      style: const TextStyle(
                        color: Color(0xFFFFD7A1),
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  '씨앗이 바람을 품고 있어요',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExhalePhase() {
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height * 0.58;

    return Stack(
      children: [
        // Breath-reactive background glow
        Positioned.fill(
          child: CustomPaint(
            painter: _BreathGlowPainter(
              center: Offset(cx, cy),
              renderState: _renderState,
              repaintNotifier: _repaintNotifier,
            ),
          ),
        ),
        // Particle + trail layer (CustomPainter — no widget rebuild needed)
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _ParticleTrailPainter(
                seeds: _seeds,
                particlePool: _particlePool,
                center: Offset(cx, cy),
                repaintNotifier: _repaintNotifier,
              ),
            ),
          ),
        ),
        // Flying seeds — original SVG (flutter_svg caches parsed data internally)
        // Driven by _repaintNotifier via ListenableBuilder
        ListenableBuilder(
          listenable: _repaintNotifier,
          builder: (context, _) {
            return Stack(
              children: _seeds.map((seed) {
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
              }).toList(),
            );
          },
        ),
        // Dandelion with attached seeds
        _buildDandelionWithSeeds(cx: cx, cy: cy),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 52),
                child: ValueListenableBuilder<double>(
                  valueListenable: _exhaleElapsed,
                  builder: (context, elapsed, _) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (elapsed / _maxExhaleSecs).clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: Colors.white12,
                        valueColor:
                            const AlwaysStoppedAnimation(Color(0xFF7ADAA5)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              _buildBreathIndicator(),
              const SizedBox(height: 16),
              ValueListenableBuilder<bool>(
                valueListenable: _showNoDetectionHint,
                builder: (context, showHint, child) {
                  return AnimatedOpacity(
                    opacity: showHint ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 600),
                    child: child,
                  );
                },
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
    final isLast = _round.value >= _totalRounds;
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
// Repaint notifier — triggers CustomPainter without widget rebuild
// ─────────────────────────────────────────────

class _GameRepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

// ─────────────────────────────────────────────
// Breath glow background painter
// ─────────────────────────────────────────────

class _BreathGlowPainter extends CustomPainter {
  _BreathGlowPainter({
    required this.center,
    required this.renderState,
    required _GameRepaintNotifier repaintNotifier,
  }) : super(repaint: repaintNotifier);

  final Offset center;
  final _DandelionRenderState renderState;

  static final Paint _glowPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (!renderState.breathActive || renderState.breathLevel <= 0) return;
    final breathTint = renderState.breathLevel * 0.08;
    if (breathTint <= 0) return;
    _glowPaint.shader = ui.Gradient.radial(
      Offset(center.dx, center.dy - size.height * 0.1),
      size.width * 0.9,
      [
        const Color(0xFF7ADAA5).withValues(alpha: breathTint),
        const Color(0x00000000),
      ],
    );
    canvas.drawRect(Offset.zero & size, _glowPaint);
    _glowPaint.shader = null;
  }

  @override
  bool shouldRepaint(covariant _BreathGlowPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────
// Particle + trail painter (no blur for performance)
// ─────────────────────────────────────────────

class _ParticleTrailPainter extends CustomPainter {
  _ParticleTrailPainter({
    required this.seeds,
    required this.particlePool,
    required this.center,
    required _GameRepaintNotifier repaintNotifier,
  }) : super(repaint: repaintNotifier);

  final List<_FlyingSeed> seeds;
  final _ParticlePool particlePool;
  final Offset center;

  static final Paint _particlePaint = Paint();
  static final Paint _trailPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    // Glow particles (simple circles — no expensive MaskFilter.blur)
    final pool = particlePool.pool;
    for (int i = 0; i < pool.length; i++) {
      final p = pool[i];
      if (!p.alive) continue;
      _particlePaint.color = p.color.withValues(alpha: p.opacity * 0.7);
      canvas.drawCircle(
        Offset(center.dx + p.x, center.dy + p.y),
        p.radius * p.opacity,
        _particlePaint,
      );
    }

    // Seed trails (simple strokes — no blur)
    for (final seed in seeds) {
      if (seed.trail.length < 2) continue;
      final trailList = seed.trail.toList(growable: false);
      for (int i = 1; i < trailList.length; i++) {
        final t = i / trailList.length;
        _trailPaint
          ..color = const Color(0xFFF7F3E9)
              .withValues(alpha: t * seed.opacity * 0.25)
          ..strokeWidth = t * 2.5;
        canvas.drawLine(
          Offset(center.dx + trailList[i - 1].dx,
              center.dy + trailList[i - 1].dy),
          Offset(
              center.dx + trailList[i].dx, center.dy + trailList[i].dy),
          _trailPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleTrailPainter oldDelegate) => false;
}
