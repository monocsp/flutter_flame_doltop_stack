import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:blow_away_worry/services/mic_service.dart';
import 'package:blow_away_worry/utils/note_colors.dart';
import 'package:blow_away_worry/widgets/blown_message.dart';
import 'package:blow_away_worry/widgets/color_picker.dart';
import 'package:blow_away_worry/widgets/mic_button.dart';
import 'package:blow_away_worry/widgets/particle_effect.dart';
import 'package:blow_away_worry/widgets/sticky_note.dart';
import 'package:blow_away_worry/widgets/wind_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';

class BlowScreen extends StatefulWidget {
  const BlowScreen({super.key});

  @override
  State<BlowScreen> createState() => _BlowScreenState();
}

class _BlowScreenState extends State<BlowScreen> with TickerProviderStateMixin {
  static const double _flyAwayThreshold = 3.8;
  static const double _blowThreshold = 0.12;

  final TextEditingController _textController = TextEditingController();
  final MicService _micService = MicService();
  final math.Random _random = math.Random();
  final List<NoteParticle> _particles = <NoteParticle>[];

  StreamSubscription<double>? _blowSubscription;
  late final Ticker _ticker;

  Duration? _lastElapsed;
  int _selectedColorIndex = 0;
  bool _micEnabled = false;
  bool _permissionDenied = false;
  bool _hasFlownAway = false;

  double _targetBlowStrength = 0;
  double _blowStrength = 0;
  double _cumulativeBlow = 0;
  double _flickerPhase = 0;
  double _pulsePhase = 0;

  double _noteAngle = 0;
  double _jitterX = 0;
  double _jitterY = 0;
  double _tapeScaleY = 1;
  double _tapeOpacity = 0.82;
  double _shadowLift = 0.12;

  double _flightX = 0;
  double _flightY = 0;
  double _flightAngle = 0;
  double _flightOpacity = 1;
  double _flightVelX = 0;
  double _flightVelY = 0;
  double _flightRotVel = 0;

  NoteColorOption get _selectedColor => NoteColors.palette[_selectedColorIndex];

  double get _progress => (_cumulativeBlow / _flyAwayThreshold).clamp(0.0, 1.0);

  bool get _isBlowing =>
      _micEnabled && _blowStrength >= _blowThreshold && !_hasFlownAway;

  String get _statusMessage {
    if (_permissionDenied) {
      return '마이크 권한을 허용해 주세요';
    }
    if (_hasFlownAway) {
      return '고민이 바람에 날아갔어요';
    }
    if (_progress < 0.3) {
      if (_isBlowing) {
        return '바람이 느껴져요...';
      }
      return _micEnabled ? '후~ 바람을 불어보세요' : '마이크를 켜고 시작해 보세요';
    }
    if (_progress < 0.7) {
      return '포스트잇이 흔들리고 있어요!';
    }
    return '거의 떨어지려고 해요! 조금만 더!';
  }

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
    super.dispose();
  }

  Future<void> _toggleMic() async {
    if (_micEnabled) {
      await _stopListening();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final bool granted = await _micService.start();
    if (!mounted) {
      return;
    }

    if (!granted) {
      setState(() {
        _permissionDenied = true;
        _micEnabled = false;
        _targetBlowStrength = 0;
      });
      return;
    }

    await _blowSubscription?.cancel();
    _blowSubscription = _micService.blowStrengthStream.listen((double value) {
      _targetBlowStrength = value;
    });

    setState(() {
      _permissionDenied = false;
      _micEnabled = true;
    });
  }

  Future<void> _stopListening() async {
    await _blowSubscription?.cancel();
    _blowSubscription = null;
    await _micService.stop();
    _micEnabled = false;
    _targetBlowStrength = 0;
  }

  Future<void> _resetExperience() async {
    await _stopListening();
    if (!mounted) {
      return;
    }
    setState(() {
      _permissionDenied = false;
      _hasFlownAway = false;
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
    });
  }

  void _onTick(Duration elapsed) {
    final Duration previous = _lastElapsed ?? elapsed;
    _lastElapsed = elapsed;
    final double dt =
        ((elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond)
            .clamp(0.0, 0.05);

    if (dt <= 0 || !mounted) {
      return;
    }

    _pulsePhase += dt * 2.4;
    _blowStrength =
        lerpDouble(
          _blowStrength,
          _targetBlowStrength,
          (dt * 8).clamp(0.0, 1.0),
        ) ??
        _targetBlowStrength;

    if (_hasFlownAway) {
      _updateFlight(dt);
    } else {
      _updateAccumulation(dt);
      _updateNoteAnimation(dt);
    }

    _updateParticles(dt);
    setState(() {});
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
    _noteAngle =
        progress * 0.25 +
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
    _hasFlownAway = true;
    _targetBlowStrength = 0;
    _blowStrength = 0;
    _flightVelX = 300 + _random.nextDouble() * 200;
    _flightVelY = -(200 + _random.nextDouble() * 150);
    _flightRotVel = 3 + _random.nextDouble() * 4;
    _spawnParticles();
    unawaited(_stopListening());
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

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final double pulse = _micEnabled ? (math.sin(_pulsePhase * 2) + 1) / 2 : 0;

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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                child: Column(
                  children: <Widget>[
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
                    Text(
                      '포스트잇에 고민을 적고, 후~ 불어서 날려버리세요',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.74),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: <Widget>[
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ParticleEffect(particles: _particles),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Flexible(
                                child: Center(
                                  child: Transform(
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
                                        enabled: !_hasFlownAway,
                                        tapeOpacity: _tapeOpacity.clamp(
                                          0.3,
                                          1.0,
                                        ),
                                        tapeScaleY: _tapeScaleY,
                                        shadowLift: _hasFlownAway
                                            ? 1
                                            : _shadowLift,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              ColorPicker(
                                options: NoteColors.palette,
                                selectedIndex: _selectedColorIndex,
                                onSelected: (int index) {
                                  setState(() {
                                    _selectedColorIndex = index;
                                  });
                                },
                              ),
                            ],
                          ),
                          if (_hasFlownAway && _flightOpacity < 0.28)
                            Align(
                              alignment: Alignment.center,
                              child: BlownMessage(onReset: _resetExperience),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    WindMeter(
                      strength: _blowStrength,
                      cumulativeProgress: _progress,
                      statusMessage: _statusMessage,
                    ),
                    const SizedBox(height: 18),
                    MicButton(
                      isActive: _micEnabled,
                      pulse: pulse,
                      onTap: _toggleMic,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _micEnabled ? '후~ 불어보세요' : '마이크 버튼을 눌러 시작',
                      style: textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
}
