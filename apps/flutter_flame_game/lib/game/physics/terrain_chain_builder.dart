import 'package:flame_forge2d/flame_forge2d.dart';

/// 곡면 포인트를 물리 엔진에 적합한 폴리라인으로 정리합니다.
class TerrainChainBuilder {
  const TerrainChainBuilder();

  List<Vector2> sanitizePoints(
    List<Vector2> rawPoints, {
    double minSegmentLength = 0.22,
  }) {
    if (rawPoints.length < 2) return rawPoints;

    final result = <Vector2>[rawPoints.first.clone()];
    for (var i = 1; i < rawPoints.length; i++) {
      final p = rawPoints[i];
      if (p.distanceTo(result.last) >= minSegmentLength) {
        result.add(p.clone());
      }
    }

    if (result.length == 1 && rawPoints.length > 1) {
      result.add(rawPoints.last.clone());
    } else if (result.length > 1 &&
        result.last.distanceTo(rawPoints.last) > 1e-6) {
      result.add(rawPoints.last.clone());
    }

    return result;
  }
}
