import 'package:flutter/material.dart';

class NoteParticle {
  NoteParticle({
    required this.position,
    required this.velocity,
    required this.radius,
    required this.color,
    required this.life,
    required this.gravity,
  }) : _remainingLife = life;

  Offset position;
  Offset velocity;
  final double radius;
  final Color color;
  final double life;
  final double gravity;
  double _remainingLife;

  double get opacity => (_remainingLife / life).clamp(0.0, 1.0);

  bool get isAlive => _remainingLife > 0;

  void update(double dt) {
    _remainingLife -= dt;
    velocity = Offset(velocity.dx, velocity.dy + gravity * dt);
    position = Offset(
      position.dx + velocity.dx * dt,
      position.dy + velocity.dy * dt,
    );
  }
}

class ParticleEffect extends StatelessWidget {
  const ParticleEffect({required this.particles, super.key});

  final List<NoteParticle> particles;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _ParticlePainter(particles: particles));
  }
}

class _ParticlePainter extends CustomPainter {
  const _ParticlePainter({required this.particles});

  final List<NoteParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);

    for (final NoteParticle particle in particles) {
      final Paint paint = Paint()
        ..color = particle.color.withValues(alpha: particle.opacity * 0.9);
      canvas.drawCircle(center + particle.position, particle.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
}
