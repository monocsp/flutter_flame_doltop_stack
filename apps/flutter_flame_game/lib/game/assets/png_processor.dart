import 'dart:math' as math;
import 'package:flame/extensions.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'stone_asset_data.dart';
import '../../utils/asset_path_resolver.dart';

/// PNG 이미지를 분석하여 충돌 힌트와 물리 메타데이터를 추출하는 클래스입니다.
class PngProcessor {
  static const bool _logEnabled = true;

  /// 여러 PNG 에셋들을 분석하여 StoneAssetData 맵을 반환합니다.
  Future<Map<String, StoneAssetData>> prepareAssets(List<String> assetPaths) async {
    final metadataMap = <String, StoneAssetData>{};
    final rawMassByAsset = <String, double>{};
    final tempHints = <String, List<Vector2>>{};
    final tempAspects = <String, double>{};

    for (final assetPath in assetPaths) {
      if (!assetPath.toLowerCase().endsWith('.png')) continue;
      
      try {
        final bytes = await loadAssetBytes(assetPath);
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        
        final aspect = decoded.width / decoded.height;
        final pixelArea = (decoded.width * decoded.height).toDouble();
        rawMassByAsset[assetPath] = pixelArea;
        tempAspects[assetPath] = aspect;
        
        final hint = _buildCollisionHintFromDecoded(decoded);
        if (hint != null && hint.length >= 3) {
          tempHints[assetPath] = hint;
        }
      } catch (e) {
        if (_logEnabled) {
          debugPrint('[PngProcessor] Error processing $assetPath: $e');
        }
      }
    }

    if (rawMassByAsset.isEmpty) return metadataMap;
    
    final meanArea = rawMassByAsset.values.reduce((a, b) => a + b) / rawMassByAsset.length;
    
    for (final assetPath in assetPaths) {
      if (!tempAspects.containsKey(assetPath)) continue;
      
      final area = rawMassByAsset[assetPath]!;
      final normalized = (area / meanArea).clamp(0.5, 2.6);
      final emphasized = math.pow(normalized, 1.25).toDouble();
      final densityMultiplier = emphasized.clamp(0.75, 1.9);
      
      metadataMap[assetPath] = StoneAssetData(
        assetPath: assetPath,
        type: StoneAssetType.png,
        aspectRatio: tempAspects[assetPath]!,
        densityMultiplier: densityMultiplier,
        collisionHint: tempHints[assetPath],
      );
    }
    
    return metadataMap;
  }

  /// 이미지 알파 픽셀에서 정규화된 볼록 껍질 형태 힌트를 추출합니다.
  List<Vector2>? _buildCollisionHintFromDecoded(img.Image decoded) {
    final opaque = <Vector2>[];
    for (var y = 0; y < decoded.height; y += 2) {
      for (var x = 0; x < decoded.width; x += 2) {
        final p = decoded.getPixel(x, y);
        if (p.a.toInt() > 20) {
          opaque.add(Vector2(x.toDouble(), y.toDouble()));
        }
      }
    }
    if (opaque.length < 12) return null;

    final center = _centroid(opaque);
    final support = <Vector2>[];
    const supportCount = 8;
    for (var i = 0; i < supportCount; i++) {
      final angle = i * (2 * math.pi / supportCount);
      final dir = Vector2(math.cos(angle), math.sin(angle));
      var best = opaque.first;
      var bestDot = (best - center).dot(dir);
      for (var j = 1; j < opaque.length; j++) {
        final candidate = opaque[j];
        final dot = (candidate - center).dot(dir);
        if (dot > bestDot) {
          bestDot = dot;
          best = candidate;
        }
      }
      support.add(best);
    }

    final hull = _convexHull(_dedup(support));
    if (hull.length < 3) return null;

    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final point in hull) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }
    final halfW = ((maxX - minX) * 0.5).clamp(1.0, double.infinity);
    final halfH = ((maxY - minY) * 0.5).clamp(1.0, double.infinity);
    final centerX = (minX + maxX) * 0.5;
    final centerY = (minY + maxY) * 0.5;

    return hull
        .map(
          (p) => Vector2(
            (p.x - centerX) / halfW,
            (p.y - centerY) / halfH,
          ),
        )
        .toList(growable: false);
  }

  Vector2 _centroid(List<Vector2> points) {
    var x = 0.0;
    var y = 0.0;
    for (final p in points) {
      x += p.x;
      y += p.y;
    }
    return Vector2(x / points.length, y / points.length);
  }

  List<Vector2> _dedup(List<Vector2> points) {
    final out = <Vector2>[];
    for (final p in points) {
      if (out.any((q) => q.distanceToSquared(p) < 0.01)) continue;
      out.add(Vector2.copy(p));
    }
    return out;
  }

  List<Vector2> _convexHull(List<Vector2> points) {
    if (points.length <= 2) return points;
    final sorted = points.map(Vector2.copy).toList(growable: true)
      ..sort((a, b) {
        final cx = a.x.compareTo(b.x);
        if (cx != 0) return cx;
        return a.y.compareTo(b.y);
      });

    double cross(Vector2 o, Vector2 a, Vector2 b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    final lower = <Vector2>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <Vector2>[];
    for (var i = sorted.length - 1; i >= 0; i--) {
      final p = sorted[i];
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }
}
