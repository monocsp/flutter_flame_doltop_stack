import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

class BoundaryComponent extends BodyComponent {
  BoundaryComponent({required this.worldSize});

  final Vector2 worldSize;

  static const double thickness = 0.8;
  static const double floorMarginFromBottom = 2.4;

  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2.zero();

    final body = world.createBody(bodyDef);
    body.userData = this;
    final floorCenterY = worldSize.y - floorMarginFromBottom - thickness / 2;

    final leftWall = PolygonShape()
      ..setAsBox(
        thickness / 2,
        floorCenterY / 2,
        Vector2(thickness / 2, floorCenterY / 2),
        0,
      );

    final rightWall = PolygonShape()
      ..setAsBox(
        thickness / 2,
        floorCenterY / 2,
        Vector2(worldSize.x - thickness / 2, floorCenterY / 2),
        0,
      );

    final floor = PolygonShape()
      ..setAsBox(
        worldSize.x / 2,
        thickness / 2,
        Vector2(worldSize.x / 2, floorCenterY),
        0,
      );

    body.createFixture(FixtureDef(leftWall)..friction = 0.62..restitution = 0.0);
    body.createFixture(FixtureDef(rightWall)..friction = 0.62..restitution = 0.0);
    body.createFixture(FixtureDef(floor)..friction = 0.68..restitution = 0.0);

    return body;
  }

  @override
  void render(Canvas canvas) {
    final floorTopY = worldSize.y - floorMarginFromBottom - thickness;
    final wallHeight = floorTopY + thickness;
    final paint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, thickness, wallHeight), paint);
    canvas.drawRect(
      Rect.fromLTWH(worldSize.x - thickness, 0, thickness, wallHeight),
      paint,
    );
    canvas.drawRect(Rect.fromLTWH(0, floorTopY, worldSize.x, thickness), paint);
  }
}
