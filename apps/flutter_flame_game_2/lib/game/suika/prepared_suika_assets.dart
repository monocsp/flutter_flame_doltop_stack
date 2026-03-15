import 'dart:async';
import 'dart:ui' as ui;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/services.dart';

import 'assets/png_processor.dart';
import 'assets/stone_asset_data.dart';
import 'stone_spec.dart';

class PreparedStoneAsset {
  const PreparedStoneAsset({
    required this.spec,
    required this.assetData,
    required this.image,
    required this.overlayPolygon,
  });

  final StoneSpec spec;
  final StoneAssetData assetData;
  final ui.Image image;
  final List<Vector2>? overlayPolygon;
}

class PreparedSuikaAssets {
  PreparedSuikaAssets._({
    required this.catalog,
    required this.droppableCatalog,
    required this.assetsByPath,
  });

  final List<StoneSpec> catalog;
  final List<StoneSpec> droppableCatalog;
  final Map<String, PreparedStoneAsset> assetsByPath;

  static Future<PreparedSuikaAssets> load({
    List<String>? stoneAssetPaths,
  }) async {
    final List<StoneSpec> catalog = StoneCatalog.buildValues(stoneAssetPaths);
    final PngProcessor pngProcessor = PngProcessor();
    final Map<String, StoneAssetData> metadata = await pngProcessor.prepareAssets(
      catalog.map((StoneSpec spec) => spec.assetPath).toList(growable: false),
    );

    final Map<String, PreparedStoneAsset> assetsByPath =
        <String, PreparedStoneAsset>{};
    for (final StoneSpec spec in catalog) {
      final ByteData data = await rootBundle.load(spec.assetPath);
      final ui.Image image = await _decodeUiImage(data);
      final StoneAssetData assetData =
          metadata[spec.assetPath] ??
          StoneAssetData(
            assetPath: spec.assetPath,
            aspectRatio: 1.0,
            densityMultiplier: 1.0,
          );

      assetsByPath[spec.assetPath] = PreparedStoneAsset(
        spec: spec,
        assetData: assetData,
        image: image,
        overlayPolygon: _buildOverlayPolygon(spec: spec, assetData: assetData),
      );
    }

    return PreparedSuikaAssets._(
      catalog: catalog,
      droppableCatalog: catalog
          .where((StoneSpec spec) => spec.isDroppable)
          .toList(growable: false),
      assetsByPath: assetsByPath,
    );
  }

  PreparedStoneAsset assetFor(StoneSpec spec) {
    return assetsByPath[spec.assetPath]!;
  }

  static Future<ui.Image> _decodeUiImage(ByteData data) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromList(data.buffer.asUint8List(), (ui.Image image) {
      completer.complete(image);
    });
    return completer.future;
  }

  static List<Vector2>? _buildOverlayPolygon({
    required StoneSpec spec,
    required StoneAssetData assetData,
  }) {
    final List<Vector2>? hint = assetData.collisionHint;
    if (hint == null || hint.length < 3) {
      return null;
    }

    final Vector2 halfSize = _computeHalfSize(
      assetData.aspectRatio,
      spec.radius * 2,
    );
    final List<Vector2> scaled = hint
        .map((Vector2 point) => Vector2(point.x * halfSize.x, point.y * halfSize.y))
        .toList(growable: false);
    final List<Vector2> safe = _toConvexWithin8(scaled);
    if (safe.length < 3 || safe.length > 8) {
      return null;
    }
    return safe;
  }

  static Vector2 _computeHalfSize(double aspect, double diameter) {
    final double safeAspect = aspect <= 0 ? 1.0 : aspect;
    if (safeAspect >= 1.0) {
      final double halfHeight = diameter * 0.5;
      return Vector2(halfHeight * safeAspect, halfHeight);
    }

    final double halfWidth = diameter * 0.5;
    return Vector2(halfWidth, halfWidth / safeAspect);
  }

  static List<Vector2> _toConvexWithin8(List<Vector2> points) {
    final List<Vector2> out = points.map(Vector2.copy).toList(growable: true);
    if (out.length <= 8) {
      return out;
    }

    while (out.length > 8) {
      var minIndex = 0;
      var minLoss = double.infinity;
      for (int i = 0; i < out.length; i += 1) {
        final Vector2 prev = out[(i - 1 + out.length) % out.length];
        final Vector2 curr = out[i];
        final Vector2 next = out[(i + 1) % out.length];
        final double loss =
            ((prev.x * (curr.y - next.y)) +
                    (curr.x * (next.y - prev.y)) +
                    (next.x * (prev.y - curr.y)))
                .abs();
        if (loss < minLoss) {
          minLoss = loss;
          minIndex = i;
        }
      }
      out.removeAt(minIndex);
    }

    return out;
  }
}
