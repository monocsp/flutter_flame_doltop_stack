import 'package:flame_forge2d/flame_forge2d.dart';

/// 스톤 이미지의 물리/렌더링 메타데이터입니다.
class StoneAssetData {
  const StoneAssetData({
    required this.assetPath,
    required this.aspectRatio,
    required this.densityMultiplier,
    this.collisionHint,
  });

  final String assetPath;
  final double aspectRatio;
  final double densityMultiplier;
  final List<Vector2>? collisionHint;
}
