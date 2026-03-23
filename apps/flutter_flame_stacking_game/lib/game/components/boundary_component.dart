import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

/// 월드의 고정 경계(왼쪽 벽, 오른쪽 벽, 바닥)입니다.
///
/// 하나의 정적 Forge2D 바디에 3개 fixture를 붙여,
/// 스폰된 돌이 플레이 영역 밖으로 나가지 않게 합니다.
class BoundaryComponent extends BodyComponent {
  BoundaryComponent({required this.worldSize, this.includeFloor = true});

  final Vector2 worldSize;
  final bool includeFloor;

  /// 좌/우 벽 fixture 참조. 돌의 접촉 판별에서 벽/바닥을 구분하는 데 사용합니다.
  final Set<Fixture> wallFixtures = {};

  // 물리 벽/바닥 fixture의 두께(충돌 판정 두께)입니다.
  static const double thickness = 0.8;
  // 원래 기본 바닥 오프셋(하단 기준 기본 여백)입니다.
  static const double floorBaseMarginFromBottom = 2.4;
  // 추가 안전 여백으로, 바닥을 화면 하단에서 더 위로 띄우는 값입니다.
  static const double floorSafetyMarginFromBottom = 4.0;
  static const double floorMarginFromBottom =
      floorBaseMarginFromBottom + floorSafetyMarginFromBottom;

  /// 정적 물리 바디와 fixture들을 생성합니다.
  @override
  Body createBody() {
    final bodyDef = BodyDef()
      ..type = BodyType.static
      ..position = Vector2.zero();

    final body = world.createBody(bodyDef);
    body.userData = this;
    final floorCenterY = worldSize.y - floorMarginFromBottom - thickness / 2;

    // 벽의 높이를 위쪽으로 매우 크게 확장하여 무한 스택을 지원합니다.
    const wallHeight = 20000.0;
    final wallCenterY = floorCenterY - wallHeight / 2;

    final leftWall = PolygonShape()
      ..setAsBox(
        thickness / 2,
        wallHeight / 2,
        Vector2(thickness / 2, wallCenterY),
        0,
      );

    final rightWall = PolygonShape()
      ..setAsBox(
        thickness / 2,
        wallHeight / 2,
        Vector2(worldSize.x - thickness / 2, wallCenterY),
        0,
      );

    body.createFixture(
      FixtureDef(leftWall)
        ..friction = 0.9
        ..restitution = 0.0,
    );
    body.createFixture(
      FixtureDef(rightWall)
        ..friction = 0.9
        ..restitution = 0.0,
    );

    // 벽 fixture 참조 보관 (fixture 목록에서 마지막 두 개)
    wallFixtures.addAll(body.fixtures.toList());

    if (includeFloor) {
      final floor = PolygonShape()
        ..setAsBox(
          worldSize.x / 2,
          thickness / 2,
          Vector2(worldSize.x / 2, floorCenterY),
          0,
        );
      body.createFixture(
        FixtureDef(floor)
          ..friction = 1.0
          ..restitution = 0.0,
      );
    }

    return body;
  }

  /// 물리 경계를 화면에 단순한 사각형으로 그립니다.
  @override
  void render(Canvas canvas) {
    // 물리 경계는 유지하고, 시각 테두리는 투명 처리합니다.
    return;
  }
}
