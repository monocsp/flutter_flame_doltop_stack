# doltop_game 패키지 연동 가이드

이 문서는 `doltop_game` 돌탑 쌓기 게임 패키지를 새 Flutter 프로젝트에 연동하는 방법을 설명합니다.
Codex CLI에 이 파일을 전달하고 "이 패키지를 현재 프로젝트에 연동해줘"라고 하면 자동으로 연동됩니다.

---

## 복사 범위

`doltop_game/` 폴더 전체를 타겟 프로젝트 **옆** (같은 부모 디렉토리)에 놓습니다.

```
parent/
├── my_app/              ← 타겟 Flutter 프로젝트
│   ├── lib/
│   ├── assets/          ← 에셋을 여기에 복사
│   └── pubspec.yaml
└── doltop_game/         ← 이 폴더 통째로 복사 (lib/ ~ pubspec.yaml 전부)
```

에셋은 패키지가 아닌 **타겟 앱** 안에 있어야 합니다.
원본 프로젝트(`flutter_flame_stacking_game/assets/`)에서 아래 폴더를 복사하세요:

| 복사할 폴더 | 용도 | 필수 |
|------------|------|------|
| `assets/images/unstructured/` | 돌 이미지 77개 (td_*.png) | ✅ |
| `assets/images/structured/` | 가공된 돌 이미지 | 선택 |
| `assets/background/` | 루핑 배경 (1~6.png, base.png) | 배경 사용 시 |
| `assets/fonts/PretendardVariable.ttf` | 프리텐다드 폰트 | 선택 |

---

## Codex CLI 연동 프롬프트

> 아래 내용을 Codex CLI에 그대로 전달하면 됩니다.

### 지시사항

다음 단계를 순서대로 수행하세요.

#### 1. pubspec.yaml — 의존성 추가

현재 프로젝트의 `pubspec.yaml` `dependencies:` 에 추가:

```yaml
dependencies:
  doltop_game:
    path: ../doltop_game
```

#### 2. pubspec.yaml — 에셋 등록

`flutter:` 섹션에 아래를 추가 (이미 있는 항목은 건너뜀):

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/unstructured/
    - assets/images/structured/         # structured 돌 사용 시
    - assets/images/structured/face/    # structured 돌 사용 시
    - assets/background/                # 배경 이미지 사용 시
  fonts:
    - family: Pretendard
      fonts:
        - asset: assets/fonts/PretendardVariable.ttf
```

#### 3. main.dart 작성

```dart
import 'package:flutter/material.dart';
import 'package:doltop_game/doltop_game.dart';

void main() {
  runApp(
    MaterialApp(
      title: '돌탑 쌓기',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        fontFamily: 'Pretendard',
      ),
      home: const OnboardingScreen(
        // Flame 월드 배경 이미지 (assets/background/ 복사 시):
        backgroundAssetPaths: [
          'assets/background/1.png',
          'assets/background/2.png',
          'assets/background/3.png',
          'assets/background/4.png',
          'assets/background/5.png',
          'assets/background/6.png',
        ],
        backgroundBaseAssetPath: 'assets/background/base.png',
      ),
    ),
  );
}
```

#### 4. 의존성 설치 및 검증

```bash
flutter pub get
flutter analyze
```

에러 없으면 연동 완료.

---

## 매개변수 레퍼런스

`OnboardingScreen`과 `FlameScreen` 공통:

| 매개변수 | 타입 | 기본 동작 | 설명 |
|---------|------|----------|------|
| `backgroundGradient` | `Gradient?` | 보라→핑크→피치 | Flutter UI 그라데이션 |
| `backgroundWidget` | `Widget?` | 별빛 파티클 | 배경 위젯 |
| `backgroundAssetPaths` | `List<String>?` | 없음 | Flame 루핑 배경 경로 |
| `backgroundBaseAssetPath` | `String?` | 없음 | Flame 바닥 오버레이 경로 |

`FlameScreen` 전용:

| 매개변수 | 타입 | 기본값 | 설명 |
|---------|------|-------|------|
| `stoneAssetPaths` | `List<String>?` | 자동 수집 | 돌 에셋 경로 |
| `initialSpawnCount` | `int` | `5` | 초기 돌 수 |
| `enableHaptic` | `bool` | `true` | 햅틱 피드백 |
| `difficulty` | `DifficultyLevel` | `.easy` | 난이도 |

### 커스텀 배경 예시

```dart
OnboardingScreen(
  backgroundGradient: const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
  ),
  backgroundWidget: const SizedBox.shrink(), // 파티클 제거
)
```

### 온보딩 없이 바로 게임

```dart
home: const FlameScreen(
  backgroundAssetPaths: [...],
  backgroundBaseAssetPath: 'assets/background/base.png',
)
```
