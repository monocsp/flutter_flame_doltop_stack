import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:blow_away_worry/services/mic_service.dart';
import 'package:blow_away_worry/utils/note_colors.dart';
import 'package:blow_away_worry/widgets/color_picker.dart';
import 'package:blow_away_worry/widgets/mic_button.dart';
import 'package:blow_away_worry/widgets/particle_effect.dart';
import 'package:blow_away_worry/widgets/sticky_note.dart';
import 'package:blow_away_worry/widgets/wind_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

// ---------------------------------------------------------------------------
// Game phases
// ---------------------------------------------------------------------------
enum _Phase { idle, calibrating, blowing, flownAway, done }

// ---------------------------------------------------------------------------
// BlowScreen
// ---------------------------------------------------------------------------
class BlowScreen extends StatefulWidget {
  const BlowScreen({super.key});

  @override
  State<BlowScreen> createState() => _BlowScreenState();
}

class _BlowScreenState extends State<BlowScreen> with TickerProviderStateMixin {
  static const double _flyAwayThreshold = 3.8;
  static const double _blowThreshold = 0.12;
  static const double _calibrationSeconds = 2.5;

  final TextEditingController _textController = TextEditingController();
  final MicService _micService = MicService();
  final math.Random _random = math.Random();
  final List<NoteParticle> _particles = <NoteParticle>[];

  StreamSubscription<double>? _blowSubscription;
  late final Ticker _ticker;

  Duration? _lastElapsed;

  // --- ValueNotifiers (no more per-frame setState) ---
  final ValueNotifier<_Phase> _phase = ValueNotifier<_Phase>(_Phase.idle);
  final ValueNotifier<int> _selectedColorIndex = ValueNotifier<int>(0);
  final ValueNotifier<bool> _permissionDenied = ValueNotifier<bool>(false);

  // Repaint notifier drives CustomPainters without widget rebuilds
  final _RepaintTrigger _repaint = _RepaintTrigger();

  double _targetBlowStrength = 0;
  double _blowStrength = 0;
  double _cumulativeBlow = 0;
  double _flickerPhase = 0;
  double _pulsePhase = 0;
  double _calibrationElapsed = 0;

  // Note transform values
  double _noteAngle = 0;
  double _jitterX = 0;
  double _jitterY = 0;
  double _tapeScaleY = 1;
  double _tapeOpacity = 0.82;
  double _shadowLift = 0.12;

  // Flight values
  double _flightX = 0;
  double _flightY = 0;
  double _flightAngle = 0;
  double _flightOpacity = 1;
  double _flightVelX = 0;
  double _flightVelY = 0;
  double _flightRotVel = 0;

  NoteColorOption get _selectedColor =>
      NoteColors.palette[_selectedColorIndex.value];

  double get _progress => (_cumulativeBlow / _flyAwayThreshold).clamp(0.0, 1.0);

  bool get _isBlowing =>
      _phase.value == _Phase.blowing && _blowStrength >= _blowThreshold;

  String get _statusMessage {
    if (_permissionDenied.value) {
      return '마이크 권한을 허용해 주세요';
    }
    switch (_phase.value) {
      case _Phase.idle:
        return '마이크를 켜고 시작해 보세요';
      case _Phase.calibrating:
        return '주변 소리를 측정하고 있어요...';
      case _Phase.blowing:
        if (_progress < 0.3) {
          return _isBlowing ? '바람이 느껴져요...' : '후~ 바람을 불어보세요';
        }
        if (_progress < 0.7) {
          return '포스트잇이 흔들리고 있어요!';
        }
        return '거의 떨어지려고 해요! 조금만 더!';
      case _Phase.flownAway:
      case _Phase.done:
        return '고민이 바람에 날아갔어요';
    }
  }

