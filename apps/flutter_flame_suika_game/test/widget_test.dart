import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_flame_game_2/main.dart';

void main() {
  testWidgets('renders game select screen', (WidgetTester tester) async {
    await tester.pumpWidget(const GameHubApp());

    expect(find.text('FLAME GAME HUB'), findsOneWidget);
    expect(find.text('스택게임'), findsOneWidget);
    expect(find.text('수박게임'), findsOneWidget);
  });
}
