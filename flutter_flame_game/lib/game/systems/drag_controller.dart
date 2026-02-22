import 'package:flame_forge2d/flame_forge2d.dart';

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

  Future<void> initialize() async {
    _groundBody = world.createBody(BodyDef()..type = BodyType.static);
  }

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

  void updateDrag(Vector2 worldPoint) {
    if (_mouseJoint == null) return;
    _dragTarget = worldPoint;
    _mouseJoint!.setTarget(worldPoint);
  }

  void endDrag() {
    _destroyJoint();
    if (_draggedBody != null) {
      _draggedBody!.linearVelocity = Vector2.zero();
      _draggedBody!.setAwake(true);
      _draggedBody = null;
    }
    _dragTarget = null;
  }

  void tick() {
    if (_draggedBody == null || _dragTarget == null) return;
    final toTarget = _dragTarget! - _draggedBody!.position;
    _draggedBody!.linearVelocity = toTarget * tuning.velocityGain;
    _draggedBody!.angularVelocity *= tuning.angularDampingGain;
    _draggedBody!.setAwake(true);
  }

  void _destroyJoint() {
    if (_mouseJoint == null) return;
    world.destroyJoint(_mouseJoint!);
    _mouseJoint = null;
  }
}
