import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_flame_game_2/main.dart';

void main() {
  testWidgets('renders Flame game widget', (WidgetTester tester) async {
    await tester.pumpWidget(
      GameWidget(
        game: BasicFlameGame(),
      ),
    );

    expect(find.byType(GameWidget<BasicFlameGame>), findsOneWidget);
  });
}
