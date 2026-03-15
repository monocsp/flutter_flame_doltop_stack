import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'stone_asset_data.dart';

/// PNG 이미지에서 충돌 힌트와 질량 보정값을 추출합니다.
class PngProcessor {
  Future<Map<String, StoneAssetData>> prepareAssets(
    List<String> assetPaths,
  ) async {
    final Map<String, StoneAssetData> metadataMap = <String, StoneAssetData>{};
    final Map<String, double> rawMassByAsset = <String, double>{};
    final Map<String, List<Vector2>> tempHints = <String, List<Vector2>>{};
    final Map<String, double> tempAspects = <String, double>{};

    for (final String assetPath in assetPaths) {
      try {
        final Uint8List bytes = (await rootBundle.load(
          assetPath,
        )).buffer.asUint8List();
        final img.Image? decoded = img.decodeImage(bytes);
        if (decoded == null) {
          continue;
        }

        final double aspect = decoded.width / decoded.height;
        final double pixelArea = (decoded.width * decoded.height).toDouble();
        rawMassByAsset[assetPath] = pixelArea;
        tempAspects[assetPath] = aspect;

        final List<Vector2>? hint = _buildCollisionHintFromDecoded(decoded);
        if (hint != null && hint.length >= 3) {
          tempHints[assetPath] = hint;
        }
      } catch (_) {
        continue;
      }
    }

    if (rawMassByAsset.isEmpty) {
      return metadataMap;
    }

    final double meanArea =
        rawMassByAsset.values.reduce((double a, double b) => a + b) /
        rawMassByAsset.length;

    for (final String assetPath in assetPaths) {
      final double? aspect = tempAspects[assetPath];
      if (aspect == null) {
        continue;
      }

      final double area = rawMassByAsset[assetPath]!;
      final double normalized = (area / meanArea).clamp(0.5, 2.6);
      final double emphasized = math.pow(normalized, 1.25).toDouble();
      final double densityMultiplier = emphasized.clamp(0.75, 1.9);

      metadataMap[assetPath] = StoneAssetData(
        assetPath: assetPath,
        aspectRatio: aspect,
        densityMultiplier: densityMultiplier,
        collisionHint: tempHints[assetPath],
      );
    }

    return metadataMap;
  }

  List<Vector2>? _buildCollisionHintFromDecoded(img.Image decoded) {
    final List<Vector2> opaque = <Vector2>[];
    for (int y = 0; y < decoded.height; y += 2) {
      for (int x = 0; x < decoded.width; x += 2) {
        final img.Pixel pixel = decoded.getPixel(x, y);
        if (pixel.a.toInt() > 20) {
          opaque.add(Vector2(x.toDouble(), y.toDouble()));
        }
      }
    }

    if (opaque.length < 12) {
      return null;
    }

    final Vector2 center = _centroid(opaque);
    final List<Vector2> support = <Vector2>[];
    const int supportCount = 8;
    for (int i = 0; i < supportCount; i += 1) {
      final double angle = i * (2 * math.pi / supportCount);
      final Vector2 dir = Vector2(math.cos(angle), math.sin(angle));
      Vector2 best = opaque.first;
      double bestDot = (best - center).dot(dir);
      for (int j = 1; j < opaque.length; j += 1) {
        final Vector2 candidate = opaque[j];
        final double dot = (candidate - center).dot(dir);
        if (dot > bestDot) {
          bestDot = dot;
          best = candidate;
        }
      }
      support.add(best);
    }

    final List<Vector2> hull = _convexHull(_dedup(support));
    if (hull.length < 3) {
      return null;
    }

    double minX = double.infinity;
    double maxX = -double.infinity;
    double minY = double.infinity;
    double maxY = -double.infinity;
    for (final Vector2 point in hull) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }

    final double halfW = ((maxX - minX) * 0.5).clamp(1.0, double.infinity);
    final double halfH = ((maxY - minY) * 0.5).clamp(1.0, double.infinity);
    final double centerX = (minX + maxX) * 0.5;
    final double centerY = (minY + maxY) * 0.5;

    return hull
        .map(
          (Vector2 p) =>
              Vector2((p.x - centerX) / halfW, (p.y - centerY) / halfH),
        )
        .toList(growable: false);
  }

  Vector2 _centroid(List<Vector2> points) {
    double x = 0.0;
    double y = 0.0;
    for (final Vector2 p in points) {
      x += p.x;
      y += p.y;
    }
    return Vector2(x / points.length, y / points.length);
  }

  List<Vector2> _dedup(List<Vector2> points) {
    final List<Vector2> out = <Vector2>[];
    for (final Vector2 p in points) {
      if (out.any((Vector2 q) => q.distanceToSquared(p) < 0.01)) {
        continue;
      }
      out.add(Vector2.copy(p));
    }
    return out;
  }

  List<Vector2> _convexHull(List<Vector2> points) {
    if (points.length <= 2) {
      return points;
    }

    final List<Vector2> sorted = points.map(Vector2.copy).toList(growable: true)
      ..sort((Vector2 a, Vector2 b) {
        final int cx = a.x.compareTo(b.x);
        if (cx != 0) {
          return cx;
        }
        return a.y.compareTo(b.y);
      });

    double cross(Vector2 o, Vector2 a, Vector2 b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    final List<Vector2> lower = <Vector2>[];
    for (final Vector2 p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final List<Vector2> upper = <Vector2>[];
    for (int i = sorted.length - 1; i >= 0; i -= 1) {
      final Vector2 p = sorted[i];
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return <Vector2>[...lower, ...upper];
  }
}
