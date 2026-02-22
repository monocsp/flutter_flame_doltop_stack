import 'package:flame_forge2d/flame_forge2d.dart';

/// 마우스 조인트 기반 드래그 튜닝값입니다.
class DragTuning {
  const DragTuning({
    this.pickRadius = 3.2,
    this.maxForcePerMass = 5200,
    this.frequencyHz = 14.0,
    this.dampingRatio = 0.96,
    this.velocityGain = 18.0,
    this.angularDampingGain = 0.6,
  });

  final double pickRadius;
  final double maxForcePerMass;
  final double frequencyHz;
  final double dampingRatio;
  final double velocityGain;
  final double angularDampingGain;
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

  /// `MouseJoint` 생성에 필요한 정적 기준 바디를 만듭니다.
  Future<void> initialize() async {
    _groundBody = world.createBody(BodyDef()..type = BodyType.static);
  }

  /// 가장 가까운 드래그 가능 바디를 골라 드래그 조인트를 시작합니다.
  void startDrag(Vector2 worldPoint) {
    _destroyJoint();

    Body? selectedBody;
    var bestDistance = double.infinity;
    final pickRadiusSquared = tuning.pickRadius * tuning.pickRadius;

    for (final body in bodyCandidates()) {
      if (body.bodyType != BodyType.dynamic) continue;

      final distance = body.position.distanceToSquared(worldPoint);
      final touched = body.fixtures.any((fixture) => fixture.testPoint(worldPoint));
      if (!touched && distance > pickRadiusSquared) continue;

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
      _draggedBody!.linearVelocity = Vector2.zero();
      _draggedBody!.setAwake(true);
      _draggedBody = null;
    }
    _dragTarget = null;
  }

  /// 드래그 중 프레임마다 속도/회전을 안정화합니다.
  void tick() {
    if (_draggedBody == null || _dragTarget == null) return;
    final toTarget = _dragTarget! - _draggedBody!.position;
    _draggedBody!.linearVelocity = toTarget * tuning.velocityGain;
    _draggedBody!.angularVelocity *= tuning.angularDampingGain;
    _draggedBody!.setAwake(true);
  }

  /// 현재 마우스 조인트가 있으면 안전하게 제거합니다.
  void _destroyJoint() {
    if (_mouseJoint == null) return;
    world.destroyJoint(_mouseJoint!);
    _mouseJoint = null;
  }
}
