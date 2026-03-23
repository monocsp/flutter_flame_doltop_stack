import 'stone_asset_data.dart';
import 'png_processor.dart';
import 'svg_processor.dart';

/// PNG와 SVG 에셋 로딩 및 메타데이터 추출을 통합 관리하는 클래스입니다.
class AssetManager {
  final PngProcessor _pngProcessor = PngProcessor();
  final SvgProcessor _svgProcessor = SvgProcessor();

  /// 모든 에셋 리스트를 받아 형식을 구분하여 분석하고 통합 메타데이터 맵을 반환합니다.
  Future<Map<String, StoneAssetData>> prepareAllAssets(List<String> assetPaths) async {
    final Map<String, StoneAssetData> allMetadata = {};

    // PNG 처리
    final pngMetadata = await _pngProcessor.prepareAssets(assetPaths);
    allMetadata.addAll(pngMetadata);

    // SVG 처리
    final svgMetadata = await _svgProcessor.prepareAssets(assetPaths);
    allMetadata.addAll(svgMetadata);

    return allMetadata;
  }
}
