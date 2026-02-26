import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';
import 'stone_asset_data.dart';

/// SVG 파일을 분석하여 종횡비와 메타데이터를 추출하는 클래스입니다.
class SvgProcessor {
  static const bool _logEnabled = true;

  /// 여러 SVG 에셋들을 분석하여 StoneAssetData 맵을 반환합니다.
  Future<Map<String, StoneAssetData>> prepareAssets(List<String> assetPaths) async {
    final metadataMap = <String, StoneAssetData>{};

    for (final assetPath in assetPaths) {
      if (!assetPath.toLowerCase().endsWith('.svg')) continue;

      try {
        final svgString = await rootBundle.loadString(assetPath);
        final document = XmlDocument.parse(svgString);
        final svgElement = document.rootElement;

        double? width;
        double? height;

        // width/height 속성 확인
        final wAttr = svgElement.getAttribute('width');
        final hAttr = svgElement.getAttribute('height');
        if (wAttr != null && hAttr != null) {
          width = double.tryParse(wAttr.replaceAll(RegExp(r'[^0-9.]'), ''));
          height = double.tryParse(hAttr.replaceAll(RegExp(r'[^0-9.]'), ''));
        }

        // viewBox 속성 확인 (width/height가 없거나 유효하지 않을 때)
        if (width == null || height == null) {
          final viewBox = svgElement.getAttribute('viewBox');
          if (viewBox != null) {
            final parts = viewBox.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList();
            if (parts.length == 4) {
              width = double.tryParse(parts[2]);
              height = double.tryParse(parts[3]);
            }
          }
        }

        final aspect = (width != null && height != null && height != 0) 
            ? width / height 
            : 1.0;

        metadataMap[assetPath] = StoneAssetData(
          assetPath: assetPath,
          type: StoneAssetType.svg,
          aspectRatio: aspect,
          densityMultiplier: 1.0, // SVG는 기본 밀도 1.0 (필요시 파싱 가능)
          collisionHint: null,    // SVG용 충돌 힌트 추출은 복잡하므로 일단 null
        );
        
        if (_logEnabled) {
          debugPrint('[SvgProcessor] Processed $assetPath: aspect=$aspect');
        }
      } catch (e) {
        if (_logEnabled) {
          debugPrint('[SvgProcessor] Error processing $assetPath: $e');
        }
      }
    }

    return metadataMap;
  }
}
