# Stone Asset System Refactoring Report (PNG & SVG Integration)

본 문서는 게임 내 돌(Stone) 자산 관리 시스템을 PNG와 SVG 형식을 모두 지원하도록 리팩토링한 내역을 기록합니다.

## 1. 개요
기존의 PNG 전용 로직을 추상화하고, SVG 지원을 추가하여 자산 형식에 관계없이 동일한 물리 엔진과 렌더링 파이프라인을 사용할 수 있도록 구조를 개선했습니다.

---

## 2. 단계별 진행 사항

### [1단계] 데이터 인터페이스 통합 (Data Interface Refactoring)
**목적:** 물리 엔진과 렌더러에 필요한 데이터를 하나의 모델로 통합하여 의존성 단순화.
- **수정된 파일:**
    - `lib/game/assets/stone_asset_data.dart`: `StoneAssetType` (png, svg) 열거형 및 `isSvg` 헬퍼 추가.
    - `lib/game/components/falling_polygon_component.dart`: 생성자에서 개별 파라미터 대신 `StoneAssetData` 객체를 받도록 변경.
    - `lib/game/stacking_game.dart`: `_spawnStone` 로직에서 자산 데이터를 `StoneAssetData`로 캡슐화하여 전달.

### [2단계] PNG 로직 분리 (PNG Logic Separation)
**목적:** `StackingGame` 클래스의 비대화를 방지하고 PNG 분석 로직의 재사용성 확보.
- **새로 추가된 파일:**
    - `lib/game/assets/png_processor.dart`: 기존 `StackingGame`에 있던 픽셀 분석, 볼록 껍질(Convex Hull) 계산, 밀도 정규화 로직을 이관.
- **수정된 파일:**
    - `lib/game/stacking_game.dart`: 수백 줄의 PNG 분석 코드를 제거하고 `PngProcessor`를 호출하도록 경량화.

### [3단계] SVG 지원 및 관리자 도입 (SVG Support & Asset Manager)
**목적:** SVG 파일의 특성을 분석하고, 여러 형식의 자산을 통합 관리하는 단일 진입점 구축.
- **새로 추가된 파일:**
    - `lib/game/assets/svg_processor.dart`: XML 파싱을 통해 SVG의 `viewBox` 또는 `width/height`에서 종횡비를 추출하는 로직 구현.
    - `lib/game/assets/asset_manager.dart`: `PngProcessor`와 `SvgProcessor`를 통합하여 게임 시작 시 모든 자산을 한 번에 준비하는 인터페이스 제공.
- **수정된 파일:**
    - `lib/game/stacking_game.dart`: `onLoad` 시 `AssetManager`를 통해 통합된 메타데이터를 로드하도록 수정.

### [4단계] 라이브러리 연동 및 렌더링 추상화 (Library & Rendering)
**목적:** 실제 SVG 렌더링 기능을 구현하고 외부 라이브러리 의존성 해결.
- **의존성 추가 (`pubspec.yaml`):**
    - `flame_svg`: SVG 렌더링 지원.
    - `xml`: SVG 파일 구조 분석.
- **수정된 파일:**
    - `lib/game/components/falling_polygon_component.dart`: 
        - `onLoad` 시 에셋 타입에 따라 `SpriteComponent`(PNG) 또는 `SvgComponent`(SVG)를 동적으로 생성하여 부착.
        - 시각적 에셋 로드 실패 시에도 물리 기반의 폴리곤 렌더링이 작동하는 Fallback 메커니즘 유지.

---

## 3. 최종 설계 구조의 장점
1. **확장성:** 새로운 이미지 형식(예: WebP) 추가 시 `Processor` 클래스만 구현하면 기존 로직 수정 없이 확장 가능.
2. **가독성:** 게임 흐름(StackingGame), 물리/렌더링(Component), 자산 분석(Processor)의 역할이 명확히 분리됨.
3. **유지보수성:** PNG의 복잡한 충돌 알고리즘이 독립된 파일(`png_processor.dart`)에 격리되어 있어 관리가 용이함.
4. **시각적 품질:** SVG 지원을 통해 다양한 해상도에서도 깨짐 없는 고품질 그래픽 제공 가능.
