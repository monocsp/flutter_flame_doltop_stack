import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 무작위 위치에 별(파티클)을 그려주는 커스텀 페인터
class ParticleBackground extends StatefulWidget {
  const ParticleBackground({super.key});

  @override
  State<ParticleBackground> createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<ParticleBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final int _particleCount = 20;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    final random = math.Random();
    _particles = List.generate(
      _particleCount,
      (index) => _Particle(
        x: random.nextDouble(), // 0.0 ~ 1.0 (화면 비율)
        y: random.nextDouble(), // 0.0 ~ 1.0 (화면 비율)
        size: random.nextDouble() * 4 + 2, // 2 ~ 6
        opacityOffset: random.nextDouble() * 2 * math.pi, // 깜박임 타이밍 위상
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size.infinite,
          painter: _ParticlePainter(
            particles: _particles,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.opacityOffset,
  });

  final double x;
  final double y;
  final double size;
  final double opacityOffset; // 애니메이션 페이즈 시프트용
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.particles, required this.progress});

  final List<_Particle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;

    for (final particle in particles) {
      // 진행도(progress)와 파티클별 고유 오프셋을 결합하여 사인파 곡선으로 깜박임(반짝임) 효과 생성
      final alpha =
          (math.sin(progress * math.pi * 2 + particle.opacityOffset) + 1) / 2;
      paint.color = Colors.white.withValues(alpha: alpha * 0.8 + 0.1);

      final dx = particle.x * size.width;
      final dy = particle.y * size.height;

      // 십자가 무늬 별 모양 그리기 (야매)
      canvas.drawCircle(Offset(dx, dy), particle.size / 2, paint);

      // 약간의 길쭉한 빛 퍼짐 추가
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(dx, dy),
          width: particle.size * 2,
          height: particle.size / 3,
        ),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(dx, dy),
          width: particle.size / 3,
          height: particle.size * 2,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
