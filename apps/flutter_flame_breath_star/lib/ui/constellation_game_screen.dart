import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:noise_meter/noise_meter.dart';

import '../models/constellation.dart';
import 'result_screen.dart';

// ─────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────

const Color _kBackground = Color(0xFF09111F);
const Color _kAccent = Color(0xFF9EDCFF);
const Color _kLavender = Color(0xFFC7B6FF);
const Color _kGold = Color(0xFFFFDCA8);
const Color _kText = Color(0xFFF7F3E9);
const Color _kTextMuted = Color(0xFFAFC3D9);

// ─────────────────────────────────────────────
// Game phase enum
// ─────────────────────────────────────────────

enum _GamePhase { prepare, inhale, exhale, roundBreak }

// ─────────────────────────────────────────────
// Poolable particle
// ─────────────────────────────────────────────

class _GlowParticle {
  double x = 0;
  double y = 0;
  double vx = 0;
  double vy = 0;
  double radius = 0;
  double lifetime = 0;
  Color color = _kText;
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
    vy -= 6.0 * dt;
    vx *= 0.98;
    vy *= 0.98;
    if (age >= lifetime) alive = false;
  }
}

// ─────────────────────────────────────────────
// Particle pool
// ─────────────────────────────────────────────

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
    return null;
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
// Background star dust (fixed positions, slight parallax)
// ─────────────────────────────────────────────

class _BackgroundDot {
  final Offset position;
  final double radius;
  final double baseOpacity;
  final double parallaxFactor; // 0 = no parallax, 1 = full

  const _BackgroundDot({
    required this.position,
    required this.radius,
    required this.baseOpacity,
    required this.parallaxFactor,
  });
}

// ─────────────────────────────────────────────
// Repaint notifier
// ─────────────────────────────────────────────

class _GameRepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

// ─────────────────────────────────────────────
// Main game screen
// ─────────────────────────────────────────────

class ConstellationGameScreen extends StatefulWidget {
  const ConstellationGameScreen({super.key});

  @override
  State<ConstellationGameScreen> createState() =>
      _ConstellationGameScreenState();
}