  // --- Lifecycle ---

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _blowSubscription?.cancel();
    _micService.dispose();
    _textController.dispose();
    _phase.dispose();
    _selectedColorIndex.dispose();
    _permissionDenied.dispose();
    _repaint.dispose();
    super.dispose();
  }

  // --- Mic control ---

  Future<void> _toggleMic() async {
    if (_phase.value == _Phase.calibrating || _phase.value == _Phase.blowing) {
      await _stopListening();
      _phase.value = _Phase.idle;
      return;
    }

    final bool granted = await _micService.start();
    if (!mounted) return;

    if (!granted) {
      _permissionDenied.value = true;
      _phase.value = _Phase.idle;
      _targetBlowStrength = 0;
      return;
    }

    _permissionDenied.value = false;

    // Start calibration
    _micService.startCalibration();
    _calibrationElapsed = 0;
    _phase.value = _Phase.calibrating;

    await _blowSubscription?.cancel();
    _blowSubscription = _micService.blowStrengthStream.listen((double value) {
      _targetBlowStrength = value;
    });
  }

  Future<void> _stopListening() async {
    await _blowSubscription?.cancel();
    _blowSubscription = null;
    await _micService.stop();
    _targetBlowStrength = 0;
  }

  Future<void> _resetExperience() async {
    await _stopListening();
    if (!mounted) return;
    _phase.value = _Phase.idle;
    _permissionDenied.value = false;
    _cumulativeBlow = 0;
    _blowStrength = 0;
    _flickerPhase = 0;
    _noteAngle = 0;
    _jitterX = 0;
    _jitterY = 0;
    _tapeScaleY = 1;
    _tapeOpacity = 0.82;
    _shadowLift = 0.12;
    _flightX = 0;
    _flightY = 0;
    _flightAngle = 0;
    _flightOpacity = 1;
    _flightVelX = 0;
    _flightVelY = 0;
    _flightRotVel = 0;
    _particles.clear();
    _textController.clear();
    _repaint.notify();
  }

  // --- Tick ---

  void _onTick(Duration elapsed) {
    final Duration previous = _lastElapsed ?? elapsed;
    _lastElapsed = elapsed;
    final double dt =
        ((elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond)
            .clamp(0.0, 0.05);
    if (dt <= 0 || !mounted) return;

    _pulsePhase += dt * 2.4;
    _blowStrength = lerpDouble(
            _blowStrength, _targetBlowStrength, (dt * 8).clamp(0.0, 1.0)) ??
        _targetBlowStrength;

    switch (_phase.value) {
      case _Phase.idle:
        break;
      case _Phase.calibrating:
        _calibrationElapsed += dt;
        if (_calibrationElapsed >= _calibrationSeconds) {
          _micService.finishCalibration();
          _phase.value = _Phase.blowing;
        }
      case _Phase.blowing:
        _updateAccumulation(dt);
        _updateNoteAnimation(dt);
      case _Phase.flownAway:
        _updateFlight(dt);
        if (_flightOpacity < 0.05) {
          _phase.value = _Phase.done;
          unawaited(_stopListening());
        }
      case _Phase.done:
        break;
    }

    _updateParticles(dt);
    _repaint.notify();
  }

  void _updateAccumulation(double dt) {
    if (_isBlowing) {
      _cumulativeBlow = math.min(
        _flyAwayThreshold,
        _cumulativeBlow + dt * _blowStrength * 2,
      );
    } else {
      _cumulativeBlow = math.max(0, _cumulativeBlow - dt * 0.6);
    }

    if (_cumulativeBlow >= _flyAwayThreshold) {
      _triggerFlyAway();
    }
  }

  void _updateNoteAnimation(double dt) {
    final double progress = _progress;
    final double phaseSpeed = _isBlowing ? 1 : 0.35;
    _flickerPhase += dt * (3 + progress * 12) * phaseSpeed;

    final double flickerAmp = progress * 0.15;
    _noteAngle = progress * 0.25 +
        math.sin(_flickerPhase) * flickerAmp +
        math.sin(_flickerPhase * 2.3) * flickerAmp * 0.4 +
        math.sin(_flickerPhase * 5.1) * flickerAmp * 0.15;
    _jitterX = math.sin(_flickerPhase * 3.7) * progress * 8;
    _jitterY = math.sin(_flickerPhase * 2.1) * progress * 4;
    _tapeScaleY = 1 + progress * 0.18;
    _tapeOpacity = 0.82 - progress * 0.34;
    _shadowLift = 0.12 + progress * 0.88;
  }

  void _triggerFlyAway() {
    _phase.value = _Phase.flownAway;
    _targetBlowStrength = 0;
    _blowStrength = 0;
    _flightVelX = 300 + _random.nextDouble() * 200;
    _flightVelY = -(200 + _random.nextDouble() * 150);
    _flightRotVel = 3 + _random.nextDouble() * 4;
    _spawnParticles();
  }

  void _updateFlight(double dt) {
    _flightVelY += 400 * dt;
    _flightVelX *= math.pow(0.99, dt * 60).toDouble();
    _flightX += _flightVelX * dt;
    _flightY += _flightVelY * dt;
    _flightAngle += _flightRotVel * dt;
    _flightOpacity = math.max(0, _flightOpacity - 0.5 * dt);
  }

  void _spawnParticles() {
    final Color color = _selectedColor.color;
    for (int i = 0; i < 20; i++) {
      final double speed = 80 + _random.nextDouble() * 180;
      final double angle = -math.pi + _random.nextDouble() * math.pi * 2;
      _particles.add(
        NoteParticle(
          position: Offset(
            (_random.nextDouble() - 0.5) * 60,
            (_random.nextDouble() - 0.5) * 40,
          ),
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          radius: 4 + _random.nextDouble() * 7,
          color: color,
          life: 1 + _random.nextDouble() * 0.8,
          gravity: 220 + _random.nextDouble() * 140,
        ),
      );
    }
  }

  void _updateParticles(double dt) {
    for (final NoteParticle particle in _particles) {
      particle.update(dt);
    }
    _particles.removeWhere((NoteParticle particle) => !particle.isAlive);
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool compact = constraints.maxHeight < 780;
              final double noteWidth = math.min(
                constraints.maxWidth * 0.72,
                compact ? 300 : 360,
              );
              final double noteHeight = compact ? 360 : 430;

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Column(
                  children: <Widget>[
                    // Title
                    Text(
                      '고민을 날려버려',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.caveat(
                        fontSize: compact ? 40 : 48,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<_Phase>(
                      valueListenable: _phase,
                      builder: (_, _Phase phase, _) {
                        final String subtitle = phase == _Phase.calibrating
                            ? '조용히 기다려 주세요...'
                            : '포스트잇에 고민을 적고, 후~ 불어서 날려버리세요';
                        return Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.74),
                              ),
                        );
                      },
                    ),
                    const SizedBox(height: 22),

                    // Central area
                    Expanded(
                      child: _buildCenterArea(noteWidth, noteHeight),
                    ),
                    const SizedBox(height: 16),

                    // Wind meter
                    _buildWindMeter(),
                    const SizedBox(height: 18),

                    // Mic button
                    _buildMicButton(),
                    const SizedBox(height: 12),

                    // Bottom hint
                    _buildBottomHint(),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCenterArea(double noteWidth, double noteHeight) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        // Background glow
        Positioned.fill(
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: _repaint,
              builder: (_, _) => CustomPaint(
                painter: _BreathGlowPainter(
                  blowStrength: _blowStrength,
                  phase: _phase.value,
                  color: _selectedColor.color,
                ),
              ),
            ),
          ),
        ),

        // Particles
        Positioned.fill(
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: _repaint,
              builder: (_, _) => ParticleEffect(particles: _particles),
            ),
          ),
        ),

        // Note + color picker
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: Center(
                child: ListenableBuilder(
                  listenable: Listenable.merge(<Listenable>[
                    _repaint,
                    _selectedColorIndex,
                  ]),
                  builder: (_, _) {
                    return Transform(
                      alignment: Alignment.topCenter,
                      transform: Matrix4.translationValues(
                        _jitterX + _flightX,
                        _jitterY + _flightY,
                        0,
                      )..rotateZ(_noteAngle + _flightAngle),
                      child: Opacity(
                        opacity: _flightOpacity,
                        child: StickyNote(
                          width: noteWidth,
                          height: noteHeight,
                          color: _selectedColor.color,
                          controller: _textController,
                          enabled: _phase.value == _Phase.idle ||
                              _phase.value == _Phase.calibrating ||
                              _phase.value == _Phase.blowing,
                          tapeOpacity: _tapeOpacity.clamp(0.3, 1.0),
                          tapeScaleY: _tapeScaleY,
                          shadowLift: _phase.value == _Phase.flownAway
                              ? 1
                              : _shadowLift,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            ValueListenableBuilder<int>(
              valueListenable: _selectedColorIndex,
              builder: (_, int index, _) {
                return ColorPicker(
                  options: NoteColors.palette,
                  selectedIndex: index,
                  onSelected: (int i) => _selectedColorIndex.value = i,
                );
              },
            ),
          ],
        ),

        // Done message
        ValueListenableBuilder<_Phase>(
          valueListenable: _phase,
          builder: (_, _Phase phase, _) {
            if (phase != _Phase.done) return const SizedBox.shrink();
            return _DoneMessage(onReset: _resetExperience);
          },
        ),
      ],
    );
  }

  Widget _buildWindMeter() {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_repaint, _phase]),
      builder: (_, _) => WindMeter(
        strength: _blowStrength,
        cumulativeProgress: _progress,
        statusMessage: _statusMessage,
      ),
    );
  }

  Widget _buildMicButton() {
    return ValueListenableBuilder<_Phase>(
      valueListenable: _phase,
      builder: (_, _Phase phase, _) {
        final bool active =
            phase == _Phase.calibrating || phase == _Phase.blowing;
        return ListenableBuilder(
          listenable: _repaint,
          builder: (_, _) {
            final double pulse =
                active ? (math.sin(_pulsePhase * 2) + 1) / 2 : 0;
            return MicButton(
              isActive: active,
              pulse: pulse,
              onTap: _toggleMic,
            );
          },
        );
      },
    );
  }

  Widget _buildBottomHint() {
    return ValueListenableBuilder<_Phase>(
      valueListenable: _phase,
      builder: (_, _Phase phase, _) {
        String text;
        switch (phase) {
          case _Phase.idle:
            text = '마이크 버튼을 눌러 시작';
          case _Phase.calibrating:
            text = '주변 소리 측정 중...';
          case _Phase.blowing:
            text = '후~ 불어보세요';
          case _Phase.flownAway:
          case _Phase.done:
            text = '';
        }
        return Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.88),
                fontWeight: FontWeight.w600,
              ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Repaint trigger — replaces per-frame setState
// ---------------------------------------------------------------------------
class _RepaintTrigger extends ChangeNotifier {
  void notify() => notifyListeners();
}

// ---------------------------------------------------------------------------
// Background glow painter — visual feedback when blowing
// ---------------------------------------------------------------------------
class _BreathGlowPainter extends CustomPainter {
  const _BreathGlowPainter({
    required this.blowStrength,
    required this.phase,
    required this.color,
  });

  final double blowStrength;
  final _Phase phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (phase != _Phase.blowing && phase != _Phase.flownAway) return;
    if (blowStrength < 0.05) return;

    final Offset center = Offset(size.width / 2, size.height * 0.55);
    final double maxRadius = size.longestSide * 0.6;
    final double radius = maxRadius * blowStrength.clamp(0.0, 1.0);
    final double opacity = (blowStrength * 0.35).clamp(0.0, 0.35);

    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          color.withValues(alpha: opacity),
          color.withValues(alpha: opacity * 0.3),
          color.withValues(alpha: 0),
        ],
        stops: const <double>[0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _BreathGlowPainter old) => true;
}

// ---------------------------------------------------------------------------
// Done message — fade-in animated completion card
// ---------------------------------------------------------------------------
class _DoneMessage extends StatefulWidget {
  const _DoneMessage({required this.onReset});
  final VoidCallback onReset;

  @override
  State<_DoneMessage> createState() => _DoneMessageState();
}

class _DoneMessageState extends State<_DoneMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF34343A).withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '고민이 바람에 날아갔어요',
                textAlign: TextAlign.center,
                style: GoogleFonts.caveat(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '한결 가벼워졌나요?',
                textAlign: TextAlign.center,
                style: textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '가볍게, 다시 시작해보세요',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.56),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: widget.onReset,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFE066),
                  foregroundColor: const Color(0xFF2A2A2E),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                ),
                child: const Text('새로운 고민 적기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
