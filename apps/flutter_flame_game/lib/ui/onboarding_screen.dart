import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/stacking_game.dart';
import 'app_shell.dart';
import 'widgets/particle_background.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final ValueNotifier<int> _currentPage = ValueNotifier(0);

  List<String> _stoneAssets = [];
  String? _selectedStoneAsset;
  StackingGame? _gameInstance;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _currentPage.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage.value < 3) {
      _currentPage.value++;
      if (_currentPage.value == 1 && _gameInstance != null) {
        _gameInstance!.transitionToStep2SelectStone();
      }
    } else {
      _goToMainGame();
    }
  }

  void _goToMainGame() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const FlameScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  void _onGameCreated(StackingGame game) {
    _gameInstance = game;

    // 2단계 스폰 시 플러터 UI에도 어떤 돌이 스폰되었는지 알려줌
    _gameInstance?.onStonesSpawned = (List<String> spawnedAssets) {
      if (mounted) {
        setState(() {
          _stoneAssets = List.from(spawnedAssets);
          // 임시로 첫 번째를 할당해두고 나중에 탭 시점에 진짜 선택된 걸로 엎어침
          if (_selectedStoneAsset == null && _stoneAssets.isNotEmpty) {
            _selectedStoneAsset = _stoneAssets.first;
          }
        });
      }
    };

    // 2단계 (돌 1개 선택)에서 선택 완료 시 3단계(다음 페이지)로 자동 이동할 수 있게 콜백 설정
    _gameInstance?.onStoneSelected = (String path) {
      if (_currentPage.value == 1) {
        setState(() {
          _selectedStoneAsset = path;
        });
        _nextPage();
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 공통 그라데이션 배경
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.3, 1.0],
                colors: [
                  Color(0xFF997FFF), // 상단 보라
                  Color(0xFFF293FF), // 중상단 핑크
                  Color(0xFFFFD582), // 하단 피치
                ],
              ),
            ),
          ),

          // 2. 파티클(별빛) 이펙트 배경
          const ParticleBackground(),

          // 3. Flame 화면 (Step 2, Step 3에서만 돌과 바닥을 보여주기 위함)
          ValueListenableBuilder<int>(
            valueListenable: _currentPage,
            builder: (context, pageIndex, child) {
              // 0번(Step1), 3번(Step4)일 땐 Flame 영역을 숨기거나 터치를 막아도 됨.
              // 하지만 구조상 렌더링은 유지하되 opacity 섞어 시각적 제어만 함.
              final isFlameVisible = pageIndex == 1 || pageIndex == 2;
              return IgnorePointer(
                ignoring: !isFlameVisible,
                child: AnimatedOpacity(
                  opacity: isFlameVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 600),
                  child: FlameScreen(
                    initialOnboarding: true,
                    onGameCreated: _onGameCreated,
                  ),
                ),
              );
            },
          ),

          // 4. 단계별 텍스트 및 UI 레이어 (투명 빈 공간 터치 허용)
          ValueListenableBuilder<int>(
            valueListenable: _currentPage,
            builder: (context, pageIndex, _) {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: () {
                  switch (pageIndex) {
                    case 0:
                      return _Step1Intro(
                        key: const ValueKey(0),
                        onNext: _nextPage,
                      );
                    case 1:
                      return const _Step2SelectStone(key: ValueKey(1));
                    case 2:
                      return _Step3DragStone(
                        key: const ValueKey(2),
                        onNext: _nextPage,
                      );
                    case 3:
                      return _Step4StackFinish(
                        key: const ValueKey(3),
                        stoneAssets: _stoneAssets,
                        selectedStoneAsset:
                            _selectedStoneAsset ?? _stoneAssets.first,
                        onNext: _goToMainGame,
                      );
                    default:
                      return const SizedBox.shrink(key: ValueKey('empty'));
                  }
                }(),
              );
            },
          ),

          // 5. 페이지 인디케이터 (상단 표시)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 32,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<int>(
              valueListenable: _currentPage,
              builder: (context, pageIndex, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final isActive = index == pageIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 16 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: isActive ? 1.0 : 0.4,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                );
              },
            ),
          ),

          // 6. 스킵 버튼 (전체 단계 공통, 우측 상단 인디케이터 라인 근처)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: _goToMainGame,
            ),
          ),
        ],
      ),
    );
  }
}

// --- 단계별 서브 위젯들 ---

