import 'package:flame_forge2d/flame_forge2d.dart';

/// 이미지 곡면에서 추출된 월드 좌표 프로파일입니다.
class TerrainProfile {
  TerrainProfile({
    required this.worldPoints,
    required this.worldWidth,
    required this.baseBottomY,
  });

  final List<Vector2> worldPoints;
  final double worldWidth;
  final double baseBottomY;
}
