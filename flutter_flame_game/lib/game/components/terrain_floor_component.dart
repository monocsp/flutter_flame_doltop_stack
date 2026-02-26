import 'package:flame_forge2d/flame_forge2d.dart';

import '../physics/terrain_chain_builder.dart';
import '../terrain/terrain_profile.dart';

/// 이미지에서 추출된 곡면을 물리 바닥으로 구성합니다.
class TerrainFloorComponent extends BodyComponent {
  TerrainFloorComponent({
    required this.profile,
    this.friction = 1.0,
    this.restitution = 0.0,
  });

  final TerrainProfile profile;
  final double friction;
  final double restitution;

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2.zero();

    final body = world.createBody(bodyDef);
    body.userData = this;

    final points = const TerrainChainBuilder().sanitizePoints(
      profile.worldPoints,
    );
    if (points.length < 2) return body;

    for (var i = 0; i < points.length - 1; i++) {
      final edge = EdgeShape()..set(points[i], points[i + 1]);
      body.createFixture(
        FixtureDef(edge)
          ..friction = friction
          ..restitution = restitution,
      );
    }

    return body;
  }
}
