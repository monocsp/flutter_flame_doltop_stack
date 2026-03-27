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

enum _GamePhase { prepare, inhale, hold, exhale, roundBreak }

// ─────────────────────────────────────────────
// Mutable render state read by the painter
// ─────────────────────────────────────────────

class _GameRenderState {
  Offset cameraPosition = Offset.zero;
  double cameraZoom = 1.8;
  double elapsedTime = 0;
  bool breathActive = false;
  double breathLevel = 0;
  int nextStartStarId = 0;
  _GamePhase phase = _GamePhase.prepare;
}

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
  static const double _maxExhaleSecs = 8.0;
  static const int _holdSeconds = 7;
  static const double _defaultZoom = 1.8;
  static const int _sustainedTicksRequired = 2;

  // ── ValueNotifier-backed UI state ──
  final ValueNotifier<_GamePhase> _phase = ValueNotifier(_GamePhase.prepare);
  final ValueNotifier<int> _round = ValueNotifier(0);
  final ValueNotifier<int> _countdown = ValueNotifier<int>(3);
  final ValueNotifier<double> _exhaleElapsed = ValueNotifier(0);
  final ValueNotifier<double> _breathLevel = ValueNotifier(0.0);
  final ValueNotifier<bool> _breathActive = ValueNotifier(false);
  final ValueNotifier<bool> _showNoDetectionHint = ValueNotifier(false);

  // ── Internal logic state (plain fields) ──
  bool _endingExhale = false;

  // ── Constellation ──
  final ConstellationState _constellation = ConstellationState();
  final Random _random = Random();
  List<StarEdge> _activeEdges = [];
  int _nextStartStarId = 0;

  // ── Camera ──
  Offset _cameraFrom = Offset.zero;
  Offset _cameraTo = Offset.zero;
  late AnimationController _cameraAnimController;
  late Animation<double> _cameraCurve;

  // ── Render state (shared mutable object read by painter) ──
  final _GameRenderState _renderState = _GameRenderState();

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

  // ── No-detection hint ──
  Timer? _noDetectionTimer;
  bool _everDetectedThisRound = false;

  // ── Timers ──
  Timer? _countdownTimer;
  Timer? _breathPollTimer;

  // ── Branches created this round ──
  bool _branchesCreatedThisRound = false;

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

    _renderState.cameraPosition = Offset.zero;
    _renderState.nextStartStarId = _nextStartStarId;
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
    _countdown.dispose();
    _phase.dispose();
    _round.dispose();
    _exhaleElapsed.dispose();
    _breathLevel.dispose();
    _breathActive.dispose();
    _showNoDetectionHint.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // World → Screen coordinate transform
  // ─────────────────────────────────────────────

  Offset worldToScreen(Offset worldPos, Size screenSize) {
    final cameraWorldCenter = Offset(
      _renderState.cameraPosition.dx,
      _renderState.cameraPosition.dy - screenSize.height * 0.25 / _renderState.cameraZoom,
    );
    return Offset(
      (worldPos.dx - cameraWorldCenter.dx) * _renderState.cameraZoom + screenSize.width / 2,
      (worldPos.dy - cameraWorldCenter.dy) * _renderState.cameraZoom +
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

    _renderState.elapsedTime += dt;

    // ── Camera interpolation (AnimationController-driven) ──
    if (_cameraAnimController.isAnimating) {
      _renderState.cameraPosition = Offset.lerp(
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
    if (_phase.value == _GamePhase.exhale && !_endingExhale && _breathActive.value) {
      bool anyCompleted = false;
      for (final edge in _activeEdges) {
        if (edge.growthProgress < 1.0) {
          // Logarithmic slowdown: speed = base * (1 - progress^1.5)
          // Fast at start, decelerates toward the end
          final remaining = 1.0 - edge.growthProgress;
          final speedFactor = remaining.clamp(0.15, 1.0); // min 15% speed
          edge.growthProgress =
              (edge.growthProgress + _breathLevel.value * 1.2 * speedFactor * dt)
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
    if (_phase.value == _GamePhase.exhale && _breathActive.value) {
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
    if (_phase.value == _GamePhase.exhale && !_endingExhale) {
      _exhaleElapsed.value += dt;
      if (_exhaleElapsed.value >= _maxExhaleSecs) {
        _endingExhale = true;
        _endExhale();
      }
    }

    // ── Dynamic zoom: zoom out during exhale if lines approach screen edge ──
    if (_phase.value == _GamePhase.exhale && _activeEdges.isNotEmpty) {
      final screenSize = MediaQuery.of(context).size;
      double neededZoom = _defaultZoom;

      for (final edge in _activeEdges) {
        if (edge.growthProgress <= 0) continue;
        final fromStar = _constellation.starById(edge.fromStarId);
        final toStar = _constellation.starById(edge.toStarId);
        final tip = Offset.lerp(
            fromStar.position, toStar.position, edge.growthProgress)!;

        final dx = (tip.dx - _renderState.cameraPosition.dx).abs();
        final dy = (tip.dy - _renderState.cameraPosition.dy).abs();
        const margin = 60.0;
        if (dx > 1) {
          neededZoom = min(neededZoom, (screenSize.width / 2 - margin) / dx);
        }
        if (dy > 1) {
          neededZoom = min(neededZoom, (screenSize.height * 0.6 - margin) / dy);
        }
      }
      neededZoom = neededZoom.clamp(0.8, _defaultZoom);
      _renderState.cameraZoom += (neededZoom - _renderState.cameraZoom) * 3.0 * dt;
    } else {
      // Restore zoom when not in exhale
      _renderState.cameraZoom += (_defaultZoom - _renderState.cameraZoom) * 3.0 * dt;
    }

    // ── Sync render state for painter ──
    _renderState.breathActive = _breathActive.value;
    _renderState.breathLevel = _breathLevel.value;
    _renderState.nextStartStarId = _nextStartStarId;
    _renderState.phase = _phase.value;

    // Notify painter
    _repaintNotifier.notify();
  }

  // ─────────────────────────────────────────────
  // Phase transitions
  // ─────────────────────────────────────────────

  void _startPreparePhase() {
    if (!mounted) return;
    _countdown.value = 3;
    _endingExhale = false;
    _breathLevel.value = 0;
    _phase.value = _GamePhase.prepare;

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
    _countdown.value = 4; // 4-7-8: inhale 4 seconds
    _phase.value = _GamePhase.inhale;

    // Start ambient calibration
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
    // Finish calibration first
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

    // Start hold countdown (7 seconds)
    if (!mounted) return;
    _countdown.value = _holdSeconds;
    _phase.value = _GamePhase.hold;

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _countdown.value--;
      if (_countdown.value <= 0) {
        timer.cancel();
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

    // Don't create branches yet — wait for first breath detection
    _constellation.currentStarId = _nextStartStarId;
    _activeEdges = [];
    _branchesCreatedThisRound = false;

    _exhaleElapsed.value = 0;
    _endingExhale = false;
    _consecutiveAboveTicks = 0;
    _breathActive.value = false;
    _breathLevel.value = 0;
    _showNoDetectionHint.value = false;
    _everDetectedThisRound = false;
    _phase.value = _GamePhase.exhale;

    _startNoiseListening();
    _startBreathPolling();
    _startNoDetectionTimer();
  }

  void _startNoDetectionTimer() {
    _noDetectionTimer?.cancel();
    _noDetectionTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _phase.value == _GamePhase.exhale && !_everDetectedThisRound) {
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
  // Breath polling with sustained detection
  // ─────────────────────────────────────────────

  void _startBreathPolling() {
    _breathPollTimer?.cancel();
    _breathPollTimer =
        Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _phase.value != _GamePhase.exhale) return;

      final normalized =
          ((_currentDb - _dynamicThreshold) / _breathRangeDb).clamp(0.0, 1.0);

      if (normalized <= 0) {
        _consecutiveAboveTicks = 0;
        _breathActive.value = false;
        return;
      }

      _consecutiveAboveTicks++;
      if (_consecutiveAboveTicks < _sustainedTicksRequired) return;
      _breathActive.value = true;

      // Create branches on first breath detection
      if (!_branchesCreatedThisRound) {
        _branchesCreatedThisRound = true;
        final screenSize = MediaQuery.of(context).size;
        final nextId = createBranches(
          state: _constellation,
          random: _random,
          breathIntensity: _breathLevel.value,
          screenSize: screenSize,
          cameraZoom: _renderState.cameraZoom,
        );
        _nextStartStarId = nextId;
        _activeEdges = _constellation.edges
            .where((e) => e.growthProgress == 0.0)
            .toList();
      }

      if (!_everDetectedThisRound) {
        _everDetectedThisRound = true;
        _noDetectionTimer?.cancel();
        if (_showNoDetectionHint.value) {
          _showNoDetectionHint.value = false;
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
      breathIntensity: _breathLevel.value,
      screenSize: MediaQuery.of(context).size,
      cameraZoom: _renderState.cameraZoom,
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
    _cameraFrom = _renderState.cameraPosition;
    _cameraTo = nextStar.position;
    _cameraAnimController.forward(from: 0);

    _breathLevel.value = 0;
    _showNoDetectionHint.value = false;
    _phase.value = _GamePhase.roundBreak;

    _round.value++;

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      if (_round.value >= _totalRounds) {
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
          ListenableBuilder(
            listenable: Listenable.merge([_phase, _round]),
            builder: (context, _) {
              if (_round.value == 0 &&
                  (_phase.value == _GamePhase.prepare ||
                      _phase.value == _GamePhase.inhale)) {
                return const SizedBox.shrink();
              }
              return Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _ConstellationPainter(
                      constellation: _constellation,
                      activeEdges: _activeEdges,
                      particlePool: _particlePool,
                      bgDots: _bgDots,
                      renderState: _renderState,
                      repaintNotifier: _repaintNotifier,
                    ),
                  ),
                ),
              );
            },
          ),
          // UI overlay — phase switch
          ValueListenableBuilder<_GamePhase>(
            valueListenable: _phase,
            builder: (_, phase, _) => switch (phase) {
              _GamePhase.prepare => _buildPreparePhase(),
              _GamePhase.inhale => _buildInhalePhase(),
              _GamePhase.hold => _buildHoldPhase(),
              _GamePhase.exhale => _buildExhalePhase(),
              _GamePhase.roundBreak => _buildRoundBreak(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRoundBadge() {
    return ValueListenableBuilder<int>(
      valueListenable: _round,
      builder: (_, round, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          '${round + 1} / $_totalRounds',
          style: const TextStyle(
            color: _kGold,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildBreathIndicator() {
    return ListenableBuilder(
      listenable: Listenable.merge([_breathLevel, _breathActive]),
      builder: (context, _) {
        final level = _breathLevel.value.clamp(0.0, 1.0);
        final isActive = _breathActive.value;
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
                  color: _kAccent.withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
              child: Center(
                child: ValueListenableBuilder<int>(
                  valueListenable: _countdown,
                  builder: (_, value, _) => Text(
                    '$value',
                    style: const TextStyle(
                      color: _kText,
                      fontSize: 70,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 36),
            ValueListenableBuilder<int>(
              valueListenable: _round,
              builder: (_, round, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    round == 0
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
                    round == 0 ? '별빛을 이을 준비를 해요' : '별빛이 기다리고 있어요',
                    style: TextStyle(
                      color: _kTextMuted.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                  if (round == 0) ...[
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
            ValueListenableBuilder<int>(
              valueListenable: _countdown,
              builder: (_, value, _) => Text(
                '$value',
                style: const TextStyle(
                  color: _kGold,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                ),
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

  Widget _buildHoldPhase() {
    // Pulsing happens on the actual star in the painter, not here
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildRoundBadge(),
            const SizedBox(height: 32),
            const Text(
              '숨을 참으세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _kText,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ValueListenableBuilder<int>(
              valueListenable: _countdown,
              builder: (_, value, _) => Text(
                '$value',
                style: const TextStyle(
                  color: _kGold,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '별빛이 응축되고 있어요...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
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
        ValueListenableBuilder<bool>(
          valueListenable: _breathActive,
          builder: (_, breathActive, child) => AnimatedOpacity(
            opacity: breathActive ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 400),
            child: child!,
          ),
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
                  child: ValueListenableBuilder<double>(
                    valueListenable: _exhaleElapsed,
                    builder: (_, exhaleElapsed, _) => LinearProgressIndicator(
                      value: (exhaleElapsed / _maxExhaleSecs).clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(_kAccent),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildBreathIndicator(),
              const SizedBox(height: 16),
              ValueListenableBuilder<bool>(
                valueListenable: _showNoDetectionHint,
                builder: (_, showHint, child) => AnimatedOpacity(
                  opacity: showHint ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 600),
                  child: child!,
                ),
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
              _branchesCreatedThisRound
                  ? '새로운 별이 태어났어요'
                  : '다시 한번 해볼까요?',
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
    required this.renderState,
    required _GameRepaintNotifier repaintNotifier,
  }) : super(repaint: repaintNotifier);

  final ConstellationState constellation;
  final List<StarEdge> activeEdges;
  final _ParticlePool particlePool;
  final List<_BackgroundDot> bgDots;
  final _GameRenderState renderState;

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
      renderState.cameraPosition.dx,
      renderState.cameraPosition.dy - size.height * 0.25 / renderState.cameraZoom,
    );
    return Offset(
      (worldPos.dx - cameraWorldCenter.dx) * renderState.cameraZoom + size.width / 2,
      (worldPos.dy - cameraWorldCenter.dy) * renderState.cameraZoom + size.height / 2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cameraPosition = renderState.cameraPosition;
    final cameraZoom = renderState.cameraZoom;
    final elapsedTime = renderState.elapsedTime;
    final nextStartStarId = renderState.nextStartStarId;
    final phase = renderState.phase;

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

    // 3. Edges (drawn full length — stars are drawn on top and cover overlap)
    for (final edge in constellation.edges) {
      if (edge.growthProgress <= 0) continue;

      final fromStar = constellation.starById(edge.fromStarId);
      final toStar = constellation.starById(edge.toStarId);
      final fromScreen = _worldToScreen(fromStar.position, size);

      final isActive = activeEdges.contains(edge);

      if (edge.growthProgress >= 1.0 && !isActive) {
        final toScreen = _worldToScreen(toStar.position, size);
        _edgePaint
          ..color = _kAccent.withValues(alpha: 0.6)
          ..strokeWidth = 1.5 * cameraZoom;
        canvas.drawLine(fromScreen, toScreen, _edgePaint);
      } else {
        // Growing edge
        final tip = Offset.lerp(fromStar.position, toStar.position,
            edge.growthProgress.clamp(0.0, 1.0))!;
        final tipScreen = _worldToScreen(tip, size);

        _edgePaint
          ..color = _kAccent.withValues(alpha: 0.5)
          ..strokeWidth = 1.5 * cameraZoom;
        canvas.drawLine(fromScreen, tipScreen, _edgePaint);

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
        // Stage 4: stable star
        final isNextStart = star.id == nextStartStarId;
        final isHoldPulsing = isNextStart && phase == _GamePhase.hold;
        final isHighlighted = isNextStart &&
            (phase == _GamePhase.roundBreak ||
             phase == _GamePhase.prepare ||
             phase == _GamePhase.hold);

        final twinkle =
            0.85 + 0.15 * sin(elapsedTime * 2.0 + star.flickerPhase);

        // Hold phase: pulsing effect on the next start star
        final double pulseScale;
        final double pulseGlow;
        if (isHoldPulsing) {
          final pulse = 0.5 + 0.5 * sin(elapsedTime * 1.8);
          pulseScale = 1.0 + pulse * 0.4; // 1.0~1.4x
          pulseGlow = 0.2 + pulse * 0.3;
        } else {
          pulseScale = 1.0;
          pulseGlow = 0.12;
        }

        // Choose color: gold for highlighted, accent for normal
        final glowColor = isHighlighted ? _kGold : _kAccent;
        final coreColor = isHighlighted ? _kGold : _kText;

        // Outer glow
        _glowPaint.shader = ui.Gradient.radial(
            screenPos,
            baseRadius * 3.5 * pulseScale,
            [
              glowColor.withValues(alpha: pulseGlow * twinkle),
              glowColor.withValues(alpha: 0.0),
            ],
          );
        canvas.drawCircle(
            screenPos, baseRadius * 3.5 * pulseScale, _glowPaint);
        _glowPaint.shader = null;

        // Core
        _starPaint.color = coreColor.withValues(alpha: twinkle);
        canvas.drawCircle(screenPos, baseRadius * pulseScale, _starPaint);
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
