import 'dart:math';
import 'dart:ui';

class StarNode {
  StarNode({
    required this.id,
    required this.position,
    required this.radius,
    required this.flickerPhase,
    this.bloomProgress = 0.0,
  });

  final int id;
  final Offset position;
  final double radius;
  final double flickerPhase;
  double bloomProgress;
}

class StarEdge {
  StarEdge({
    required this.fromStarId,
    required this.toStarId,
  });

  final int fromStarId;
  final int toStarId;
  double growthProgress = 0.0;
}

class ConstellationState {
  final List<StarNode> stars = [];
  final List<StarEdge> edges = [];
  int nextStarId = 0;
  int currentStarId = 0;

  StarNode get currentStar =>
      stars.firstWhere((s) => s.id == currentStarId);

  StarNode starById(int id) => stars.firstWhere((s) => s.id == id);

  Rect get boundingBox {
    if (stars.isEmpty) return Rect.zero;
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final s in stars) {
      if (s.position.dx < minX) minX = s.position.dx;
      if (s.position.dx > maxX) maxX = s.position.dx;
      if (s.position.dy < minY) minY = s.position.dy;
      if (s.position.dy > maxY) maxY = s.position.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

/// Creates 1-2 branches from the current star.
/// Returns the id of the randomly selected next start star.
/// [screenSize] and [cameraZoom] are used to ensure new stars stay on screen.
int createBranches({
  required ConstellationState state,
  required Random random,
  required double breathIntensity,
  required Size screenSize,
  required double cameraZoom,
}) {
  final current = state.currentStar;
  final branchCount = random.nextDouble() < 0.7 ? 1 : 2;

  // Calculate safe distance limits based on visible screen area
  // The current star sits at ~75% screen height (bottom 25%), so
  // upward space is larger than sideways space.
  final maxDx = screenSize.width / cameraZoom * 0.38;  // ~38% of visible width
  final maxDyUp = screenSize.height / cameraZoom * 0.30; // upward from current star
  final maxDyDown = screenSize.height / cameraZoom * 0.12; // downward (less space)

  // Collect existing edge angles from this star to avoid overlap
  final existingAngles = <double>[];
  for (final edge in state.edges) {
    if (edge.fromStarId == current.id) {
      final toStar = state.starById(edge.toStarId);
      existingAngles.add(atan2(
        toStar.position.dy - current.position.dy,
        toStar.position.dx - current.position.dx,
      ));
    }
  }

  final newStarIds = <int>[];
  for (int i = 0; i < branchCount; i++) {
    final angle = _pickAngle(existingAngles, random);
    existingAngles.add(angle);

    // Base distance (shorter for 2 branches)
    final distanceScale = branchCount == 2 ? 0.6 : 1.0;
    var distance = (80.0 + breathIntensity * 50.0 + random.nextDouble() * 40.0) * distanceScale;

    // Clamp distance so endpoint stays within visible screen bounds
    final dx = cos(angle) * distance;
    final dy = sin(angle) * distance;
    double scale = 1.0;
    if (dx.abs() > maxDx) {
      scale = min(scale, maxDx / dx.abs());
    }
    if (dy < 0 && dy.abs() > maxDyUp) {
      // Going upward (negative Y = up in world coords)
      scale = min(scale, maxDyUp / dy.abs());
    }
    if (dy > 0 && dy > maxDyDown) {
      scale = min(scale, maxDyDown / dy);
    }
    distance *= scale;

    final endpoint = Offset(
      current.position.dx + cos(angle) * distance,
      current.position.dy + sin(angle) * distance,
    );

    final newStar = StarNode(
      id: state.nextStarId++,
      position: endpoint,
      radius: 5.0 + random.nextDouble() * 3.0,
      flickerPhase: random.nextDouble() * pi * 2,
    );
    state.stars.add(newStar);
    state.edges.add(StarEdge(
      fromStarId: current.id,
      toStarId: newStar.id,
    ));
    newStarIds.add(newStar.id);
  }

  return newStarIds[random.nextInt(newStarIds.length)];
}

/// Pick an angle in the upper hemisphere, avoiding existing angles.
double _pickAngle(List<double> existing, Random random) {
  const minSeparation = 0.5; // ~29 degrees
  for (int attempt = 0; attempt < 20; attempt++) {
    // Range: roughly -170 to -10 degrees (upper hemisphere, going upward)
    final angle = -pi + random.nextDouble() * pi * 0.9 + 0.05 * pi;
    bool tooClose = false;
    for (final ea in existing) {
      if ((angle - ea).abs() < minSeparation) {
        tooClose = true;
        break;
      }
    }
    if (!tooClose) return angle;
  }
  // Fallback: random upward angle
  return -pi * 0.5 + (random.nextDouble() - 0.5) * pi * 0.8;
}

/// Random poetic constellation name generator.
String generateConstellationName(Random random) {
  const names = [
    '고요한 숨결자리',
    '잊혀진 새벽의 길',
    '먼 곳의 기억',
    '은은한 파문자리',
    '작은 항로',
    '새벽의 분기점',
    '밤의 나침반',
    '푸른 갈림길',
    '흩어진 빛의 자리',
    '조용한 여정',
    '바람이 머문 자리',
    '별빛 산책로',
    '숨결의 흔적',
    '하늘의 갈래길',
    '어둠 속 이정표',
    '고요한 물결자리',
    '빛나는 발자국',
    '밤하늘의 속삭임',
    '희미한 등대자리',
    '꿈길의 교차점',
    '은하의 실타래',
    '새벽빛 나뭇가지',
    '별이 쉬는 자리',
    '바람의 길목',
    '하늘 위 징검다리',
    '달빛 갈림길',
    '오늘의 별자리',
    '숨결이 닿은 곳',
    '빛의 여울자리',
    '고요한 은하수',
  ];
  return names[random.nextInt(names.length)];
}
