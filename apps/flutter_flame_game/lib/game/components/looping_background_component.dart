import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/services.dart';

/// 월드 하단을 기준으로 1~6 이미지를 위로 반복 타일링해 그리는 배경 컴포넌트입니다.
class LoopingBackgroundComponent extends Component with HasGameReference {
  LoopingBackgroundComponent({
    required this.assetPathsInOrder,
    required this.baseBottomY,
    required this.worldWidth,
    this.bottomOverlayAssetPath,
    this.preloadMargin = 6.0,
    super.priority,
  });

  final List<String> assetPathsInOrder;
  final double baseBottomY;
  final double worldWidth;
  final String? bottomOverlayAssetPath;
  final double preloadMargin;

  final List<ui.Image> _images = <ui.Image>[];
  final List<double> _scaledHeights = <double>[];
  ui.Image? _bottomOverlayImage;
  double _bottomOverlayScaledHeight = 0.0;
  double _cycleHeight = 0.0;
  bool _loaded = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (assetPathsInOrder.isEmpty) return;

    for (final path in assetPathsInOrder) {
      final image = await _loadUiImageFromAsset(path);
      _images.add(image);
      final scaledHeight = worldWidth * (image.height / image.width);
      _scaledHeights.add(scaledHeight);
      _cycleHeight += scaledHeight;
    }
    if (bottomOverlayAssetPath != null && bottomOverlayAssetPath!.isNotEmpty) {
      _bottomOverlayImage = await _loadUiImageFromAsset(bottomOverlayAssetPath!);
      _bottomOverlayScaledHeight =
          worldWidth * (_bottomOverlayImage!.height / _bottomOverlayImage!.width);
    }
    _loaded = _images.isNotEmpty && _cycleHeight > 0;
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    if (!_loaded) return;

    final zoom = game.camera.viewfinder.zoom;
    final viewTop = game.camera.viewfinder.position.y;
    final viewHeight = game.size.y / zoom;
    final viewBottom = viewTop + viewHeight;
    final drawTop = viewTop - preloadMargin;
    final drawBottom = viewBottom + preloadMargin;

    var startBottom = baseBottomY;
    var tileIndex = 0;
    final patternCount = _images.length;

    if (drawBottom < baseBottomY) {
      final skipDistance = baseBottomY - drawBottom;
      final fullCycles = (skipDistance / _cycleHeight).floor();
      if (fullCycles > 0) {
        startBottom -= fullCycles * _cycleHeight;
        tileIndex += fullCycles * patternCount;
      }

      while (true) {
        final h = _scaledHeights[tileIndex % patternCount];
        final nextTop = startBottom - h;
        if (nextTop <= drawBottom) break;
        startBottom = nextTop;
        tileIndex++;
      }
    }

    var bottom = startBottom;
    while (bottom > drawTop) {
      final idx = tileIndex % patternCount;
      final image = _images[idx];
      final h = _scaledHeights[idx];
      final top = bottom - h;

      if (bottom >= drawTop && top <= drawBottom) {
        canvas.drawImageRect(
          image,
          ui.Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          ),
          ui.Rect.fromLTWH(0, top, worldWidth, h),
          ui.Paint(),
        );
      }

      bottom = top;
      tileIndex++;
    }

    final overlay = _bottomOverlayImage;
    if (overlay != null && _bottomOverlayScaledHeight > 0) {
      final overlayTop = baseBottomY - _bottomOverlayScaledHeight;
      final overlayBottom = baseBottomY;
      if (overlayBottom >= drawTop && overlayTop <= drawBottom) {
        canvas.drawImageRect(
          overlay,
          ui.Rect.fromLTWH(
            0,
            0,
            overlay.width.toDouble(),
            overlay.height.toDouble(),
          ),
          ui.Rect.fromLTWH(0, overlayTop, worldWidth, _bottomOverlayScaledHeight),
          ui.Paint(),
        );
      }
    }
  }

  Future<ui.Image> _loadUiImageFromAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
