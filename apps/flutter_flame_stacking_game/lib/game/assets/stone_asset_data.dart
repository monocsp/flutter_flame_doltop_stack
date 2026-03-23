import 'package:flame/extensions.dart';

enum StoneAssetType { png, svg }

/// 돌 에셋의 물리 및 렌더링에 필요한 통합 데이터 모델입니다.
class StoneAssetData {
  const StoneAssetData({
    required this.assetPath,
    required this.type,
    required this.aspectRatio,
    required this.densityMultiplier,
    this.collisionHint,
  });

  final String assetPath;
  final StoneAssetType type;
  final double aspectRatio;
  final double densityMultiplier;
  final List<Vector2>? collisionHint;

  bool get isSvg => type == StoneAssetType.svg;
}
