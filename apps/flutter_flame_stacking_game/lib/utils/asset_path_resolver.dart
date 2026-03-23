import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const String _packagePrefix = 'packages/flutter_flame_game/';

Iterable<String> assetPathCandidates(String assetPath) sync* {
  yield assetPath;

  if (assetPath.startsWith(_packagePrefix)) {
    yield assetPath.substring(_packagePrefix.length);
    return;
  }

  if (assetPath.startsWith('assets/')) {
    yield '$_packagePrefix$assetPath';
  }
}

Future<ByteData> loadAssetByteData(String assetPath) async {
  FlutterError? lastError;

  for (final candidate in assetPathCandidates(assetPath)) {
    try {
      return await rootBundle.load(candidate);
    } on FlutterError catch (error) {
      lastError = error;
    }
  }

  throw lastError ??
      FlutterError('Unable to load asset candidates for "$assetPath".');
}

Future<Uint8List> loadAssetBytes(String assetPath) async {
  final data = await loadAssetByteData(assetPath);
  return data.buffer.asUint8List();
}

Future<ui.Image> loadUiImageFromAsset(String assetPath) async {
  final bytes = await loadAssetBytes(assetPath);
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}