/// [Step 1] 천천히 느껴지는 감각에 집중해 보세요
class _Step1Intro extends StatefulWidget {
  const _Step1Intro({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  State<_Step1Intro> createState() => _Step1IntroState();
}

class _Step1IntroState extends State<_Step1Intro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // 3초 후 다음 장면으로 자동 전환
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        widget.onNext();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (mounted) {
          _timer?.cancel();
          widget.onNext();
        }
      },
      child: Center(
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: const Text(
              '천천히 느껴지는\n감각에 집중해 보세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.w500,
                height: 1.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [Step 2] 첫 번째 돌을 골라볼까요?
/// (Flame 영역이 돌들을 렌더링하므로 이 위젯은 화면 상단 '텍스트'만 투명 레이어로 뿌림)
class _Step2SelectStone extends StatelessWidget {
  const _Step2SelectStone({super.key});

  @override
  Widget build(BuildContext context) {
    // 하단 터치는 Flame 영역(아래 레이어)으로 통과되어야 합니다.
    return const IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 150), // Positioned 대신 간격으로 중앙 정렬 맞춤
          Text(
            '첫 번째 돌을 골라볼까요?',
            textAlign: TextAlign.center, // 중앙 정렬 보장
            style: TextStyle(
              color: Colors.black87,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 16),
          Text(
            '지금 눈에 보이는 것 중\n가장 눈에 띄는 돌을 골라보세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// [Step 3] 돌을 쌓을 때 손끝에 느껴지는 감각을 느껴보세요
class _Step3DragStone extends StatefulWidget {
  const _Step3DragStone({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<_Step3DragStone> createState() => _Step3DragStoneState();
}

class _Step3DragStoneState extends State<_Step3DragStone> {
  /// false = 첫 번째 텍스트, true = 두 번째 텍스트
  bool _showSecondText = false;
  Timer? _switchTimer;

  @override
  void initState() {
    super.initState();
    // 3초 후 두 번째 텍스트로 전환
    _switchTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showSecondText = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _switchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 상단 텍스트 영역 (터치 무시)
        IgnorePointer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 150),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                // 등장하는 텍스트만 300ms 페이드 인
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                // 이전 텍스트는 즉시 사라짐
                switchOutCurve: Curves.linear,
                switchInCurve: Curves.easeOut,
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // 이전 텍스트 즉시 숨기기
                      ...previousChildren.map(
                        (child) => Opacity(opacity: 0, child: child),
                      ),
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: _showSecondText
                    ? RichText(
                        key: const ValueKey('second'),
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            height: 1.6,
                          ),
                          children: [
                            TextSpan(text: '돌을 쌓을때 '),
                            TextSpan(
                              text: '들리는 소리',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: '에\n집중해 보세요'),
                          ],
                        ),
                      )
                    : RichText(
                        key: const ValueKey('first'),
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                            height: 1.6,
                          ),
                          children: [
                            TextSpan(text: '돌을 쌓을 때 '),
                            TextSpan(
                              text: '손끝에 느껴지는',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: '\n감각을 느껴보세요'),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),

        // 다음으로 버튼 (요구사항: 좌측 상단, X버튼과 동일한 y위치)
        Positioned(
          top: MediaQuery.paddingOf(context).top + 16,
          left: 16,
          child: TextButton(
            onPressed: widget.onNext,
            style: TextButton.styleFrom(
              backgroundColor: Colors.black45,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text('다음으로', style: TextStyle(color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

/// [Step 4] 이제부터 돌탑을 차분히 쌓아볼까요?
class _Step4StackFinish extends StatefulWidget {
  const _Step4StackFinish({
    super.key,
    required this.stoneAssets,
    required this.selectedStoneAsset,
    required this.onNext,
  });

  final List<String> stoneAssets;
  final String selectedStoneAsset;
  final VoidCallback onNext;

  @override
  State<_Step4StackFinish> createState() => _Step4StackFinishState();
}

const _stoneDimensions = {
  'assets/images/unstructured/td_1_11_3.png': (168.0, 129.0),
  'assets/images/unstructured/td_1_33_5.png': (140.0, 80.0),
  'assets/images/unstructured/td_1_30_6.png': (163.0, 156.0),
  'assets/images/unstructured/td_1_9_2.png': (101.0, 126.0),
  'assets/images/unstructured/td_1_15_4.png': (111.0, 111.0),
  'assets/images/unstructured/td_1_24_7.png': (181.0, 103.0),
  'assets/images/unstructured/td_1_1_1.png': (210.0, 120.0),
};

class _Step4StackFinishState extends State<_Step4StackFinish>
    with SingleTickerProviderStateMixin {
  AnimationController? _titleController;
  Animation<double>? _titleFade;
  Animation<Offset>? _titleSlide;
  bool _showTapText = false;
  Timer? _tapTextTimer;

  @override
  void initState() {
    super.initState();

    // 타이틀: 300ms 동안 fade in + slide up, 즉시 시작
    _titleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _titleController!, curve: Curves.easeOut),
    );

    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _titleController!, curve: Curves.easeOut),
        );

    // 즉시 시작
    _titleController!.forward();

    // 타이틀 완료 후 500ms 뒤에 '터치하여 시작' 표시
    _tapTextTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showTapText = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _tapTextTimer?.cancel();
    _titleController?.dispose();
    super.dispose();
  }

  void _startMainGame() {
    HapticFeedback.heavyImpact();
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _startMainGame,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 기존처럼 UI 위에 돌탑이 쌓여있는 모습 렌더링
          Positioned(
            top: 273,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 첫 번째에는 사용자가 선택한 돌을 배치
                  Image.asset(
                    widget.selectedStoneAsset,
                    width: _stoneDimensions[widget.selectedStoneAsset]?.$1,
                    height: _stoneDimensions[widget.selectedStoneAsset]?.$2,
                    fit: BoxFit.contain,
                  ),

                  // 나머지 돌들 (7개 중 본인을 제외하고 차례대로 아래로 그림)
                  for (var asset in widget.stoneAssets.where(
                    (a) => a != widget.selectedStoneAsset,
                  ))
                    Image.asset(
                      asset,
                      width: _stoneDimensions[asset]?.$1,
                      height: _stoneDimensions[asset]?.$2,
                      fit: BoxFit.contain,
                    ),
                ],
              ),
            ),
          ),

          // 타이틀: fade in + slide up (300ms, 즉시)
          SlideTransition(
            position: _titleSlide ?? AlwaysStoppedAnimation(Offset.zero),
            child: FadeTransition(
              opacity: _titleFade ?? AlwaysStoppedAnimation(0.0),
              child: const Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 150.0),
                  child: Text(
                    '이제부터 돌탑을\n차분히 쌓아볼까요?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // '터치하여 시작' — 타이틀 완료 후 500ms 뒤 fade in
          AnimatedOpacity(
            opacity: _showTapText ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 500),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 230.0),
                child: Text(
                  '화면을 터치하여 시작하기',
                  style: TextStyle(
                    color: Colors.black87.withValues(alpha: 0.5),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
