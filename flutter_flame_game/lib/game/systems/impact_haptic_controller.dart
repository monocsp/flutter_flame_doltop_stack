import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 돌 충돌 시 실시간으로 진동을 발생시킵니다.
///
/// - 매 `beginContact`마다 그 순간의 속도로 강도 결정 → 즉시 1회 진동
/// - 80ms 쿨다운으로 과도한 진동 방지
/// - iOS / Android 공통 `HapticFeedback` API 사용
class ImpactHapticController {
  ImpactHapticController();

  /// 마지막 진동 발생 시각 (쿨다운용)
  DateTime _lastHapticTime = DateTime(2000);

  // ── 튜닝 상수 ──────────────────────────────────────
  /// 연속 진동 최소 간격 (ms)
  static const int _cooldownMs = 80;

  /// 속도 → 강도 매핑 임계값
  static const double _heavyThreshold = 20.0;
  static const double _mediumThreshold = 12.0;
  static const double _lightThreshold = 5.0;

  /// 돌 터치(드래그 시작) 시 1회 진동
  void onDragStart() {
    _log('drag-start → lightImpact');
    HapticFeedback.lightImpact();
    _lastHapticTime = DateTime.now();
  }

  /// 충돌 발생 시 속도에 따라 즉시 1회 진동합니다.
  ///
  /// [impactSpeed] : 충돌 순간 돌의 `linearVelocity.length`
  void onImpact(double impactSpeed) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastHapticTime).inMilliseconds;

    if (elapsed < _cooldownMs) {
      _log(
        'impact COOLDOWN (${elapsed}ms ago) speed=${impactSpeed.toStringAsFixed(2)}',
      );
      return;
    }

    final intensity = _intensityFromSpeed(impactSpeed);
    _log(
      'realtime-impact speed=${impactSpeed.toStringAsFixed(2)} → intensity=${intensity.name}',
    );

    intensity.fire();
    _lastHapticTime = now;
  }

  /// 리소스 정리
  void dispose() {}

  // ── 강도 매핑 ─────────────────────────────────────
  _HapticIntensity _intensityFromSpeed(double speed) {
    if (speed >= _heavyThreshold) return _HapticIntensity.heavy;
    if (speed >= _mediumThreshold) return _HapticIntensity.medium;
    if (speed >= _lightThreshold) return _HapticIntensity.light;
    return _HapticIntensity.selectionClick;
  }

  void _log(String message) {
    if (!kDebugMode) return;
    debugPrint('[Haptic] $message');
  }
}

enum _HapticIntensity {
  heavy,
  medium,
  light,
  selectionClick;

  void fire() {
    switch (this) {
      case heavy:
        HapticFeedback.heavyImpact();
      case medium:
        HapticFeedback.mediumImpact();
      case light:
        HapticFeedback.lightImpact();
      case selectionClick:
        HapticFeedback.selectionClick();
    }
  }
}
