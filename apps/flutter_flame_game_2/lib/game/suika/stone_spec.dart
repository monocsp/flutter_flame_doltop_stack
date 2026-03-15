import 'package:flutter/material.dart';

/// Suika 단계별 규격을 정의합니다.
class StoneSpec {
  /// 단계, 반지름, 색상과 점수 정책을 함께 보관합니다.
  const StoneSpec({
    required this.stage,
    required this.label,
    required this.radius,
    required this.color,
    required this.assetPath,
    required this.score,
    required this.isDroppable,
  });

  /// 단계 번호를 표현합니다.
  final int stage;

  /// HUD와 바디 내부에 표시할 짧은 라벨입니다.
  final String label;

  /// 원형 바디의 반지름을 월드 좌표 기준으로 보관합니다.
  final double radius;

  /// 단계별 시각 구분을 위한 대표 색상입니다.
  final Color color;

  /// 스톤 이미지 에셋 경로입니다.
  final String assetPath;

  /// 합체 성공 시 누적할 점수입니다.
  final int score;

  /// 초기 드롭 풀에 포함되는지 여부를 나타냅니다.
  final bool isDroppable;
}

class _StoneTemplate {
  const _StoneTemplate({
    required this.stage,
    required this.label,
    required this.radius,
    required this.color,
    required this.score,
    required this.isDroppable,
  });

  final int stage;
  final String label;
  final double radius;
  final Color color;
  final int score;
  final bool isDroppable;
}

/// Suika 단계 카탈로그와 드롭 풀 접근자를 제공합니다.
class StoneCatalog {
  static const int stageCount = 9;

  /// 현재 프로젝트에서 사용할 기본 스톤 이미지 경로입니다.
  static const List<String> defaultAssetPaths = <String>[
    'assets/stones/stone_1.png',
    'assets/stones/stone_2.png',
    'assets/stones/stone_3.png',
    'assets/stones/stone_4.png',
    'assets/stones/stone_5.png',
    'assets/stones/stone_6.png',
    'assets/stones/stone_7.png',
    'assets/stones/stone_8.png',
    'assets/stones/stone_9.png',
  ];

  static const List<_StoneTemplate> _templates = <_StoneTemplate>[
    _StoneTemplate(
      stage: 0,
      label: '1',
      radius: 0.50,
      color: Color(0xFFF7A541),
      score: 2,
      isDroppable: true,
    ),
    _StoneTemplate(
      stage: 1,
      label: '2',
      radius: 0.62,
      color: Color(0xFFFFC857),
      score: 4,
      isDroppable: true,
    ),
    _StoneTemplate(
      stage: 2,
      label: '3',
      radius: 0.76,
      color: Color(0xFFE9724C),
      score: 8,
      isDroppable: true,
    ),
    _StoneTemplate(
      stage: 3,
      label: '4',
      radius: 0.92,
      color: Color(0xFFC5283D),
      score: 16,
      isDroppable: true,
    ),
    _StoneTemplate(
      stage: 4,
      label: '5',
      radius: 1.10,
      color: Color(0xFF7D5BA6),
      score: 32,
      isDroppable: false,
    ),
    _StoneTemplate(
      stage: 5,
      label: '6',
      radius: 1.30,
      color: Color(0xFF3B8EA5),
      score: 64,
      isDroppable: false,
    ),
    _StoneTemplate(
      stage: 6,
      label: '7',
      radius: 1.52,
      color: Color(0xFF2A9D8F),
      score: 128,
      isDroppable: false,
    ),
    _StoneTemplate(
      stage: 7,
      label: '8',
      radius: 1.76,
      color: Color(0xFF588157),
      score: 256,
      isDroppable: false,
    ),
    _StoneTemplate(
      stage: 8,
      label: '9',
      radius: 2.02,
      color: Color(0xFF344E41),
      score: 512,
      isDroppable: false,
    ),
  ];

  /// 9개 경로를 받아 Suika 카탈로그를 생성합니다.
  static List<StoneSpec> buildValues([List<String>? assetPaths]) {
    final List<String> resolved = List<String>.from(
      assetPaths ?? defaultAssetPaths,
      growable: false,
    );
    assert(
      resolved.length == stageCount,
      'Suika stone image paths must contain exactly 9 entries.',
    );
    return List<StoneSpec>.generate(_templates.length, (int index) {
      final _StoneTemplate template = _templates[index];
      return StoneSpec(
        stage: template.stage,
        label: template.label,
        radius: template.radius,
        color: template.color,
        assetPath: resolved[index],
        score: template.score,
        isDroppable: template.isDroppable,
      );
    }, growable: false);
  }

  /// 첫 4단계만 드롭 풀로 노출합니다.
  static List<StoneSpec> droppableValues([List<String>? assetPaths]) {
    return buildValues(assetPaths)
        .where((StoneSpec spec) => spec.isDroppable)
        .toList(growable: false);
  }

  /// 다음 단계가 없으면 `null`을 반환합니다.
  static StoneSpec? nextOf(StoneSpec spec, List<StoneSpec> values) {
    if (spec.stage >= values.length - 1) {
      return null;
    }
    return values[spec.stage + 1];
  }
}
