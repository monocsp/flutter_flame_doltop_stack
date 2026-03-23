import 'package:flutter/foundation.dart';
import 'package:flutter_flame_game_2/game/suika/stone_spec.dart';

/// Flutter HUD와 Flame 게임 사이의 반응형 상태를 중계합니다.
class SuikaHudState {
  /// HUD에 필요한 노티파이어를 한 곳에 모읍니다.
  SuikaHudState({int initialBestScore = 0, List<StoneSpec>? initialCatalog})
    : score = ValueNotifier<int>(0),
      bestScore = ValueNotifier<int>(initialBestScore),
      nextStone = ValueNotifier<StoneSpec>(
        (initialCatalog ?? StoneCatalog.droppableValues()).first,
      ),
      revealedStages = ValueNotifier<Set<int>>(<int>{0, 1, 2, 3, 4, 5}),
      comboPendingBonus = ValueNotifier<int>(0),
      comboRemainingSeconds = ValueNotifier<double>(0),
      isComboActive = ValueNotifier<bool>(false),
      comboPulseToken = ValueNotifier<int>(0),
      isPaused = ValueNotifier<bool>(false),
      isGameOver = ValueNotifier<bool>(false);

  /// 현재 점수를 노출합니다.
  final ValueNotifier<int> score;

  /// 세션 중 최고 점수를 보관합니다.
  final ValueNotifier<int> bestScore;

  /// 다음 드롭 대상 미리보기를 제공합니다.
  final ValueNotifier<StoneSpec> nextStone;

  /// 도감에서 공개된 단계 목록을 보관합니다.
  final ValueNotifier<Set<int>> revealedStages;

  /// 아직 정산되지 않은 콤보 보너스 점수입니다.
  final ValueNotifier<int> comboPendingBonus;

  /// 현재 콤보 유지 시간입니다.
  final ValueNotifier<double> comboRemainingSeconds;

  /// 현재 콤보 활성 여부입니다.
  final ValueNotifier<bool> isComboActive;

  /// 중앙 Combo 연출을 재생하기 위한 트리거 토큰입니다.
  final ValueNotifier<int> comboPulseToken;

  /// 일시정지 상태를 노출합니다.
  final ValueNotifier<bool> isPaused;

  /// 게임오버 상태를 노출합니다.
  final ValueNotifier<bool> isGameOver;

  /// 점수와 게임오버 플래그를 초기값으로 돌립니다.
  void resetForNewGame() {
    score.value = 0;
    comboPendingBonus.value = 0;
    comboRemainingSeconds.value = 0;
    isComboActive.value = false;
    isPaused.value = false;
    isGameOver.value = false;
  }

  /// 최고 점수를 포함해 현재 점수를 갱신합니다.
  void setScore(int nextScore) {
    score.value = nextScore;
    if (nextScore > bestScore.value) {
      bestScore.value = nextScore;
    }
  }

  /// 다음 미리보기 스톤을 갱신합니다.
  void setNextStone(StoneSpec spec) {
    nextStone.value = spec;
  }

  /// 특정 단계 스톤을 도감에서 공개 상태로 전환합니다.
  void revealStone(StoneSpec spec) {
    final Set<int> current = revealedStages.value;
    if (current.contains(spec.stage)) {
      return;
    }
    revealedStages.value = <int>{...current, spec.stage};
  }

  /// 콤보 HUD 상태를 한 번에 갱신합니다.
  void setComboState({
    required bool active,
    required double remainingSeconds,
    required int pendingBonus,
  }) {
    isComboActive.value = active;
    comboRemainingSeconds.value = remainingSeconds;
    comboPendingBonus.value = pendingBonus;
  }

  /// 콤보 시작 문구를 한 번 재생합니다.
  void triggerComboPulse() {
    comboPulseToken.value += 1;
  }

  /// 일시정지 상태를 HUD에 반영합니다.
  void setPaused(bool value) {
    isPaused.value = value;
  }

  /// 게임오버를 HUD에 반영합니다.
  void setGameOver(bool value) {
    isGameOver.value = value;
  }

  /// 생성한 노티파이어를 정리합니다.
  void dispose() {
    score.dispose();
    bestScore.dispose();
    nextStone.dispose();
    revealedStages.dispose();
    comboPendingBonus.dispose();
    comboRemainingSeconds.dispose();
    isComboActive.dispose();
    comboPulseToken.dispose();
    isPaused.dispose();
    isGameOver.dispose();
  }
}
