import 'dart:typed_data';

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:image/image.dart' as img;

import 'terrain_profile.dart';
import '../../utils/asset_path_resolver.dart';

/// 바닥 오버레이 이미지에서 상단 경계선을 추출해 월드 프로파일로 변환합니다.
class TerrainProfileExtractor {
  const TerrainProfileExtractor();

  Future<TerrainProfile?> extractTopSilhouetteFromAsset({
    required String assetPath,
    required double worldWidth,
    required double baseBottomY,
    int sampleStepPx = 8,
    int alphaThreshold = 10,
  }) async {
    final bytes = await _loadAssetBytes(assetPath);
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width < 2 || decoded.height < 2) {
      return null;
    }

    final step = sampleStepPx.clamp(1, decoded.width - 1);
    final points = <img.Point>[];

    for (var x = 0; x < decoded.width; x += step) {
      final y = _findFirstOpaqueY(
        image: decoded,
        x: x,
        alphaThreshold: alphaThreshold,
      );
      if (y != null) {
        points.add(img.Point(x, y));
      }
    }

    if (points.isEmpty || points.last.x != decoded.width - 1) {
      final x = decoded.width - 1;
      final y = _findFirstOpaqueY(
        image: decoded,
        x: x,
        alphaThreshold: alphaThreshold,
      );
      if (y != null) {
        points.add(img.Point(x, y));
      }
    }

    if (points.length < 2) return null;

    final worldHeight = worldWidth * (decoded.height / decoded.width);
    final overlayTopY = baseBottomY - worldHeight;
    final worldPoints = points
        .map(
          (p) => _imageToWorld(
            x: p.x.toDouble(),
            y: p.y.toDouble(),
            imageWidth: decoded.width.toDouble(),
            imageHeight: decoded.height.toDouble(),
            worldWidth: worldWidth,
            worldHeight: worldHeight,
            overlayTopY: overlayTopY,
          ),
        )
        .toList(growable: false);

    return TerrainProfile(
      worldPoints: worldPoints,
      worldWidth: worldWidth,
      baseBottomY: baseBottomY,
    );
  }

  Future<Uint8List> _loadAssetBytes(String path) async {
    return loadAssetBytes(path);
  }

  int? _findFirstOpaqueY({
    required img.Image image,
    required int x,
    required int alphaThreshold,
  }) {
    for (var y = 0; y < image.height; y++) {
      final pixel = image.getPixel(x, y);
      if (pixel.a * 255.0 >= alphaThreshold) {
        return y;
      }
    }
    return null;
  }

  Vector2 _imageToWorld({
    required double x,
    required double y,
    required double imageWidth,
    required double imageHeight,
    required double worldWidth,
    required double worldHeight,
    required double overlayTopY,
  }) {
    final nx = x / (imageWidth - 1);
    final ny = y / (imageHeight - 1);
    return Vector2(nx * worldWidth, overlayTopY + ny * worldHeight);
  }
}
