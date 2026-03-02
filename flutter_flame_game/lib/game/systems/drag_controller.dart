import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart';

/// 마우스 조인트 기반 드래그 튜닝값입니다.
class DragTuning {
  const DragTuning({
    this.pickRadius = 3.2,
    this.maxForcePerMass = 5200,
    this.frequencyHz = 14.0,
    this.dampingRatio = 0.96,
    this.velocityGain = 18.0,
    this.angularDampingGain = 0.6,
    this.upwardVelocityMultiplier = 2.8,
    this.downwardVelocityMultiplier = 0.35,
    this.maxUpwardVelocity = 60.0,
    this.maxDownwardVelocity = 7.0,
    this.compressionSuppressionPerStone = 0.55,
    this.maxCompressionSuppression = 0.15,
  });

  final double pickRadius;
  final double maxForcePerMass;
  final double frequencyHz;
  final double dampingRatio;
  final double velocityGain;
  final double angularDampingGain;
  final double upwardVelocityMultiplier;
  final double downwardVelocityMultiplier;
  final double maxUpwardVelocity;
  final double maxDownwardVelocity;
  final double compressionSuppressionPerStone;
  final double maxCompressionSuppression;
}

/// 포인터 입력을 Forge2D 드래그 동작으로 변환합니다.
///
/// 내부적으로 `MouseJoint`와 프레임별 속도 보정을 함께 사용해
/// 드래그 반응성을 유지합니다.
class DragController {
  DragController({
    required this.world,
    required this.bodyCandidates,
    this.tuning = const DragTuning(),
  });

  final Forge2DWorld world;
  final Iterable<Body> Function() bodyCandidates;
  final DragTuning tuning;

  MouseJoint? _mouseJoint;
  Body? _groundBody;
  Body? _draggedBody;
  Vector2? _dragTarget;

  /// 현재 돌을 드래그 중인지 여부를 반환합니다.
  bool get isDragging => _draggedBody != null;
  bool isBodyBeingDragged(Body body) => identical(_draggedBody, body);

  /// 가장 마지막으로 드래그했던 바디 (드래그 종료 후에도 유지)
  Body? lastDraggedBody;

  /// `MouseJoint` 생성에 필요한 정적 기준 바디를 만듭니다.
  Future<void> initialize() async {
    _groundBody = world.createBody(BodyDef()..type = BodyType.static);
  }

  /// 가장 가까운 드래그 가능 바디를 골라 드래그 조인트를 시작합니다.
  void startDrag(Vector2 worldPoint) {
    _destroyJoint();

    Body? selectedBody;
    var bestDistance = double.infinity;
    for (final body in bodyCandidates()) {
      if (body.bodyType != BodyType.dynamic) continue;

      final distance = body.position.distanceToSquared(worldPoint);
      final touched = body.fixtures.any(
        (fixture) => fixture.testPoint(worldPoint),
      );
      if (!touched) continue;

      if (distance < bestDistance) {
        bestDistance = distance;
        selectedBody = body;
      }
    }

    if (selectedBody == null || _groundBody == null) return;

    final def = MouseJointDef()
      ..bodyA = _groundBody!
      ..bodyB = selectedBody
      ..target.setFrom(worldPoint)
      ..maxForce = tuning.maxForcePerMass * selectedBody.mass
      ..dampingRatio = tuning.dampingRatio
      ..frequencyHz = tuning.frequencyHz;

    _mouseJoint = MouseJoint(def);
    world.createJoint(_mouseJoint!);
    _draggedBody = selectedBody;
    _dragTarget = worldPoint;
    selectedBody.linearVelocity = Vector2.zero();
    selectedBody.angularVelocity = 0.0;
    selectedBody.setAwake(true);
  }

  /// 현재 드래그 타겟 좌표를 갱신합니다.
  void updateDrag(Vector2 worldPoint) {
    if (_mouseJoint == null) return;
    _dragTarget = worldPoint;
    _mouseJoint!.setTarget(worldPoint);
  }

  /// 드래그를 종료하고 조인트를 해제합니다.
  void endDrag() {
    _destroyJoint();
    if (_draggedBody != null) {
      lastDraggedBody = _draggedBody;
      _draggedBody!.linearVelocity = Vector2.zero();
      _draggedBody!.setAwake(true);
      _draggedBody = null;
    } else {
      debugPrint('[Haptic][Drag] endDrag WARNING: _draggedBody was null!');
    }
    _dragTarget = null;
  }

  /// 드래그 중 프레임마다 속도/회전을 안정화합니다.
  void tick() {
    if (_draggedBody == null || _dragTarget == null) return;
    final body = _draggedBody!;
    final toTarget = _dragTarget! - body.position;
    final rawVelocity = toTarget * tuning.velocityGain;
    final aboveContactCount = _countCompressingBodiesAbove(body);

    // Forge2D 좌표계에서 +Y는 아래 방향입니다.
    var vy = rawVelocity.y;
    if (vy < 0) {
      final suppressionFactor = math.max(
        tuning.maxCompressionSuppression,
        math
            .pow(tuning.compressionSuppressionPerStone, aboveContactCount)
            .toDouble(),
      );
      final upwardMultiplier = aboveContactCount > 0
          ? tuning.downwardVelocityMultiplier * suppressionFactor
          : tuning.upwardVelocityMultiplier;
      final upwardMaxVelocity = aboveContactCount > 0
          ? tuning.maxDownwardVelocity * suppressionFactor
          : tuning.maxUpwardVelocity;
      vy *= upwardMultiplier;
      vy = vy.clamp(-upwardMaxVelocity, 0.0);
    } else {
      vy *= tuning.downwardVelocityMultiplier;
      vy = vy.clamp(0.0, tuning.maxDownwardVelocity);
    }

    body.linearVelocity = Vector2(rawVelocity.x, vy);
    body.angularVelocity *= tuning.angularDampingGain;
    body.setAwake(true);
  }

  int _countCompressingBodiesAbove(Body body) {
    var count = 0;
    for (final contact in body.contacts) {
      if (!contact.isTouching()) continue;
      final other = contact.fixtureA.body == body
          ? contact.fixtureB.body
          : contact.fixtureA.body;
      if (other.bodyType != BodyType.dynamic) continue;
      if (other.position.y < body.position.y - 0.15) {
        count++;
      }
    }
    return count;
  }

  /// 현재 마우스 조인트가 있으면 안전하게 제거합니다.
  void _destroyJoint() {
    if (_mouseJoint == null) return;
    world.destroyJoint(_mouseJoint!);
    _mouseJoint = null;
  }
}
