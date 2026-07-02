# flutter_flame_doltop_stack

> 만든 이유: 게이미피케이션 데모가 필요해서 Flame + Forge2D로 물리 기반 게임을 직접 만들어 봤습니다.

> Flame + Forge2D 기반 2D 물리 게임 모노레포 — **돌탑 쌓기(Stone Stacking)** 와 **수박게임(Suika)** 두 편을 담고 있습니다.

<!-- 배지 값(버전/라이선스 등)은 배포/공개 정책 확정 후 실제 값으로 교체하세요. -->
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.8%2B-0175C2?logo=dart&logoColor=white)
![Flame](https://img.shields.io/badge/flame-1.35.1-orange)
![Forge2D](https://img.shields.io/badge/flame__forge2d-0.19.2-orange)
![Melos](https://img.shields.io/badge/monorepo-melos-0A7EA4)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey)
![License](https://img.shields.io/badge/license-TODO-lightgrey) <!-- [TODO] LICENSE 파일 추가 후 갱신 -->

Flutter/Flame과 물리엔진 [Forge2D(Box2D 포팅)](https://pub.dev/packages/flame_forge2d)로 만든 두 개의 캐주얼 물리 게임을 하나의 [Melos](https://melos.invertase.dev/) 모노레포에서 관리합니다. 두 게임 모두 **PNG 이미지의 실제 실루엣에서 충돌 도형(콜라이더)을 추출**하고 **충돌 속도에 반응하는 햅틱(진동)** 과 **고정 timestep 물리 루프**로 적층 안정성을 확보합니다.

- **돌탑 쌓기** (`apps/flutter_flame_game`): 위에서 떨어지는 다양한 형태의 돌을 드래그로 옮겨 높이 쌓는 게임. 난이도별 돌 형태 필터링, 온보딩, 지형(곡면 바닥) 생성 포함.
- **수박게임** (`apps/flutter_flame_game_2`): 같은 단계의 돌을 붙여 합체시키며 점수를 올리는 Suika류 게임. 게임 허브에서 위 돌탑 쌓기 게임도 함께 실행할 수 있습니다.

<!-- 데모 캡처 자리 -->
![stacking demo](docs/stacking.gif) <!-- [TODO] 돌탑 쌓기 플레이 GIF 추가 -->
![suika demo](docs/suika.gif) <!-- [TODO] 수박게임 플레이 GIF 추가 -->

---

## ✨ Features

### 공통

- **이미지 픽셀 → Convex Hull 콜라이더 자동 생성**
  PNG의 알파(불투명) 픽셀을 2px 간격으로 샘플링하고 8방향 서포트 포인트를 뽑아 [Andrew's monotone chain](https://en.wikipedia.org/wiki/Convex_hull_algorithms) 볼록 껍질을 계산합니다. Forge2D `PolygonShape`의 정점 상한(8개)에 맞춰 면적 손실이 가장 작은 정점부터 제거해 다각형 fixture로 부착합니다. 힌트를 얻지 못하면 원(circle) fixture로 자동 폴백합니다.
- **픽셀 면적 기반 밀도(질량) 보정**
  각 돌 이미지의 픽셀 넓이를 세트 평균으로 정규화(`pow 1.25`, clamp)해 큰 돌일수록 무겁게 느껴지도록 `densityMultiplier`를 계산합니다.
- **고정 timestep 물리 루프** (`FixedStepForge2DWorld`)
  가변 프레임 `dt`를 누산기(accumulator)로 모아 `1/60`초 고정 스텝으로 sub-step을 밟습니다(최대 6 sub-step). 프레임 드랍 시에도 적층이 흔들리지 않게 하는 구현입니다.
- **충돌 속도 기반 햅틱 피드백**
  `HapticFeedback` API로 충돌/합체 순간의 속도에 따라 진동 세기를 다르게 발생시킵니다.

### 돌탑 쌓기 (`flutter_flame_game`)

- 3개 충돌 전략 선택: `circleCompound`(원 복합), `convexPolygon`, `autoFromImage`(이미지 실루엣).
- `MouseJoint` + 프레임별 속도/각속도 보정 기반 **드래그 컨트롤러**. 위에 다른 돌이 눌러 쌓인 정도에 따라 밀어올림 강도를 억제(compression suppression)합니다.
- **난이도 3단계**(easy/normal/hard): 돌의 가로세로 비율(aspect ratio)로 스폰 형태를 필터링. 목표 높이 easy 50m / normal 100m / hard 200m, 목표 달성 후 안정 유지 시 카운트다운→클리어.
- **온보딩 플로우 4단계**(intro → 돌 선택 → 드래그 → 마무리).
- **자동 카메라 추적**: 최상단 돌 높이에 맞춰 카메라를 밀어올리고 수동 팬/스크롤 시 3초간 자동 추적을 멈춥니다.
- **이미지에서 곡면 지형 바닥 추출**: 배경 하단 오버레이 이미지의 상단 실루엣을 샘플링해 지형(`TerrainFloorComponent`) 바닥을 만듭니다.
- AABB 기반 실시간 탑 높이(미터) 측정, 루핑 배경, PNG/SVG 스프라이트 지원.

### 수박게임 (`flutter_flame_game_2`)

- **게임 허브**(`GameSelectScreen`)에서 스택게임/수박게임 선택. 스택게임은 `flutter_flame_game` 패키지를 path 의존성으로 그대로 재사용합니다.
- **9단계 스톤 카탈로그**: 반지름 0.50→2.02, 점수 2→512(단계마다 2배). 초기 드롭 풀은 앞 4단계만 노출.
- **안정적인 합체 로직**: 같은 단계 접촉을 프레임 큐(`pendingMerges`)로 모아 동일 프레임 중복 합체를 방지하고 스프라이트 외곽 기준(`mergeRadius`) 시각적 접촉까지 판정합니다.
- **단계별 햅틱 시퀀스**: 합체 결과 단계에 따라 selection/light/medium/heavy 진동을 조합.
- **위험선(danger line)**: 상단 위험선을 1초 연속 침범하면 게임 오버.
- 점수/최고 점수/다음 돌 미리보기 HUD, 재시작, 게임오버 오버레이.

---

## 🛠 Tech Stack / 아키텍처

| 영역 | 사용 기술 |
| --- | --- |
| 게임 엔진 | [Flame](https://pub.dev/packages/flame) `1.35.1` |
| 물리 | [flame_forge2d](https://pub.dev/packages/flame_forge2d) `0.19.2+4` (Box2D 포팅) |
| 이미지 처리 | [image](https://pub.dev/packages/image), 자체 Convex Hull 구현 |
| 벡터/기하 | vector_math, dart_earcut (돌탑 쌓기) |
| 벡터 그래픽 | flame_svg, xml (돌탑 쌓기) |
| 모노레포 | [Melos](https://melos.invertase.dev/) |
| 폰트 | Pretendard (돌탑 쌓기) |

### 특이 구현 하이라이트

**1. 이미지 실루엣 → 물리 콜라이더** — `png_processor.dart`

```
알파 픽셀 샘플링(step 2px, a>20)
  → centroid 기준 8방향 서포트 포인트
    → convex hull(monotone chain)
      → 정점 8개 이하로 축소(면적 손실 최소 정점부터 제거)
        → [-1, 1] 정규화된 collisionHint 저장
          → 런타임에 half-size 스케일 적용 후 PolygonShape fixture
```

**2. 고정 timestep 월드** — `FixedStepForge2DWorld` (두 게임 공통 패턴)

```dart
@override
void update(double dt) {
  _accumulator += dt.clamp(0.0, fixedStep * maxSubSteps);
  var steps = 0;
  while (_accumulator >= fixedStep && steps < maxSubSteps) {
    physicsWorld.stepDt(fixedStep); // 1/60초 고정 스텝
    _accumulator -= fixedStep;
    steps++;
  }
  if (steps >= maxSubSteps) _accumulator = 0; // 스파이럴 오브 데스 방지
}
```

- 돌탑 쌓기: `gravity (0, 50)`, velocity/position iterations `8 / 12`
- 수박게임: `gravity (0, 36)`, velocity/position iterations `10 / 14`

**3. 충돌 속도 → 햅틱 매핑** — `impact_haptic_controller.dart` (돌탑 쌓기)

- 매 `beginContact`마다 그 순간의 `linearVelocity.length`로 세기 결정
- 80ms 쿨다운으로 과도한 진동 억제
- 임계값(5.0) 이상은 `lightImpact`, 미만은 `selectionClick`

---

## 🚀 Getting Started

### 사전 요구사항

- Flutter SDK (Dart `3.8+` / 수박게임은 `3.11+`)
- iOS 시뮬레이터·실기기 또는 Android 에뮬레이터·실기기 (햅틱은 실기기에서 체감됩니다)

### 개별 앱 실행

```bash
# 돌탑 쌓기
cd apps/flutter_flame_game
flutter pub get
flutter run

# 수박게임 (+ 게임 허브: 두 게임 모두 실행 가능)
cd apps/flutter_flame_game_2
flutter pub get
flutter run
```

### 모노레포 도구 (Melos)

루트에서 Melos로 두 앱을 한 번에 다룹니다.

```bash
dart pub global activate melos
melos bootstrap        # 각 앱 pub get + 로컬 패키지 링크
melos run analyze      # 전체 앱 flutter analyze
melos run test         # 전체 앱 flutter test
```

> 정의된 Melos 스크립트는 `analyze`, `test` 두 가지입니다 (`melos.yaml` 참고).

---

## 📖 Usage

### 돌탑 쌓기 화면 임베드 — `FlameScreen`

에셋 목록을 지정하지 않으면 `AssetManifest`에서 `td_*` 패턴의 돌 이미지를 자동 수집합니다.

```dart
import 'package:flame/game.dart';
import 'package:flutter_flame_game/game/stacking_game.dart';
import 'package:flutter_flame_game/ui/app_shell.dart';

FlameScreen(
  initialOnboarding: false,           // 온보딩부터 시작할지
  difficulty: DifficultyLevel.easy,   // easy | normal | hard (기본 easy)
  initialSpawnCount: 5,               // 시작 시 떨어뜨릴 돌 개수
  enableHaptic: true,                 // 충돌 햅틱 on/off
);
```

### 게임 인스턴스를 직접 생성 (커스텀 통합)

```dart
final game = StackingGame(
  stoneSpriteAssets: assetPaths,      // 돌 이미지 경로 목록
  enableImageCollisionHints: true,    // 이미지 실루엣 콜라이더 사용
  difficulty: DifficultyLevel.normal,
);
GameWidget(game: game); // 게임 상태는 game.towerHeightMeters / game.activeStoneCount 등 ValueNotifier로 관찰
```

### 수박게임 화면 — `SuikaScreen`

1~9 단계에 대응하는 스톤 이미지 경로 **정확히 9개**를 넘깁니다(기본값 제공).

```dart
import 'package:flutter_flame_game_2/game/suika/stone_spec.dart';
import 'package:flutter_flame_game_2/ui/suika_screen.dart';

SuikaScreen(
  stoneAssetPaths: StoneCatalog.defaultAssetPaths, // 커스텀 시 length == 9 필수
);
```

### 이미지에서 콜라이더 힌트만 추출 — `PngProcessor`

```dart
final processor = PngProcessor();
final Map<String, StoneAssetData> meta =
    await processor.prepareAssets(['assets/stones/stone_1.png']);

final data = meta['assets/stones/stone_1.png']!;
final hull = data.collisionHint;          // [-1,1] 정규화된 볼록 껍질 정점
final density = data.densityMultiplier;    // 픽셀 면적 기반 밀도 보정값
```

---

## 🧩 폴더 구조

```text
flutter_flame_doltop_stack/
├─ melos.yaml                     # 모노레포 설정 (packages: apps/**, scripts: analyze/test)
└─ apps/
   ├─ flutter_flame_game/         # 돌탑 쌓기
   │  ├─ lib/
   │  │  ├─ main.dart
   │  │  ├─ game/
   │  │  │  ├─ stacking_game.dart          # 메인 게임 (FixedStepForge2DWorld 포함)
   │  │  │  ├─ assets/                      # png_processor(convex hull), svg_processor, asset_manager
   │  │  │  ├─ components/                  # falling_polygon, boundary, terrain_floor, looping_background
   │  │  │  ├─ physics/terrain_chain_builder.dart
   │  │  │  ├─ systems/                     # drag_controller, impact_haptic_controller
   │  │  │  └─ terrain/                     # terrain_profile(_extractor)
   │  │  ├─ ui/                             # app_shell, onboarding_screen, widgets
   │  │  └─ utils/asset_path_resolver.dart
   │  └─ assets/                            # images/{unstructured,structured}, background, fonts, stones
   │
   └─ flutter_flame_game_2/       # 수박게임 + 게임 허브
      ├─ lib/
      │  ├─ main.dart                       # GameHubApp
      │  ├─ game/suika/                     # suika_game, suika_stone_body, stone_spec,
      │  │                                  #   prepared_suika_assets, suika_hud_state, assets/
      │  └─ ui/                             # game_select_screen, suika_screen
      └─ assets/stones/                     # stone_1.png ~ stone_9.png
```

> `flutter_flame_game_2`는 `flutter_flame_game`을 path 의존성으로 참조하여 스택게임 화면을 재사용합니다.

---

## 📄 License

<!-- [TODO] 현재 저장소에 LICENSE 파일이 없습니다. 공개 전에 라이선스를 결정해 추가하세요 (예: MIT). -->
아직 라이선스가 지정되지 않았습니다. `[TODO]`

---

<sub>본 README는 소스 코드(pubspec / lib / melos.yaml) 기준으로 작성되었습니다. 배지 값·데모 미디어·라이선스 등 `[TODO]` 항목은 공개 정책 확정 후 채워 주세요.</sub>

## 배운 점

- 블록 모양 그대로 충돌을 잡으려고 이미지 픽셀에서 Convex Hull 폴리곤 콜라이더를 생성했습니다.
- 프레임마다 물리를 돌리면 적층이 불안정해서, 고정 timestep(accumulator) 루프로 안정성을 확보했습니다.
