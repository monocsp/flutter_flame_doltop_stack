import 'package:flutter/material.dart';

/// Suika 단계별 규격을 정의합니다.
class StoneSpec {
  /// 단계, 반지름, 색상과 점수 정책을 함께 보관합니다.
  const StoneSpec({
    required this.stage,
    required this.label,
    required this.radius,
    required this.color,
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

  /// 합체 성공 시 누적할 점수입니다.
  final int score;

  /// 초기 드롭 풀에 포함되는지 여부를 나타냅니다.
  final bool isDroppable;
}

/// Suika 단계 카탈로그와 드롭 풀 접근자를 제공합니다.
class StoneCatalog {
  /// 9단계 고정 카탈로그를 제공합니다.
  static const List<StoneSpec> values = <StoneSpec>[
    StoneSpec(
      stage: 0,
      label: '1',
      radius: 0.56,
      color: Color(0xFFF7A541),
      score: 2,
      isDroppable: true,
    ),
    StoneSpec(
      stage: 1,
      label: '2',
      radius: 0.66,
      color: Color(0xFFFFC857),
      score: 4,
      isDroppable: true,
    ),
    StoneSpec(
      stage: 2,
      label: '3',
      radius: 0.76,
      color: Color(0xFFE9724C),
      score: 8,
      isDroppable: true,
    ),
    StoneSpec(
      stage: 3,
      label: '4',
      radius: 0.88,
      color: Color(0xFFC5283D),
      score: 16,
      isDroppable: true,
    ),
    StoneSpec(
      stage: 4,
      label: '5',
      radius: 1.00,
      color: Color(0xFF7D5BA6),
      score: 32,
      isDroppable: false,
    ),
    StoneSpec(
      stage: 5,
      label: '6',
      radius: 1.12,
      color: Color(0xFF3B8EA5),
      score: 64,
      isDroppable: false,
    ),
    StoneSpec(
      stage: 6,
      label: '7',
      radius: 1.26,
      color: Color(0xFF2A9D8F),
      score: 128,
      isDroppable: false,
    ),
    StoneSpec(
      stage: 7,
      label: '8',
      radius: 1.42,
      color: Color(0xFF588157),
      score: 256,
      isDroppable: false,
    ),
    StoneSpec(
      stage: 8,
      label: '9',
      radius: 1.58,
      color: Color(0xFF344E41),
      score: 512,
      isDroppable: false,
    ),
  ];

  /// 첫 4단계만 드롭 풀로 노출합니다.
  static List<StoneSpec> droppableValues() {
    return values.where((StoneSpec spec) => spec.isDroppable).toList(growable: false);
  }

  /// 다음 단계가 없으면 `null`을 반환합니다.
  static StoneSpec? nextOf(StoneSpec spec) {
    if (spec.stage >= values.length - 1) {
      return null;
    }
    return values[spec.stage + 1];
  }
}
