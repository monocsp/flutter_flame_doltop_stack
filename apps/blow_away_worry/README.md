# blow_away_worry

포스트잇에 고민을 적고, 마이크에 바람을 불어 고민을 날려버리는 단일 화면 Flutter 앱이다.

## 무엇을 만들려고 했는가

이 프로젝트는 "고민을 날려버려"라는 감정 정리용 인터랙션을 목표로 한다.

- 사용자는 중앙의 포스트잇에 현재 고민을 적는다.
- 마이크 버튼을 켜고 후 하고 바람을 불면 바람 세기에 따라 포스트잇이 흔들린다.
- 일정 시간 이상 바람이 끊기지 않으면 포스트잇이 화면 밖으로 날아가며 고민을 흩날려 보낸다.
- 날아간 뒤에는 가벼워졌다는 메시지와 함께 다시 시작할 수 있다.

핵심은 단순 메모 앱이 아니라, 입력한 감정을 물리적인 제스처로 정리하는 짧은 의식 같은 경험을 만드는 것이다.

## 어떻게 구현했는가

앱은 Flutter 기본 위젯과 `Ticker` 기반 프레임 루프 중심으로 구성했다. 이 프로젝트는 게임 월드보다는 단일 UI 인터랙션에 가깝기 때문에 Flame 대신 일반 Flutter 구조가 더 적합하다고 판단했다.

### 화면 구성

- 상단: `Caveat` 스타일 타이틀과 설명 문구
- 중앙: 포스트잇 입력 영역, 테이프, 색상 선택기
- 하단: 바람 세기 미터, 마이크 버튼, 상태 문구
- 완료 상태: 날아간 뒤 안내 메시지와 리셋 버튼

### 포스트잇 표현

- `CustomPainter`로 포스트잇 본체를 그린다.
- 하단 접힌 모서리는 `quadraticBezierTo` 기반 path로 만들었다.
- `RadialGradient`로 접힌 쪽이 조금 더 밝게 보이도록 처리했다.
- 그림자는 blur shadow로 그리고, 진행도가 높아질수록 그림자가 더 들뜬 느낌이 나도록 했다.
- 포스트잇 위에는 반투명 테이프를 별도 위젯으로 올렸다.
- 내부 입력창은 줄이 그어진 배경 위에 `TextField`를 얹는 방식으로 구현했다.

### 바람 감지

- `noise_meter`로 마이크 입력을 받아 `meanDecibel`을 사용한다.
- 데시벨은 대략 `50dB ~ 90dB` 구간을 `0.0 ~ 1.0`의 `blowStrength`로 정규화한다.
- 입력이 너무 튀지 않도록 화면에서는 보간을 한 번 더 적용했다.
- `permission_handler`로 Android/iOS 마이크 권한을 요청한다.

### 흔들림과 날아가기

- `TickerProviderStateMixin`으로 매 프레임 `dt`를 계산한다.
- 바람이 감지되면 `cumulativeBlow += dt * blowStrength * 2`
- 바람이 약해지면 `cumulativeBlow -= dt * 0.6`
- 누적값이 임계치 `3.8`에 도달하면 날아가기 상태로 전환한다.
- 흔들림은 `flickerPhase`, `sin`, `progress`를 조합해 각도와 미세한 x/y jitter를 계산한다.
- 날아가기 상태에서는 우상향 초기 속도, 중력, 회전, 감쇠, 투명도 감소를 매 프레임 갱신한다.
- 동시에 포스트잇 색상 기반 파티클 20개를 뿌려 마무리 감각을 준다.

## 주요 파일

- `lib/main.dart`: 앱 테마와 진입점
- `lib/screens/blow_screen.dart`: 전체 상태, Ticker 루프, 마이크 제어, 날아가기 로직
- `lib/services/mic_service.dart`: 마이크 권한 요청과 데시벨 정규화
- `lib/widgets/sticky_note.dart`: 포스트잇 입력 위젯 조합
- `lib/widgets/sticky_note_painter.dart`: 포스트잇 본체, 접힘, 그림자, 하이라이트 렌더링
- `lib/widgets/particle_effect.dart`: 날아갈 때 퍼지는 파티클 렌더링

## 실행과 검증

```bash
cd apps/blow_away_worry
flutter run
```

검증한 항목:

- `flutter analyze`
- `flutter test`

둘 다 통과했다.

## 메모

초기 요구사항에는 `noise_meter: ^6.0.0`이 있었지만 현재 해석 가능한 버전이 아니어서 실제로 설치 가능한 `^5.0.2`로 맞췄다. 나머지 구조와 동작은 원래 의도에 맞게 구현했다.
