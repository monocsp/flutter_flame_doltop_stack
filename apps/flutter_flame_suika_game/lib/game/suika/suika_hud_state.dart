import 'package:flutter/foundation.dart';
import 'package:flutter_flame_game_2/game/suika/stone_spec.dart';

/// Flutter HUD와 Flame 게임 사이의 반응형 상태를 중계합니다.
class SuikaHudState {
  /// HUD에 필요한 노티파이어를 한 곳에 모읍니다.
  SuikaHudState({
    int initialBestScore = 0,
    List<StoneSpec>? initialCatalog,
  }) : score = ValueNotifier<int>(0),
       bestScore = ValueNotifier<int>(initialBestScore),
       nextStone = ValueNotifier<StoneSpec>(
         (initialCatalog ?? StoneCatalog.droppableValues()).first,
       ),
       isPaused = ValueNotifier<bool>(false),
       isGameOver = ValueNotifier<bool>(false);

  /// 현재 점수를 노출합니다.
  final ValueNotifier<int> score;

  /// 세션 중 최고 점수를 보관합니다.
  final ValueNotifier<int> bestScore;

  /// 다음 드롭 대상 미리보기를 제공합니다.
  final ValueNotifier<StoneSpec> nextStone;

  /// 일시정지 상태를 노출합니다.
  final ValueNotifier<bool> isPaused;

  /// 게임오버 상태를 노출합니다.
  final ValueNotifier<bool> isGameOver;

  /// 점수와 게임오버 플래그를 초기값으로 돌립니다.
  void resetForNewGame() {
    score.value = 0;
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
    isPaused.dispose();
    isGameOver.dispose();
  }
}
