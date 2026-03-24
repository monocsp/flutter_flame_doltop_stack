class BreathConcept {
  const BreathConcept({
    required this.title,
    required this.tagline,
    required this.summary,
  });

  final String title;
  final String tagline;
  final String summary;
}

class BreathGameBlueprint {
  const BreathGameBlueprint({
    required this.title,
    required this.subtitle,
    required this.concepts,
    required this.foundationScopes,
    required this.nextSteps,
  });

  final String title;
  final String subtitle;
  final List<BreathConcept> concepts;
  final List<String> foundationScopes;
  final List<String> nextSteps;

  static const BreathGameBlueprint starter = BreathGameBlueprint(
    title: 'Breath Journey',
    subtitle: '호흡을 시각적 움직임과 감정 흐름으로 연결하는 세 번째 게임 베이스',
    concepts: <BreathConcept>[
      BreathConcept(
        title: 'Breath Dive',
        tagline: '들이쉬고 내쉬는 리듬으로 스쿠버 다이빙처럼 유영하기',
        summary: '호흡 강도와 길이에 맞춰 캐릭터가 위아래 수압층을 통과하며 흐름을 타는 콘셉트입니다.',
      ),
      BreathConcept(
        title: 'Dandelion Breath',
        tagline: '호흡으로 민들레 씨앗을 멀리 보내기',
        summary: '날숨의 길이와 안정감을 이용해 씨앗이 퍼지고, 마지막에는 위로 문장을 보여주는 콘셉트입니다.',
      ),
      BreathConcept(
        title: 'Constellation Breath',
        tagline: '호흡할수록 별들이 이어져 별자리가 완성되기',
        summary: '정해진 호흡 패턴을 유지하면 점들이 선으로 연결되고, 차분한 밤하늘 구성이 완성되는 콘셉트입니다.',
      ),
    ],
    foundationScopes: <String>[
      '독립 앱 폴더와 실행 진입점',
      'Flame 프리뷰 월드',
      '아이디어 비교용 홈 화면',
      '다음 구현 단계 정리',
    ],
    nextSteps: <String>[
      '핵심 조작을 한 가지로 고정',
      '호흡 입력 방식을 센서/터치 기반으로 결정',
      '점수 또는 감정 피드백 시스템 정의',
      '시각 테마와 사운드 방향 확정',
    ],
  );
}