class _ConstellationGameScreenState extends State<ConstellationGameScreen>
    with TickerProviderStateMixin {
  // ── Constants ──
  static const int _totalRounds = 3;
  static const double _ambientOffsetDb = 10.0;
  static const double _breathRangeDb = 18.0;
  static const double _fallbackThresholdDb = 52.0;
  static const double _maxExhaleSecs = 5.0;
  static const int _sustainedTicksRequired = 2;

  // ── Game state ──
  _GamePhase _phase = _GamePhase.prepare;
  int _round = 0;
  int _countdown = 3;
  double _exhaleElapsed = 0;
  bool _endingExhale = false;

  // ── Constellation ──
  final ConstellationState _constellation = ConstellationState();
  final Random _random = Random();
  List<StarEdge> _activeEdges = [];
  int _nextStartStarId = 0;

  // ── Camera ──
  Offset _cameraPosition = Offset.zero;
  Offset _cameraFrom = Offset.zero;
  Offset _cameraTo = Offset.zero;
  final double _cameraZoom = 1.8;
  late AnimationController _cameraAnimController;
  late Animation<double> _cameraCurve;

  // ── Background star dust ──
  late final List<_BackgroundDot> _bgDots;

  // ── Particles ──
  final _ParticlePool _particlePool = _ParticlePool();

  // ── Ticker ──
  late Ticker _ticker;
  Duration _lastTickElapsed = Duration.zero;

  // ── Repaint notifier ──
  final _GameRepaintNotifier _repaintNotifier = _GameRepaintNotifier();

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

  // ── Timers ──
  Timer? _countdownTimer;
  Timer? _breathPollTimer;

  // ── Elapsed time for twinkle animation ──
  double _elapsedTime = 0;

  @override
  void initState() {
    super.initState();

    // Generate background star dust
    _bgDots = List.generate(35, (i) {
      return _BackgroundDot(
        position: Offset(
          (_random.nextDouble() - 0.5) * 1200,
          (_random.nextDouble() - 0.5) * 1200,
        ),
        radius: 0.8 + _random.nextDouble() * 1.5,
        baseOpacity: 0.1 + _random.nextDouble() * 0.3,
        parallaxFactor: 0.15 + _random.nextDouble() * 0.35,
      );
    });

    // Create origin star
    final originStar = StarNode(
      id: _constellation.nextStarId++,
      position: Offset.zero,
      radius: 7.0,
      flickerPhase: _random.nextDouble() * pi * 2,
      bloomProgress: 1.0,
    );
    _constellation.stars.add(originStar);
    _constellation.currentStarId = originStar.id;
    _nextStartStarId = originStar.id;

    _cameraPosition = Offset.zero;
    _cameraFrom = Offset.zero;
    _cameraTo = Offset.zero;

    _cameraAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _cameraCurve = CurvedAnimation(
      parent: _cameraAnimController,
      curve: Curves.easeInOutCubic,
    );

    _ticker = createTicker(_onTick)..start();
    _startPreparePhase();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _countdownTimer?.cancel();
    _breathPollTimer?.cancel();
    _noDetectionTimer?.cancel();
    _noiseSubscription?.cancel();
    _repaintNotifier.dispose();
    _cameraAnimController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // World → Screen coordinate transform
  // ─────────────────────────────────────────────

  Offset worldToScreen(Offset worldPos, Size screenSize) {
    final cameraWorldCenter = Offset(
      _cameraPosition.dx,
      _cameraPosition.dy - screenSize.height * 0.25 / _cameraZoom,
    );
    return Offset(
      (worldPos.dx - cameraWorldCenter.dx) * _cameraZoom + screenSize.width / 2,
      (worldPos.dy - cameraWorldCenter.dy) * _cameraZoom +
          screenSize.height / 2,
    );
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

    // ── Camera interpolation (AnimationController-driven) ──
    if (_cameraAnimController.isAnimating) {
      _cameraPosition = Offset.lerp(
        _cameraFrom,
        _cameraTo,
        _cameraCurve.value,
      )!;
    }

    // ── Star bloom animation (only for stars with bloomProgress > 0) ──
    for (final star in _constellation.stars) {
      if (star.bloomProgress > 0 && star.bloomProgress < 1.0) {
        star.bloomProgress = (star.bloomProgress + 1.5 * dt).clamp(0.0, 1.0);
      }
    }

    // ── Edge growth during exhale (logarithmic deceleration) ──
    if (_phase == _GamePhase.exhale && !_endingExhale && _breathActive) {
      bool anyCompleted = false;
      for (final edge in _activeEdges) {
        if (edge.growthProgress < 1.0) {
          // Logarithmic slowdown: speed = base * (1 - progress^1.5)
          // Fast at start, decelerates toward the end
          final remaining = 1.0 - edge.growthProgress;
          final speedFactor = remaining.clamp(0.15, 1.0); // min 15% speed
          edge.growthProgress =
              (edge.growthProgress + _breathLevel * 1.2 * speedFactor * dt)
                  .clamp(0.0, 1.0);

          // When line reaches endpoint, trigger star bloom
          if (edge.growthProgress >= 1.0) {
            final toStar = _constellation.starById(edge.toStarId);
            if (toStar.bloomProgress <= 0) {
              toStar.bloomProgress = 0.01;
            }
            anyCompleted = true;
          }
        }
      }

      // ── Chain branching: when all active edges complete, spawn new ones ──
      if (anyCompleted && _activeEdges.every((e) => e.growthProgress >= 1.0)) {
        _chainBranch();
      }
    }

    // ── Spawn sparkle particles for blooming stars (stage 3: 0.45-0.8) ──
    for (final star in _constellation.stars) {
      if (star.bloomProgress > 0.45 && star.bloomProgress < 0.8) {
        if (_random.nextDouble() < 0.4) {
          final p = _particlePool.acquire();
          if (p != null) {
            final angle = _random.nextDouble() * pi * 2;
            final speed = 15.0 + _random.nextDouble() * 25.0;
            p.reset(
              x: star.position.dx,
              y: star.position.dy,
              vx: cos(angle) * speed,
              vy: sin(angle) * speed,
              radius: 1.0 + _random.nextDouble() * 2.0,
              lifetime: 0.4 + _random.nextDouble() * 0.5,
              color: _random.nextBool() ? _kGold : _kAccent,
            );
          }
        }
      }
    }

    // ── Spawn particles at edge growth tips ──
    if (_phase == _GamePhase.exhale && _breathActive) {
      for (final edge in _activeEdges) {
        if (edge.growthProgress > 0 && edge.growthProgress < 1.0) {
          if (_random.nextDouble() < 0.35) {
            final from = _constellation.starById(edge.fromStarId);
            final to = _constellation.starById(edge.toStarId);
            final tip = Offset.lerp(
                from.position, to.position, edge.growthProgress)!;
            final p = _particlePool.acquire();
            if (p != null) {
              p.reset(
                x: tip.dx,
                y: tip.dy,
                vx: (_random.nextDouble() - 0.5) * 18,
                vy: (_random.nextDouble() - 0.5) * 18,
                radius: 1.2 + _random.nextDouble() * 1.8,
                lifetime: 0.3 + _random.nextDouble() * 0.4,
                color: _kGold,
              );
            }
          }
        }
      }
    }

    // ── Update particles ──
    _particlePool.updateAll(dt);

    // ── Exhale timer ──
    if (_phase == _GamePhase.exhale && !_endingExhale) {
      _exhaleElapsed += dt;
      if (_exhaleElapsed >= _maxExhaleSecs) {
        _endingExhale = true;
        _endExhale();
      }
    }

    // Notify painter
    _repaintNotifier.notify();

    // setState for UI overlays + camera position updates to painter
    if (_phase == _GamePhase.exhale ||
        _phase == _GamePhase.roundBreak ||
        _cameraAnimController.isAnimating) {
      setState(() {});
    }
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

    // Start ambient calibration
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

  bool _branchesCreatedThisRound = false;

  void _startExhalePhase() {
    if (!mounted) return;

    // Don't create branches yet — wait for first breath detection
    _constellation.currentStarId = _nextStartStarId;
    _activeEdges = [];
    _branchesCreatedThisRound = false;

    setState(() {
      _phase = _GamePhase.exhale;
      _exhaleElapsed = 0;
      _endingExhale = false;
      _consecutiveAboveTicks = 0;
      _breathActive = false;
      _breathLevel = 0;
      _showNoDetectionHint = false;
      _everDetectedThisRound = false;
    });

    _startNoiseListening();
    _startBreathPolling();
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
          _currentDb =
              reading.maxDecibel.isFinite ? reading.maxDecibel : 0.0;
          _breathLevel =
              ((_currentDb - _dynamicThreshold) / _breathRangeDb)
                  .clamp(0.0, 1.0);
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
  // Breath polling with sustained detection
  // ─────────────────────────────────────────────

  void _startBreathPolling() {
    _breathPollTimer?.cancel();
    _breathPollTimer =
        Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _phase != _GamePhase.exhale) return;

      final normalized =
          ((_currentDb - _dynamicThreshold) / _breathRangeDb).clamp(0.0, 1.0);

      if (normalized <= 0) {
        _consecutiveAboveTicks = 0;
        _breathActive = false;
        return;
      }

      _consecutiveAboveTicks++;
      if (_consecutiveAboveTicks < _sustainedTicksRequired) return;
      _breathActive = true;

      // Create branches on first breath detection
      if (!_branchesCreatedThisRound) {
        _branchesCreatedThisRound = true;
        final screenSize = MediaQuery.of(context).size;
        final nextId = createBranches(
          state: _constellation,
          random: _random,
          breathIntensity: _breathLevel,
          screenSize: screenSize,
          cameraZoom: _cameraZoom,
        );
        _nextStartStarId = nextId;
        _activeEdges = _constellation.edges
            .where((e) => e.growthProgress == 0.0)
            .toList();
      }

      if (!_everDetectedThisRound) {
        _everDetectedThisRound = true;
        _noDetectionTimer?.cancel();
        if (_showNoDetectionHint) {
          setState(() => _showNoDetectionHint = false);
        }
      }
    });
  }

  /// Chain branching: when active edges complete during exhale,
  /// pick a random completed endpoint and spawn new branches from it.
  void _chainBranch() {
    // Find the last completed edge's endpoint
    final completedEndpoints = _activeEdges
        .where((e) => e.growthProgress >= 1.0)
        .map((e) => e.toStarId)
        .toList();
    if (completedEndpoints.isEmpty) return;

    // Pick random endpoint as next branch origin
    final nextOriginId =
        completedEndpoints[_random.nextInt(completedEndpoints.length)];
    _constellation.currentStarId = nextOriginId;

    // Create new branch(es) from that star
    final nextId = createBranches(
      state: _constellation,
      random: _random,
      breathIntensity: _breathLevel,
      screenSize: MediaQuery.of(context).size,
      cameraZoom: _cameraZoom,
    );
    _nextStartStarId = nextId;

    // Collect newly created edges
    _activeEdges = _constellation.edges
        .where((e) => e.growthProgress == 0.0)
        .toList();
  }

  void _endExhale() {
    _noiseSubscription?.cancel();
    _noiseSubscription = null;
    _breathPollTimer?.cancel();
    _breathPollTimer = null;
    _noDetectionTimer?.cancel();

    // Finalize edges at their CURRENT progress position (not snapped to 1.0)
    const minProgress = 0.15;
    final edgesToRemove = <StarEdge>[];
    for (final edge in _activeEdges) {
      if (edge.growthProgress >= minProgress) {
        // Move the endpoint star to where the line actually reached
        final fromStar = _constellation.starById(edge.fromStarId);
        final toStar = _constellation.starById(edge.toStarId);
        final actualPos = Offset.lerp(
          fromStar.position,
          toStar.position,
          edge.growthProgress,
        )!;
        toStar.position = actualPos;
        edge.growthProgress = 1.0;
        if (toStar.bloomProgress <= 0) {
          toStar.bloomProgress = 0.01;
        }
      } else {
        edgesToRemove.add(edge);
      }
    }
    for (final edge in edgesToRemove) {
      _constellation.edges.remove(edge);
      _constellation.stars.removeWhere((s) => s.id == edge.toStarId);
    }
    _activeEdges = [];

    // If next start star was removed, fall back to current star
    final hasNextStar =
        _constellation.stars.any((s) => s.id == _nextStartStarId);
    if (!hasNextStar) {
      _nextStartStarId = _constellation.currentStarId;
    }

    // Animate camera to the next start star
    final nextStar = _constellation.starById(_nextStartStarId);
    _cameraFrom = _cameraPosition;
    _cameraTo = nextStar.position;
    _cameraAnimController.forward(from: 0);

    setState(() {
      _phase = _GamePhase.roundBreak;
      _breathLevel = 0;
      _showNoDetectionHint = false;
    });

    _round++;

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      if (_round >= _totalRounds) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                ResultScreen(constellation: _constellation),
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
      backgroundColor: _kBackground,
      body: Stack(
        children: [
          // Constellation painter: hidden only during first round prepare/inhale
          if (!(_round == 0 && (_phase == _GamePhase.prepare || _phase == _GamePhase.inhale)))
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _ConstellationPainter(
                    constellation: _constellation,
                    activeEdges: _activeEdges,
                    particlePool: _particlePool,
                    bgDots: _bgDots,
                    cameraPosition: _cameraPosition,
                    cameraZoom: _cameraZoom,
                    elapsedTime: _elapsedTime,
                    breathActive: _breathActive,
                    breathLevel: _breathLevel,
                    repaintNotifier: _repaintNotifier,
                  ),
                ),
              ),
          ),
          // UI overlay
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
          color: _kGold,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildBreathIndicator() {
    final level = _breathLevel.clamp(0.0, 1.0);
    final isActive = _breathActive;
    const baseSize = 52.0;
    final pulseSize = baseSize + level * 24.0;
    final glowOpacity = isActive ? 0.15 + level * 0.25 : 0.06;
    final iconColor = isActive
        ? Color.lerp(_kAccent, _kText, level)!
        : _kTextMuted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: pulseSize,
          height: pulseSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kAccent.withValues(alpha: glowOpacity),
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
            color: isActive ? _kAccent : Colors.white.withValues(alpha: 0.35),
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
                  color: _kAccent.withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  '$_countdown',
                  style: const TextStyle(
                    color: _kText,
                    fontSize: 70,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 36),
            Text(
              _round == 0
                  ? '입을 마이크에\n가까이 대세요'
                  : '다음 별을\n이어볼까요?',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _kText,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _round == 0 ? '별빛을 이을 준비를 해요' : '별빛이 기다리고 있어요',
              style: TextStyle(
                color: _kTextMuted.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            if (_round == 0) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: _kAccent,
                size: 36,
              ),
            ),
            ],
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
                color: _kText,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$_countdown',
              style: const TextStyle(
                color: _kGold,
                fontSize: 56,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '별빛을 모으고 있어요...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 36),
            // Pulsing star icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kAccent.withValues(alpha: 0.08),
                border: Border.all(
                  color: _kAccent.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: _kGold,
                size: 36,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExhalePhase() {
    return Stack(
      children: [
        // UI overlay — fades out when breath is detected
        AnimatedOpacity(
          opacity: _breathActive ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 400),
          child: SafeArea(
            child: Column(
            children: [
              const SizedBox(height: 28),
              _buildRoundBadge(),
              const SizedBox(height: 18),
              const Text(
                '내쉬세요',
                style: TextStyle(
                  color: _kText,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 52),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (_exhaleElapsed / _maxExhaleSecs).clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(_kAccent),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildBreathIndicator(),
              const SizedBox(height: 16),
              AnimatedOpacity(
                opacity: _showNoDetectionHint ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 600),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: _kGold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _kGold.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: _kGold,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          '혹시 마이크에서 떨어져있거나,\n막혀있지 않나요?',
                          style: TextStyle(
                            color: _kGold,
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
                  '별의 길이 이어지고 있어요',
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
                color: _kAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLast ? Icons.check_rounded : Icons.auto_awesome,
                color: _kAccent,
                size: 36,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isLast ? '완료!' : '잘했어요!',
              style: const TextStyle(
                color: _kText,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '새로운 별이 태어났어요',
              style: TextStyle(
                color: _kLavender.withValues(alpha: 0.8),
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
// Single CustomPainter: renders everything
// ─────────────────────────────────────────────

class _ConstellationPainter extends CustomPainter {
  _ConstellationPainter({
    required this.constellation,
    required this.activeEdges,
    required this.particlePool,
    required this.bgDots,
    required this.cameraPosition,
    required this.cameraZoom,
    required this.elapsedTime,
    required this.breathActive,
    required this.breathLevel,
    required _GameRepaintNotifier repaintNotifier,
  }) : super(repaint: repaintNotifier);

  final ConstellationState constellation;
  final List<StarEdge> activeEdges;
  final _ParticlePool particlePool;
  final List<_BackgroundDot> bgDots;
  final Offset cameraPosition;
  final double cameraZoom;
  final double elapsedTime;
  final bool breathActive;
  final double breathLevel;

  // Reusable paint objects
  static final Paint _bgDotPaint = Paint();
  static final Paint _edgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Paint _starPaint = Paint();
  static final Paint _glowPaint = Paint();
  static final Paint _particlePaint = Paint();

  Offset _worldToScreen(Offset worldPos, Size size) {
    final cameraWorldCenter = Offset(
      cameraPosition.dx,
      cameraPosition.dy - size.height * 0.25 / cameraZoom,
    );
    return Offset(
      (worldPos.dx - cameraWorldCenter.dx) * cameraZoom + size.width / 2,
      (worldPos.dy - cameraWorldCenter.dy) * cameraZoom + size.height / 2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _kBackground,
    );

    // 2. Background star dust (parallax)
    for (final dot in bgDots) {
      final parallaxOffset = Offset(
        cameraPosition.dx * dot.parallaxFactor,
        cameraPosition.dy * dot.parallaxFactor,
      );
      final screenPos = _worldToScreen(
        dot.position + parallaxOffset,
        size,
      );
      // Only draw if on screen (with margin)
      if (screenPos.dx < -20 ||
          screenPos.dx > size.width + 20 ||
          screenPos.dy < -20 ||
          screenPos.dy > size.height + 20) {
        continue;
      }
      // Very slow twinkle to avoid flickering with countdown
      final twinkle =
          0.7 + 0.3 * sin(elapsedTime * 0.4 + dot.position.dx * 0.1);
      _bgDotPaint.color = Colors.white
          .withValues(alpha: dot.baseOpacity * twinkle);
      canvas.drawCircle(screenPos, dot.radius * cameraZoom * 0.5, _bgDotPaint);
    }

    // 3. Edges (shorten lines so they don't overlap star centers)
    for (final edge in constellation.edges) {
      if (edge.growthProgress <= 0) continue;

      final fromStar = constellation.starById(edge.fromStarId);
      final toStar = constellation.starById(edge.toStarId);
      final fromScreen = _worldToScreen(fromStar.position, size);

      final isActive = activeEdges.contains(edge);

      if (edge.growthProgress >= 1.0 && !isActive) {
        // Fully completed edge — shorten both ends to avoid overlapping stars
        final toScreen = _worldToScreen(toStar.position, size);
        final dir = toScreen - fromScreen;
        final len = dir.distance;
        if (len > 1) {
          final norm = dir / len;
          final fromInset = fromStar.radius * cameraZoom * 1.2;
          final toInset = toStar.radius * cameraZoom * 1.2;
          final p1 = fromScreen + norm * fromInset;
          final p2 = toScreen - norm * toInset;
          _edgePaint
            ..color = _kAccent.withValues(alpha: 0.6)
            ..strokeWidth = 1.5 * cameraZoom;
          canvas.drawLine(p1, p2, _edgePaint);
        }
      } else {
        // Growing edge
        final tip = Offset.lerp(fromStar.position, toStar.position,
            edge.growthProgress.clamp(0.0, 1.0))!;
        final tipScreen = _worldToScreen(tip, size);

        // Shorten from start star
        final dir = tipScreen - fromScreen;
        final len = dir.distance;
        Offset lineStart = fromScreen;
        if (len > 1) {
          final norm = dir / len;
          lineStart = fromScreen + norm * (fromStar.radius * cameraZoom * 1.2);
        }

        _edgePaint
          ..color = _kAccent.withValues(alpha: 0.5)
          ..strokeWidth = 1.5 * cameraZoom;
        canvas.drawLine(lineStart, tipScreen, _edgePaint);

        // Glow circle at tip
        final tipGlowRadius = 4.0 * cameraZoom;
        _glowPaint.shader = ui.Gradient.radial(
            tipScreen,
            tipGlowRadius * 3,
            [
              _kGold.withValues(alpha: 0.5),
              _kGold.withValues(alpha: 0.0),
            ],
          );
        canvas.drawCircle(tipScreen, tipGlowRadius * 3, _glowPaint);
        _glowPaint.shader = null;

        _starPaint.color = _kGold;
        canvas.drawCircle(tipScreen, tipGlowRadius * 0.5, _starPaint);
      }
    }

    // 4. Stars (4-stage bloom rendering)
    for (final star in constellation.stars) {
      final screenPos = _worldToScreen(star.position, size);
      final bloom = star.bloomProgress;
      final baseRadius = star.radius * cameraZoom;

      if (bloom <= 0) continue;

      if (bloom < 0.15) {
        // Stage 1: dark tiny dot
        _starPaint.color = _kTextMuted.withValues(alpha: 0.4);
        canvas.drawCircle(screenPos, 2.0 * cameraZoom, _starPaint);
      } else if (bloom < 0.45) {
        // Stage 2: flicker (radius/opacity oscillation)
        final flickerT = (bloom - 0.15) / 0.3;
        final flicker =
            0.5 + 0.5 * sin(elapsedTime * 12.0 + star.flickerPhase);
        final radius = (2.0 + flickerT * (baseRadius - 2.0)) * cameraZoom *
            (0.7 + 0.3 * flicker);
        final opacity = 0.4 + flickerT * 0.4 + flicker * 0.2;
        _starPaint.color = _kAccent.withValues(alpha: opacity.clamp(0.0, 1.0));
        canvas.drawCircle(screenPos, radius / cameraZoom, _starPaint);
      } else if (bloom < 0.8) {
        // Stage 3: bloom expansion + sparkle
        final expandT = (bloom - 0.45) / 0.35;
        final radius = baseRadius * (0.6 + expandT * 0.4);

        // Outer glow
        _glowPaint.shader = ui.Gradient.radial(
            screenPos,
            radius * 3.5,
            [
              _kAccent.withValues(alpha: 0.2 * expandT),
              _kAccent.withValues(alpha: 0.0),
            ],
          );
        canvas.drawCircle(screenPos, radius * 3.5, _glowPaint);
        _glowPaint.shader = null;

        // Core
        _starPaint.color = _kText.withValues(alpha: 0.7 + expandT * 0.3);
        canvas.drawCircle(screenPos, radius, _starPaint);
      } else {
        // Stage 4: stable + gentle twinkle
        final twinkle =
            0.85 + 0.15 * sin(elapsedTime * 2.0 + star.flickerPhase);

        // Outer glow
        _glowPaint.shader = ui.Gradient.radial(
            screenPos,
            baseRadius * 3.5,
            [
              _kAccent.withValues(alpha: 0.12 * twinkle),
              _kAccent.withValues(alpha: 0.0),
            ],
          );
        canvas.drawCircle(screenPos, baseRadius * 3.5, _glowPaint);
        _glowPaint.shader = null;

        // Core
        _starPaint.color = _kText.withValues(alpha: twinkle);
        canvas.drawCircle(screenPos, baseRadius, _starPaint);
      }
    }

    // 5. Particles from pool
    final pool = particlePool.pool;
    for (int i = 0; i < pool.length; i++) {
      final p = pool[i];
      if (!p.alive) continue;
      final screenPos = _worldToScreen(Offset(p.x, p.y), size);
      _particlePaint.color = p.color.withValues(alpha: p.opacity * 0.7);
      canvas.drawCircle(
        screenPos,
        p.radius * p.opacity * cameraZoom * 0.6,
        _particlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConstellationPainter oldDelegate) => false;
}
